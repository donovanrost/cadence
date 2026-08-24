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

    presentation = correction_form_presentation(html)
    root = presentation["root"]

    assert root == %{
             "id" => "dashboard-historical-workflow-correction-form",
             "class" => "space-y-3 rounded border border-warning/40 bg-warning/10 p-2",
             "attrs" => %{
               "phx-submit" => "record_corrected_historical_workflow_request",
               "data-workflow-action-id" => "request-correction",
               "data-workflow-action-eligible" => "true",
               "data-workflow-action-reason" => "correction_request_required",
               "data-workflow-action-preview" => "Request corrected backfill run.",
               "data-historical-workflow-correction-request-mode" => "bulk_points",
               "data-historical-workflow-correction-request-group" => "request-group-1",
               "data-historical-workflow-correction-request-item" => "2/3",
               "data-historical-workflow-correction-request-item-count" => "3"
             }
           }

    assert root["attrs"]["phx-submit"] ==
             "record_corrected_historical_workflow_request"

    assert root["attrs"]["data-workflow-action-id"] == "request-correction"
    assert root["attrs"]["data-workflow-action-eligible"] == "true"

    assert root["attrs"]["data-historical-workflow-correction-request-mode"] ==
             "bulk_points"

    assert root["attrs"]["data-historical-workflow-correction-request-group"] ==
             "request-group-1"

    assert root["attrs"]["data-historical-workflow-correction-request-item"] == "2/3"

    group_context = presentation["group_context"]

    assert group_context == %{
             "visible" => true,
             "id" => "dashboard-historical-workflow-correction-group-context",
             "class" =>
               "grid grid-cols-[7rem_minmax(0,1fr)] gap-x-2 gap-y-1 rounded border border-warning/30 bg-base-100/70 p-2 text-xs",
             "attrs" => %{
               "data-historical-workflow-correction-group-context-request-mode" => "bulk_points",
               "data-historical-workflow-correction-group-context-request-group" =>
                 "request-group-1",
               "data-historical-workflow-correction-group-context-request-item" => "2/3",
               "data-historical-workflow-correction-group-context-replacement-run" =>
                 "run-1-corrected"
             },
             "rows" => [
               group_context_row("group", "Group", "request-group-1", "font-mono break-all"),
               group_context_row("item", "Item", "2/3", "font-mono"),
               group_context_row(
                 "replacement",
                 "Replacement",
                 "run-1-corrected",
                 "font-mono break-all"
               )
             ]
           }

    assert group_context["attrs"][
             "data-historical-workflow-correction-group-context-request-group"
           ] == "request-group-1"

    assert group_context["attrs"][
             "data-historical-workflow-correction-group-context-replacement-run"
           ] == "run-1-corrected"

    hidden_fields = presentation["hidden_fields"]

    assert hidden_fields == [
             hidden_field("workflow", "workflow", "backfill"),
             hidden_field("original-run-id", "original_run_id", "run-1"),
             hidden_field("original-event-id", "original_event_id", "event-1"),
             hidden_field("original-job-id", "original_job_id", "job-1"),
             hidden_field("dashboard-id", "dashboard_id", "dashboard-1"),
             hidden_field("dashboard-version", "dashboard_version", "7"),
             hidden_field("dashboard-time-mode", "dashboard_time_mode", "replay_run"),
             hidden_field(
               "dashboard-replay-run-id",
               "dashboard_replay_run_id",
               "replay-1"
             ),
             hidden_field("dashboard-data-view", "dashboard_data_view", "all_revisions"),
             hidden_field("dashboard-limit-mode", "dashboard_limit_mode", "observed"),
             hidden_field("request-mode", "request_mode", "bulk_points"),
             hidden_field("request-group-id", "request_group_id", "request-group-1"),
             hidden_field("request-item-index", "request_item_index", "2"),
             hidden_field("request-item-count", "request_item_count", "3"),
             hidden_field("request-item-run-id", "request_item_run_id", "run-1-corrected"),
             hidden_field(
               "comparison-review-request-event-id",
               "comparison_review_request_event_id",
               ""
             ),
             hidden_field(
               "comparison-review-request-kind",
               "comparison_review_request_kind",
               ""
             ),
             hidden_field(
               "comparison-review-open-count",
               "comparison_review_open_count",
               ""
             ),
             hidden_field(
               "comparison-review-open-placement-ids",
               "comparison_review_open_placement_ids",
               ""
             ),
             hidden_field(
               "comparison-review-workflow-kind",
               "comparison_review_workflow_kind",
               ""
             ),
             hidden_field(
               "comparison-review-workflow-action",
               "comparison_review_workflow_action",
               ""
             ),
             hidden_field(
               "comparison-review-workflow-selection-kind",
               "comparison_review_workflow_selection_kind",
               ""
             ),
             hidden_field(
               "comparison-review-workflow-selection-count",
               "comparison_review_workflow_selection_count",
               ""
             ),
             hidden_field(
               "comparison-review-primary-data-view",
               "comparison_review_primary_data_view",
               ""
             ),
             hidden_field(
               "comparison-review-compare-data-view",
               "comparison_review_compare_data_view",
               ""
             ),
             hidden_field(
               "comparison-review-scope-kind",
               "comparison_review_scope_kind",
               ""
             ),
             hidden_field("comparison-review-scope-ids", "comparison_review_scope_ids", ""),
             hidden_field(
               "comparison-review-contact-ids",
               "comparison_review_contact_ids",
               ""
             ),
             hidden_field(
               "comparison-review-resource-ids",
               "comparison_review_resource_ids",
               ""
             ),
             hidden_field(
               "comparison-review-transport-ids",
               "comparison_review_transport_ids",
               ""
             ),
             hidden_field(
               "comparison-review-source-endpoint-ids",
               "comparison_review_source_endpoint_ids",
               ""
             ),
             hidden_field(
               "comparison-review-ground-station-ids",
               "comparison_review_ground_station_ids",
               ""
             ),
             hidden_field(
               "comparison-review-scope-link-ids",
               "comparison_review_scope_link_ids",
               ""
             )
           ]

    hidden_fields_by_id = Map.new(hidden_fields, &{&1["id"], &1})

    assert hidden_fields_by_id["dashboard-historical-workflow-correction-dashboard-id"][
             "value"
           ] == "dashboard-1"

    assert hidden_fields_by_id[
             "dashboard-historical-workflow-correction-dashboard-version"
           ]["value"] == "7"

    assert hidden_fields_by_id[
             "dashboard-historical-workflow-correction-dashboard-replay-run-id"
           ]["value"] == "replay-1"

    assert hidden_fields_by_id[
             "dashboard-historical-workflow-correction-dashboard-limit-mode"
           ]["value"] == "observed"

    assert hidden_fields_by_id["dashboard-historical-workflow-correction-request-mode"][
             "value"
           ] == "bulk_points"

    assert hidden_fields_by_id[
             "dashboard-historical-workflow-correction-request-group-id"
           ]["value"] == "request-group-1"

    assert hidden_fields_by_id[
             "dashboard-historical-workflow-correction-request-item-index"
           ]["value"] == "2"

    assert hidden_fields_by_id[
             "dashboard-historical-workflow-correction-request-item-count"
           ]["value"] == "3"

    assert hidden_fields_by_id[
             "dashboard-historical-workflow-correction-request-item-run-id"
           ]["value"] == "run-1-corrected"

    assert presentation["header"] == %{
             "class" => "flex items-center justify-between gap-2",
             "heading" => %{"class" => "hud-label", "text" => "Correct Request"},
             "badge" => %{
               "class" => "badge badge-xs badge-warning",
               "text" => "New run"
             }
           }

    assert presentation["new_run"] == text_field("run_id", "New Run", "run-1-corrected")

    assert presentation["source_fields_class"] == "grid grid-cols-1 gap-2"

    assert presentation["source_fields"] == [
             text_field("realm", "Realm", "flight"),
             text_field("data_source_id", "Data Source", "questdb-flight"),
             text_field("source_binding_id", "Source Binding", "binding-flight"),
             text_field("observable_id", "Observable", "HK.counter"),
             text_field("point_id", "Point", "HK.counter"),
             text_field("source_from", "Source From", "2026-06-22T10:00:00Z"),
             text_field("source_to", "Source To", "2026-06-22T11:00:00Z"),
             text_field("reason", "Reason", "correct missing point id")
           ]

    assert presentation["confirmation"] == %{
             "row" => %{
               "id" => "dashboard-historical-workflow-correction-confirm-row",
               "class" =>
                 "flex items-start gap-2 rounded border border-warning/40 bg-base-100/70 p-2 text-xs"
             },
             "input" => %{
               "id" => "dashboard-historical-workflow-correction-confirm",
               "type" => "checkbox",
               "name" => "historical_workflow_correction[confirmed]",
               "value" => "confirmed",
               "required" => true,
               "class" => "checkbox checkbox-xs mt-0.5"
             },
             "label" => %{
               "class" => "text-base-content/80",
               "text" => "Confirm corrected workflow request"
             }
           }

    assert presentation["confirmation"]["input"]["value"] == "confirmed"

    assert presentation["submit"] == %{
             "id" => "dashboard-historical-workflow-correction-submit",
             "type" => "submit",
             "class" => "btn btn-xs btn-warning btn-outline w-full justify-start",
             "icon" => %{
               "name" => "hero-document-plus",
               "class" => "h-3.5 w-3.5"
             },
             "text" => "Request corrected workflow"
           }
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
             |> LazyHTML.query("#historical-workflow-correction-form-component")
             |> LazyHTML.attribute("id")
  end

  defp correction_form_presentation(html) do
    assert ["historical-workflow-correction-form-component"] =
             html
             |> LazyHTML.from_fragment()
             |> LazyHTML.query("#historical-workflow-correction-form-component")
             |> LazyHTML.attribute("id")

    vue =
      LiveVue.Test.get_vue(html,
        id: "historical-workflow-correction-form-component"
      )

    assert vue.component == "HistoricalWorkflowCorrectionForm"
    assert vue.id == "historical-workflow-correction-form-component"
    assert vue.ssr == false
    assert vue.class == "contents"
    assert vue.handlers == %{}
    assert Map.keys(vue.props) == ["presentation"]
    assert vue.props == Jason.decode!(Jason.encode!(vue.props))

    Map.fetch!(vue.props, "presentation")
  end

  defp hidden_field(id_suffix, field, value) do
    %{
      "id" => "dashboard-historical-workflow-correction-#{id_suffix}",
      "type" => "hidden",
      "name" => "historical_workflow_correction[#{field}]",
      "value" => value
    }
  end

  defp text_field(field, label, value) do
    %{
      "id" => "historical_workflow_correction_#{field}",
      "name" => "historical_workflow_correction[#{field}]",
      "type" => "text",
      "value" => value,
      "required" => false,
      "wrapper_class" => "fieldset",
      "label" => %{"class" => "hud-label block mb-1.5", "text" => label},
      "input_class" => "w-full input",
      "errors" => [],
      "error_class" => "mt-1.5 text-sm text-error"
    }
  end

  defp group_context_row(key, label, value, value_class) do
    %{
      "key" => key,
      "label" => %{"class" => "text-base-content/60", "text" => label},
      "value" => %{"class" => value_class, "text" => value}
    }
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
