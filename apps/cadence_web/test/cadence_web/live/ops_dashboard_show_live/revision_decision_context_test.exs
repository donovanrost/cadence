defmodule CadenceWeb.OpsDashboardShowLive.RevisionDecisionContextTest do
  use ExUnit.Case, async: true

  alias CadenceWeb.OpsDashboardShowLive.RevisionDecisionContext

  test "build extracts revision decision source and comparison fields from atom-key rows" do
    context =
      RevisionDecisionContext.build(%{
        target: :comparison_finding,
        target_id: "placement-1",
        link_label: "Comparison finding",
        rows: [
          %{label: "Revision decision event", value: "decision-event-1"},
          %{label: "Observation identity", value: "identity-1"},
          %{label: "Decision", value: "mark_advisory"},
          %{label: "Dashboard context limit mode", value: "compare"},
          %{label: "Realm", value: "flight"},
          %{label: "Data source", value: "questdb-flight"},
          %{label: "Source binding", value: "binding-flight"},
          %{label: "New canonical observation", value: "observation-2"},
          %{label: "New canonical sample", value: "sample-2"},
          %{label: "New canonical revision", value: "2"},
          %{label: "Decision reason", value: "dashboard_comparison_finding"},
          %{label: "Correction workflow", value: "workflow-1"},
          %{label: "Correction authority", value: "comparison"},
          %{label: "State", value: "increased"},
          %{label: "Delta", value: "+2"},
          %{label: "Primary sample", value: "sample-primary-1"},
          %{label: "Compare sample", value: "sample-compare-1"},
          %{label: "Primary data view", value: "all_revisions"},
          %{label: "Compare data view", value: "canonical"},
          %{label: "Primary count", value: "4"},
          %{label: "Compare count", value: "2"},
          %{label: "Widget", value: "widget-1"},
          %{label: "Widget title", value: "Counter comparison"}
        ]
      })

    assert context == %{
             source_decision_event_id: "decision-event-1",
             source_target: "comparison_finding",
             source_target_id: "placement-1",
             source_link_label: "Comparison finding",
             observation_identity_id: "identity-1",
             source_decision: "mark_advisory",
             dashboard_limit_mode: "compare",
             realm: "flight",
             data_source_id: "questdb-flight",
             source_binding_id: "binding-flight",
             canonical_observation_id: "observation-2",
             canonical_sample_id: "sample-2",
             canonical_revision: "2",
             decision_reason: "dashboard_comparison_finding",
             correction_workflow_id: "workflow-1",
             authority: "comparison",
             comparison_state: "increased",
             comparison_delta: "+2",
             primary_sample_id: "sample-primary-1",
             compare_sample_id: "sample-compare-1",
             primary_data_view: "all_revisions",
             compare_data_view: "canonical",
             primary_count: "4",
             compare_count: "2",
             widget_id: "widget-1",
             widget_title: "Counter comparison"
           }
  end

  test "build falls back to previous canonical rows and default correction metadata" do
    context =
      RevisionDecisionContext.build(%{
        target: "telemetry_revision_decision_event",
        rows: [
          %{label: "Observation identity", value: "identity-1"},
          %{label: "Previous canonical observation", value: "observation-1"},
          %{label: "Previous canonical sample", value: "sample-1"},
          %{label: "Previous canonical revision", value: "1"},
          %{label: "Decision reason", value: ""},
          %{label: "Correction authority", value: ""}
        ]
      })

    assert context.source_target == "telemetry_revision_decision_event"
    assert context.canonical_observation_id == "observation-1"
    assert context.canonical_sample_id == "sample-1"
    assert context.canonical_revision == "1"
    assert context.decision_reason == "dashboard_revision_decision"
    assert context.authority == "dashboard_operator"
  end

  test "build supports string-key rows and normalizes blank values" do
    context =
      RevisionDecisionContext.build(%{
        rows: [
          %{"label" => "Observation identity", "value" => "identity-1"},
          %{"label" => "Realm", "value" => ""},
          %{"label" => "Data source", "value" => nil},
          %{"label" => "Source binding", "value" => "binding-flight"}
        ]
      })

    assert context.source_target == ""
    assert context.observation_identity_id == "identity-1"
    assert context.realm == nil
    assert context.data_source_id == nil
    assert context.source_binding_id == "binding-flight"
  end

  test "build falls back to inspector context rows for dashboard limit mode" do
    context =
      RevisionDecisionContext.build(%{
        rows: [%{label: "Observation identity", value: "identity-1"}],
        context_rows: [%{label: "Limit mode", value: "recomputed"}]
      })

    assert context.dashboard_limit_mode == "recomputed"
  end

  test "build returns empty-compatible context when inspector is missing rows" do
    context = RevisionDecisionContext.build(%{})

    assert context.source_decision_event_id == nil
    assert context.source_target == ""
    assert context.observation_identity_id == nil
    assert context.decision_reason == "dashboard_revision_decision"
    assert context.authority == "dashboard_operator"
  end
end
