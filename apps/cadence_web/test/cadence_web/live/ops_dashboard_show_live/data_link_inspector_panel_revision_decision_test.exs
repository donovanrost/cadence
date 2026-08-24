defmodule CadenceWeb.OpsDashboardShowLive.DataLinkInspectorPanelRevisionDecisionTest do
  use ExUnit.Case, async: true

  import Phoenix.LiveViewTest, only: [render_component: 2]

  alias Cadence.Dashboards.Document
  alias CadenceWeb.OpsDashboardShowLive.DataLinkInspectorPanelComponents
  alias CadenceWeb.OpsDashboardShowLive.RevisionDecisionActionOutcome
  alias CadenceWeb.OpsDashboardShowLive.ViewTestSupport

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

    presentation = ViewTestSupport.data_link_inspector_presentation(html)
    revision = presentation["revision_decision"]
    revision_outcome_attrs = revision["action_outcome"]["attrs"]
    action_attrs = presentation["action_outcome"]["attrs"]

    assert revision["attrs"]["data-revision-decision-observation-identity"] == "identity-1"
    assert revision_outcome_attrs["data-revision-decision-action-status"] == "ok"
    assert action_attrs["data-data-link-action-outcome-action"] == "revision_decision"
    assert action_attrs["data-data-link-action-outcome-decision"] == "mark_conflict"
    assert action_attrs["data-data-link-action-outcome-dashboard-limit-mode"] == "compare"

    assert action_attrs["data-data-link-action-outcome-result-event-id"] ==
             "decision-event-applied"

    assert action_attrs["data-data-link-action-outcome-target-event-id"] ==
             "decision-event-applied"

    assert action_attrs["data-data-link-action-outcome-target-observation-identity-id"] ==
             "identity-1"

    assert Jason.decode!(action_attrs["data-data-link-action-outcome-metadata"]) == %{
             "decision" => "mark_conflict",
             "dashboard_limit_mode" => "compare",
             "result_event_id" => "decision-event-applied",
             "target_event_id" => "decision-event-applied",
             "target_observation_identity_id" => "identity-1"
           }

    assert revision_outcome_attrs["data-revision-decision-action-decision"] == "mark_conflict"

    assert revision_outcome_attrs["data-revision-decision-action-dashboard-limit-mode"] ==
             "compare"

    assert revision_outcome_attrs["data-revision-decision-action-result-event-id"] ==
             "decision-event-applied"

    assert revision["attrs"]["data-revision-decision-default-effect"] ==
             "removes this identity from canonical reads until resolved"

    assert revision["form"]["attrs"]["phx-submit"] == "apply_revision_decision"

    effects = Map.new(revision["effects"], &{&1["attrs"]["data-revision-decision-effect"], &1})

    assert effects["mark_conflict"]["summary"]["text"] ==
             "removes this identity from canonical reads until resolved"

    assert effects["mark_canonical"]["summary"]["text"] ==
             "sets this identity canonical for default dashboard reads"

    assert effects["mark_superseded"]["summary"]["text"] ==
             "marks this identity superseded by a correction"

    assert effects["mark_advisory"]["summary"]["text"] ==
             "keeps this identity as advisory history only"

    assert revision["form"]["submit"]["text"] == "Apply revision decision"

    assert revision_form_value(
             presentation,
             "dashboard-revision-decision-observation-identity-id"
           ) == "identity-1"

    assert revision_form_value(presentation, "dashboard-revision-decision-source-event-id") ==
             "decision-event-1"

    assert revision_form_value(presentation, "revision_decision_realm") == "flight"

    assert revision_form_value(presentation, "revision_decision_data_source_id") ==
             "questdb-flight"

    assert revision_form_value(presentation, "revision_decision_source_binding_id") ==
             "binding-flight"

    assert revision_form_value(
             presentation,
             "dashboard-revision-decision-dashboard-limit-mode"
           ) == "compare"

    assert revision_form_value(presentation, "revision_decision_canonical_observation_id") ==
             "observation-2"

    assert revision_form_value(presentation, "revision_decision_canonical_sample_id") ==
             "sample-2"

    assert revision_form_value(presentation, "revision_decision_canonical_revision") == "2"
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

    presentation = ViewTestSupport.data_link_inspector_presentation(html)
    revision = presentation["revision_decision"]

    assert revision["attrs"]["data-revision-decision-observation-identity"] ==
             "identity-primary-1"

    assert revision_form_value(
             presentation,
             "dashboard-revision-decision-observation-identity-id"
           ) == "identity-primary-1"

    assert revision_form_value(presentation, "revision_decision_authority") == "comparison"

    assert revision_form_value(presentation, "revision_decision_decision_reason") ==
             "dashboard_comparison_finding"

    assert revision_form_value(presentation, "revision_decision_canonical_sample_id") ==
             "sample-primary-1"

    assert revision_form_value(presentation, "dashboard-revision-decision-source-target") ==
             "comparison_finding"

    assert revision_form_value(presentation, "dashboard-revision-decision-source-target-id") ==
             "placement-1"

    assert revision_form_value(presentation, "dashboard-revision-decision-source-link-label") ==
             "Comparison finding"

    assert revision_form_value(presentation, "dashboard-revision-decision-comparison-state") ==
             "increased"

    assert revision_form_value(presentation, "dashboard-revision-decision-comparison-delta") ==
             "+2"

    assert revision_form_value(presentation, "dashboard-revision-decision-primary-sample") ==
             "sample-primary-1"

    assert revision_form_value(presentation, "dashboard-revision-decision-compare-sample") ==
             "sample-compare-1"
  end

  defp revision_form_value(presentation, id) do
    presentation
    |> ViewTestSupport.data_link_inspector_form_field("revision_decision", id)
    |> Map.fetch!("value")
  end
end
