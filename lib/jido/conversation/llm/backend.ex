defmodule Jido.Conversation.LLM.Backend do
  @moduledoc """
  Behaviour contract for LLM backend adapters.

  Adapters implement normalized request/stream/cancel operations while handling
  backend-native protocol differences internally.
  """

  alias Jido.Conversation.LLM.Error
  alias Jido.Conversation.LLM.Event
  alias Jido.Conversation.LLM.Request
  alias Jido.Conversation.LLM.Result

  @type execution_ref :: term()
  @type options :: keyword()
  @type stream_callback :: (Event.t() -> term())

  @type capabilities :: %{
          required(:streaming?) => boolean(),
          required(:cancellation?) => boolean(),
          required(:provider_selection?) => boolean(),
          required(:model_selection?) => boolean(),
          optional(atom()) => term()
        }

  @callback capabilities() :: capabilities()

  @callback start(Request.t(), options()) ::
              {:ok, Result.t()}
              | {:ok, Result.t(), execution_ref()}
              | {:error, Error.t()}

  @callback stream(Request.t(), stream_callback(), options()) ::
              {:ok, Result.t()}
              | {:ok, Result.t(), execution_ref()}
              | {:error, Error.t()}

  @callback cancel(execution_ref(), options()) :: :ok | {:error, Error.t()}
end
