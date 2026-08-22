defmodule CadenceWeb.OpsDataOperationsLive.PresentationTest do
  use ExUnit.Case, async: true

  alias Cadence.Telemetry.Storage.BackfillLifecycleEvent
  alias CadenceWeb.OpsDataOperationsLive.Presentation

  test "orders lifecycle events chronologically across second boundaries" do
    requested = event("requested", "requested", ~U[2026-08-17 03:24:32.981423Z])
    approved = event("approved", "approved", ~U[2026-08-17 03:24:33.033979Z])

    assert [group] = Presentation.build([requested, approved])
    assert group.state == "approved"
    assert group.updated_at == approved.occurred_at
    assert group.eligibility.approve == 0
    assert group.eligibility.start == 1

    assert Enum.map(group.audit_events, & &1.backfill_lifecycle_event_id) == [
             "approved",
             "requested"
           ]
  end

  defp event(event_id, stage, occurred_at) do
    BackfillLifecycleEvent.new(%{
      backfill_lifecycle_event_id: event_id,
      backfill_run_id: "managed-operation-1",
      organization_id: "org-1",
      mission_id: "mission-1",
      realm: :flight,
      event_type: :"backfill_#{stage}",
      occurred_at: occurred_at,
      payload: %{
        "workflow" => "backfill",
        "stage" => stage,
        "request_group_id" => "managed-operation-1",
        "request_item_index" => 1,
        "request_item_count" => 1
      }
    })
  end
end
