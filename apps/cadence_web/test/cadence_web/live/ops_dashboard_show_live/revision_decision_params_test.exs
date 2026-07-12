defmodule CadenceWeb.OpsDashboardShowLive.RevisionDecisionParamsTest do
  use ExUnit.Case, async: true

  alias CadenceWeb.OpsDashboardShowLive.RevisionDecisionParams

  describe "from_event/1" do
    test "unwraps and normalizes revision decision form params" do
      params =
        RevisionDecisionParams.from_event(%{
          "revision_decision" => %{
            "observation_identity_id" => " identity-1 ",
            "decision" => " mark_conflict ",
            "canonical_revision" => "2",
            "confirmed" => "confirmed"
          }
        })

      assert %RevisionDecisionParams{
               observation_identity_id: "identity-1",
               decision: "mark_conflict",
               canonical_revision: 2,
               confirmed: "confirmed"
             } = params

      assert RevisionDecisionParams.confirmed?(params)
    end

    test "accepts atom-key params without dynamic atom creation" do
      assert %RevisionDecisionParams{
               observation_identity_id: "identity-1",
               decision: "mark_canonical",
               realm: "flight"
             } =
               RevisionDecisionParams.from_event(%{
                 observation_identity_id: "identity-1",
                 decision: :mark_canonical,
                 realm: "flight"
               })
    end
  end

  describe "attrs/3" do
    test "builds command attrs and evidence ref from typed params" do
      params =
        RevisionDecisionParams.from_event(%{
          "observation_identity_id" => "identity-1",
          "decision" => "mark_conflict",
          "realm" => "flight",
          "data_source_id" => "source-1",
          "source_binding_id" => "binding-1",
          "canonical_observation_id" => "observation-1",
          "canonical_sample_id" => "sample-1",
          "canonical_revision" => "3",
          "decision_reason" => "operator_review",
          "correction_workflow_id" => "workflow-1",
          "authority" => "operator",
          "source_decision_event_id" => "event-source-1",
          "source_target" => "comparison_finding",
          "source_target_id" => "placement-1",
          "source_link_label" => "Comparison finding",
          "source_decision" => "mark_advisory",
          "dashboard_time_mode" => "replay_run",
          "dashboard_replay_run_id" => "replay-1",
          "dashboard_data_view" => "all_revisions",
          "dashboard_limit_mode" => "compare",
          "comparison_state" => "increased",
          "comparison_delta" => "+2",
          "primary_sample_id" => "sample-primary",
          "compare_sample_id" => "sample-compare",
          "primary_data_view" => "all_revisions",
          "compare_data_view" => "canonical",
          "primary_data_management" => "recomputed_analysis",
          "compare_data_management" => "degraded",
          "widget_id" => "widget-1",
          "widget_title" => "Counter"
        })

      assert RevisionDecisionParams.attrs(
               params,
               %{organization_id: "org-1", user: %{id: "operator-1"}},
               %{mission_id: "mission-1"}
             ) == %{
               organization_id: "org-1",
               mission_id: "mission-1",
               realm: "flight",
               data_source_id: "source-1",
               binding_id: "binding-1",
               canonical_observation_id: "observation-1",
               canonical_sample_id: "sample-1",
               canonical_revision: 3,
               decision_reason: "operator_review",
               correction_workflow_id: "workflow-1",
               authority: "operator",
               requested_by: "dashboard_data_link_inspector",
               operator_id: "operator-1",
               actor_id: "operator-1",
               actor_kind: "operator",
               evidence_ref: %{
                 "kind" => "dashboard_revision_decision",
                 "id" => "event-source-1",
                 "source_target" => "comparison_finding",
                 "source_target_id" => "placement-1",
                 "source_link_label" => "Comparison finding",
                 "source_panel" => "data_link_inspector",
                 "source_decision" => "mark_advisory",
                 "dashboard_context" => %{
                   "dashboard_time_mode" => "replay_run",
                   "dashboard_replay_run_id" => "replay-1",
                   "dashboard_data_view" => "all_revisions",
                   "dashboard_limit_mode" => "compare"
                 },
                 "comparison_finding" => %{
                   "placement_id" => "placement-1",
                   "state" => "increased",
                   "delta" => "+2",
                   "primary_sample_id" => "sample-primary",
                   "compare_sample_id" => "sample-compare",
                   "primary_data_view" => "all_revisions",
                   "compare_data_view" => "canonical",
                   "primary_data_management" => "recomputed_analysis",
                   "compare_data_management" => "degraded",
                   "widget_id" => "widget-1",
                   "widget_title" => "Counter"
                 }
               }
             }
    end
  end
end
