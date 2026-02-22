defmodule Jido.Conversation.LLM.BackendTest do
  use ExUnit.Case, async: true

  alias Jido.Conversation.LLM.Backend
  alias Jido.Conversation.LLM.Event
  alias Jido.Conversation.LLM.Request
  alias Jido.Conversation.LLM.Result

  defmodule TestBackend do
    @behaviour Backend

    alias Jido.Conversation.LLM.Error

    @impl true
    def capabilities do
      %{
        streaming?: true,
        cancellation?: true,
        provider_selection?: true,
        model_selection?: true
      }
    end

    @impl true
    def start(%Request{} = request, _opts) do
      {:ok,
       Result.new!(%{
         request_id: request.request_id,
         conversation_id: request.conversation_id,
         backend: request.backend,
         status: :completed,
         text: "ok"
       })}
    end

    @impl true
    def stream(%Request{} = request, emit, _opts) when is_function(emit, 1) do
      _ =
        emit.(
          Event.new!(%{
            request_id: request.request_id,
            conversation_id: request.conversation_id,
            backend: request.backend,
            lifecycle: :delta,
            delta: "partial"
          })
        )

      {:ok,
       Result.new!(%{
         request_id: request.request_id,
         conversation_id: request.conversation_id,
         backend: request.backend,
         status: :completed,
         text: "partial"
       }), :ref}
    end

    @impl true
    def cancel(:ref, _opts), do: :ok

    def cancel(_ref, _opts) do
      {:error, Error.new!(category: :unknown, message: "not_found")}
    end
  end

  test "behaviour implementation can execute normalized start/stream/cancel flow" do
    request =
      Request.new!(%{
        request_id: "r1",
        conversation_id: "c1",
        backend: :jido_ai,
        messages: [%{role: :user, content: "hello"}]
      })

    assert %{streaming?: true, cancellation?: true} = TestBackend.capabilities()
    assert {:ok, %Result{text: "ok"}} = TestBackend.start(request, [])

    assert {:ok, %Result{text: "partial"}, :ref} =
             TestBackend.stream(request, fn %Event{} -> :ok end, [])

    assert :ok = TestBackend.cancel(:ref, [])
  end
end
