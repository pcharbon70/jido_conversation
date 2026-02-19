defmodule JidoConversation.Runtime.CoordinatorTest do
  use ExUnit.Case, async: true

  alias JidoConversation.Runtime.Coordinator

  test "partition_for_subject is deterministic for same subject" do
    count = 8

    partition_a = Coordinator.partition_for_subject("conversation-123", count)
    partition_b = Coordinator.partition_for_subject("conversation-123", count)

    assert partition_a == partition_b
    assert partition_a in 0..(count - 1)
  end

  test "partition_for_subject handles nil subject" do
    count = 4

    partition = Coordinator.partition_for_subject(nil, count)

    assert partition in 0..(count - 1)
  end
end
