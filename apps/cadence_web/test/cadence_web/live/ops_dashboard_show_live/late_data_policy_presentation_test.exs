defmodule CadenceWeb.OpsDashboardShowLive.LateDataPolicyPresentationTest do
  use ExUnit.Case, async: true

  alias CadenceWeb.OpsDashboardShowLive.LateDataPolicyPresentation

  test "build presents sample execution policy controls and defaults" do
    context = %{
      source_event_id: "event-1",
      source_event_type: "backfill_completed",
      run_id: "run-1",
      realm: "flight",
      data_source_id: "questdb-flight",
      source_binding_id: "binding-flight",
      dashboard_time_mode: "live",
      dashboard_replay_run_id: nil,
      dashboard_limit_mode: "compare",
      observable_id: "HK.counter",
      point_id: "HK.counter",
      source_from: "2026-06-22T10:00:00Z",
      source_to: "2026-06-22T11:00:00Z",
      receipt_from: "2026-06-22T12:00:00Z",
      receipt_to: "2026-06-22T12:10:00Z",
      sample_count: 3,
      authority: "comparison"
    }

    policy = LateDataPolicyPresentation.build(context)

    assert policy.execution_mode == "sample_execution"
    assert policy.execution_label == "Sample execution"
    assert policy.execution_badge_class == "badge-success badge-outline"
    assert policy.accept_effect == "canonical history; refreshes current/latest projections"
    assert policy.reject_effect == "advisory history only; current/latest projections unchanged"

    assert policy.form_params == %{
             "execution_mode" => "sample_execution",
             "source_event_id" => "event-1",
             "source_event_type" => "backfill_completed",
             "run_id" => "run-1",
             "dashboard_time_mode" => "live",
             "dashboard_replay_run_id" => "",
             "dashboard_limit_mode" => "compare",
             "realm" => "flight",
             "data_source_id" => "questdb-flight",
             "source_binding_id" => "binding-flight",
             "observable_id" => "HK.counter",
             "point_id" => "HK.counter",
             "source_from" => "2026-06-22T10:00:00Z",
             "source_to" => "2026-06-22T11:00:00Z",
             "receipt_from" => "2026-06-22T12:00:00Z",
             "receipt_to" => "2026-06-22T12:10:00Z",
             "sample_count" => "3",
             "decision" => "accept",
             "authority" => "comparison",
             "reason" => "dashboard_late_data_policy_for_backfill_completed",
             "confirmed" => nil
           }
  end

  test "build forces replay-run policy controls to event-only audit mode" do
    policy =
      LateDataPolicyPresentation.build(%{
        source_event_id: "event-1",
        source_event_type: "backfill_completed",
        run_id: "run-1",
        realm: "flight",
        data_source_id: "questdb-flight",
        source_binding_id: "binding-flight",
        dashboard_time_mode: "replay_run",
        dashboard_replay_run_id: "replay-1",
        dashboard_limit_mode: "compare",
        observable_id: "HK.counter",
        point_id: "HK.counter",
        source_from: "2026-06-22T10:00:00Z",
        source_to: "2026-06-22T11:00:00Z"
      })

    assert policy.execution_mode == "event_only"
    assert policy.execution_label == "Event only"
    assert policy.execution_badge_class == "badge-warning badge-outline"
    assert policy.accept_effect == "auditable policy decision; telemetry projections unchanged"
    assert policy.form_params["execution_mode"] == "event_only"
    assert policy.form_params["dashboard_time_mode"] == "replay_run"
    assert policy.form_params["dashboard_replay_run_id"] == "replay-1"
    assert policy.form_params["dashboard_limit_mode"] == "compare"
  end

  test "build presents event-only policy controls with fallback defaults" do
    policy =
      LateDataPolicyPresentation.build(%{
        source_event_id: "event-1",
        source_event_type: "",
        run_id: "run-1",
        realm: "flight",
        data_source_id: "questdb-flight",
        source_binding_id: "binding-flight",
        authority: "unknown"
      })

    assert policy.execution_mode == "event_only"
    assert policy.execution_label == "Event only"
    assert policy.execution_badge_class == "badge-warning badge-outline"
    assert policy.form_params["execution_mode"] == "event_only"
    assert policy.form_params["authority"] == "authoritative"
    assert policy.form_params["reason"] == "dashboard_late_data_policy"
  end

  test "build exposes stable decision and authority options" do
    policy = LateDataPolicyPresentation.build(%{})

    assert policy.decision_options == [
             {"Accept late data", "accept"},
             {"Reject late data", "reject"}
           ]

    assert policy.authority_options == [
             {"Authoritative", "authoritative"},
             {"Advisory", "advisory"},
             {"Comparison", "comparison"}
           ]
  end

  test "controls_available requires source identity and excludes late-data policy events" do
    context = %{
      source_event_id: "event-1",
      source_event_type: "backfill_completed",
      run_id: "run-1",
      realm: "flight",
      data_source_id: "questdb-flight",
      source_binding_id: "binding-flight"
    }

    assert LateDataPolicyPresentation.controls_available?(context)

    refute LateDataPolicyPresentation.controls_available?(%{
             context
             | source_event_type: "late_data_accepted"
           })

    refute LateDataPolicyPresentation.controls_available?(%{context | source_binding_id: ""})
    refute LateDataPolicyPresentation.controls_available?(nil)
  end
end
