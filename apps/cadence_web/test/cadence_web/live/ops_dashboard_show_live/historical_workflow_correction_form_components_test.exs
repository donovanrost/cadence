defmodule CadenceWeb.OpsDashboardShowLive.HistoricalWorkflowCorrectionFormComponentsTest do
  use ExUnit.Case, async: true

  import Phoenix.Component, only: [to_form: 2]
  import Phoenix.LiveViewTest, only: [render_component: 2]

  alias CadenceWeb.OpsDashboardShowLive.HistoricalWorkflowCorrectionFormComponents

  test "corrected_request_form renders submit contract, action metadata, and hidden context" do
    html =
      render_component(&HistoricalWorkflowCorrectionFormComponents.corrected_request_form/1,
        form: correction_form(),
        workflow_context: workflow_context(),
        workflow_controls: %{
          correction_requestable: true,
          correction_request_action: %{
            id: "request-correction",
            eligible?: true,
            reason: "correction_request_required",
            preview: "Request corrected backfill run."
          }
        }
      )

    document = LazyHTML.from_fragment(html)

    assert ["record_corrected_historical_workflow_request"] =
             document
             |> LazyHTML.query("#dashboard-historical-workflow-correction-form")
             |> LazyHTML.attribute("phx-submit")

    assert ["request-correction"] =
             document
             |> LazyHTML.query("#dashboard-historical-workflow-correction-form")
             |> LazyHTML.attribute("data-workflow-action-id")

    assert ["true"] =
             document
             |> LazyHTML.query("#dashboard-historical-workflow-correction-form")
             |> LazyHTML.attribute("data-workflow-action-eligible")

    assert ["bulk_points"] =
             document
             |> LazyHTML.query("#dashboard-historical-workflow-correction-form")
             |> LazyHTML.attribute("data-historical-workflow-correction-request-mode")

    assert ["request-group-1"] =
             document
             |> LazyHTML.query("#dashboard-historical-workflow-correction-form")
             |> LazyHTML.attribute("data-historical-workflow-correction-request-group")

    assert ["2/3"] =
             document
             |> LazyHTML.query("#dashboard-historical-workflow-correction-form")
             |> LazyHTML.attribute("data-historical-workflow-correction-request-item")

    assert ["request-group-1"] =
             document
             |> LazyHTML.query("#dashboard-historical-workflow-correction-group-context")
             |> LazyHTML.attribute(
               "data-historical-workflow-correction-group-context-request-group"
             )

    assert ["run-1-corrected"] =
             document
             |> LazyHTML.query("#dashboard-historical-workflow-correction-group-context")
             |> LazyHTML.attribute(
               "data-historical-workflow-correction-group-context-replacement-run"
             )

    assert ["dashboard-1"] =
             document
             |> LazyHTML.query("#dashboard-historical-workflow-correction-dashboard-id")
             |> LazyHTML.attribute("value")

    assert ["7"] =
             document
             |> LazyHTML.query("#dashboard-historical-workflow-correction-dashboard-version")
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

    assert ["bulk_points"] =
             document
             |> LazyHTML.query("#dashboard-historical-workflow-correction-request-mode")
             |> LazyHTML.attribute("value")

    assert ["request-group-1"] =
             document
             |> LazyHTML.query("#dashboard-historical-workflow-correction-request-group-id")
             |> LazyHTML.attribute("value")

    assert ["2"] =
             document
             |> LazyHTML.query("#dashboard-historical-workflow-correction-request-item-index")
             |> LazyHTML.attribute("value")

    assert ["3"] =
             document
             |> LazyHTML.query("#dashboard-historical-workflow-correction-request-item-count")
             |> LazyHTML.attribute("value")

    assert ["run-1-corrected"] =
             document
             |> LazyHTML.query("#dashboard-historical-workflow-correction-request-item-run-id")
             |> LazyHTML.attribute("value")

    assert ["confirmed"] =
             document
             |> LazyHTML.query("#dashboard-historical-workflow-correction-confirm")
             |> LazyHTML.attribute("value")
  end

  test "corrected_request_form does not render when correction is not requestable" do
    html =
      render_component(&HistoricalWorkflowCorrectionFormComponents.corrected_request_form/1,
        form: correction_form(),
        workflow_context: workflow_context(),
        workflow_controls: %{
          correction_requestable: false,
          correction_request_action: %{
            id: "request-correction",
            eligible?: false,
            reason: "job_not_failed",
            preview: "No correction needed."
          }
        }
      )

    document = LazyHTML.from_fragment(html)

    assert [] =
             document
             |> LazyHTML.query("#dashboard-historical-workflow-correction-form")
             |> LazyHTML.attribute("id")
  end

  defp correction_form do
    %{
      "workflow" => "backfill",
      "run_id" => "run-1-corrected",
      "original_run_id" => "run-1",
      "original_event_id" => "event-1",
      "original_job_id" => "job-1",
      "realm" => "flight",
      "data_source_id" => "questdb-flight",
      "source_binding_id" => "binding-flight",
      "observable_id" => "HK.counter",
      "point_id" => "HK.counter",
      "source_from" => "2026-06-22T10:00:00Z",
      "source_to" => "2026-06-22T11:00:00Z",
      "reason" => "correct missing point id",
      "dashboard_id" => "dashboard-1",
      "dashboard_version" => "7",
      "dashboard_time_mode" => "replay_run",
      "dashboard_replay_run_id" => "replay-1",
      "dashboard_data_view" => "all_revisions",
      "dashboard_limit_mode" => "observed",
      "request_mode" => "bulk_points",
      "request_group_id" => "request-group-1",
      "request_item_index" => "2",
      "request_item_count" => "3",
      "request_item_run_id" => "run-1-corrected",
      "confirmed" => ""
    }
    |> to_form(as: :historical_workflow_correction)
  end

  defp workflow_context do
    %{
      workflow: "backfill",
      run_id: "run-1",
      event_id: "event-1",
      job_id: "job-1",
      dashboard_id: "dashboard-1",
      dashboard_version: "7",
      dashboard_time_mode: "replay_run",
      dashboard_replay_run_id: "replay-1",
      dashboard_data_view: "all_revisions",
      dashboard_limit_mode: "observed",
      request_mode: "bulk_points",
      request_group_id: "request-group-1",
      request_item: "2/3",
      request_item_count: 3
    }
  end
end
