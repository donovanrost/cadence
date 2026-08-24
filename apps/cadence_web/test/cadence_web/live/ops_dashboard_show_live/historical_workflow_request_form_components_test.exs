defmodule CadenceWeb.OpsDashboardShowLive.HistoricalWorkflowRequestFormComponentsTest do
  use ExUnit.Case, async: true

  import Phoenix.Component, only: [to_form: 2]
  import Phoenix.LiveViewTest, only: [render_component: 2]

  alias CadenceWeb.OpsDashboardShowLive.HistoricalWorkflowRequestFormComponents

  @hidden_field_keys ~w(
    dashboard_id dashboard_version dashboard_time_mode dashboard_replay_run_id
    dashboard_data_view dashboard_limit_mode comparison_review_request_event_id
    comparison_review_request_kind comparison_review_open_count
    comparison_review_open_placement_ids comparison_review_workflow_kind
    comparison_review_workflow_action comparison_review_workflow_selection_kind
    comparison_review_workflow_selection_count comparison_review_primary_data_view
    comparison_review_compare_data_view comparison_review_scope_kind
    comparison_review_scope_ids comparison_review_contact_ids comparison_review_resource_ids
    comparison_review_transport_ids comparison_review_source_endpoint_ids
    comparison_review_ground_station_ids comparison_review_scope_link_ids
  )

  test "request_form renders submit contract and request context fields" do
    params = %{
      "workflow" => "backfill",
      "run_id" => "run-1",
      "realm" => "flight",
      "data_source_id" => "questdb-flight",
      "source_binding_id" => "binding-flight",
      "observable_id" => "EPS.power",
      "point_id" => "point-power",
      "point_ids" => "point-power",
      "source_from" => "2026-06-25T00:00:00Z",
      "source_to" => "2026-06-25T01:00:00Z",
      "reason" => "historical_gap",
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
      "comparison_review_workflow_kind" => "comparison_review",
      "comparison_review_workflow_action" => "prepare_backfill",
      "comparison_review_workflow_selection_kind" => "placements",
      "comparison_review_workflow_selection_count" => "2",
      "comparison_review_primary_data_view" => "all_revisions",
      "comparison_review_compare_data_view" => "as_recorded",
      "comparison_review_scope_kind" => "transport",
      "comparison_review_scope_ids" => "transport-alpha,transport-beta",
      "comparison_review_contact_ids" => "contact-alpha,contact-beta",
      "comparison_review_resource_ids" => "transport-alpha",
      "comparison_review_transport_ids" => "transport-alpha",
      "comparison_review_source_endpoint_ids" => "endpoint-alpha",
      "comparison_review_ground_station_ids" => "dss-14",
      "comparison_review_scope_link_ids" => "link-alpha"
    }

    html =
      render_component(&HistoricalWorkflowRequestFormComponents.request_form/1,
        form: to_form(params, as: :historical_workflow_request)
      )

    presentation = request_form_presentation(html)
    request_fields = request_context_fields(presentation)
    hidden_fields = hidden_fields(presentation)
    preview_rows = preview_rows(presentation)

    assert presentation["root"]["attrs"]["phx-submit"] ==
             "record_historical_workflow_request"

    assert selected_option(request_fields["workflow"])["attrs"]["value"] == "backfill"

    assert request_fields["run_id"]["control"]["attrs"]["value"] == "run-1"

    assert request_fields["realm"]["control"]["attrs"]["value"] == "flight"

    assert request_fields["data_source_id"]["control"]["attrs"]["value"] ==
             "questdb-flight"

    assert request_fields["source_binding_id"]["control"]["attrs"]["value"] ==
             "binding-flight"

    assert hidden_fields["dashboard_id"]["attrs"]["value"] == "dashboard-power"

    assert hidden_fields["dashboard_version"]["attrs"]["value"] == "3"

    assert hidden_fields["dashboard_time_mode"]["attrs"]["value"] == "archive"

    assert hidden_fields["dashboard_replay_run_id"]["attrs"]["value"] == "replay-1"

    assert hidden_fields["dashboard_data_view"]["attrs"]["value"] == "as_recorded"

    assert hidden_fields["dashboard_limit_mode"]["attrs"]["value"] == "observed"

    assert hidden_fields["comparison_review_request_event_id"]["attrs"]["value"] ==
             "review-request-1"

    assert hidden_fields["comparison_review_request_kind"]["attrs"]["value"] ==
             "comparison_open_findings_review"

    assert hidden_fields["comparison_review_open_count"]["attrs"]["value"] == "2"

    assert hidden_fields["comparison_review_open_placement_ids"]["attrs"]["value"] ==
             "placement-1,placement-2"

    assert hidden_fields["comparison_review_scope_kind"]["attrs"]["value"] == "transport"

    assert hidden_fields["comparison_review_scope_ids"]["attrs"]["value"] ==
             "transport-alpha,transport-beta"

    assert hidden_fields["comparison_review_contact_ids"]["attrs"]["value"] ==
             "contact-alpha,contact-beta"

    assert hidden_fields["comparison_review_source_endpoint_ids"]["attrs"]["value"] ==
             "endpoint-alpha"

    assert preview_rows["workflow"]["value"]["text"] == "Backfill"

    assert preview_rows["source"]["value"]["text"] ==
             "flight / questdb-flight / binding-flight"

    assert preview_rows["dashboard"]["value"]["text"] == "dashboard-power v3"

    assert preview_rows["runtime"]["value"]["text"] ==
             "archive / replay-1 / as_recorded / observed"

    assert preview_rows["comparison_scope"]["value"]["text"] ==
             "transport / transport-alpha,transport-beta / contact-alpha,contact-beta / transport-alpha / endpoint-alpha / dss-14 / link-alpha"

    assert presentation["root"] == %{
             "id" => "dashboard-historical-workflow-request-form",
             "class" => "space-y-3",
             "attrs" => %{"phx-submit" => "record_historical_workflow_request"}
           }

    assert presentation["hidden_fields"] == expected_hidden_fields(params)

    assert presentation["request_context"]
           |> Map.take(["class", "title"]) == %{
             "class" => "space-y-2 rounded border border-base-300 bg-base-100/70 p-2 text-xs",
             "title" => %{"class" => "hud-label", "text" => "Request Context"}
           }

    assert presentation["request_context"]["group"]["class"] ==
             "grid grid-cols-1 gap-2"

    assert request_fields["workflow"] ==
             select_field(
               "workflow",
               "Workflow",
               "backfill",
               [{"Backfill", "backfill"}, {"Import", "import"}]
             )

    assert request_fields["run_id"] == text_field("run_id", "Run", "run-1")
    assert request_fields["realm"] == text_field("realm", "Realm", "flight")

    assert request_fields["data_source_id"] ==
             text_field("data_source_id", "Data Source", "questdb-flight")

    assert request_fields["source_binding_id"] ==
             text_field("source_binding_id", "Source Binding", "binding-flight")

    assert presentation["preview"]
           |> Map.drop(["list"]) == %{
             "id" => "dashboard-historical-workflow-request-preview",
             "class" => "space-y-2 rounded border border-info/30 bg-info/10 p-2 text-xs",
             "title" => %{"class" => "hud-label", "text" => "Request Preview"}
           }

    assert presentation["preview"]["list"]["class"] ==
             "grid grid-cols-[minmax(5.5rem,auto)_1fr] gap-x-3 gap-y-1"

    assert Enum.map(presentation["preview"]["list"]["rows"], & &1["key"]) ==
             ~w(workflow effect points source window dashboard runtime comparison comparison_scope)

    assert Enum.map(presentation["preview"]["list"]["rows"], & &1["label"]["text"]) == [
             "Workflow",
             "Effect",
             "Points",
             "Source",
             "Window",
             "Dashboard",
             "Runtime",
             "Comparison",
             "Comparison Scope"
           ]

    assert preview_values(presentation) == %{
             "workflow" => "Backfill",
             "effect" => "Create backfill request event; samples are written after start.",
             "points" => "point-power",
             "source" => "flight / questdb-flight / binding-flight",
             "window" => "2026-06-25T00:00:00Z -> 2026-06-25T01:00:00Z",
             "dashboard" => "dashboard-power v3",
             "runtime" => "archive / replay-1 / as_recorded / observed",
             "comparison" =>
               "comparison_review / prepare_backfill / 2 / all_revisions / as_recorded",
             "comparison_scope" =>
               "transport / transport-alpha,transport-beta / contact-alpha,contact-beta / transport-alpha / endpoint-alpha / dss-14 / link-alpha"
           }

    assert Enum.all?(presentation["preview"]["list"]["rows"], fn row ->
             row["class"] == "contents" and
               row["attrs"] == %{"data-preview-field" => row["key"]} and
               row["label"]["class"] == "text-base-content/60" and
               row["value"]["class"] == "min-w-0 truncate text-base-content" and
               row["value"]["attrs"] == %{"title" => row["value"]["text"]}
           end)
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

    presentation = request_form_presentation(html)
    source_fields = source_window_fields(presentation)
    preview_rows = preview_rows(presentation)

    assert source_fields["observable_id"]["control"]["attrs"]["value"] == "HK.counter"

    assert source_fields["point_id"]["control"]["attrs"]["value"] == "point-1"

    assert source_fields["point_ids"]["control"]["attrs"]["placeholder"] ==
             "Comma, space, or newline separated point IDs"

    assert preview_rows["points"]["value"]["text"] == "2 points: point-1, point-2"

    assert preview_rows["window"]["value"]["text"] ==
             "2026-06-26T00:00:00Z -> 2026-06-26T01:00:00Z"

    assert presentation["confirmation"]["field"]["attrs"]["value"] == "confirmed"

    assert presentation["confirmation"]["field"]["attrs"]["required"] == ""

    assert presentation["submit"]["text"] == "Record request"

    assert presentation["source_window"]
           |> Map.take(["class", "title"]) == %{
             "class" => "space-y-2 rounded border border-base-300 bg-base-100/70 p-2 text-xs",
             "title" => %{"class" => "hud-label", "text" => "Source Window"}
           }

    assert source_fields["observable_id"] ==
             text_field("observable_id", "Observable", "HK.counter")

    assert source_fields["point_id"] == text_field("point_id", "Point", "point-1")

    assert source_fields["point_ids"] ==
             text_field(
               "point_ids",
               "Points",
               "point-1,point-2",
               "Comma, space, or newline separated point IDs"
             )

    assert source_fields["source_from"] ==
             text_field("source_from", "Source From", "2026-06-26T00:00:00Z")

    assert source_fields["source_to"] ==
             text_field("source_to", "Source To", "2026-06-26T01:00:00Z")

    assert source_fields["reason"] == text_field("reason", "Reason", "operator_requested")

    assert presentation["confirmation"] == %{
             "id" => "dashboard-historical-workflow-request-confirm-row",
             "class" =>
               "flex items-start gap-2 rounded border border-warning/40 bg-warning/10 p-2 text-xs",
             "field" => %{
               "class" => "checkbox checkbox-xs mt-0.5",
               "attrs" => %{
                 "id" => "dashboard-historical-workflow-request-confirm",
                 "type" => "checkbox",
                 "name" => "historical_workflow_request[confirmed]",
                 "value" => "confirmed",
                 "required" => ""
               }
             },
             "label" => %{
               "class" => "text-base-content/80",
               "text" => "Confirm historical data workflow request"
             }
           }

    assert presentation["submit"] == %{
             "id" => "dashboard-historical-workflow-request-submit",
             "type" => "submit",
             "class" => "btn btn-xs btn-primary w-full justify-start",
             "icon" => %{"name" => "hero-document-plus", "class" => "h-3.5 w-3.5"},
             "text" => "Record request"
           }
  end

  test "request_form preserves Phoenix boolean and nil attribute semantics in the DTO" do
    html =
      render_component(&HistoricalWorkflowRequestFormComponents.request_form/1,
        form:
          to_form(
            %{
              "run_id" => false,
              "realm" => true,
              "data_source_id" => 7,
              "source_binding_id" => nil,
              "dashboard_id" => nil,
              "dashboard_version" => false,
              "dashboard_time_mode" => true,
              "dashboard_replay_run_id" => :replay
            },
            as: :historical_workflow_request
          )
      )

    presentation = request_form_presentation(html)
    request_fields = request_context_fields(presentation)
    hidden_fields = hidden_fields(presentation)

    refute Map.has_key?(request_fields["run_id"]["control"]["attrs"], "value")
    assert request_fields["realm"]["control"]["attrs"]["value"] == ""
    assert request_fields["data_source_id"]["control"]["attrs"]["value"] == "7"
    refute Map.has_key?(request_fields["source_binding_id"]["control"]["attrs"], "value")
    refute Map.has_key?(hidden_fields["dashboard_id"]["attrs"], "value")
    refute Map.has_key?(hidden_fields["dashboard_version"]["attrs"], "value")
    assert hidden_fields["dashboard_time_mode"]["attrs"]["value"] == ""
    assert hidden_fields["dashboard_replay_run_id"]["attrs"]["value"] == "replay"
  end

  defp request_form_presentation(html) do
    document = LazyHTML.from_fragment(html)

    assert document
           |> LazyHTML.query("#historical-workflow-request-form-component")
           |> Enum.count() == 1

    vue =
      LiveVue.Test.get_vue(html,
        id: "historical-workflow-request-form-component"
      )

    assert vue.component == "HistoricalWorkflowRequestForm"
    assert vue.id == "historical-workflow-request-form-component"
    assert vue.ssr == false
    assert vue.class == "contents"
    assert vue.handlers == %{}
    assert vue.slots == %{}
    assert Map.keys(vue.props) == ["presentation"]
    assert vue.props == Jason.decode!(Jason.encode!(vue.props))

    Map.fetch!(vue.props, "presentation")
  end

  defp request_context_fields(presentation) do
    (presentation["request_context"]["fields"] ++
       presentation["request_context"]["group"]["fields"])
    |> Map.new(&{&1["key"], &1})
  end

  defp source_window_fields(presentation) do
    Map.new(presentation["source_window"]["fields"], &{&1["key"], &1})
  end

  defp hidden_fields(presentation) do
    Map.new(presentation["hidden_fields"], &{&1["key"], &1})
  end

  defp preview_rows(presentation) do
    Map.new(presentation["preview"]["list"]["rows"], &{&1["key"], &1})
  end

  defp preview_values(presentation) do
    Map.new(presentation["preview"]["list"]["rows"], &{&1["key"], &1["value"]["text"]})
  end

  defp selected_option(field) do
    Enum.find(field["control"]["options"], &Map.has_key?(&1["attrs"], "selected"))
  end

  defp expected_hidden_fields(params) do
    Enum.map(@hidden_field_keys, fn key ->
      %{
        "key" => key,
        "attrs" => %{
          "type" => "hidden",
          "name" => "historical_workflow_request[#{key}]",
          "value" => Map.fetch!(params, key)
        }
      }
    end)
  end

  defp select_field(key, label, selected_value, options) do
    %{
      "key" => key,
      "type" => "select",
      "wrapper_class" => "fieldset",
      "label" => %{"class" => "hud-label block mb-1.5", "text" => label},
      "control" => %{
        "class" => "w-full select",
        "attrs" => %{
          "id" => "historical_workflow_request_#{key}",
          "name" => "historical_workflow_request[#{key}]"
        },
        "options" =>
          Enum.map(options, fn {option_label, value} ->
            %{
              "key" => value,
              "text" => option_label,
              "attrs" =>
                %{"value" => value}
                |> then(fn attrs ->
                  if value == selected_value, do: Map.put(attrs, "selected", ""), else: attrs
                end)
            }
          end)
      },
      "errors" => []
    }
  end

  defp text_field(key, label, value, placeholder \\ nil) do
    attrs = %{
      "id" => "historical_workflow_request_#{key}",
      "name" => "historical_workflow_request[#{key}]",
      "type" => "text",
      "value" => value
    }

    attrs = if placeholder, do: Map.put(attrs, "placeholder", placeholder), else: attrs

    %{
      "key" => key,
      "type" => "text",
      "wrapper_class" => "fieldset",
      "label" => %{"class" => "hud-label block mb-1.5", "text" => label},
      "control" => %{"class" => "w-full input", "attrs" => attrs, "options" => []},
      "errors" => []
    }
  end
end
