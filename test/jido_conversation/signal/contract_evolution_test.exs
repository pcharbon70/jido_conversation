defmodule JidoConversation.Signal.ContractEvolutionTest do
  use ExUnit.Case, async: true

  alias JidoConversation.Signal.Contract

  @namespace_examples [
    {:in, "conv.in.message.received", %{message_id: "msg-1", ingress: "web"}},
    {:applied, "conv.applied.event.applied", %{applied_event_id: "evt-1"}},
    {:effect, "conv.effect.tool.execution.started",
     %{effect_id: "effect-1", lifecycle: "started"}},
    {:out, "conv.out.assistant.completed", %{output_id: "out-1", channel: "ide"}},
    {:audit, "conv.audit.policy.decision_recorded", %{audit_id: "audit-1", category: "policy"}}
  ]

  test "required payload key definitions remain stable for v1 streams" do
    assert Contract.required_payload_keys(:in) == [:message_id, :ingress]
    assert Contract.required_payload_keys(:applied) == [:applied_event_id]
    assert Contract.required_payload_keys(:effect) == [:effect_id, :lifecycle]
    assert Contract.required_payload_keys(:out) == [:output_id, :channel]
    assert Contract.required_payload_keys(:audit) == [:audit_id, :category]
  end

  test "normalize accepts canonical v1 payloads across stream namespaces" do
    Enum.each(@namespace_examples, fn {_stream, type, data} ->
      assert {:ok, signal} = Contract.normalize(base_attrs(type, data))
      assert signal.type == type
      assert signal.extensions["contract_major"] == 1
    end)
  end

  test "normalize accepts string payload keys across stream namespaces" do
    Enum.each(@namespace_examples, fn {_stream, type, data} ->
      assert {:ok, signal} = Contract.normalize(base_attrs(type, stringify_payload_keys(data)))
      assert signal.type == type
      assert signal.extensions["contract_major"] == 1
    end)
  end

  test "normalize rejects unsupported contract major across stream namespaces" do
    Enum.each(@namespace_examples, fn {_stream, type, data} ->
      assert {:error, {:contract_version, {:unsupported, 2, [1]}}} =
               Contract.normalize(base_attrs(type, data, %{extensions: %{contract_major: 2}}))
    end)
  end

  test "normalize reports missing required payload keys per stream namespace" do
    Enum.each(@namespace_examples, fn {stream, type, data} ->
      [missing_key | _] = Contract.required_payload_keys(stream)

      assert {:error, {:payload, ^stream, {:missing_keys, missing_keys}}} =
               Contract.normalize(base_attrs(type, Map.delete(data, missing_key)))

      assert missing_key in missing_keys
    end)
  end

  test "extensions contract_major takes precedence over top-level alias" do
    attrs =
      base_attrs(
        "conv.audit.policy.decision_recorded",
        %{audit_id: "audit-2", category: "policy"},
        %{contract_major: 2, extensions: %{contract_major: 1}}
      )

    assert {:ok, signal} = Contract.normalize(attrs)
    assert signal.extensions["contract_major"] == 1
  end

  defp base_attrs(type, data, overrides \\ %{}) do
    Map.merge(
      %{
        type: type,
        source: "/tests/contract-evolution",
        subject: "conversation-contract-evolution",
        data: data,
        extensions: %{contract_major: 1}
      },
      overrides
    )
  end

  defp stringify_payload_keys(payload) do
    Map.new(payload, fn {key, value} -> {to_string(key), value} end)
  end
end
