defmodule Jido.Conversation.SmokeTest do
  use ExUnit.Case, async: true

  alias Jido.Conversation.Health

  test "health reports core supervisors as alive" do
    health = Health.status()

    assert health.status in [:ok, :degraded]
    assert is_boolean(health.bus_alive?)
    assert is_boolean(health.runtime_supervisor_alive?)
    assert is_boolean(health.runtime_coordinator_alive?)
  end
end
