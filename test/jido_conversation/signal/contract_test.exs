defmodule JidoConversation.Signal.ContractTest do
  use ExUnit.Case, async: true

  alias Jido.Signal
  alias JidoConversation.Signal.Contract

  test "normalizes valid map input into a signal" do
    attrs = %{
      type: "conv.in.message.received",
      source: "/messaging/telegram",
      subject: "conversation-123",
      data: %{
        message_id: "msg-1",
        ingress: "telegram"
      },
      extensions: %{
        contract_major: 1
      }
    }

    assert {:ok, %Signal{} = signal} = Contract.normalize(attrs)
    assert signal.type == "conv.in.message.received"
    assert signal.subject == "conversation-123"
    assert signal.extensions["contract_major"] == 1
  end

  test "normalizes conversation_id alias into subject" do
    attrs = %{
      type: "conv.in.message.received",
      source: "/messaging/slack",
      conversation_id: "conversation-456",
      data: %{"message_id" => "msg-2", "ingress" => "slack"},
      contract_major: 1
    }

    assert {:ok, signal} = Contract.normalize(attrs)
    assert signal.subject == "conversation-456"
    assert signal.extensions["contract_major"] == 1
  end

  test "accepts already-built valid signal" do
    {:ok, signal} =
      Signal.new(
        "conv.out.assistant.completed",
        %{output_id: "out-1", channel: "ide"},
        source: "/llm/provider-x",
        subject: "conversation-789",
        extensions: %{contract_major: 1}
      )

    assert {:ok, ^signal} = Contract.normalize(signal)
  end

  test "rejects missing subject" do
    attrs = %{
      type: "conv.in.message.received",
      source: "/messaging/discord",
      data: %{message_id: "msg-3", ingress: "discord"},
      extensions: %{contract_major: 1}
    }

    assert {:error, {:field, :subject, :missing}} = Contract.normalize(attrs)
  end

  test "rejects unsupported type namespace" do
    attrs = %{
      type: "random.event.type",
      source: "/unknown/source",
      subject: "conversation-222",
      data: %{},
      extensions: %{contract_major: 1}
    }

    assert {:error, {:type_namespace, "random.event.type"}} = Contract.normalize(attrs)
  end

  test "rejects missing contract major" do
    attrs = %{
      type: "conv.audit.policy.decision_recorded",
      source: "/policy/engine",
      subject: "conversation-333",
      data: %{audit_id: "audit-1", category: "policy"},
      extensions: %{}
    }

    assert {:error, {:contract_version, :missing}} = Contract.normalize(attrs)
  end

  test "rejects unsupported contract major" do
    attrs = %{
      type: "conv.audit.policy.decision_recorded",
      source: "/policy/engine",
      subject: "conversation-334",
      data: %{audit_id: "audit-2", category: "policy"},
      extensions: %{contract_major: 2}
    }

    assert {:error, {:contract_version, {:unsupported, 2, [1]}}} = Contract.normalize(attrs)
  end

  test "rejects non-map payload" do
    attrs = %{
      type: "conv.effect.tool.execution.started",
      source: "/tool/runtime",
      subject: "conversation-444",
      data: "not-a-map",
      extensions: %{contract_major: 1}
    }

    assert {:error, {:payload, :effect, {:not_map, "not-a-map"}}} = Contract.normalize(attrs)
  end

  test "rejects stream payload missing required keys" do
    attrs = %{
      type: "conv.effect.tool.execution.started",
      source: "/tool/runtime",
      subject: "conversation-445",
      data: %{effect_id: "effect-1"},
      extensions: %{contract_major: 1}
    }

    assert {:error, {:payload, :effect, {:missing_keys, [:lifecycle]}}} =
             Contract.normalize(attrs)
  end
end
