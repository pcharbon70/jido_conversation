defmodule Jido.Conversation.Mode do
  @moduledoc """
  Behaviour contract for conversation modes.

  Namespace map:
  - `Jido.Conversation.Mode`: mode behaviour and shared types.
  - `Jido.Conversation.Mode.<ModeName>`: concrete mode implementation modules.
  - `Jido.Conversation.Mode.Registry`: mode lookup, validation, and configuration (phase 2+).

  Ownership boundaries:
  - Conversation runtime/server own process lifecycle and dispatch.
  - Reducer/projections own durable run-state derivation from append-only journal entries.
  - Mode modules own mode-specific planning and effect-event interpretation.

  Forbidden cross-layer dependencies:
  - Modes must not call runtime supervision/process APIs directly.
  - Runtime/server must not directly mutate mode internal state.
  - Reducer/projections must not call mode modules (state is derived from events only).
  """

  alias Jido.Signal

  @typedoc """
  Lifecycle status for a mode run.
  """
  @type run_status ::
          :pending
          | :running
          | :interrupted
          | :completed
          | :failed
          | :canceled

  @typedoc """
  Opaque mode state owned by the mode implementation.
  """
  @type mode_state :: map()

  @typedoc """
  Shared mode run snapshot persisted in conversation derived state.
  """
  @type run_state :: %{
          required(:run_id) => String.t(),
          required(:mode) => atom(),
          required(:status) => run_status(),
          optional(:step_id) => String.t() | nil,
          optional(:started_at) => integer() | nil,
          optional(:updated_at) => integer() | nil,
          optional(:reason) => String.t() | nil,
          optional(:metadata) => map()
        }

  @typedoc """
  A planned step emitted by a mode.
  """
  @type planned_step :: %{
          required(:step_id) => String.t(),
          required(:kind) => String.t(),
          required(:input) => map(),
          optional(:policy) => keyword() | map()
        }

  @typedoc """
  Directive envelope consumed by runtime orchestration.
  """
  @type mode_directive :: %{
          required(:type) =>
            :start_effect | :emit_output | :cancel_effects | :emit_audit | atom(),
          required(:payload) => map(),
          required(:cause_id) => String.t()
        }

  @typedoc """
  Common success return envelope for mode callbacks.
  """
  @type callback_ok ::
          {:ok, mode_state(), [mode_directive()]}
          | {:next, planned_step(), mode_state(), [mode_directive()]}
          | {:complete, mode_state(), [mode_directive()]}

  @typedoc """
  Common failure return envelope for mode callbacks.
  """
  @type callback_error :: {:error, term(), mode_state(), [mode_directive()]}

  @typedoc """
  Callback return envelope.
  """
  @type callback_result :: callback_ok() | callback_error()

  @callback id() :: atom()

  @doc """
  Initializes mode state for a conversation.
  """
  @callback init(conversation_state :: map(), opts :: keyword()) :: callback_result()

  @doc """
  Plans the next execution step for an active mode run.
  """
  @callback plan_next_step(mode_state(), run_state(), opts :: keyword()) :: callback_result()

  @doc """
  Handles an effect lifecycle signal and updates mode state accordingly.
  """
  @callback handle_effect_event(mode_state(), run_state(), Signal.t(), opts :: keyword()) ::
              callback_result()

  @doc """
  Interrupts the active run and returns updated mode state.
  """
  @callback interrupt(mode_state(), run_state(), reason :: String.t(), opts :: keyword()) ::
              callback_result()

  @doc """
  Resumes a previously interrupted run.
  """
  @callback resume(mode_state(), run_state(), opts :: keyword()) :: callback_result()

  @doc """
  Finalizes a run when it reaches a terminal status.
  """
  @callback finalize(mode_state(), run_state(), reason :: term(), opts :: keyword()) ::
              callback_result()
end
