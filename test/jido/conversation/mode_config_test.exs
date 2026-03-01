defmodule Jido.Conversation.Mode.ConfigTest do
  use ExUnit.Case, async: false

  alias Jido.Conversation.Mode.Config
  alias Jido.Conversation.Mode.Registry

  test "resolve/4 applies precedence request > conversation > mode defaults > app defaults" do
    previous_defaults = Application.get_env(:jido_conversation, :mode_option_defaults, %{})

    on_exit(fn ->
      Application.put_env(:jido_conversation, :mode_option_defaults, previous_defaults)
    end)

    Application.put_env(:jido_conversation, :mode_option_defaults, %{
      engineering: %{topic: "app topic", max_options: "9"}
    })

    {:ok, metadata} = Registry.fetch(:engineering)

    conversation_options = %{topic: "conversation topic", max_options: "5", stakeholders: ["qa"]}
    request_options = %{"topic" => "request topic"}

    assert {:ok, resolved} = Config.resolve(metadata, request_options, conversation_options)
    assert resolved.topic == "request topic"
    assert resolved.max_options == 5
    assert resolved.stakeholders == ["qa"]
  end

  test "resolve/4 rejects missing required options" do
    {:ok, metadata} = Registry.fetch(:planning)

    assert {:error, diagnostics} = Config.resolve(metadata, %{}, %{})

    assert Enum.any?(diagnostics, fn diagnostic ->
             diagnostic.code == :required and diagnostic.path == [:mode_state, :objective]
           end)
  end

  test "resolve/4 rejects unknown keys for modes with :reject policy" do
    {:ok, metadata} = Registry.fetch(:engineering)

    assert {:error, diagnostics} =
             Config.resolve(metadata, %{topic: "architecture", unexpected: true}, %{})

    assert Enum.any?(diagnostics, fn diagnostic ->
             diagnostic.code == :unknown_key and diagnostic.path == [:mode_state, :unexpected]
           end)
  end

  test "resolve/4 allows unknown keys for modes with :allow policy" do
    {:ok, metadata} = Registry.fetch(:coding)

    assert {:ok, resolved} =
             Config.resolve(metadata, %{custom_setting: "value"}, %{style: "terse"})

    assert resolved.custom_setting == "value"
    assert resolved.style == "terse"
  end

  test "resolve/4 emits invalid key diagnostics for unsupported key types" do
    {:ok, metadata} = Registry.fetch(:engineering)

    assert {:error, diagnostics} =
             Config.resolve(metadata, %{1 => "invalid key", topic: "architecture"}, %{})

    assert Enum.any?(diagnostics, fn diagnostic ->
             diagnostic.code == :invalid_key and
               diagnostic.path == [:mode_state, :request, "invalid"]
           end)
  end
end
