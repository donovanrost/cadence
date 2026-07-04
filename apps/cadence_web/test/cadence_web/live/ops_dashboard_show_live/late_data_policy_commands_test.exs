defmodule CadenceWeb.OpsDashboardShowLive.LateDataPolicyCommandsTest do
  use CadenceWeb.ConnCase, async: false

  alias Cadence.Telemetry.Storage
  alias CadenceWeb.OpsDashboardShowLive.LateDataPolicyCommands
  alias CadenceWeb.OpsDashboardShowLive.LateDataPolicyParams

  @opts [dashboard_runtime_invalidation?: false]
  @scope %{organization_id: "org-dashboard-late-policy", user: %{id: "operator-late"}}
  @mission %{mission_id: "mission-dashboard-late-policy"}

  test "records accepted late-data policy decisions as lifecycle events" do
    params = %{
      "decision" => "accept",
      "execution_mode" => "sample_execution",
      "run_id" => "late-policy-run-1",
      "dashboard_time_mode" => "live",
      "dashboard_limit_mode" => "compare",
      "realm" => "flight",
      "data_source_id" => "managed_questdb_primary",
      "source_binding_id" => "default_flight_telemetry",
      "observable_id" => "HK.counter",
      "point_id" => "HK.counter",
      "source_from" => "2026-06-22T10:00:00Z",
      "source_to" => "2026-06-22T11:00:00Z",
      "receipt_from" => "2026-06-22T12:00:00Z",
      "receipt_to" => "2026-06-22T12:10:00Z",
      "sample_count" => "3",
      "authority" => "authoritative",
      "reason" => "operator_accepts_late_data",
      "source_event_id" => "source-backfill-event-1",
      "source_event_type" => "backfill_completed"
    }

    assert {:ok, event} =
             LateDataPolicyCommands.record_decision(params, @scope, @mission, @opts)

    assert event.event_type == :late_data_accepted
    assert event.backfill_run_id == "late-policy-run-1"
    assert event.organization_id == @scope.organization_id
    assert event.mission_id == @mission.mission_id
    assert event.realm == :flight
    assert event.data_source_id == "managed_questdb_primary"
    assert event.binding_id == "default_flight_telemetry"
    assert event.point_id == "HK.counter"
    assert event.sample_count == 0
    assert event.authority == :authoritative
    assert event.reason == "operator_accepts_late_data"
    assert event.actor_id == "operator-late"
    assert event.actor_kind == "operator"
    assert event.payload["kind"] == "late_data_policy_decision"
    assert event.payload["policy_decision"] == "accept"
    assert event.payload["execution_mode"] == "sample_execution"
    assert event.payload["source_event_id"] == "source-backfill-event-1"
    assert event.payload["source_event_type"] == "backfill_completed"
    assert event.payload["dashboard_context"]["dashboard_time_mode"] == "live"
    refute Map.has_key?(event.payload["dashboard_context"], "dashboard_replay_run_id")
    assert event.payload["dashboard_context"]["dashboard_limit_mode"] == "compare"
    assert event.payload["selected_sample_count"] == 0
    assert event.payload["write_validity_state"] == "canonical"
    assert event.payload["record_current_values"]
    assert event.payload["refresh_latest_value"]

    assert event.payload["projection_effect"] ==
             "canonical_history_and_current_projection"

    assert [listed] =
             Storage.list_backfill_lifecycle_events(@mission.mission_id,
               organization_id: @scope.organization_id,
               event_type: :late_data_accepted
             )

    assert listed.backfill_lifecycle_event_id == event.backfill_lifecycle_event_id
  end

  test "records rejected late-data policy decisions as lifecycle events" do
    params =
      LateDataPolicyParams.from_event(%{
        "decision" => "reject",
        "execution_mode" => "event_only",
        "run_id" => "late-policy-run-2",
        "realm" => "flight",
        "data_source_id" => "managed_questdb_primary",
        "source_binding_id" => "default_flight_telemetry",
        "authority" => "advisory",
        "reason" => "operator_rejects_late_data"
      })

    assert {:ok, event} =
             LateDataPolicyCommands.record_decision(params, @scope, @mission, @opts)

    assert event.event_type == :late_data_rejected
    assert event.authority == :advisory
    assert event.reason == "operator_rejects_late_data"
    refute Map.has_key?(event.payload, "selected_sample_count")
    assert event.payload["execution_mode"] == "event_only"
    assert event.payload["write_validity_state"] == "advisory"
    refute event.payload["record_current_values"]
    refute event.payload["refresh_latest_value"]
    assert event.payload["projection_effect"] == "audit_event_only"
  end

  test "records replay late-data policy decisions as event-only audit events" do
    params =
      LateDataPolicyParams.from_event(%{
        "decision" => "accept",
        "execution_mode" => "event_only",
        "run_id" => "late-policy-replay-run",
        "dashboard_time_mode" => "replay_run",
        "dashboard_replay_run_id" => "replay-policy-1",
        "dashboard_limit_mode" => "compare",
        "realm" => "flight",
        "data_source_id" => "managed_questdb_primary",
        "source_binding_id" => "default_flight_telemetry",
        "point_id" => "HK.counter",
        "source_from" => "2026-06-22T10:00:00Z",
        "source_to" => "2026-06-22T11:00:00Z",
        "authority" => "comparison",
        "reason" => "operator_accepts_replay_late_data",
        "source_event_id" => "source-replay-event-1",
        "source_event_type" => "backfill_completed"
      })

    assert {:ok, event} =
             LateDataPolicyCommands.record_decision(params, @scope, @mission, @opts)

    assert event.event_type == :late_data_accepted
    assert event.sample_count == nil
    assert event.authority == :comparison
    assert event.reason == "operator_accepts_replay_late_data"
    assert event.payload["kind"] == "late_data_policy_decision"
    assert event.payload["policy_decision"] == "accept"
    assert event.payload["execution_mode"] == "event_only"
    assert event.payload["source_event_id"] == "source-replay-event-1"
    assert event.payload["source_event_type"] == "backfill_completed"
    assert event.payload["dashboard_context"]["dashboard_time_mode"] == "replay_run"
    assert event.payload["dashboard_context"]["dashboard_replay_run_id"] == "replay-policy-1"
    assert event.payload["dashboard_context"]["dashboard_limit_mode"] == "compare"
    refute Map.has_key?(event.payload, "selected_sample_count")
    assert event.payload["write_validity_state"] == "canonical"
    refute event.payload["record_current_values"]
    refute event.payload["refresh_latest_value"]
    assert event.payload["projection_effect"] == "audit_event_only"
  end

  test "does not fall back from sample execution to event-only recording" do
    params = %{
      "decision" => "accept",
      "execution_mode" => "sample_execution",
      "run_id" => "late-policy-run-missing-point",
      "realm" => "flight",
      "data_source_id" => "managed_questdb_primary",
      "source_binding_id" => "default_flight_telemetry",
      "source_from" => "2026-06-22T10:00:00Z",
      "source_to" => "2026-06-22T11:00:00Z"
    }

    assert {:error, {:missing_field, :point_id}} =
             LateDataPolicyCommands.record_decision(params, @scope, @mission, @opts)

    assert [] =
             Storage.list_backfill_lifecycle_events(@mission.mission_id,
               organization_id: @scope.organization_id,
               event_type: :late_data_accepted
             )
  end

  test "rejects replay sample execution instead of writing canonical samples" do
    params = %{
      "decision" => "accept",
      "execution_mode" => "sample_execution",
      "run_id" => "late-policy-replay-sample-run",
      "dashboard_time_mode" => "replay_run",
      "dashboard_replay_run_id" => "replay-policy-1",
      "realm" => "flight",
      "data_source_id" => "managed_questdb_primary",
      "source_binding_id" => "default_flight_telemetry",
      "point_id" => "HK.counter",
      "source_from" => "2026-06-22T10:00:00Z",
      "source_to" => "2026-06-22T11:00:00Z"
    }

    assert {:error, :replay_late_data_policy_requires_event_only} =
             LateDataPolicyCommands.record_decision(params, @scope, @mission, @opts)

    assert [] =
             Storage.list_backfill_lifecycle_events(@mission.mission_id,
               organization_id: @scope.organization_id,
               event_type: :late_data_accepted
             )
  end

  test "requires a decision" do
    assert {:error, {:missing_field, :decision}} =
             LateDataPolicyCommands.record_decision(%{}, @scope, @mission, @opts)
  end

  test "requires an explicit execution mode" do
    assert {:error, {:missing_field, :execution_mode}} =
             LateDataPolicyCommands.record_decision(
               %{"decision" => "accept"},
               @scope,
               @mission,
               @opts
             )
  end

  test "rejects unsupported execution modes" do
    assert {:error, {:unsupported_late_data_policy_execution_mode, "silent_fallback"}} =
             LateDataPolicyCommands.record_decision(
               %{"decision" => "accept", "execution_mode" => "silent_fallback"},
               @scope,
               @mission,
               @opts
             )
  end
end
