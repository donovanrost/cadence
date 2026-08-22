defmodule CadenceWeb.OpsDashboardShowLive.HistoricalWorkflowRequestFormComponentsTest do
  use ExUnit.Case, async: true

  import Phoenix.Component, only: [to_form: 2]
  import Phoenix.LiveViewTest, only: [render_component: 2]

  alias CadenceWeb.OpsDashboardShowLive.HistoricalWorkflowRequestFormComponents

  test "request_form renders submit contract and request context fields" do
    html =
      render_component(&HistoricalWorkflowRequestFormComponents.request_form/1,
        form:
          to_form(
            %{
              "workflow" => "backfill",
              "run_id" => "run-1",
              "realm" => "flight",
              "data_source_id" => "questdb-flight",
              "source_binding_id" => "binding-flight",
              "dashboard_id" => "dashboard-power",
              "dashboard_version" => "3",
              "dashboard_time_mode" => "archive",
              "dashboard_replay_run_id" => "replay-1",
              "dashboard_data_view" => "as_recorded",
              "dashboard_limit_mode" => "observed",
              "comparison_review_request_event_id" => "review-request-1",
              "comparison_review_request_kind" => "comparison_open_findings_review",
              "comparison_review_open_count" => "2",
              "comparison_review_open_placement_ids" => "placement-1,placement-2",
              "comparison_review_scope_kind" => "transport",
              "comparison_review_scope_ids" => "transport-alpha,transport-beta",
              "comparison_review_contact_ids" => "contact-alpha,contact-beta",
              "comparison_review_resource_ids" => "transport-alpha",
              "comparison_review_transport_ids" => "transport-alpha",
              "comparison_review_source_endpoint_ids" => "endpoint-alpha",
              "comparison_review_ground_station_ids" => "dss-14",
              "comparison_review_scope_link_ids" => "link-alpha"
            },
            as: :historical_workflow_request
          )
      )

    document = LazyHTML.from_fragment(html)

    assert ["record_historical_workflow_request"] =
             document
             |> LazyHTML.query("#dashboard-historical-workflow-request-form")
             |> LazyHTML.attribute("phx-submit")

    assert ["backfill"] =
             document
             |> LazyHTML.query(
               ~s(select[name="historical_workflow_request[workflow]"] option[selected])
             )
             |> LazyHTML.attribute("value")

    assert ["run-1"] =
             document
             |> LazyHTML.query(~s(input[name="historical_workflow_request[run_id]"]))
             |> LazyHTML.attribute("value")

    assert ["flight"] =
             document
             |> LazyHTML.query(~s(input[name="historical_workflow_request[realm]"]))
             |> LazyHTML.attribute("value")

    assert ["questdb-flight"] =
             document
             |> LazyHTML.query(~s(input[name="historical_workflow_request[data_source_id]"]))
             |> LazyHTML.attribute("value")

    assert ["binding-flight"] =
             document
             |> LazyHTML.query(~s(input[name="historical_workflow_request[source_binding_id]"]))
             |> LazyHTML.attribute("value")

    assert ["dashboard-power"] =
             document
             |> LazyHTML.query(~s(input[name="historical_workflow_request[dashboard_id]"]))
             |> LazyHTML.attribute("value")

    assert ["3"] =
             document
             |> LazyHTML.query(~s(input[name="historical_workflow_request[dashboard_version]"]))
             |> LazyHTML.attribute("value")

    assert ["archive"] =
             document
             |> LazyHTML.query(~s(input[name="historical_workflow_request[dashboard_time_mode]"]))
             |> LazyHTML.attribute("value")

    assert ["replay-1"] =
             document
             |> LazyHTML.query(
               ~s(input[name="historical_workflow_request[dashboard_replay_run_id]"])
             )
             |> LazyHTML.attribute("value")

    assert ["as_recorded"] =
             document
             |> LazyHTML.query(~s(input[name="historical_workflow_request[dashboard_data_view]"]))
             |> LazyHTML.attribute("value")

    assert ["observed"] =
             document
             |> LazyHTML.query(
               ~s(input[name="historical_workflow_request[dashboard_limit_mode]"])
             )
             |> LazyHTML.attribute("value")

    assert ["review-request-1"] =
             document
             |> LazyHTML.query(
               ~s(input[name="historical_workflow_request[comparison_review_request_event_id]"])
             )
             |> LazyHTML.attribute("value")

    assert ["comparison_open_findings_review"] =
             document
             |> LazyHTML.query(
               ~s(input[name="historical_workflow_request[comparison_review_request_kind]"])
             )
             |> LazyHTML.attribute("value")

    assert ["2"] =
             document
             |> LazyHTML.query(
               ~s(input[name="historical_workflow_request[comparison_review_open_count]"])
             )
             |> LazyHTML.attribute("value")

    assert ["placement-1,placement-2"] =
             document
             |> LazyHTML.query(
               ~s(input[name="historical_workflow_request[comparison_review_open_placement_ids]"])
             )
             |> LazyHTML.attribute("value")

    assert ["transport"] =
             document
             |> LazyHTML.query(
               ~s(input[name="historical_workflow_request[comparison_review_scope_kind]"])
             )
             |> LazyHTML.attribute("value")

    assert ["transport-alpha,transport-beta"] =
             document
             |> LazyHTML.query(
               ~s(input[name="historical_workflow_request[comparison_review_scope_ids]"])
             )
             |> LazyHTML.attribute("value")

    assert ["contact-alpha,contact-beta"] =
             document
             |> LazyHTML.query(
               ~s(input[name="historical_workflow_request[comparison_review_contact_ids]"])
             )
             |> LazyHTML.attribute("value")

    assert ["endpoint-alpha"] =
             document
             |> LazyHTML.query(
               ~s(input[name="historical_workflow_request[comparison_review_source_endpoint_ids]"])
             )
             |> LazyHTML.attribute("value")

    assert "Backfill" =
             document
             |> LazyHTML.query(~s([data-preview-field="workflow"] dd))
             |> selected_text()

    assert "flight / questdb-flight / binding-flight" =
             document
             |> LazyHTML.query(~s([data-preview-field="source"] dd))
             |> selected_text()

    assert "dashboard-power v3" =
             document
             |> LazyHTML.query(~s([data-preview-field="dashboard"] dd))
             |> selected_text()

    assert "archive / replay-1 / as_recorded / observed" =
             document
             |> LazyHTML.query(~s([data-preview-field="runtime"] dd))
             |> selected_text()

    assert "transport / transport-alpha,transport-beta / contact-alpha,contact-beta / transport-alpha / endpoint-alpha / dss-14 / link-alpha" =
             document
             |> LazyHTML.query(~s([data-preview-field="comparison_scope"] dd))
             |> selected_text()
  end

  test "request_form renders source window fields and confirmation control" do
    html =
      render_component(&HistoricalWorkflowRequestFormComponents.request_form/1,
        form:
          to_form(
            %{
              "observable_id" => "HK.counter",
              "point_id" => "point-1",
              "point_ids" => "point-1,point-2",
              "source_from" => "2026-06-26T00:00:00Z",
              "source_to" => "2026-06-26T01:00:00Z",
              "reason" => "operator_requested"
            },
            as: :historical_workflow_request
          )
      )

    document = LazyHTML.from_fragment(html)

    assert ["HK.counter"] =
             document
             |> LazyHTML.query(~s(input[name="historical_workflow_request[observable_id]"]))
             |> LazyHTML.attribute("value")

    assert ["point-1"] =
             document
             |> LazyHTML.query(~s(input[name="historical_workflow_request[point_id]"]))
             |> LazyHTML.attribute("value")

    assert ["Comma, space, or newline separated point IDs"] =
             document
             |> LazyHTML.query(~s(input[name="historical_workflow_request[point_ids]"]))
             |> LazyHTML.attribute("placeholder")

    assert "2 points: point-1, point-2" =
             document
             |> LazyHTML.query(~s([data-preview-field="points"] dd))
             |> selected_text()

    assert "2026-06-26T00:00:00Z -> 2026-06-26T01:00:00Z" =
             document
             |> LazyHTML.query(~s([data-preview-field="window"] dd))
             |> selected_text()

    assert ["confirmed"] =
             document
             |> LazyHTML.query("#dashboard-historical-workflow-request-confirm")
             |> LazyHTML.attribute("value")

    assert [""] =
             document
             |> LazyHTML.query("#dashboard-historical-workflow-request-confirm")
             |> LazyHTML.attribute("required")

    assert "Record request" =
             document
             |> LazyHTML.query("#dashboard-historical-workflow-request-submit")
             |> selected_text()
  end

  defp selected_text(document) do
    document
    |> LazyHTML.text()
    |> String.trim()
  end
end
