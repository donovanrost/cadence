defmodule CadenceWeb.OpsDashboardShowLive.RevisionDecisionPresentationTest do
  use ExUnit.Case, async: true

  alias CadenceWeb.OpsDashboardShowLive.RevisionDecisionPresentation

  test "build presents form params from revision decision context" do
    context = %{
      source_decision_event_id: "decision-event-1",
      source_target: :comparison_finding,
      source_target_id: "placement-1",
      source_link_label: "Comparison finding",
      observation_identity_id: "identity-1",
      source_decision: :mark_advisory,
      dashboard_time_mode: "replay_run",
      dashboard_replay_run_id: "replay-1",
      dashboard_data_view: "all_revisions",
      dashboard_limit_mode: "compare",
      realm: "flight",
      data_source_id: "questdb-flight",
      source_binding_id: "binding-flight",
      canonical_observation_id: "observation-2",
      canonical_sample_id: "sample-2",
      canonical_revision: 2,
      decision_reason: "dashboard_comparison_finding",
      correction_workflow_id: "workflow-1",
      authority: "comparison",
      comparison_state: "increased",
      comparison_delta: "+2",
      primary_sample_id: "sample-primary-1",
      compare_sample_id: "sample-compare-1",
      primary_data_view: "all_revisions",
      compare_data_view: "canonical",
      primary_count: 4,
      compare_count: 2,
      widget_id: "widget-1",
      widget_title: "Counter comparison"
    }

    presentation = RevisionDecisionPresentation.build(context)

    assert presentation.form_params == %{
             "source_decision_event_id" => "decision-event-1",
             "source_target" => "comparison_finding",
             "source_target_id" => "placement-1",
             "source_link_label" => "Comparison finding",
             "observation_identity_id" => "identity-1",
             "source_decision" => "mark_advisory",
             "dashboard_time_mode" => "replay_run",
             "dashboard_replay_run_id" => "replay-1",
             "dashboard_data_view" => "all_revisions",
             "dashboard_limit_mode" => "compare",
             "decision" => "mark_conflict",
             "realm" => "flight",
             "data_source_id" => "questdb-flight",
             "source_binding_id" => "binding-flight",
             "canonical_observation_id" => "observation-2",
             "canonical_sample_id" => "sample-2",
             "canonical_revision" => "2",
             "decision_reason" => "dashboard_comparison_finding",
             "correction_workflow_id" => "workflow-1",
             "authority" => "comparison",
             "comparison_state" => "increased",
             "comparison_delta" => "+2",
             "primary_sample_id" => "sample-primary-1",
             "compare_sample_id" => "sample-compare-1",
             "primary_data_view" => "all_revisions",
             "compare_data_view" => "canonical",
             "primary_count" => "4",
             "compare_count" => "2",
             "widget_id" => "widget-1",
             "widget_title" => "Counter comparison",
             "confirmed" => nil
           }
  end

  test "build exposes stable decision options and effects" do
    presentation = RevisionDecisionPresentation.build(%{})

    assert presentation.options == [
             {"Mark conflict", "mark_conflict"},
             {"Mark canonical", "mark_canonical"},
             {"Mark superseded", "mark_superseded"},
             {"Mark advisory", "mark_advisory"}
           ]

    assert presentation.default_effect ==
             "removes this identity from canonical reads until resolved"

    assert presentation.effects == [
             %{
               value: "mark_conflict",
               label: "Conflict",
               effect: "removes this identity from canonical reads until resolved",
               class: "border-warning/30 bg-warning/10"
             },
             %{
               value: "mark_canonical",
               label: "Canonical",
               effect: "sets this identity canonical for default dashboard reads",
               class: "border-success/30 bg-success/10"
             },
             %{
               value: "mark_superseded",
               label: "Superseded",
               effect: "marks this identity superseded by a correction",
               class: "border-info/30 bg-info/10"
             },
             %{
               value: "mark_advisory",
               label: "Advisory",
               effect: "keeps this identity as advisory history only",
               class: "border-base-300 bg-base-100/70"
             }
           ]
  end

  test "controls_available requires identity and source scope" do
    context = %{
      observation_identity_id: "identity-1",
      realm: "flight",
      data_source_id: "questdb-flight",
      source_binding_id: "binding-flight"
    }

    assert RevisionDecisionPresentation.controls_available?(context)

    refute RevisionDecisionPresentation.controls_available?(%{
             context
             | observation_identity_id: ""
           })

    refute RevisionDecisionPresentation.controls_available?(%{context | realm: nil})
    refute RevisionDecisionPresentation.controls_available?(nil)
  end
end
