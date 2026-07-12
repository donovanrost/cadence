defmodule CadenceWeb.OpsDashboardShowLive.HistoricalWorkflowGroupFormComponentsTest do
  use ExUnit.Case, async: true

  import Phoenix.Component, only: [to_form: 2]
  import Phoenix.LiveViewTest, only: [render_component: 2]

  alias CadenceWeb.OpsDashboardShowLive.HistoricalWorkflowGroupFormComponents

  test "group_transition_form renders submit contract, hidden context, and group actions" do
    html =
      render_component(&HistoricalWorkflowGroupFormComponents.group_transition_form/1,
        form: group_form(),
        workflow_context: workflow_context(),
        workflow_controls: %{
          group_actions: true,
          group_stage_actions: [
            %{
              stage: "approved",
              id: "group-approve",
              label: "Approve",
              icon: "hero-check-circle",
              class: "btn-success btn-outline",
              disabled?: false,
              eligible?: true,
              eligible_count: 3,
              reason: nil,
              preview: "Approve eligible items.",
              correction_tasks:
                "HK.current run-3 replacement run-3-corrected stage requested next approve"
            },
            %{
              stage: "completed",
              id: "group-complete",
              label: "Complete",
              icon: "hero-flag",
              class: "btn-primary btn-outline",
              disabled?: true,
              eligible?: false,
              eligible_count: 0,
              reason: "not_started",
              preview: "Complete after start."
            },
            %{
              stage: "started",
              id: "group-start",
              label: "Start",
              icon: "hero-play",
              class: "btn-info btn-outline",
              disabled?: false,
              eligible?: true,
              eligible_count: 3,
              reason: "eligible_group_items",
              preview: "Record start transition for 3 eligible review items.",
              state_summary: "group request-group-1; progress 3/3; eligible 3 for started"
            }
          ]
        }
      )

    document = LazyHTML.from_fragment(html)

    assert ["record_historical_workflow_group_stage"] =
             document
             |> LazyHTML.query("#dashboard-historical-workflow-group-form")
             |> LazyHTML.attribute("phx-submit")

    assert ["request-group-1"] =
             document
             |> LazyHTML.query("#dashboard-historical-workflow-group-request-group-id")
             |> LazyHTML.attribute("value")

    assert ["dashboard-1"] =
             document
             |> LazyHTML.query("#dashboard-historical-workflow-group-dashboard-id")
             |> LazyHTML.attribute("value")

    assert ["observed"] =
             document
             |> LazyHTML.query("#dashboard-historical-workflow-group-dashboard-limit-mode")
             |> LazyHTML.attribute("value")

    assert ["confirmed"] =
             document
             |> LazyHTML.query("#dashboard-historical-workflow-group-confirm")
             |> LazyHTML.attribute("value")

    assert ["request-group-1"] =
             document
             |> LazyHTML.query("#dashboard-historical-workflow-group-eligible-items")
             |> LazyHTML.attribute("data-historical-workflow-group-eligible-request-group")

    assert ["3"] =
             document
             |> LazyHTML.query(~s([data-historical-workflow-group-eligible-action="approved"]))
             |> LazyHTML.attribute("data-historical-workflow-group-eligible-count")

    assert ["true"] =
             document
             |> LazyHTML.query(~s([data-historical-workflow-group-eligible-action="approved"]))
             |> LazyHTML.attribute("data-historical-workflow-group-eligible-state")

    assert ["HK.current run-3 replacement run-3-corrected stage requested next approve"] =
             document
             |> LazyHTML.query(~s([data-historical-workflow-group-eligible-action="approved"]))
             |> LazyHTML.attribute("data-workflow-action-correction-tasks")

    assert ["0"] =
             document
             |> LazyHTML.query(~s([data-historical-workflow-group-eligible-action="completed"]))
             |> LazyHTML.attribute("data-historical-workflow-group-eligible-count")

    assert ["not_started"] =
             document
             |> LazyHTML.query(~s([data-historical-workflow-group-eligible-action="completed"]))
             |> LazyHTML.attribute("data-historical-workflow-group-eligible-reason")

    assert ["start_eligible_items"] =
             document
             |> LazyHTML.query("#dashboard-historical-workflow-group-start-orchestration")
             |> LazyHTML.attribute("data-historical-workflow-group-start-next-action")

    assert ["3"] =
             document
             |> LazyHTML.query("#dashboard-historical-workflow-group-start-orchestration")
             |> LazyHTML.attribute("data-historical-workflow-group-start-eligible")

    assert ["3"] =
             document
             |> LazyHTML.query("#dashboard-historical-workflow-group-start-orchestration")
             |> LazyHTML.attribute("data-historical-workflow-group-start-expected-jobs")

    assert ["review-request-1"] =
             document
             |> LazyHTML.query("#dashboard-historical-workflow-group-start-orchestration")
             |> LazyHTML.attribute("data-historical-workflow-group-start-review-request")

    assert ["placement-1,placement-2,placement-3"] =
             document
             |> LazyHTML.query("#dashboard-historical-workflow-group-start-orchestration")
             |> LazyHTML.attribute("data-historical-workflow-group-start-review-placements")

    assert ["transport-alpha,transport-beta"] =
             document
             |> LazyHTML.query("#dashboard-historical-workflow-group-comparison-review-scope-ids")
             |> LazyHTML.attribute("value")

    assert ["contact-alpha,contact-beta"] =
             document
             |> LazyHTML.query(
               "#dashboard-historical-workflow-group-comparison-review-contact-ids"
             )
             |> LazyHTML.attribute("value")

    assert ["transport-alpha,transport-beta"] =
             document
             |> LazyHTML.query("#dashboard-historical-workflow-group-start-orchestration")
             |> LazyHTML.attribute("data-historical-workflow-group-start-review-scope-ids")

    assert ["contact-alpha,contact-beta"] =
             document
             |> LazyHTML.query("#dashboard-historical-workflow-group-start-orchestration")
             |> LazyHTML.attribute("data-historical-workflow-group-start-review-contact-ids")

    assert ["eligible_group_items"] =
             document
             |> LazyHTML.query("#dashboard-historical-workflow-group-start-orchestration")
             |> LazyHTML.attribute("data-historical-workflow-group-start-reason")

    assert document
           |> LazyHTML.query("#dashboard-historical-workflow-group-start-orchestration")
           |> LazyHTML.text()
           |> String.contains?("3 review findings are attached.")

    assert ["approved"] =
             document
             |> LazyHTML.query("#dashboard-historical-workflow-group-approved")
             |> LazyHTML.attribute("value")

    assert ["3"] =
             document
             |> LazyHTML.query("#dashboard-historical-workflow-group-approved")
             |> LazyHTML.attribute("data-historical-workflow-group-action-eligible")

    assert ["true"] =
             document
             |> LazyHTML.query("#dashboard-historical-workflow-group-approved")
             |> LazyHTML.attribute("data-workflow-action-eligible")

    assert ["HK.current run-3 replacement run-3-corrected stage requested next approve"] =
             document
             |> LazyHTML.query("#dashboard-historical-workflow-group-approved")
             |> LazyHTML.attribute("data-workflow-action-correction-tasks")

    assert ["completed"] =
             document
             |> LazyHTML.query("#dashboard-historical-workflow-group-completed")
             |> LazyHTML.attribute("value")

    assert [_disabled] =
             document
             |> LazyHTML.query("#dashboard-historical-workflow-group-completed")
             |> LazyHTML.attribute("disabled")

    assert ["not_started"] =
             document
             |> LazyHTML.query("#dashboard-historical-workflow-group-completed")
             |> LazyHTML.attribute("data-workflow-action-reason")
  end

  test "group_transition_form does not render when group actions are unavailable" do
    html =
      render_component(&HistoricalWorkflowGroupFormComponents.group_transition_form/1,
        form: group_form(),
        workflow_context: workflow_context(),
        workflow_controls: %{group_actions: false, group_stage_actions: []}
      )

    document = LazyHTML.from_fragment(html)

    assert [] =
             document
             |> LazyHTML.query("#dashboard-historical-workflow-group-form")
             |> LazyHTML.attribute("id")
  end

  defp group_form do
    %{
      "workflow" => "backfill",
      "request_group_id" => "request-group-1",
      "realm" => "flight",
      "data_source_id" => "questdb-flight",
      "source_binding_id" => "binding-flight",
      "dashboard_id" => "dashboard-1",
      "dashboard_version" => "7",
      "dashboard_time_mode" => "replay_run",
      "dashboard_replay_run_id" => "replay-1",
      "dashboard_data_view" => "all_revisions",
      "dashboard_limit_mode" => "observed",
      "reason" => "operator group transition",
      "confirmed" => ""
    }
    |> to_form(as: :historical_workflow_group)
  end

  defp workflow_context do
    %{
      workflow: "backfill",
      request_group_id: "request-group-1",
      realm: "flight",
      data_source_id: "questdb-flight",
      source_binding_id: "binding-flight",
      dashboard_id: "dashboard-1",
      dashboard_version: "7",
      dashboard_time_mode: "replay_run",
      dashboard_replay_run_id: "replay-1",
      dashboard_data_view: "all_revisions",
      dashboard_limit_mode: "observed",
      request_item_count: "3",
      comparison_review_request_event_id: "review-request-1",
      comparison_review_request_kind: "comparison_open_findings_review",
      comparison_review_open_count: "3",
      comparison_review_open_placement_ids: "placement-1,placement-2,placement-3",
      comparison_review_scope_kind: "transport",
      comparison_review_scope_ids: "transport-alpha,transport-beta",
      comparison_review_contact_ids: "contact-alpha,contact-beta",
      comparison_review_resource_ids: "transport-alpha",
      comparison_review_transport_ids: "transport-alpha",
      comparison_review_source_endpoint_ids: "endpoint-alpha",
      comparison_review_ground_station_ids: "dss-14",
      comparison_review_scope_link_ids: "link-alpha",
      reason: "operator group transition"
    }
  end
end
