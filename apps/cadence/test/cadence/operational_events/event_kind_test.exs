defmodule Cadence.OperationalEvents.EventKindTest do
  use ExUnit.Case, async: true

  alias Cadence.OperationalEvents.Event

  test "decodes persisted event kinds without producer module load order" do
    for kind <- [
          "source_health_degraded",
          "transport_initialized",
          "provider_audit_recorded"
        ] do
      event =
        Event.new(%{
          "event_id" => "operational-event-kind-#{kind}",
          "mission_id" => "mission-1",
          "occurred_at" => ~U[2026-08-02 12:00:00Z],
          "category" => "runtime",
          "kind" => kind
        })

      assert Atom.to_string(event.kind) == kind
    end
  end

  test "rejects event kinds outside the canonical vocabulary" do
    assert_raise ArgumentError, ~s(unsupported kind: "unregistered_operational_event_kind"), fn ->
      Event.new(%{
        "event_id" => "operational-event-kind-unknown",
        "mission_id" => "mission-1",
        "occurred_at" => ~U[2026-08-02 12:00:00Z],
        "category" => "runtime",
        "kind" => "unregistered_operational_event_kind"
      })
    end
  end
end
