defmodule CadenceWeb.OpsDashboardShowLive.HistoricalWorkflowParamsTest do
  use ExUnit.Case, async: true

  alias CadenceWeb.OpsDashboardShowLive.HistoricalWorkflowParams

  describe "params extraction" do
    test "unwraps historical workflow form params" do
      params = %{"historical_workflow" => %{"workflow" => "backfill"}}

      assert %HistoricalWorkflowParams{kind: :stage, workflow: "backfill"} =
               HistoricalWorkflowParams.event_params(params)
    end

    test "unwraps request, correction, and group form params" do
      assert %HistoricalWorkflowParams{kind: :request, workflow: "backfill"} =
               HistoricalWorkflowParams.request_params(%{
                 "historical_workflow_request" => %{"workflow" => "backfill"}
               })

      assert %HistoricalWorkflowParams{kind: :correction_request, workflow: "import"} =
               HistoricalWorkflowParams.correction_params(%{
                 "historical_workflow_correction" => %{"workflow" => "import"}
               })

      assert %HistoricalWorkflowParams{kind: :group_stage, request_group_id: "group-1"} =
               HistoricalWorkflowParams.group_params(%{
                 "historical_workflow_group" => %{"request_group_id" => "group-1"}
               })
    end

    test "converts typed params to compact event params for navigation links" do
      params =
        HistoricalWorkflowParams.event_params(%{
          "workflow" => " backfill ",
          "stage" => " approved ",
          "confirmed" => "",
          "event_id" => "event-1"
        })

      assert HistoricalWorkflowParams.to_event_params(params) == %{
               "workflow" => "backfill",
               "stage" => "approved",
               "event_id" => "event-1"
             }
    end

    test "preserves grouped correction request context as compact event params" do
      params =
        HistoricalWorkflowParams.correction_params(%{
          "workflow" => "backfill",
          "run_id" => "run-1-corrected",
          "request_mode" => "bulk_points",
          "request_group_id" => " group-1 ",
          "request_item_index" => " 2 ",
          "request_item_count" => " 3 ",
          "request_item_run_id" => " run-1-corrected "
        })

      assert HistoricalWorkflowParams.to_event_params(params) == %{
               "workflow" => "backfill",
               "run_id" => "run-1-corrected",
               "request_mode" => "bulk_points",
               "request_group_id" => "group-1",
               "request_item_index" => "2",
               "request_item_count" => "3",
               "request_item_run_id" => "run-1-corrected"
             }
    end
  end

  describe "attrs/3" do
    test "builds compact command attrs from mixed legacy and form keys" do
      params = %{
        "workflow" => "backfill",
        "stage" => "approved",
        "run-id" => "run-1",
        "realm" => "backfill",
        "data_source_id" => "source-1",
        "source-binding-id" => "binding-1",
        "observable_id" => "obs-1",
        "point-id" => "point-1",
        "source_from" => "2026-06-25T00:00:00Z",
        "source-to" => "2026-06-25T01:00:00Z",
        "reason" => ""
      }

      scope = %{organization_id: "org-1", user: %{id: "user-1"}}
      mission = %{mission_id: "mission-1"}

      assert HistoricalWorkflowParams.attrs(params, scope, mission) == %{
               backfill_run_id: "run-1",
               import_run_id: "run-1",
               organization_id: "org-1",
               mission_id: "mission-1",
               realm: "backfill",
               data_source_id: "source-1",
               binding_id: "binding-1",
               observable_id: "obs-1",
               point_id: "point-1",
               source_from: "2026-06-25T00:00:00Z",
               source_to: "2026-06-25T01:00:00Z",
               actor_id: "user-1",
               actor_kind: "operator",
               authority: :authoritative,
               reason: "dashboard_backfill_approved"
             }
    end

    test "uses explicit reason and fallback user_id actor field" do
      params = %{"workflow" => "backfill", "stage" => "failed", "reason" => "operator note"}
      scope = %{organization_id: "org-1", user: %{user_id: "user-2"}}
      mission = %{mission_id: "mission-1"}

      assert %{
               actor_id: "user-2",
               authority: :advisory,
               reason: "operator note"
             } = HistoricalWorkflowParams.attrs(params, scope, mission)
    end

    test "includes dashboard request context payload when submitted" do
      params = %{
        "workflow" => "backfill",
        "stage" => "requested",
        "dashboard_id" => "dashboard-power",
        "dashboard_version" => "7",
        "dashboard_time_mode" => "archive",
        "dashboard_replay_run_id" => "replay-7",
        "dashboard_data_view" => "as_recorded",
        "dashboard_limit_mode" => "observed",
        "comparison_review_request_event_id" => "review-request-1",
        "comparison_review_request_kind" => "comparison_open_findings_review",
        "comparison_review_open_count" => "2",
        "comparison_review_open_placement_ids" => "placement-1,placement-2",
        "comparison_review_workflow_kind" => "bulk_correction_authority_review",
        "comparison_review_workflow_action" => "request_comparison_review",
        "comparison_review_workflow_selection_kind" => "open_comparison_findings",
        "comparison_review_workflow_selection_count" => "2",
        "comparison_review_primary_data_view" => "all_revisions",
        "comparison_review_compare_data_view" => "canonical",
        "comparison_review_scope_kind" => "transport",
        "comparison_review_scope_ids" => "transport-alpha,transport-beta",
        "comparison_review_contact_ids" => "contact-alpha,contact-beta",
        "comparison_review_resource_ids" => "transport-alpha",
        "comparison_review_transport_ids" => "transport-alpha",
        "comparison_review_source_endpoint_ids" => "endpoint-alpha",
        "comparison_review_ground_station_ids" => "dss-14",
        "comparison_review_scope_link_ids" => "link-alpha"
      }

      scope = %{organization_id: "org-1", user: %{id: "user-1"}}
      mission = %{mission_id: "mission-1"}

      assert %{
               payload: %{
                 "dashboard_context" => %{
                   "dashboard_id" => "dashboard-power",
                   "dashboard_version" => "7",
                   "dashboard_time_mode" => "archive",
                   "dashboard_replay_run_id" => "replay-7",
                   "dashboard_data_view" => "as_recorded",
                   "dashboard_limit_mode" => "observed"
                 },
                 "comparison_review_origin" => %{
                   "request_event_id" => "review-request-1",
                   "request_kind" => "comparison_open_findings_review",
                   "open_count" => "2",
                   "open_placement_ids" => "placement-1,placement-2",
                   "workflow_kind" => "bulk_correction_authority_review",
                   "workflow_action" => "request_comparison_review",
                   "workflow_selection_kind" => "open_comparison_findings",
                   "workflow_selection_count" => "2",
                   "primary_data_view" => "all_revisions",
                   "compare_data_view" => "canonical",
                   "scope_kind" => "transport",
                   "scope_ids" => "transport-alpha,transport-beta",
                   "contact_ids" => "contact-alpha,contact-beta",
                   "resource_ids" => "transport-alpha",
                   "transport_ids" => "transport-alpha",
                   "source_endpoint_ids" => "endpoint-alpha",
                   "ground_station_ids" => "dss-14",
                   "scope_link_ids" => "link-alpha"
                 }
               }
             } = HistoricalWorkflowParams.attrs(params, scope, mission)
    end
  end

  describe "actor_attrs/2" do
    test "returns compact tenant and actor attrs for retry commands" do
      scope = %{organization_id: "org-1", user: %{}}
      mission = %{mission_id: "mission-1"}

      assert HistoricalWorkflowParams.actor_attrs(scope, mission) == %{
               organization_id: "org-1",
               mission_id: "mission-1",
               actor_kind: "operator"
             }
    end
  end

  describe "request_point_ids/1" do
    test "splits comma, whitespace, tab, and newline separated point ids" do
      params = %{"point_ids" => " point-1,point-2\npoint-3\tpoint-2 "}

      assert HistoricalWorkflowParams.request_point_ids(params) == [
               "point-1",
               "point-2",
               "point-3"
             ]
    end

    test "falls back to point_id and observable_id when bulk point ids are blank" do
      params = %{"point_ids" => " ", "point_id" => "point-1", "observable_id" => "point-1"}

      assert HistoricalWorkflowParams.request_point_ids(params) == ["point-1"]
    end
  end

  describe "confirmation and group ids" do
    test "accepts submitted confirmation values" do
      assert HistoricalWorkflowParams.confirmed?(%{"confirmed" => "true"})
      assert HistoricalWorkflowParams.confirmed?(%{"confirmed" => "confirmed"})
      assert HistoricalWorkflowParams.confirmed?(%{"confirmed" => "on"})
      refute HistoricalWorkflowParams.confirmed?(%{"confirmed" => "false"})
    end

    test "normalizes request group ids" do
      assert HistoricalWorkflowParams.request_group_id(%{"request_group_id" => " group-1 "}) ==
               "group-1"

      assert is_nil(HistoricalWorkflowParams.request_group_id(%{"request_group_id" => " "}))
    end
  end
end
