defmodule JidoConversation.Rollout.Manager do
  @moduledoc """
  Stateful rollout manager that tracks accept streaks and can apply transitions.
  """

  use GenServer

  alias JidoConversation.Config
  alias JidoConversation.Rollout.Controller
  alias JidoConversation.Rollout.Reporter
  alias JidoConversation.Rollout.Verification

  @app :jido_conversation
  @key JidoConversation.EventSystem

  @type evaluation_result :: %{
          evaluated_at: DateTime.t(),
          verification: Verification.report(),
          recommendation: Controller.recommendation(),
          applied?: boolean(),
          apply_error: term() | nil
        }

  @type snapshot :: %{
          current_stage: Controller.stage(),
          current_mode: Controller.mode(),
          accept_streak: non_neg_integer(),
          last_result: evaluation_result() | nil,
          recent_results: [evaluation_result()],
          evaluation_count: non_neg_integer(),
          applied_count: non_neg_integer()
        }

  @spec start_link(keyword()) :: GenServer.on_start()
  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @spec snapshot() :: snapshot()
  def snapshot do
    GenServer.call(__MODULE__, :snapshot)
  end

  @spec reset() :: :ok
  def reset do
    GenServer.call(__MODULE__, :reset)
  end

  @spec evaluate(keyword()) :: evaluation_result()
  def evaluate(opts \\ []) when is_list(opts) do
    GenServer.call(__MODULE__, {:evaluate, opts})
  end

  @impl true
  def init(_opts) do
    max_history =
      Config.rollout_manager()
      |> Keyword.get(:max_history, 100)

    {:ok,
     %{
       max_history: max_history,
       accept_streak: 0,
       last_result: nil,
       recent_results: [],
       evaluation_count: 0,
       applied_count: 0
     }}
  end

  @impl true
  def handle_call(:snapshot, _from, state) do
    snapshot = build_snapshot(state)
    {:reply, snapshot, state}
  end

  def handle_call(:reset, _from, state) do
    reset_state = %{
      state
      | accept_streak: 0,
        last_result: nil,
        recent_results: [],
        evaluation_count: 0,
        applied_count: 0
    }

    {:reply, :ok, reset_state}
  end

  def handle_call({:evaluate, opts}, _from, state) do
    verification_opts = Keyword.get(opts, :verification_opts, [])
    controller_opts = Keyword.get(opts, :controller_opts, [])
    manager_cfg = Config.rollout_manager()
    apply? = Keyword.get(opts, :apply?, Keyword.get(manager_cfg, :auto_apply, false))
    accept_streak = Keyword.get(opts, :accept_streak, state.accept_streak)

    verification = Verification.evaluate(Reporter.snapshot(), verification_opts)

    recommendation =
      Controller.recommend(
        verification,
        Keyword.put_new(controller_opts, :accept_streak, accept_streak)
      )

    {applied?, apply_error} = maybe_apply_recommendation(recommendation, apply?)

    result = %{
      evaluated_at: DateTime.utc_now(),
      verification: verification,
      recommendation: recommendation,
      applied?: applied?,
      apply_error: apply_error
    }

    new_state = %{
      state
      | accept_streak: recommendation.next_accept_streak,
        last_result: result,
        recent_results: bounded_prepend(state.recent_results, result, state.max_history),
        evaluation_count: state.evaluation_count + 1,
        applied_count: state.applied_count + if(applied?, do: 1, else: 0)
    }

    {:reply, result, new_state}
  end

  defp maybe_apply_recommendation(recommendation, true)
       when recommendation.action in [:promote, :rollback] do
    apply_rollout_transition(recommendation)
  end

  defp maybe_apply_recommendation(_recommendation, _apply?), do: {false, nil}

  defp apply_rollout_transition(recommendation) do
    existing_event_system = Application.get_env(@app, @key, [])
    existing_rollout = Keyword.get(existing_event_system, :rollout, [])

    updated_rollout = Controller.apply_recommendation(existing_rollout, recommendation)
    updated_event_system = Keyword.put(existing_event_system, :rollout, updated_rollout)

    try do
      Application.put_env(@app, @key, updated_event_system)
      Config.validate!()
      {true, nil}
    rescue
      error ->
        Application.put_env(@app, @key, existing_event_system)
        {false, {:apply_failed, Exception.message(error)}}
    catch
      kind, reason ->
        Application.put_env(@app, @key, existing_event_system)
        {false, {:apply_failed, {kind, reason}}}
    end
  end

  defp build_snapshot(state) do
    %{
      current_stage: Config.rollout_stage(),
      current_mode: Config.rollout_mode(),
      accept_streak: state.accept_streak,
      last_result: state.last_result,
      recent_results: state.recent_results,
      evaluation_count: state.evaluation_count,
      applied_count: state.applied_count
    }
  end

  defp bounded_prepend(list, entry, max_history) when is_list(list) do
    [entry | list]
    |> Enum.take(max_history)
  end
end
