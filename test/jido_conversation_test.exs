defmodule JidoConversationTest do
  use ExUnit.Case, async: true

  test "health reports core supervisors as alive" do
    health = JidoConversation.health()

    assert health.status in [:ok, :degraded]
    assert is_boolean(health.bus_alive?)
    assert is_boolean(health.runtime_supervisor_alive?)
    assert is_boolean(health.runtime_coordinator_alive?)
  end
end
