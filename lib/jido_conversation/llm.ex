defmodule Jido.Conversation.LLM do
  @moduledoc """
  Backend-agnostic LLM domain types and behaviour contracts.

  This namespace defines normalized request/result/event types used by the
  conversation runtime. Backend adapters (for example, JidoAI or Harness) are
  responsible for mapping provider-native responses into these types.
  """

  @type backend :: :jido_ai | :harness | atom()

  @type error_category ::
          :config
          | :auth
          | :timeout
          | :provider
          | :transport
          | :canceled
          | :unknown
end
