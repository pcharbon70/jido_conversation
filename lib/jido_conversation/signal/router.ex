defmodule JidoConversation.Signal.Router do
  @moduledoc """
  Router bootstrap for the conversation bus.
  """

  alias Jido.Signal.Router

  @cache_id :jido_conversation_router

  def new! do
    Router.new!(nil, cache_id: @cache_id)
  end
end
