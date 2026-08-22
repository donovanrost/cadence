defmodule CadenceWeb.OpsDashboardShowLive.DataLinkInspectorPanelRevisionDecisionTest do
  use ExUnit.Case, async: true

  import Phoenix.LiveViewTest, only: [render_component: 2]

  alias Cadence.Dashboards.Document
  alias CadenceWeb.OpsDashboardShowLive.DataLinkInspectorPanelComponents
  alias CadenceWeb.OpsDashboardShowLive.RevisionDecisionActionOutcome

  test "data_link_panel renders revision decision controls for revision decision events" do
    html =
      render_component(&DataLinkInspectorPanelComponents.data_link_panel/1,
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
        inspector: %{
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
        },
        mission_id: "mission-1",
        dashboard_document: %Document{dashboard_id: "dashboard-1", name: "Dashboard"},
        dashboard_current_path: "/missions/mission-1/ops/dashboards/dashboard-1?panel=data_link"
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

    assert ["mark_conflict"] =
             document
             |> LazyHTML.query("#dashboard-data-link-action-outcome")
             |> LazyHTML.attribute("data-data-link-action-outcome-decision")

    assert ["compare"] =
             document
             |> LazyHTML.query("#dashboard-data-link-action-outcome")
             |> LazyHTML.attribute("data-data-link-action-outcome-dashboard-limit-mode")

    assert ["decision-event-applied"] =
             document
             |> LazyHTML.query("#dashboard-data-link-action-outcome")
             |> LazyHTML.attribute("data-data-link-action-outcome-result-event-id")

    assert ["decision-event-applied"] =
             document
             |> LazyHTML.query("#dashboard-data-link-action-outcome")
             |> LazyHTML.attribute("data-data-link-action-outcome-target-event-id")

    assert ["identity-1"] =
             document
             |> LazyHTML.query("#dashboard-data-link-action-outcome")
             |> LazyHTML.attribute("data-data-link-action-outcome-target-observation-identity-id")

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

  test "data_link_panel renders revision decision controls for comparison findings with identity context" do
    html =
      render_component(&DataLinkInspectorPanelComponents.data_link_panel/1,
        inspector: %{
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
        },
        mission_id: "mission-1",
        dashboard_document: %Document{dashboard_id: "dashboard-1", name: "Dashboard"},
        dashboard_current_path: "/missions/mission-1/ops/dashboards/dashboard-1?panel=data_link"
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

  defp selected_text(lazy_html) do
    lazy_html
    |> LazyHTML.text()
    |> String.trim()
  end
end
