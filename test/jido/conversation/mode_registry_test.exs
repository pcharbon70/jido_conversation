defmodule Jido.Conversation.Mode.RegistryTest do
  use ExUnit.Case, async: true

  alias Jido.Conversation.Mode.Registry

  defmodule OverridePlanningMode do
    @behaviour Jido.Conversation.Mode

    @impl true
    def id, do: :planning

    def summary, do: "Overridden planning mode"
    def capabilities, do: %{interruptible?: true, planning?: true}
    def required_options, do: [:objective]
    def optional_options, do: [:constraints]
    def defaults, do: %{output_format: :json}
    def unknown_keys_policy, do: :reject
    def stability, do: :stable
    def version, do: 2

    @impl true
    def init(_conversation_state, _opts), do: {:ok, %{}, []}

    @impl true
    def plan_next_step(mode_state, _run_state, _opts), do: {:complete, mode_state, []}

    @impl true
    def handle_effect_event(mode_state, _run_state, _signal, _opts), do: {:ok, mode_state, []}

    @impl true
    def interrupt(mode_state, _run_state, _reason, _opts), do: {:ok, mode_state, []}

    @impl true
    def resume(mode_state, _run_state, _opts), do: {:ok, mode_state, []}

    @impl true
    def finalize(mode_state, _run_state, _reason, _opts), do: {:complete, mode_state, []}
  end

  test "supported_modes/0 returns deterministic built-in ordering" do
    assert Registry.supported_modes() == [:coding, :planning, :engineering]
  end

  test "supported_mode_metadata/1 exposes required metadata fields" do
    metadata = Registry.supported_mode_metadata()

    assert Enum.map(metadata, & &1.id) == [:coding, :planning, :engineering]

    assert Enum.all?(metadata, fn entry ->
             is_atom(entry.id) and is_atom(entry.module) and is_binary(entry.summary) and
               is_map(entry.capabilities) and is_list(entry.required_options) and
               is_list(entry.optional_options) and is_map(entry.defaults) and
               entry.unknown_keys_policy in [:allow, :reject] and
               entry.stability in [:stable, :experimental] and is_integer(entry.version)
           end)
  end

  test "supported_mode_metadata/1 filters by stability" do
    stable = Registry.supported_mode_metadata(stability: :stable)
    experimental = Registry.supported_mode_metadata(stability: :experimental)

    assert Enum.map(stable, & &1.id) == [:coding]
    assert Enum.map(experimental, & &1.id) == [:planning, :engineering]
  end

  test "runtime overrides replace lower-precedence mode definitions" do
    metadata =
      Registry.supported_mode_metadata(runtime_overrides: [{:planning, OverridePlanningMode}])

    planning = Enum.find(metadata, &(&1.id == :planning))

    assert planning.module == OverridePlanningMode
    assert planning.summary == "Overridden planning mode"
    assert planning.version == 2
    assert planning.stability == :stable
  end

  test "resolve/1 rejects duplicate IDs within the same source" do
    assert {:error, {:duplicate_mode_id, :runtime_override, :coding}} =
             Registry.resolve(runtime_overrides: [Jido.Conversation.Mode.Coding, :coding])
  end

  test "fetch/2 returns unsupported mode error with supported list" do
    assert {:error, {:unsupported_mode, :unknown, [:coding, :planning, :engineering]}} =
             Registry.fetch(:unknown)
  end
end
