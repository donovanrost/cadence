defmodule CadenceWeb.OpsDashboardShowLive.FormComponentsTest do
  use ExUnit.Case, async: true

  import Phoenix.Component, only: [to_form: 2]
  import Phoenix.LiveViewTest, only: [render_component: 2]
  import CadenceWeb.DashboardReviewFixtures

  alias Cadence.Dashboards.{ComparisonReviewQueue, DashboardAction, DataLink, Document}
  alias CadenceWeb.OpsDashboardShowLive.FormComponents
  alias CadenceWeb.OpsDashboardShowLive.LateDataPolicyActionOutcome
  alias CadenceWeb.OpsDashboardShowLive.RevisionDecisionActionOutcome

  test "data link panel renders source context rows and related link controls" do
    related_link = data_link(:telemetry_sample, "sample-1", "Telemetry sample")
    related_link_id = related_link.link_id

    html =
      render_widget_panel(
        &FormComponents.widget_panel/1,
        panel:
          {:data_link,
           %{
             status: :context_only,
             status_text: "context_only",
             title: "Telemetry point",
             target: :telemetry_point,
             target_text: "telemetry point",
             target_id: "HK.counter",
             link_label: "Counter point",
             source: :frame,
             source_text: "frame",
             message: "Telemetry point is not present in the active operator point catalog.",
             rows: [%{label: "Point", value: "HK.counter"}],
             context_rows: [
               %{label: "Data source", value: "questdb-flight"},
               %{label: "Source binding", value: "binding-flight"},
               %{label: "Time mode", value: "live"}
             ],
             related_links: [related_link],
             actions: [telemetry_explore_action()]
           }}
      )

    document = LazyHTML.from_fragment(html)

    assert ["telemetry_point"] =
             document
             |> LazyHTML.query("#dashboard-data-link-inspector")
             |> LazyHTML.attribute("data-data-link-target")

    assert "questdb-flight" =
             document
             |> LazyHTML.query(~s([data-data-link-context="Data source"]))
             |> selected_text()

    assert "binding-flight" =
             document
             |> LazyHTML.query(~s([data-data-link-context="Source binding"]))
             |> selected_text()

    assert ["telemetry sample"] =
             document
             |> LazyHTML.query("[data-data-link-related-target]")
             |> LazyHTML.attribute("data-data-link-related-target")

    assert [^related_link_id] =
             document
             |> LazyHTML.query("[data-data-link-related-ref]")
             |> LazyHTML.attribute("data-data-link-related-ref")

    assert ["open_data_link"] =
             document
             |> LazyHTML.query("[data-data-link-related-ref]")
             |> LazyHTML.attribute("phx-click")

    assert ["questdb-flight"] =
             document
             |> LazyHTML.query("[data-data-link-related-ref]")
             |> LazyHTML.attribute("phx-value-data-source-id")

    assert ["binding-flight"] =
             document
             |> LazyHTML.query("[data-data-link-related-ref]")
             |> LazyHTML.attribute("phx-value-source-binding-id")

    assert ["archive"] =
             document
             |> LazyHTML.query("[data-data-link-related-ref]")
             |> LazyHTML.attribute("phx-value-time-mode")

    assert ["receipt_time"] =
             document
             |> LazyHTML.query("[data-data-link-related-ref]")
             |> LazyHTML.attribute("phx-value-time-axis")

    assert ["telemetry_explore"] =
             document
             |> LazyHTML.query("#dashboard-data-link-explore")
             |> LazyHTML.attribute("data-dashboard-action-target")

    assert ["data_link_panel"] =
             document
             |> LazyHTML.query("#dashboard-data-link-explore")
             |> LazyHTML.attribute("data-dashboard-action-source")

    assert [explore_href] =
             document
             |> LazyHTML.query("#dashboard-data-link-explore")
             |> LazyHTML.attribute("href")

    assert explore_href =~ "/missions/mission-1/ops/telemetry/explore"
    assert explore_href =~ "point_id=HK.counter"
    assert explore_href =~ "sample_id=sample-1"
    assert explore_href =~ "realm=flight"
    assert explore_href =~ "data_source_id=questdb-flight"
    assert explore_href =~ "source_binding_id=binding-flight"
    assert explore_href =~ "source_dashboard_id=dashboard-1"
  end

  test "data link panel renders revision decision controls for revision decision events" do
    html =
      render_widget_panel(
        &FormComponents.widget_panel/1,
        data_link_action_outcome:
          RevisionDecisionActionOutcome.new(
            status: :ok,
            kind: :info,
            reason: "revision_decision_applied",
            decision: "mark_conflict",
            result_event_id: "decision-event-applied",
            target_event_id: "decision-event-applied",
            target_observation_identity_id: "identity-1",
            dashboard_limit_mode: "compare",
            message: "Telemetry revision decision applied."
          ),
        panel:
          {:data_link,
           %{
             status: :resolved,
             status_text: "resolved",
             title: "Telemetry revision decision event",
             target: :telemetry_revision_decision_event,
             target_text: "telemetry revision decision event",
             target_id: "decision-event-1",
             link_label: "Telemetry revision decision event",
             source: :annotation,
             source_text: "annotation",
             message: nil,
             rows: [
               %{label: "Revision decision event", value: "decision-event-1"},
               %{label: "Observation identity", value: "identity-1"},
               %{label: "Decision", value: "mark_advisory"},
               %{label: "Decision reason", value: "prior_review"},
               %{label: "Realm", value: "flight"},
               %{label: "Data source", value: "questdb-flight"},
               %{label: "Source binding", value: "binding-flight"},
               %{label: "New canonical observation", value: "observation-2"},
               %{label: "New canonical sample", value: "sample-2"},
               %{label: "New canonical revision", value: 2}
             ],
             context_rows: [%{label: "Limit mode", value: "compare"}],
             related_links: [],
             actions: []
           }}
      )

    document = LazyHTML.from_fragment(html)

    assert ["identity-1"] =
             document
             |> LazyHTML.query("#dashboard-revision-decision-controls")
             |> LazyHTML.attribute("data-revision-decision-observation-identity")

    assert ["ok"] =
             document
             |> LazyHTML.query("#dashboard-revision-decision-action-outcome")
             |> LazyHTML.attribute("data-revision-decision-action-status")

    assert ["revision_decision"] =
             document
             |> LazyHTML.query("#dashboard-data-link-action-outcome")
             |> LazyHTML.attribute("data-data-link-action-outcome-action")

    assert %{
             "decision" => "mark_conflict",
             "dashboard_limit_mode" => "compare",
             "result_event_id" => "decision-event-applied",
             "target_event_id" => "decision-event-applied",
             "target_observation_identity_id" => "identity-1"
           } =
             document
             |> LazyHTML.query("#dashboard-data-link-action-outcome")
             |> LazyHTML.attribute("data-data-link-action-outcome-metadata")
             |> List.first()
             |> Jason.decode!()

    assert ["mark_conflict"] =
             document
             |> LazyHTML.query("#dashboard-revision-decision-action-outcome")
             |> LazyHTML.attribute("data-revision-decision-action-decision")

    assert ["compare"] =
             document
             |> LazyHTML.query("#dashboard-revision-decision-action-outcome")
             |> LazyHTML.attribute("data-revision-decision-action-dashboard-limit-mode")

    assert ["decision-event-applied"] =
             document
             |> LazyHTML.query("#dashboard-revision-decision-action-outcome")
             |> LazyHTML.attribute("data-revision-decision-action-result-event-id")

    assert ["removes this identity from canonical reads until resolved"] =
             document
             |> LazyHTML.query("#dashboard-revision-decision-controls")
             |> LazyHTML.attribute("data-revision-decision-default-effect")

    assert ["apply_revision_decision"] =
             document
             |> LazyHTML.query("#dashboard-revision-decision-form")
             |> LazyHTML.attribute("phx-submit")

    assert "removes this identity from canonical reads until resolved" =
             document
             |> LazyHTML.query(~s([data-revision-decision-effect-summary="mark_conflict"]))
             |> selected_text()

    assert "sets this identity canonical for default dashboard reads" =
             document
             |> LazyHTML.query(~s([data-revision-decision-effect-summary="mark_canonical"]))
             |> selected_text()

    assert "marks this identity superseded by a correction" =
             document
             |> LazyHTML.query(~s([data-revision-decision-effect-summary="mark_superseded"]))
             |> selected_text()

    assert "keeps this identity as advisory history only" =
             document
             |> LazyHTML.query(~s([data-revision-decision-effect-summary="mark_advisory"]))
             |> selected_text()

    assert "Apply revision decision" =
             document
             |> LazyHTML.query("#dashboard-revision-decision-submit")
             |> selected_text()

    assert ["identity-1"] =
             document
             |> LazyHTML.query("#dashboard-revision-decision-observation-identity-id")
             |> LazyHTML.attribute("value")

    assert ["decision-event-1"] =
             document
             |> LazyHTML.query("#dashboard-revision-decision-source-event-id")
             |> LazyHTML.attribute("value")

    assert ["flight"] =
             document
             |> LazyHTML.query(~s(input[name="revision_decision[realm]"]))
             |> LazyHTML.attribute("value")

    assert ["questdb-flight"] =
             document
             |> LazyHTML.query(~s(input[name="revision_decision[data_source_id]"]))
             |> LazyHTML.attribute("value")

    assert ["binding-flight"] =
             document
             |> LazyHTML.query(~s(input[name="revision_decision[source_binding_id]"]))
             |> LazyHTML.attribute("value")

    assert ["compare"] =
             document
             |> LazyHTML.query("#dashboard-revision-decision-dashboard-limit-mode")
             |> LazyHTML.attribute("value")

    assert ["observation-2"] =
             document
             |> LazyHTML.query(~s(input[name="revision_decision[canonical_observation_id]"]))
             |> LazyHTML.attribute("value")

    assert ["sample-2"] =
             document
             |> LazyHTML.query(~s(input[name="revision_decision[canonical_sample_id]"]))
             |> LazyHTML.attribute("value")

    assert ["2"] =
             document
             |> LazyHTML.query(~s(input[name="revision_decision[canonical_revision]"]))
             |> LazyHTML.attribute("value")
  end

  test "data link panel renders revision decision controls for comparison findings with identity context" do
    html =
      render_widget_panel(
        &FormComponents.widget_panel/1,
        panel:
          {:data_link,
           %{
             status: :context_only,
             status_text: "context_only",
             title: "Comparison finding",
             target: :comparison_finding,
             target_text: "comparison finding",
             target_id: "placement-1",
             link_label: "Comparison finding",
             source: :annotation,
             source_text: "annotation",
             message: "Comparison finding is derived from the current dashboard runtime context.",
             rows: [
               %{label: "Comparison finding", value: "placement-1"},
               %{label: "State", value: "increased"},
               %{label: "Delta", value: "+2"},
               %{label: "Primary sample", value: "sample-primary-1"},
               %{label: "Compare sample", value: "sample-compare-1"},
               %{label: "Primary data view", value: "all_revisions"},
               %{label: "Compare data view", value: "canonical"},
               %{label: "Observation identity", value: "identity-primary-1"},
               %{label: "Realm", value: "flight"},
               %{label: "Data source", value: "questdb-flight"},
               %{label: "Source binding", value: "binding-flight"},
               %{label: "Decision reason", value: "dashboard_comparison_finding"},
               %{label: "Correction authority", value: "comparison"},
               %{label: "New canonical observation", value: "observation-primary-1"},
               %{label: "New canonical sample", value: "sample-primary-1"},
               %{label: "New canonical revision", value: "2"}
             ],
             context_rows: [],
             related_links: [],
             actions: []
           }}
      )

    document = LazyHTML.from_fragment(html)

    assert ["identity-primary-1"] =
             document
             |> LazyHTML.query("#dashboard-revision-decision-controls")
             |> LazyHTML.attribute("data-revision-decision-observation-identity")

    assert ["identity-primary-1"] =
             document
             |> LazyHTML.query("#dashboard-revision-decision-observation-identity-id")
             |> LazyHTML.attribute("value")

    assert ["comparison"] =
             document
             |> LazyHTML.query(~s(input[name="revision_decision[authority]"]))
             |> LazyHTML.attribute("value")

    assert ["dashboard_comparison_finding"] =
             document
             |> LazyHTML.query(~s(input[name="revision_decision[decision_reason]"]))
             |> LazyHTML.attribute("value")

    assert ["sample-primary-1"] =
             document
             |> LazyHTML.query(~s(input[name="revision_decision[canonical_sample_id]"]))
             |> LazyHTML.attribute("value")

    assert ["comparison_finding"] =
             document
             |> LazyHTML.query("#dashboard-revision-decision-source-target")
             |> LazyHTML.attribute("value")

    assert ["placement-1"] =
             document
             |> LazyHTML.query("#dashboard-revision-decision-source-target-id")
             |> LazyHTML.attribute("value")

    assert ["Comparison finding"] =
             document
             |> LazyHTML.query("#dashboard-revision-decision-source-link-label")
             |> LazyHTML.attribute("value")

    assert ["increased"] =
             document
             |> LazyHTML.query("#dashboard-revision-decision-comparison-state")
             |> LazyHTML.attribute("value")

    assert ["+2"] =
             document
             |> LazyHTML.query("#dashboard-revision-decision-comparison-delta")
             |> LazyHTML.attribute("value")

    assert ["sample-primary-1"] =
             document
             |> LazyHTML.query("#dashboard-revision-decision-primary-sample")
             |> LazyHTML.attribute("value")

    assert ["sample-compare-1"] =
             document
             |> LazyHTML.query("#dashboard-revision-decision-compare-sample")
             |> LazyHTML.attribute("value")
  end

  test "data link panel renders late-data policy controls for lifecycle events" do
    html =
      render_widget_panel(
        &FormComponents.widget_panel/1,
        data_link_action_outcome:
          LateDataPolicyActionOutcome.new(
            status: :ok,
            kind: :info,
            reason: "late_data_policy_applied",
            decision: "accept",
            execution_mode: "event_only",
            dashboard_time_mode: "replay_run",
            dashboard_replay_run_id: "replay-1",
            dashboard_limit_mode: "compare",
            result_event_id: "late-data-event-1",
            target_event_id: "late-data-event-1",
            target_run_id: "backfill-run-1",
            message: "Late-data policy applied."
          ),
        panel:
          {:data_link,
           %{
             status: :resolved,
             status_text: "resolved",
             title: "Telemetry backfill lifecycle event",
             target: :telemetry_backfill_lifecycle_event,
             target_text: "telemetry backfill lifecycle event",
             target_id: "backfill-event-1",
             link_label: "Telemetry backfill lifecycle event",
             source: :frame,
             source_text: "frame",
             message: nil,
             rows: [
               %{label: "Backfill lifecycle event", value: "backfill-event-1"},
               %{label: "Backfill run", value: "backfill-run-1"},
               %{label: "Event type", value: "backfill_completed"},
               %{label: "Workflow", value: "backfill"},
               %{label: "Workflow stage", value: "completed"},
               %{label: "Workflow run", value: "backfill-run-1"},
               %{label: "Dashboard context time mode", value: "replay_run"},
               %{label: "Dashboard context replay run", value: "replay-1"},
               %{label: "Realm", value: "flight"},
               %{label: "Data source", value: "questdb-flight"},
               %{label: "Source binding", value: "binding-flight"},
               %{label: "Observable", value: "HK.counter"},
               %{label: "Point", value: "HK.counter"},
               %{label: "Source from", value: "2026-06-22T10:00:00Z"},
               %{label: "Source to", value: "2026-06-22T11:00:00Z"},
               %{label: "Receipt from", value: "2026-06-22T12:00:00Z"},
               %{label: "Receipt to", value: "2026-06-22T12:10:00Z"},
               %{label: "Sample count", value: "3"},
               %{label: "Authority", value: "authoritative"},
               %{label: "Reason", value: "operator_backfill"}
             ],
             context_rows: [
               %{label: "Limit mode", value: "compare"}
             ],
             related_links: [],
             actions: []
           }}
      )

    document = LazyHTML.from_fragment(html)

    assert ["backfill_completed"] =
             document
             |> LazyHTML.query("#dashboard-workflow-explanation")
             |> LazyHTML.attribute("data-workflow-explanation-event-type")

    assert ["completed"] =
             document
             |> LazyHTML.query("#dashboard-workflow-explanation")
             |> LazyHTML.attribute("data-workflow-explanation-state")

    assert "backfill-run-1" =
             document
             |> LazyHTML.query(~s([data-workflow-explanation-field="Run"]))
             |> selected_text()

    assert ["backfill-event-1"] =
             document
             |> LazyHTML.query("#dashboard-late-data-policy-controls")
             |> LazyHTML.attribute("data-late-data-policy-source-event")

    assert ["event_only"] =
             document
             |> LazyHTML.query("#dashboard-late-data-policy-controls")
             |> LazyHTML.attribute("data-late-data-policy-execution-mode")

    assert ["auditable policy decision; telemetry projections unchanged"] =
             document
             |> LazyHTML.query("#dashboard-late-data-policy-controls")
             |> LazyHTML.attribute("data-late-data-policy-accept-effect")

    assert ["advisory history only; current/latest projections unchanged"] =
             document
             |> LazyHTML.query("#dashboard-late-data-policy-controls")
             |> LazyHTML.attribute("data-late-data-policy-reject-effect")

    assert ["record_late_data_policy_decision"] =
             document
             |> LazyHTML.query("#dashboard-late-data-policy-form")
             |> LazyHTML.attribute("phx-submit")

    assert "Event only" =
             document
             |> LazyHTML.query("#dashboard-late-data-policy-controls .badge-warning")
             |> selected_text()

    assert "auditable policy decision; telemetry projections unchanged" =
             document
             |> LazyHTML.query(~s([data-late-data-policy-effect-summary="accept"]))
             |> selected_text()

    assert "advisory history only; current/latest projections unchanged" =
             document
             |> LazyHTML.query(~s([data-late-data-policy-effect-summary="reject"]))
             |> selected_text()

    assert "Apply late-data policy" =
             document
             |> LazyHTML.query("#dashboard-late-data-policy-submit")
             |> selected_text()

    assert ["backfill-event-1"] =
             document
             |> LazyHTML.query("#dashboard-late-data-policy-source-event-id")
             |> LazyHTML.attribute("value")

    assert ["backfill_completed"] =
             document
             |> LazyHTML.query("#dashboard-late-data-policy-source-event-type")
             |> LazyHTML.attribute("value")

    assert ["backfill-run-1"] =
             document
             |> LazyHTML.query("#dashboard-late-data-policy-run-id")
             |> LazyHTML.attribute("value")

    assert ["compare"] =
             document
             |> LazyHTML.query("#dashboard-late-data-policy-dashboard-limit-mode")
             |> LazyHTML.attribute("value")

    assert ["replay_run"] =
             document
             |> LazyHTML.query("#dashboard-late-data-policy-dashboard-time-mode")
             |> LazyHTML.attribute("value")

    assert ["replay-1"] =
             document
             |> LazyHTML.query("#dashboard-late-data-policy-dashboard-replay-run-id")
             |> LazyHTML.attribute("value")

    assert ["questdb-flight"] =
             document
             |> LazyHTML.query("#dashboard-late-data-policy-data-source-id")
             |> LazyHTML.attribute("value")

    assert ["binding-flight"] =
             document
             |> LazyHTML.query("#dashboard-late-data-policy-source-binding-id")
             |> LazyHTML.attribute("value")

    assert ["3"] =
             document
             |> LazyHTML.query("#dashboard-late-data-policy-sample-count")
             |> LazyHTML.attribute("value")

    assert ["ok"] =
             document
             |> LazyHTML.query("#dashboard-late-data-policy-action-outcome")
             |> LazyHTML.attribute("data-late-data-policy-action-status")

    assert ["compare"] =
             document
             |> LazyHTML.query("#dashboard-late-data-policy-action-outcome")
             |> LazyHTML.attribute("data-late-data-policy-action-dashboard-limit-mode")

    assert ["replay_run"] =
             document
             |> LazyHTML.query("#dashboard-late-data-policy-action-outcome")
             |> LazyHTML.attribute("data-late-data-policy-action-dashboard-time-mode")

    assert ["replay-1"] =
             document
             |> LazyHTML.query("#dashboard-late-data-policy-action-outcome")
             |> LazyHTML.attribute("data-late-data-policy-action-dashboard-replay-run-id")

    assert ["late_data_policy"] =
             document
             |> LazyHTML.query("#dashboard-data-link-action-outcome")
             |> LazyHTML.attribute("data-data-link-action-outcome-action")

    assert %{
             "decision" => "accept",
             "execution_mode" => "event_only",
             "dashboard_time_mode" => "replay_run",
             "dashboard_replay_run_id" => "replay-1",
             "dashboard_limit_mode" => "compare",
             "result_event_id" => "late-data-event-1",
             "target_event_id" => "late-data-event-1",
             "target_run_id" => "backfill-run-1"
           } =
             document
             |> LazyHTML.query("#dashboard-data-link-action-outcome")
             |> LazyHTML.attribute("data-data-link-action-outcome-metadata")
             |> List.first()
             |> Jason.decode!()

    assert ["accept"] =
             document
             |> LazyHTML.query("#dashboard-late-data-policy-action-outcome")
             |> LazyHTML.attribute("data-late-data-policy-action-decision")

    assert ["late-data-event-1"] =
             document
             |> LazyHTML.query("#dashboard-late-data-policy-action-outcome")
             |> LazyHTML.attribute("data-late-data-policy-action-result-event-id")
  end

  test "late-data policy controls mark event-only decisions without source sample identity" do
    html =
      render_widget_panel(
        &FormComponents.widget_panel/1,
        panel:
          {:data_link,
           %{
             status: :resolved,
             status_text: "resolved",
             title: "Telemetry backfill lifecycle event",
             target: :telemetry_backfill_lifecycle_event,
             target_text: "telemetry backfill lifecycle event",
             target_id: "backfill-event-1",
             link_label: "Telemetry backfill lifecycle event",
             source: :frame,
             source_text: "frame",
             message: nil,
             rows: [
               %{label: "Backfill lifecycle event", value: "backfill-event-1"},
               %{label: "Backfill run", value: "backfill-run-1"},
               %{label: "Event type", value: "backfill_completed"},
               %{label: "Realm", value: "flight"},
               %{label: "Data source", value: "questdb-flight"},
               %{label: "Source binding", value: "binding-flight"}
             ],
             context_rows: [],
             related_links: [],
             actions: []
           }}
      )

    document = LazyHTML.from_fragment(html)

    assert ["event_only"] =
             document
             |> LazyHTML.query("#dashboard-late-data-policy-controls")
             |> LazyHTML.attribute("data-late-data-policy-execution-mode")

    assert "Event only" =
             document
             |> LazyHTML.query("#dashboard-late-data-policy-controls .badge-warning")
             |> selected_text()
  end

  test "data link panel explains failed lifecycle events that require correction" do
    html =
      render_widget_panel(
        &FormComponents.widget_panel/1,
        panel:
          {:data_link,
           %{
             status: :resolved,
             status_text: "resolved",
             title: "Telemetry backfill lifecycle event",
             target: :telemetry_backfill_lifecycle_event,
             target_text: "telemetry backfill lifecycle event",
             target_id: "failed-event-1",
             link_label: "Telemetry backfill lifecycle event",
             source: :frame,
             source_text: "frame",
             message: nil,
             rows: [
               %{label: "Backfill lifecycle event", value: "failed-event-1"},
               %{label: "Backfill run", value: "failed-run-1"},
               %{label: "Event type", value: "backfill_failed"},
               %{label: "Workflow", value: "backfill"},
               %{label: "Workflow stage", value: "failed"},
               %{label: "Workflow run", value: "failed-run-1"},
               %{label: "Dashboard context", value: "dashboard-1"},
               %{label: "Dashboard context version", value: "7"},
               %{label: "Dashboard context time mode", value: "replay_run"},
               %{label: "Dashboard context replay run", value: "replay-1"},
               %{label: "Dashboard context data view", value: "all_revisions"},
               %{label: "Dashboard context limit mode", value: "observed"},
               %{label: "Realm", value: "backfill"},
               %{label: "Data source", value: "managed_questdb_backfill"},
               %{label: "Source binding", value: "backfill_telemetry"},
               %{label: "Workflow failure code", value: "missing_field:point_id"},
               %{label: "Workflow retryable", value: "false"},
               %{label: "Workflow retry blockers", value: "missing point_id"},
               %{label: "Workflow recovery action", value: "correct_workflow_request"},
               %{label: "Workflow source data source", value: "managed_questdb_backfill"},
               %{label: "Workflow source binding", value: "backfill_telemetry"},
               %{label: "Workflow source from", value: "2026-06-22T10:00:00Z"},
               %{label: "Workflow source to", value: "2026-06-22T11:00:00Z"},
               %{label: "Request group", value: "group-1"},
               %{label: "Request group state", value: "failed"},
               %{label: "Request group progress", value: "0/1"},
               %{label: "Workflow job", value: "job-1"},
               %{label: "Workflow job status", value: "failed"}
             ],
             context_rows: [],
             related_links: [],
             actions: []
           }}
      )

    document = LazyHTML.from_fragment(html)

    assert ["failed_correction_required"] =
             document
             |> LazyHTML.query("#dashboard-workflow-explanation")
             |> LazyHTML.attribute("data-workflow-explanation-state")

    assert ["error"] =
             document
             |> LazyHTML.query("#dashboard-workflow-explanation")
             |> LazyHTML.attribute("data-workflow-explanation-severity")

    assert document
           |> LazyHTML.query("#dashboard-workflow-explanation-summary")
           |> selected_text() =~ "needs a corrected request"

    assert "correct_workflow_request" =
             document
             |> LazyHTML.query(~s([data-workflow-explanation-field="Recovery"]))
             |> selected_text()

    assert "group-1 failed" =
             document
             |> LazyHTML.query(~s([data-workflow-explanation-field="Group"]))
             |> selected_text()

    assert ["dashboard-1"] =
             document
             |> LazyHTML.query("#dashboard-historical-workflow-correction-dashboard-id")
             |> LazyHTML.attribute("value")

    assert ["replay-1"] =
             document
             |> LazyHTML.query(
               "#dashboard-historical-workflow-correction-dashboard-replay-run-id"
             )
             |> LazyHTML.attribute("value")

    assert ["observed"] =
             document
             |> LazyHTML.query("#dashboard-historical-workflow-correction-dashboard-limit-mode")
             |> LazyHTML.attribute("value")
  end

  test "data link panel does not render late-data policy controls for policy events" do
    html =
      render_widget_panel(
        &FormComponents.widget_panel/1,
        panel:
          {:data_link,
           %{
             status: :resolved,
             status_text: "resolved",
             title: "Telemetry backfill lifecycle event",
             target: :telemetry_backfill_lifecycle_event,
             target_text: "telemetry backfill lifecycle event",
             target_id: "late-event-1",
             link_label: "Telemetry backfill lifecycle event",
             source: :frame,
             source_text: "frame",
             message: nil,
             rows: [
               %{label: "Backfill lifecycle event", value: "late-event-1"},
               %{label: "Backfill run", value: "backfill-run-1"},
               %{label: "Event type", value: "late_data_accepted"},
               %{label: "Late data policy decision", value: "accept"},
               %{label: "Late data source event", value: "backfill-event-1"},
               %{label: "Late data selected samples", value: "2"},
               %{label: "Late data write validity", value: "canonical"},
               %{
                 label: "Late data projection effect",
                 value: "canonical_history_and_current_projection"
               },
               %{label: "Realm", value: "flight"},
               %{label: "Data source", value: "questdb-flight"},
               %{label: "Source binding", value: "binding-flight"}
             ],
             context_rows: [],
             related_links: [],
             actions: []
           }}
      )

    document = LazyHTML.from_fragment(html)

    assert ["late_data_accepted"] =
             document
             |> LazyHTML.query("#dashboard-workflow-explanation")
             |> LazyHTML.attribute("data-workflow-explanation-state")

    assert "backfill-event-1" =
             document
             |> LazyHTML.query(~s([data-workflow-explanation-field="Policy source"]))
             |> selected_text()

    assert "accept" =
             document
             |> LazyHTML.query(~s([data-workflow-explanation-field="Policy"]))
             |> selected_text()

    assert "2" =
             document
             |> LazyHTML.query(~s([data-workflow-explanation-field="Selected samples"]))
             |> selected_text()

    assert "canonical_history_and_current_projection" =
             document
             |> LazyHTML.query(~s([data-workflow-explanation-field="Projection"]))
             |> selected_text()

    assert "canonical" =
             document
             |> LazyHTML.query(~s([data-workflow-explanation-field="Write validity"]))
             |> selected_text()

    assert [] =
             document
             |> LazyHTML.query("#dashboard-late-data-policy-controls")
             |> LazyHTML.attribute("id")
  end

  test "evidence panel renders source detail rows and evidence data-link controls" do
    link = evidence_link(:telemetry_point, "HK.counter", "Telemetry point")
    link_id = link.link_id

    html =
      render_widget_panel(
        &FormComponents.widget_panel/1,
        panel:
          {:evidence,
           %{
             kind: :source,
             kind_text: "source",
             subject: "request-1",
             status: :resolved,
             status_text: "resolved",
             title: "Source evidence",
             message: nil,
             subject_rows: [%{label: "Source request", value: "request-1"}],
             detail_rows: [
               %{label: "Data source", value: "questdb-flight"},
               %{label: "Source binding", value: "binding-flight"}
             ],
             evidence: [],
             links: [link],
             actions: [telemetry_explore_action(), source_inventory_action()]
           }}
      )

    document = LazyHTML.from_fragment(html)

    assert ["source"] =
             document
             |> LazyHTML.query("#dashboard-evidence-inspector")
             |> LazyHTML.attribute("data-evidence-kind")

    assert "questdb-flight" =
             document
             |> LazyHTML.query(~s([data-evidence-detail="Data source"]))
             |> selected_text()

    assert "binding-flight" =
             document
             |> LazyHTML.query(~s([data-evidence-detail="Source binding"]))
             |> selected_text()

    assert ["telemetry point"] =
             document
             |> LazyHTML.query("[data-evidence-link-target]")
             |> LazyHTML.attribute("data-evidence-link-target")

    assert [^link_id] =
             document
             |> LazyHTML.query("[data-evidence-link-ref]")
             |> LazyHTML.attribute("data-evidence-link-ref")

    assert ["open_data_link"] =
             document
             |> LazyHTML.query("[data-evidence-link-ref]")
             |> LazyHTML.attribute("phx-click")

    assert ["questdb-flight"] =
             document
             |> LazyHTML.query("[data-evidence-link-ref]")
             |> LazyHTML.attribute("phx-value-data-source-id")

    assert ["binding-flight"] =
             document
             |> LazyHTML.query("[data-evidence-link-ref]")
             |> LazyHTML.attribute("phx-value-source-binding-id")

    assert ["archive"] =
             document
             |> LazyHTML.query("[data-evidence-link-ref]")
             |> LazyHTML.attribute("phx-value-time-mode")

    assert ["receipt_time"] =
             document
             |> LazyHTML.query("[data-evidence-link-ref]")
             |> LazyHTML.attribute("phx-value-time-axis")

    assert ["telemetry_explore"] =
             document
             |> LazyHTML.query("#dashboard-evidence-explore")
             |> LazyHTML.attribute("data-dashboard-action-target")

    assert ["evidence_panel"] =
             document
             |> LazyHTML.query("#dashboard-evidence-explore")
             |> LazyHTML.attribute("data-dashboard-action-source")

    assert [explore_href] =
             document
             |> LazyHTML.query("#dashboard-evidence-explore")
             |> LazyHTML.attribute("href")

    assert explore_href =~ "/missions/mission-1/ops/telemetry/explore"
    assert explore_href =~ "point_id=HK.counter"
    assert explore_href =~ "sample_id=sample-1"
    assert explore_href =~ "realm=flight"
    assert explore_href =~ "data_source_id=questdb-flight"
    assert explore_href =~ "source_binding_id=binding-flight"
    assert explore_href =~ "source_dashboard_id=dashboard-1"

    assert ["source_inventory"] =
             document
             |> LazyHTML.query("#dashboard-evidence-source-inventory")
             |> LazyHTML.attribute("data-dashboard-action-target")

    assert ["evidence_panel"] =
             document
             |> LazyHTML.query("#dashboard-evidence-source-inventory")
             |> LazyHTML.attribute("data-dashboard-action-source")

    assert [source_inventory_href] =
             document
             |> LazyHTML.query("#dashboard-evidence-source-inventory")
             |> LazyHTML.attribute("href")

    assert source_inventory_href =~ "/missions/mission-1/ops/data-sources"
    assert source_inventory_href =~ "realm=flight"
    assert source_inventory_href =~ "data_source_id=questdb-flight"
    assert source_inventory_href =~ "source_binding_id=binding-flight"
    assert source_inventory_href =~ "source_dashboard_id=dashboard-1"
  end

  test "evidence panel links dashboard health evidence to captured activity" do
    event =
      lifecycle_event(
        "dashboard-lifecycle-event-health",
        :health_snapshot_captured,
        payload: %{
          "schema" => "dashboard_health_snapshot_capture.v1",
          "snapshot_id" => "dashboard_health_snapshot_abc123",
          "snapshot_schema" => "dashboard_health_snapshot.v1"
        }
      )

    html =
      render_widget_panel(
        &FormComponents.widget_panel/1,
        panel:
          {:evidence,
           %{
             kind: :dashboard_health,
             kind_text: "dashboard health",
             subject: "dashboard health blocked",
             status: :blocked,
             status_text: "blocked",
             title: "Dashboard Health Evidence",
             message: "Captured dashboard health rollup for sharing and investigation.",
             subject_rows: [
               %{label: "Health snapshot schema", value: "dashboard_health_snapshot.v1"},
               %{label: "Health snapshot", value: "dashboard_health_snapshot_abc123"}
             ],
             detail_rows: [%{label: "Affected widgets", value: "3"}],
             evidence: [],
             links: [],
             actions: []
           }},
        dashboard_lifecycle_events: [event],
        dashboard_current_path:
          "/missions/mission-1/ops/dashboards/dashboard-1?scope_kind=mission&scope_id=mission-1&selected_placement=placement-stale"
      )

    document = LazyHTML.from_fragment(html)

    assert ["dashboard-lifecycle-event-health"] =
             document
             |> LazyHTML.query("#dashboard-evidence-health-activity-link")
             |> LazyHTML.attribute("data-dashboard-health-activity-link")

    assert ["dashboard_health_snapshot_abc123"] =
             document
             |> LazyHTML.query("#dashboard-evidence-health-activity-link")
             |> LazyHTML.attribute("data-dashboard-health-activity-snapshot-id")

    assert [href] =
             document
             |> LazyHTML.query("#dashboard-evidence-health-activity-link")
             |> LazyHTML.attribute("href")

    uri = URI.parse(href)

    assert uri.path == "/missions/mission-1/ops/dashboards/dashboard-1"

    assert URI.decode_query(uri.query) == %{
             "scope_kind" => "mission",
             "scope_id" => "mission-1",
             "panel" => "versions",
             "activity_filter" => "health_snapshots",
             "activity_event" => "dashboard-lifecycle-event-health"
           }
  end

  test "evidence panel data links fall back to warning source context" do
    link = evidence_link_without_context(:telemetry_point, "HK.counter", "Telemetry point")

    html =
      render_widget_panel(
        &FormComponents.widget_panel/1,
        panel:
          {:evidence,
           %{
             kind: :warning,
             kind_text: "warning",
             subject: "source_degraded",
             status: :warning,
             status_text: "warning",
             title: "Source degraded",
             message: nil,
             subject_rows: [%{label: "Warning", value: "source_degraded"}],
             detail_rows: [],
             source_context: %{
               realm: "flight",
               data_view: "canonical",
               data_source_id: "questdb-flight",
               source_binding_id: "binding-flight",
               time_mode: "archive",
               time_axis: "receipt_time",
               replay_run_id: "replay-1"
             },
             evidence: [],
             links: [link],
             actions: []
           }}
      )

    document = LazyHTML.from_fragment(html)

    assert ["flight"] =
             document
             |> LazyHTML.query("[data-evidence-link-ref]")
             |> LazyHTML.attribute("phx-value-realm")

    assert ["canonical"] =
             document
             |> LazyHTML.query("[data-evidence-link-ref]")
             |> LazyHTML.attribute("phx-value-data-view")

    assert ["questdb-flight"] =
             document
             |> LazyHTML.query("[data-evidence-link-ref]")
             |> LazyHTML.attribute("phx-value-data-source-id")

    assert ["binding-flight"] =
             document
             |> LazyHTML.query("[data-evidence-link-ref]")
             |> LazyHTML.attribute("phx-value-source-binding-id")

    assert ["archive"] =
             document
             |> LazyHTML.query("[data-evidence-link-ref]")
             |> LazyHTML.attribute("phx-value-time-mode")

    assert ["receipt_time"] =
             document
             |> LazyHTML.query("[data-evidence-link-ref]")
             |> LazyHTML.attribute("phx-value-time-axis")

    assert ["replay-1"] =
             document
             |> LazyHTML.query("[data-evidence-link-ref]")
             |> LazyHTML.attribute("phx-value-replay-run-id")
  end

  test "versions panel renders comparison review request activity details" do
    event =
      comparison_review_request_event(
        event_id: "dashboard-lifecycle-event-1",
        actor_id: "user-reviewer",
        placement_ids: ["placement-1", "placement-2"]
      )

    html =
      render_widget_panel(&FormComponents.widget_panel/1,
        panel: :versions,
        dashboard_review_placement_id: "placement-1",
        dashboard_lifecycle_events: [event],
        dashboard_comparison_review_queue: ComparisonReviewQueue.open_summary([event])
      )

    document = LazyHTML.from_fragment(html)

    assert ["comparison_review_requested"] =
             document
             |> LazyHTML.query("#dashboard-activity-dashboard-lifecycle-event-1")
             |> LazyHTML.attribute("data-lifecycle-event-type")

    assert ["1"] =
             document
             |> LazyHTML.query("#dashboard-activity-section")
             |> LazyHTML.attribute("data-dashboard-comparison-review-open-count")

    assert [""] =
             document
             |> LazyHTML.query("#dashboard-activity-section")
             |> LazyHTML.attribute("data-dashboard-activity-filter")

    assert ["placement-1"] =
             document
             |> LazyHTML.query("#dashboard-activity-section")
             |> LazyHTML.attribute("data-dashboard-review-selected-placement")

    assert ["dashboard-lifecycle-event-1"] =
             document
             |> LazyHTML.query("#dashboard-activity-section")
             |> LazyHTML.attribute("data-dashboard-comparison-review-open-requests")

    assert ["placement-1,placement-2"] =
             document
             |> LazyHTML.query("#dashboard-activity-section")
             |> LazyHTML.attribute("data-dashboard-comparison-review-open-placements")

    assert "1 open reviews" =
             document
             |> LazyHTML.query("[data-dashboard-comparison-review-open-badge]")
             |> selected_text()

    assert "Comparison review requested" =
             document
             |> LazyHTML.query("#dashboard-activity-dashboard-lifecycle-event-1 .font-semibold")
             |> selected_text()

    assert ["dashboard_comparison_review_request.v1"] =
             document
             |> LazyHTML.query("[data-dashboard-comparison-review-request]")
             |> LazyHTML.attribute("data-dashboard-comparison-review-schema")

    assert ["open"] =
             document
             |> LazyHTML.query("[data-dashboard-comparison-review-request]")
             |> LazyHTML.attribute("data-dashboard-comparison-review-status")

    assert ["dashboard-lifecycle-event-1"] =
             document
             |> LazyHTML.query("[data-dashboard-comparison-review-resolve-form]")
             |> LazyHTML.attribute("data-dashboard-comparison-review-resolve-form")

    assert ["resolve_comparison_review"] =
             document
             |> LazyHTML.query("[data-dashboard-comparison-review-resolve-form]")
             |> LazyHTML.attribute("phx-submit")

    assert ["dashboard-lifecycle-event-1"] =
             document
             |> LazyHTML.query(~s(input[name="review[source_request_event_id]"]))
             |> LazyHTML.attribute("value")

    assert ["placement-1"] =
             document
             |> LazyHTML.query(~s(input[name="review[selected_placement_id]"]))
             |> LazyHTML.attribute("value")

    assert ["placement-1,placement-2"] =
             document
             |> LazyHTML.query(~s(input[name="review[affected_placement_ids]"]))
             |> LazyHTML.attribute("value")

    assert ["dashboard-lifecycle-event-1"] =
             document
             |> LazyHTML.query("[data-dashboard-comparison-review-resolution-reason]")
             |> LazyHTML.attribute("data-dashboard-comparison-review-resolution-reason")

    assert ["240"] =
             document
             |> LazyHTML.query("[data-dashboard-comparison-review-resolution-reason]")
             |> LazyHTML.attribute("maxlength")

    assert ["comparison_open_findings_review"] =
             document
             |> LazyHTML.query("[data-dashboard-comparison-review-request]")
             |> LazyHTML.attribute("data-dashboard-comparison-review-kind")

    assert ["2"] =
             document
             |> LazyHTML.query("[data-dashboard-comparison-review-request]")
             |> LazyHTML.attribute("data-dashboard-comparison-review-open-count")

    assert ["placement-1,placement-2"] =
             document
             |> LazyHTML.query("[data-dashboard-comparison-review-request]")
             |> LazyHTML.attribute("data-dashboard-comparison-review-placements")

    assert ["placement-1", "placement-2"] =
             document
             |> LazyHTML.query("[data-dashboard-comparison-review-placement-link]")
             |> LazyHTML.attribute("data-dashboard-comparison-review-placement-link")

    assert ["#widget-placement-1", "#widget-placement-2"] =
             document
             |> LazyHTML.query("[data-dashboard-comparison-review-placement-link]")
             |> LazyHTML.attribute("href")

    assert ["select_review_placement", "select_review_placement"] =
             document
             |> LazyHTML.query("[data-dashboard-comparison-review-placement-link]")
             |> LazyHTML.attribute("phx-click")

    assert ["placement-1", "placement-2"] =
             document
             |> LazyHTML.query("[data-dashboard-comparison-review-placement-link]")
             |> LazyHTML.attribute("phx-value-placement-id")

    assert ["true", "false"] =
             document
             |> LazyHTML.query("[data-dashboard-comparison-review-placement-link]")
             |> LazyHTML.attribute("data-dashboard-review-placement-selected")

    assert ["2"] =
             document
             |> LazyHTML.query("[data-dashboard-comparison-review-findings]")
             |> LazyHTML.attribute("data-dashboard-comparison-review-findings")

    assert ["placement-1", "placement-2"] =
             document
             |> LazyHTML.query("[data-dashboard-comparison-review-finding]")
             |> LazyHTML.attribute("data-dashboard-comparison-review-finding")

    assert ["increased", "missing"] =
             document
             |> LazyHTML.query("[data-dashboard-comparison-review-finding]")
             |> LazyHTML.attribute("data-dashboard-comparison-review-finding-state")

    assert ["placement-1", "placement-2"] =
             document
             |> LazyHTML.query("[data-dashboard-comparison-review-finding-placement-link]")
             |> LazyHTML.attribute("data-dashboard-comparison-review-finding-placement-link")

    assert ["#widget-placement-1", "#widget-placement-2"] =
             document
             |> LazyHTML.query("[data-dashboard-comparison-review-finding-placement-link]")
             |> LazyHTML.attribute("href")

    assert ["select_review_placement", "select_review_placement"] =
             document
             |> LazyHTML.query("[data-dashboard-comparison-review-finding-placement-link]")
             |> LazyHTML.attribute("phx-click")

    assert ["placement-1", "placement-2"] =
             document
             |> LazyHTML.query("[data-dashboard-comparison-review-finding-placement-link]")
             |> LazyHTML.attribute("phx-value-placement-id")
  end

  test "versions panel renders comparison review resolution state" do
    request_event =
      comparison_review_request_event(
        event_id: "dashboard-lifecycle-event-1",
        actor_id: "user-reviewer",
        placement_ids: ["placement-1"]
      )

    resolution_event =
      comparison_review_resolution_event(
        event_id: "dashboard-lifecycle-event-2",
        source_request_event_id: "dashboard-lifecycle-event-1",
        actor_id: "user-resolver",
        payload: %{
          "workflow_intent" => %{
            "kind" => "bulk_correction_authority_review",
            "action" => "request_comparison_review",
            "selection_count" => 1
          },
          "source_open_count" => 1,
          "source_open_placement_ids" => ["placement-1"]
        }
      )

    html =
      render_widget_panel(&FormComponents.widget_panel/1,
        panel: :versions,
        dashboard_lifecycle_events: [request_event, resolution_event]
      )

    document = LazyHTML.from_fragment(html)

    assert ["resolved"] =
             document
             |> LazyHTML.query("[data-dashboard-comparison-review-request]")
             |> LazyHTML.attribute("data-dashboard-comparison-review-status")

    assert ["0"] =
             document
             |> LazyHTML.query("#dashboard-activity-section")
             |> LazyHTML.attribute("data-dashboard-comparison-review-open-count")

    assert [""] =
             document
             |> LazyHTML.query("#dashboard-activity-section")
             |> LazyHTML.attribute("data-dashboard-comparison-review-open-requests")

    assert [] =
             document
             |> LazyHTML.query("[data-dashboard-comparison-review-open-badge]")
             |> LazyHTML.attribute("data-dashboard-comparison-review-open-badge")

    assert ["dashboard-lifecycle-event-2"] =
             document
             |> LazyHTML.query("[data-dashboard-comparison-review-request]")
             |> LazyHTML.attribute("data-dashboard-comparison-review-resolution-event")

    assert ["dashboard-lifecycle-event-1"] =
             document
             |> LazyHTML.query("[data-dashboard-comparison-review-resolved]")
             |> LazyHTML.attribute("data-dashboard-comparison-review-resolved")

    assert [] =
             document
             |> LazyHTML.query("[data-dashboard-comparison-review-resolve-form]")
             |> LazyHTML.attribute("data-dashboard-comparison-review-resolve-form")

    assert ["dashboard-lifecycle-event-1"] =
             document
             |> LazyHTML.query("[data-dashboard-comparison-review-resolution]")
             |> LazyHTML.attribute("data-dashboard-comparison-review-resolution-source")

    assert ["review_completed"] =
             document
             |> LazyHTML.query("[data-dashboard-comparison-review-resolution]")
             |> LazyHTML.attribute("data-dashboard-comparison-review-resolution-disposition")

    assert ["placement-1"] =
             document
             |> LazyHTML.query("[data-dashboard-comparison-review-resolution]")
             |> LazyHTML.attribute(
               "data-dashboard-comparison-review-resolution-selected-placement"
             )

    assert ["placement-1"] =
             document
             |> LazyHTML.query("[data-dashboard-comparison-review-resolution]")
             |> LazyHTML.attribute(
               "data-dashboard-comparison-review-resolution-affected-placements"
             )

    assert ["bulk_correction_authority_review"] =
             document
             |> LazyHTML.query("[data-dashboard-comparison-review-resolution]")
             |> LazyHTML.attribute("data-dashboard-comparison-review-resolution-workflow-kind")

    assert ["request_comparison_review"] =
             document
             |> LazyHTML.query("[data-dashboard-comparison-review-resolution]")
             |> LazyHTML.attribute("data-dashboard-comparison-review-resolution-workflow-action")

    assert ["1"] =
             document
             |> LazyHTML.query("[data-dashboard-comparison-review-resolution]")
             |> LazyHTML.attribute(
               "data-dashboard-comparison-review-resolution-workflow-selection-count"
             )

    assert ["placement-1"] =
             document
             |> LazyHTML.query("[data-dashboard-comparison-review-resolution]")
             |> LazyHTML.attribute(
               "data-dashboard-comparison-review-resolution-source-open-placements"
             )

    assert "placement-1" =
             document
             |> LazyHTML.query(~s([data-activity-field="Resolution placement"]))
             |> selected_text()

    assert "placement-1" =
             document
             |> LazyHTML.query(~s([data-activity-field="Resolution affected placements"]))
             |> selected_text()

    assert "bulk_correction_authority_review / 1" =
             document
             |> LazyHTML.query(~s([data-activity-field="Resolution workflow"]))
             |> selected_text()

    assert "Comparison review resolved" =
             document
             |> LazyHTML.query("#dashboard-activity-dashboard-lifecycle-event-2 .font-semibold")
             |> selected_text()
  end

  test "versions panel renders captured health snapshot activity details" do
    snapshot = %{
      "schema" => "dashboard_health_snapshot.v1",
      "snapshot_id" => "health-snapshot-1",
      "state" => "attention",
      "severity" => "warning",
      "counts" => %{
        "widgets" => 6,
        "ready" => 2,
        "affected" => 4,
        "blocked" => 1,
        "stale" => 2,
        "degraded" => 1
      },
      "placement_ids" => %{
        "affected" => ["placement-1", "placement-2"],
        "blocked" => ["placement-3"],
        "stale" => ["placement-4"],
        "degraded" => ["placement-5"]
      }
    }

    event =
      lifecycle_event(
        "dashboard-lifecycle-event-health",
        :health_snapshot_captured,
        actor_id: "operator-1",
        payload: %{
          "schema" => "dashboard_health_snapshot_capture.v1",
          "source" => "operator",
          "dashboard_name" => "Ops Dashboard",
          "snapshot_id" => "health-snapshot-1",
          "snapshot_schema" => "dashboard_health_snapshot.v1",
          "health_state" => "attention",
          "health_severity" => "warning",
          "captured_reason" => "pre-pass review",
          "snapshot" => snapshot
        }
      )

    html =
      render_widget_panel(&FormComponents.widget_panel/1,
        panel: :versions,
        dashboard_lifecycle_events: [event]
      )

    document = LazyHTML.from_fragment(html)

    assert ["health_snapshot_captured"] =
             document
             |> LazyHTML.query("#dashboard-activity-dashboard-lifecycle-event-health")
             |> LazyHTML.attribute("data-lifecycle-event-type")

    assert "Health snapshot captured" =
             document
             |> LazyHTML.query(
               "#dashboard-activity-dashboard-lifecycle-event-health .font-semibold"
             )
             |> selected_text()

    assert ["health-snapshot-1"] =
             document
             |> LazyHTML.query("[data-dashboard-health-snapshot-event]")
             |> LazyHTML.attribute("data-dashboard-health-snapshot-id")

    assert ["dashboard_health_snapshot.v1"] =
             document
             |> LazyHTML.query("[data-dashboard-health-snapshot-event]")
             |> LazyHTML.attribute("data-dashboard-health-snapshot-schema")

    assert ["attention"] =
             document
             |> LazyHTML.query("[data-dashboard-health-snapshot-event]")
             |> LazyHTML.attribute("data-dashboard-health-snapshot-state")

    assert ["warning"] =
             document
             |> LazyHTML.query("[data-dashboard-health-snapshot-event]")
             |> LazyHTML.attribute("data-dashboard-health-snapshot-severity")

    assert ["widgets", "ready", "affected", "blocked", "stale", "degraded"] =
             document
             |> LazyHTML.query("[data-dashboard-health-snapshot-count]")
             |> LazyHTML.attribute("data-dashboard-health-snapshot-count")

    assert ["6", "2", "4", "1", "2", "1"] =
             document
             |> LazyHTML.query("[data-dashboard-health-snapshot-count]")
             |> LazyHTML.attribute("data-dashboard-health-snapshot-count-value")

    assert ["affected", "blocked", "stale", "degraded"] =
             document
             |> LazyHTML.query("[data-dashboard-health-snapshot-placements]")
             |> LazyHTML.attribute("data-dashboard-health-snapshot-placements")

    assert ["placement-1,placement-2", "placement-3", "placement-4", "placement-5"] =
             document
             |> LazyHTML.query("[data-dashboard-health-snapshot-placements]")
             |> LazyHTML.attribute("data-dashboard-health-snapshot-placement-ids")

    assert ["ClipboardButton"] =
             document
             |> LazyHTML.query(
               "#dashboard-health-snapshot-event-copy-dashboard-lifecycle-event-health"
             )
             |> LazyHTML.attribute("phx-hook")

    assert ["dashboard-lifecycle-event-health"] =
             document
             |> LazyHTML.query(
               "#dashboard-health-snapshot-event-copy-dashboard-lifecycle-event-health"
             )
             |> LazyHTML.attribute("data-dashboard-health-snapshot-event-copy")

    [snapshot_json] =
      document
      |> LazyHTML.query("#dashboard-health-snapshot-event-copy-dashboard-lifecycle-event-health")
      |> LazyHTML.attribute("data-clipboard-text")

    assert Jason.decode!(snapshot_json) == snapshot
  end

  test "versions panel filters activity by health snapshots" do
    health_event =
      lifecycle_event(
        "dashboard-lifecycle-event-health",
        :health_snapshot_captured,
        occurred_at: ~U[2026-06-24 12:03:00Z],
        payload: %{
          "schema" => "dashboard_health_snapshot_capture.v1",
          "snapshot_id" => "health-snapshot-1",
          "snapshot_schema" => "dashboard_health_snapshot.v1",
          "health_state" => "attention",
          "health_severity" => "warning",
          "snapshot" => %{
            "schema" => "dashboard_health_snapshot.v1",
            "snapshot_id" => "health-snapshot-1"
          }
        }
      )

    published_event =
      lifecycle_event(
        "dashboard-lifecycle-event-published",
        :published,
        occurred_at: ~U[2026-06-24 12:02:00Z]
      )

    review_event =
      comparison_review_request_event(
        event_id: "dashboard-lifecycle-event-review",
        occurred_at: ~U[2026-06-24 12:01:00Z]
      )

    html =
      render_widget_panel(&FormComponents.widget_panel/1,
        panel: :versions,
        dashboard_activity_filter: :health_snapshots,
        dashboard_activity_event_id: "dashboard-lifecycle-event-health",
        dashboard_lifecycle_events: [published_event, review_event, health_event],
        dashboard_current_path:
          "/missions/mission-1/ops/dashboards/dashboard-1?scope_kind=mission&scope_id=mission-1&selected_placement=placement-stale"
      )

    document = LazyHTML.from_fragment(html)

    assert ["health_snapshots"] =
             document
             |> LazyHTML.query("#dashboard-activity-section")
             |> LazyHTML.attribute("data-dashboard-activity-filter")

    assert ["health_snapshots"] =
             document
             |> LazyHTML.query("#dashboard-activity-section")
             |> LazyHTML.attribute("data-dashboard-activity-mode")

    assert ["health_snapshots"] =
             document
             |> LazyHTML.query("[data-dashboard-activity-filter-badge]")
             |> LazyHTML.attribute("data-dashboard-activity-filter-badge")

    assert [
             "",
             "version_changes",
             "comparison_reviews",
             "open_comparison_reviews",
             "health_snapshots",
             "publish_readiness"
           ] =
             document
             |> LazyHTML.query("[data-dashboard-activity-filter-option]")
             |> LazyHTML.attribute("data-dashboard-activity-filter-option")

    assert ["false", "false", "false", "false", "true", "false"] =
             document
             |> LazyHTML.query("[data-dashboard-activity-filter-option]")
             |> LazyHTML.attribute("data-dashboard-activity-filter-selected")

    assert [
             "set_activity_filter",
             "set_activity_filter",
             "set_activity_filter",
             "set_activity_filter",
             "set_activity_filter",
             "set_activity_filter"
           ] =
             document
             |> LazyHTML.query("[data-dashboard-activity-filter-option]")
             |> LazyHTML.attribute("phx-click")

    assert ["dashboard-lifecycle-event-health"] =
             document
             |> LazyHTML.query("#dashboard-activity-list > li")
             |> LazyHTML.attribute("id")
             |> Enum.map(&String.replace_prefix(&1, "dashboard-activity-", ""))

    assert ["true"] =
             document
             |> LazyHTML.query("#dashboard-activity-dashboard-lifecycle-event-health")
             |> LazyHTML.attribute("data-dashboard-activity-selected")

    assert "Selected" =
             document
             |> LazyHTML.query("[data-dashboard-activity-selected-badge]")
             |> selected_text()

    assert ["dashboard-lifecycle-event-health"] =
             document
             |> LazyHTML.query("#dashboard-selected-activity-event")
             |> LazyHTML.attribute("data-dashboard-selected-activity-event")

    assert ["true"] =
             document
             |> LazyHTML.query("#dashboard-selected-activity-event")
             |> LazyHTML.attribute("data-dashboard-selected-activity-event-found")

    assert ["true"] =
             document
             |> LazyHTML.query("#dashboard-selected-activity-event")
             |> LazyHTML.attribute("data-dashboard-selected-activity-event-visible")

    assert ["health_snapshot_captured"] =
             document
             |> LazyHTML.query("#dashboard-selected-activity-event")
             |> LazyHTML.attribute("data-dashboard-selected-activity-event-type")

    assert "Health snapshot captured" =
             document
             |> LazyHTML.query("[data-dashboard-selected-activity-title]")
             |> selected_text()

    assert ["dashboard-lifecycle-event-health"] =
             document
             |> LazyHTML.query(~s([data-dashboard-selected-activity-field="Event"]))
             |> selected_text()
             |> List.wrap()

    assert ["select_activity_event"] =
             document
             |> LazyHTML.query("#dashboard-activity-select-dashboard-lifecycle-event-health")
             |> LazyHTML.attribute("phx-click")

    assert ["dashboard-lifecycle-event-health"] =
             document
             |> LazyHTML.query("#dashboard-activity-select-dashboard-lifecycle-event-health")
             |> LazyHTML.attribute("phx-value-event-id")

    assert ["ClipboardButton"] =
             document
             |> LazyHTML.query("#dashboard-activity-link-copy-dashboard-lifecycle-event-health")
             |> LazyHTML.attribute("phx-hook")

    [activity_link] =
      document
      |> LazyHTML.query("#dashboard-activity-link-copy-dashboard-lifecycle-event-health")
      |> LazyHTML.attribute("data-clipboard-text")

    uri = URI.parse(activity_link)

    assert uri.path == "/missions/mission-1/ops/dashboards/dashboard-1"

    assert URI.decode_query(uri.query) == %{
             "scope_kind" => "mission",
             "scope_id" => "mission-1",
             "panel" => "versions",
             "activity_filter" => "health_snapshots",
             "activity_event" => "dashboard-lifecycle-event-health"
           }
  end

  test "versions panel marks selected activity hidden by the current filter" do
    health_event =
      lifecycle_event(
        "dashboard-lifecycle-event-health",
        :health_snapshot_captured,
        occurred_at: ~U[2026-06-24 12:03:00Z]
      )

    published_event =
      lifecycle_event(
        "dashboard-lifecycle-event-published",
        :published,
        occurred_at: ~U[2026-06-24 12:02:00Z]
      )

    html =
      render_widget_panel(&FormComponents.widget_panel/1,
        panel: :versions,
        dashboard_activity_filter: :health_snapshots,
        dashboard_activity_event_id: "dashboard-lifecycle-event-published",
        dashboard_lifecycle_events: [published_event, health_event]
      )

    document = LazyHTML.from_fragment(html)

    assert ["dashboard-lifecycle-event-published"] =
             document
             |> LazyHTML.query("#dashboard-selected-activity-event")
             |> LazyHTML.attribute("data-dashboard-selected-activity-event")

    assert ["true"] =
             document
             |> LazyHTML.query("#dashboard-selected-activity-event")
             |> LazyHTML.attribute("data-dashboard-selected-activity-event-found")

    assert ["false"] =
             document
             |> LazyHTML.query("#dashboard-selected-activity-event")
             |> LazyHTML.attribute("data-dashboard-selected-activity-event-visible")

    assert ["published"] =
             document
             |> LazyHTML.query("#dashboard-selected-activity-event")
             |> LazyHTML.attribute("data-dashboard-selected-activity-event-type")

    assert ["hidden"] =
             document
             |> LazyHTML.query("[data-dashboard-selected-activity-filter-state]")
             |> LazyHTML.attribute("data-dashboard-selected-activity-filter-state")

    assert "Published" =
             document
             |> LazyHTML.query("[data-dashboard-selected-activity-title]")
             |> selected_text()

    assert ["dashboard-lifecycle-event-health"] =
             document
             |> LazyHTML.query("#dashboard-activity-list > li")
             |> LazyHTML.attribute("id")
             |> Enum.map(&String.replace_prefix(&1, "dashboard-activity-", ""))
  end

  test "versions panel marks selected activity unavailable when the event is missing" do
    health_event =
      lifecycle_event(
        "dashboard-lifecycle-event-health",
        :health_snapshot_captured,
        occurred_at: ~U[2026-06-24 12:03:00Z]
      )

    html =
      render_widget_panel(&FormComponents.widget_panel/1,
        panel: :versions,
        dashboard_activity_event_id: "dashboard-lifecycle-event-missing",
        dashboard_lifecycle_events: [health_event]
      )

    document = LazyHTML.from_fragment(html)

    assert ["dashboard-lifecycle-event-missing"] =
             document
             |> LazyHTML.query("#dashboard-selected-activity-event")
             |> LazyHTML.attribute("data-dashboard-selected-activity-event")

    assert ["false"] =
             document
             |> LazyHTML.query("#dashboard-selected-activity-event")
             |> LazyHTML.attribute("data-dashboard-selected-activity-event-found")

    assert ["false"] =
             document
             |> LazyHTML.query("#dashboard-selected-activity-event")
             |> LazyHTML.attribute("data-dashboard-selected-activity-event-visible")

    assert ["missing"] =
             document
             |> LazyHTML.query("[data-dashboard-selected-activity-filter-state]")
             |> LazyHTML.attribute("data-dashboard-selected-activity-filter-state")

    assert "Activity event unavailable" =
             document
             |> LazyHTML.query("[data-dashboard-selected-activity-title]")
             |> selected_text()
  end

  test "versions panel can focus activity on open comparison reviews" do
    open_request_event =
      comparison_review_request_event(
        event_id: "dashboard-lifecycle-event-open",
        placement_ids: ["placement-open"],
        occurred_at: ~U[2026-06-24 12:00:00Z]
      )

    resolved_request_event =
      comparison_review_request_event(
        event_id: "dashboard-lifecycle-event-resolved",
        placement_ids: ["placement-resolved"],
        occurred_at: ~U[2026-06-24 12:01:00Z]
      )

    resolution_event =
      comparison_review_resolution_event(
        event_id: "dashboard-lifecycle-event-resolution",
        source_request_event_id: "dashboard-lifecycle-event-resolved",
        occurred_at: ~U[2026-06-24 12:02:00Z],
        payload: %{
          "schema" => "dashboard_comparison_review_resolution.v1",
          "source_request_event_id" => "dashboard-lifecycle-event-resolved",
          "disposition" => "review_completed"
        }
      )

    published_event =
      lifecycle_event(
        "dashboard-lifecycle-event-published",
        :published,
        occurred_at: ~U[2026-06-24 12:03:00Z]
      )

    lifecycle_events = [
      open_request_event,
      resolved_request_event,
      resolution_event,
      published_event
    ]

    html =
      render_widget_panel(&FormComponents.widget_panel/1,
        panel: :versions,
        dashboard_activity_filter: :open_comparison_reviews,
        dashboard_review_placement_id: "placement-open",
        dashboard_lifecycle_events: lifecycle_events,
        dashboard_comparison_review_queue: ComparisonReviewQueue.open_summary(lifecycle_events)
      )

    document = LazyHTML.from_fragment(html)

    assert ["open_comparison_reviews"] =
             document
             |> LazyHTML.query("#dashboard-activity-section")
             |> LazyHTML.attribute("data-dashboard-activity-filter")

    assert ["open_comparison_reviews"] =
             document
             |> LazyHTML.query("#dashboard-activity-section")
             |> LazyHTML.attribute("data-dashboard-activity-mode")

    assert ["true"] =
             document
             |> LazyHTML.query("#dashboard-activity-section")
             |> LazyHTML.attribute("data-dashboard-comparison-review-work-queue")

    assert ["1"] =
             document
             |> LazyHTML.query("#dashboard-activity-section")
             |> LazyHTML.attribute("data-dashboard-comparison-review-work-queue-count")

    assert "Review Queue" =
             document
             |> LazyHTML.query("[data-dashboard-activity-title]")
             |> selected_text()

    assert ["placement-open"] =
             document
             |> LazyHTML.query("#dashboard-activity-section")
             |> LazyHTML.attribute("data-dashboard-review-selected-placement")

    assert "Open reviews" =
             document
             |> LazyHTML.query("[data-dashboard-activity-filter-badge]")
             |> selected_text()

    assert ["open_versions"] =
             document
             |> LazyHTML.query("#dashboard-activity-clear-filter")
             |> LazyHTML.attribute("phx-click")

    assert ["open_comparison_reviews"] =
             document
             |> LazyHTML.query("#dashboard-activity-clear-filter")
             |> LazyHTML.attribute("data-dashboard-activity-clear-filter")

    assert ["1"] =
             document
             |> LazyHTML.query("#dashboard-activity-section")
             |> LazyHTML.attribute("data-dashboard-comparison-review-open-count")

    assert ["dashboard-lifecycle-event-open"] =
             document
             |> LazyHTML.query("[data-dashboard-comparison-review-request]")
             |> LazyHTML.attribute("data-dashboard-comparison-review-request")

    assert ["dashboard-lifecycle-event-open"] =
             document
             |> LazyHTML.query("#dashboard-activity-list > li")
             |> LazyHTML.attribute("id")
             |> Enum.map(&String.replace_prefix(&1, "dashboard-activity-", ""))

    assert ["1"] =
             document
             |> LazyHTML.query("#dashboard-activity-list")
             |> LazyHTML.attribute("data-dashboard-comparison-review-work-queue-count")

    assert ["dashboard-lifecycle-event-open"] =
             document
             |> LazyHTML.query("#dashboard-activity-list > li")
             |> LazyHTML.attribute("data-dashboard-comparison-review-work-queue-item")

    assert ["open"] =
             document
             |> LazyHTML.query("[data-dashboard-comparison-review-request]")
             |> LazyHTML.attribute("data-dashboard-comparison-review-status")

    assert ["true"] =
             document
             |> LazyHTML.query("[data-dashboard-comparison-review-placement-link]")
             |> LazyHTML.attribute("data-dashboard-review-placement-selected")
  end

  test "versions panel renders explicit empty review queue state" do
    request_event =
      comparison_review_request_event(
        event_id: "dashboard-lifecycle-event-resolved",
        placement_ids: ["placement-resolved"],
        occurred_at: ~U[2026-06-24 12:00:00Z]
      )

    resolution_event =
      comparison_review_resolution_event(
        event_id: "dashboard-lifecycle-event-resolution",
        source_request_event_id: "dashboard-lifecycle-event-resolved",
        occurred_at: ~U[2026-06-24 12:01:00Z],
        payload: %{
          "schema" => "dashboard_comparison_review_resolution.v1",
          "source_request_event_id" => "dashboard-lifecycle-event-resolved",
          "disposition" => "review_completed"
        }
      )

    html =
      render_widget_panel(&FormComponents.widget_panel/1,
        panel: :versions,
        dashboard_activity_filter: :open_comparison_reviews,
        dashboard_lifecycle_events: [request_event, resolution_event]
      )

    document = LazyHTML.from_fragment(html)

    assert ["empty"] =
             document
             |> LazyHTML.query("#dashboard-activity-section")
             |> LazyHTML.attribute("data-dashboard-comparison-review-queue-state")

    assert ["empty"] =
             document
             |> LazyHTML.query("[data-dashboard-comparison-review-queue-state-message]")
             |> LazyHTML.attribute("data-dashboard-comparison-review-queue-state-message")

    assert "No open comparison reviews." =
             document
             |> LazyHTML.query("[data-dashboard-comparison-review-queue-state-message]")
             |> selected_text()

    assert [] =
             document
             |> LazyHTML.query("[data-dashboard-activity-empty-filter]")
             |> LazyHTML.attribute("data-dashboard-activity-empty-filter")
  end

  test "versions panel renders stale selected placement queue state" do
    open_request_event =
      comparison_review_request_event(
        event_id: "dashboard-lifecycle-event-open",
        placement_ids: ["placement-current"],
        occurred_at: ~U[2026-06-24 12:00:00Z]
      )

    html =
      render_widget_panel(&FormComponents.widget_panel/1,
        panel: :versions,
        dashboard_activity_filter: :open_comparison_reviews,
        dashboard_review_placement_id: "placement-stale",
        dashboard_lifecycle_events: [open_request_event],
        dashboard_comparison_review_queue:
          ComparisonReviewQueue.open_summary([open_request_event])
      )

    document = LazyHTML.from_fragment(html)

    assert ["selection_stale"] =
             document
             |> LazyHTML.query("#dashboard-activity-section")
             |> LazyHTML.attribute("data-dashboard-comparison-review-queue-state")

    assert ["selection_stale"] =
             document
             |> LazyHTML.query("[data-dashboard-comparison-review-queue-state-message]")
             |> LazyHTML.attribute("data-dashboard-comparison-review-queue-state-message")

    assert "Selected review placement is no longer part of the open review queue." =
             document
             |> LazyHTML.query("[data-dashboard-comparison-review-queue-state-message]")
             |> selected_text()

    assert ["false"] =
             document
             |> LazyHTML.query("[data-dashboard-comparison-review-placement-link]")
             |> LazyHTML.attribute("data-dashboard-review-placement-selected")
  end

  defp render_widget_panel(component, attrs) do
    render_component(component, Keyword.merge(base_panel_attrs(), attrs))
  end

  defp base_panel_attrs do
    [
      form: to_form(%{}, as: :widget),
      spacecraft: [],
      operational_observables: [],
      filtered_points: [],
      filtered_operational_observables: [],
      points_empty?: true,
      selected_point: nil,
      selected_points: [],
      selected_operational_observables: [],
      dashboard_scope_context: nil,
      error: nil,
      mission_id: "mission-1",
      dashboard_document: %Document{dashboard_id: "dashboard-1", name: "Dashboard"},
      dashboard_summary: nil,
      dashboard_versions: [],
      dashboard_lifecycle_events: [],
      dashboard_comparison_review_queue: ComparisonReviewQueue.open_summary([]),
      dashboard_activity_event_id: nil,
      dashboard_review_placement_id: nil,
      dashboard_publish_readiness: nil,
      runtime_diagnostics: %{},
      dashboard_current_path: "/missions/mission-1/ops/dashboards/dashboard-1",
      historical_workflow_request_form: to_form(%{}, as: :historical_workflow_request)
    ]
  end

  defp data_link(target, target_id, label) do
    %DataLink{
      link_id: "#{target}:#{target_id}:request-1",
      label: label,
      target: target,
      target_id: target_id,
      source: :frame,
      context: %{
        data: %{
          data_source_id: "questdb-flight",
          source_binding_id: "binding-flight"
        },
        time: %{
          mode: "archive",
          axis: "receipt_time"
        }
      }
    }
  end

  defp evidence_link(target, target_id, label) do
    %{
      link_id: "#{target}:#{target_id}:request-1",
      label: label,
      target_text: target |> Atom.to_string() |> String.replace("_", " "),
      target_id: target_id,
      context: %{
        data: %{
          data_source_id: "questdb-flight",
          source_binding_id: "binding-flight"
        },
        time: %{
          mode: "archive",
          axis: "receipt_time"
        }
      }
    }
  end

  defp evidence_link_without_context(target, target_id, label) do
    %{
      link_id: "#{target}:#{target_id}:request-1",
      label: label,
      target_text: target |> Atom.to_string() |> String.replace("_", " "),
      target_id: target_id,
      context: %{}
    }
  end

  defp telemetry_explore_action do
    %DashboardAction{
      action_id: "explore",
      label: "Explore telemetry",
      target: :telemetry_explore,
      kind: :invoke,
      query: %{
        "point_id" => "HK.counter",
        "sample_id" => "sample-1",
        "realm" => "flight",
        "data_source_id" => "questdb-flight",
        "source_binding_id" => "binding-flight"
      },
      source: :frame
    }
  end

  defp source_inventory_action do
    %DashboardAction{
      action_id: "source-inventory",
      label: "Source inventory",
      target: :source_inventory,
      kind: :invoke,
      query: %{
        "realm" => "flight",
        "data_source_id" => "questdb-flight",
        "source_binding_id" => "binding-flight"
      },
      source: :frame
    }
  end

  defp selected_text(lazy_html) do
    lazy_html
    |> LazyHTML.text()
    |> String.trim()
  end
end
