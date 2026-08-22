defmodule CadenceWeb.OpsDashboardShowLive.HistoricalWorkflowStageFormComponentsTest do
  use ExUnit.Case, async: true

  import Phoenix.Component, only: [to_form: 2]
  import Phoenix.LiveViewTest, only: [render_component: 2]

  alias CadenceWeb.OpsDashboardShowLive.HistoricalWorkflowStageFormComponents

  test "stage_transition_form renders submit contract, hidden context, and stage actions" do
    html =
      render_component(&HistoricalWorkflowStageFormComponents.stage_transition_form/1,
        form: workflow_form(),
        workflow_context: workflow_context(),
        workflow_controls: %{
          stage_actions: [
            %{
              stage: "approved",
              id: "approve",
              label: "Approve",
              icon: "hero-check-circle",
              class: "btn-success btn-outline",
              disabled?: false,
              eligible?: true,
              reason: nil,
              preview: "Approve workflow run."
            },
            %{
              stage: "completed",
              id: "complete",
              label: "Complete",
              icon: "hero-flag",
              class: "btn-primary btn-outline",
              disabled?: true,
              eligible?: false,
              reason: "not_started",
              preview: "Complete after start."
            }
          ]
        }
      )

    document = LazyHTML.from_fragment(html)

    assert ["record_historical_workflow_stage"] =
             document
             |> LazyHTML.query("#dashboard-historical-workflow-form")
             |> LazyHTML.attribute("phx-submit")

    assert ["event-1"] =
             document
             |> LazyHTML.query("#dashboard-historical-workflow-event-id")
             |> LazyHTML.attribute("value")

    assert ["correction-event-1"] =
             document
             |> LazyHTML.query("#dashboard-historical-workflow-correction-source-event-id")
             |> LazyHTML.attribute("value")

    assert ["dashboard-1"] =
             document
             |> LazyHTML.query("#dashboard-historical-workflow-dashboard-id")
             |> LazyHTML.attribute("value")

    assert ["request-group-1"] =
             document
             |> LazyHTML.query("#dashboard-historical-workflow-request-group-id")
             |> LazyHTML.attribute("value")

    assert ["confirmed"] =
             document
             |> LazyHTML.query("#dashboard-historical-workflow-confirm")
             |> LazyHTML.attribute("value")

    assert ["approved"] =
             document
             |> LazyHTML.query("#dashboard-historical-workflow-approved")
             |> LazyHTML.attribute("value")

    assert ["true"] =
             document
             |> LazyHTML.query("#dashboard-historical-workflow-approved")
             |> LazyHTML.attribute("data-workflow-action-eligible")

    assert ["completed"] =
             document
             |> LazyHTML.query("#dashboard-historical-workflow-completed")
             |> LazyHTML.attribute("value")

    assert [_disabled] =
             document
             |> LazyHTML.query("#dashboard-historical-workflow-completed")
             |> LazyHTML.attribute("disabled")

    assert ["not_started"] =
             document
             |> LazyHTML.query("#dashboard-historical-workflow-completed")
             |> LazyHTML.attribute("data-workflow-action-reason")
  end

  defp workflow_form do
    %{
      "event_id" => "event-1",
      "correction_source_event_id" => "correction-event-1",
      "workflow" => "backfill",
      "run_id" => "run-1",
      "realm" => "flight",
      "data_source_id" => "questdb-flight",
      "source_binding_id" => "binding-flight",
      "observable_id" => "HK.counter",
      "point_id" => "HK.counter",
      "dashboard_id" => "dashboard-1",
      "dashboard_version" => "7",
      "dashboard_time_mode" => "replay_run",
      "dashboard_replay_run_id" => "replay-1",
      "dashboard_data_view" => "all_revisions",
      "dashboard_limit_mode" => "observed",
      "request_group_id" => "request-group-1",
      "request_mode" => "operator",
      "reason" => "operator transition",
      "source_from" => "2026-06-22T10:00:00Z",
      "source_to" => "2026-06-22T11:00:00Z",
      "confirmed" => ""
    }
    |> to_form(as: :historical_workflow)
  end

  defp workflow_context do
    %{
      event_id: "event-1",
      correction_source_event_id: "correction-event-1",
      workflow: "backfill",
      run_id: "run-1",
      realm: "flight",
      data_source_id: "questdb-flight",
      source_binding_id: "binding-flight",
      observable_id: "HK.counter",
      point_id: "HK.counter",
      dashboard_id: "dashboard-1",
      dashboard_version: "7",
      dashboard_time_mode: "replay_run",
      dashboard_replay_run_id: "replay-1",
      dashboard_data_view: "all_revisions",
      dashboard_limit_mode: "observed",
      request_group_id: "request-group-1",
      request_mode: "operator",
      reason: "operator transition"
    }
  end
end
