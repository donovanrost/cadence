defmodule CadenceWeb.OpsDashboardShowLive.WidgetDataManagementComponentsTest do
  use ExUnit.Case, async: true

  import Phoenix.LiveViewTest, only: [render_component: 2]

  alias CadenceWeb.OpsDashboardShowLive.WidgetDataManagementComponents

  test "data_management_badge renders actionable direct data-link controls" do
    html =
      render_component(&WidgetDataManagementComponents.data_management_badge/1,
        badge: actionable_badge(),
        class: "data-management-primary"
      )

    document = LazyHTML.from_fragment(html)

    assert ["open_data_link"] =
             document
             |> LazyHTML.query(~s(button[data-data-management-badge="backfill_started"]))
             |> LazyHTML.attribute("phx-click")

    assert ["direct:telemetry_backfill_lifecycle_event:backfill-event-1"] =
             document
             |> LazyHTML.query(~s(button[data-data-management-badge="backfill_started"]))
             |> LazyHTML.attribute("phx-value-link-id")

    assert ["telemetry_backfill_lifecycle_event"] =
             document
             |> LazyHTML.query(~s(button[data-data-management-badge="backfill_started"]))
             |> LazyHTML.attribute("data-data-link-target")

    assert ["replay"] =
             document
             |> LazyHTML.query(~s(button[data-data-management-badge="backfill_started"]))
             |> LazyHTML.attribute("phx-value-realm")

    assert ["all_revisions"] =
             document
             |> LazyHTML.query(~s(button[data-data-management-badge="backfill_started"]))
             |> LazyHTML.attribute("phx-value-data-view")

    assert ["questdb-replay"] =
             document
             |> LazyHTML.query(~s(button[data-data-management-badge="backfill_started"]))
             |> LazyHTML.attribute("phx-value-data-source-id")

    assert ["binding-replay"] =
             document
             |> LazyHTML.query(~s(button[data-data-management-badge="backfill_started"]))
             |> LazyHTML.attribute("phx-value-source-binding-id")

    assert ["replay_run"] =
             document
             |> LazyHTML.query(~s(button[data-data-management-badge="backfill_started"]))
             |> LazyHTML.attribute("phx-value-time-mode")

    assert ["generation_time"] =
             document
             |> LazyHTML.query(~s(button[data-data-management-badge="backfill_started"]))
             |> LazyHTML.attribute("phx-value-time-axis")

    assert ["replay-run-1"] =
             document
             |> LazyHTML.query(~s(button[data-data-management-badge="backfill_started"]))
             |> LazyHTML.attribute("phx-value-replay-run-id")

    assert ["Backfill started - Operator requested replay"] =
             document
             |> LazyHTML.query(~s(button[data-data-management-badge="backfill_started"]))
             |> LazyHTML.attribute("title")
  end

  test "data_management_badge exposes workflow job execution context" do
    html =
      render_component(&WidgetDataManagementComponents.data_management_badge/1,
        badge: workflow_job_badge()
      )

    document = LazyHTML.from_fragment(html)

    assert ["backfill-run-1"] =
             document
             |> LazyHTML.query(
               ~s(button[data-data-management-badge="backfill_started_dispatch_degraded"])
             )
             |> LazyHTML.attribute("data-data-management-workflow-run-id")

    assert ["job-1"] =
             document
             |> LazyHTML.query(
               ~s(button[data-data-management-badge="backfill_started_dispatch_degraded"])
             )
             |> LazyHTML.attribute("data-data-management-workflow-job-id")

    assert ["failed"] =
             document
             |> LazyHTML.query(
               ~s(button[data-data-management-badge="backfill_started_dispatch_degraded"])
             )
             |> LazyHTML.attribute("data-data-management-workflow-job-status")

    assert ["dispatcher unavailable"] =
             document
             |> LazyHTML.query(
               ~s(button[data-data-management-badge="backfill_started_dispatch_degraded"])
             )
             |> LazyHTML.attribute("data-data-management-workflow-job-failure")

    assert ["Backfill dispatch failed - workflow job failed: dispatcher unavailable"] =
             document
             |> LazyHTML.query(
               ~s(button[data-data-management-badge="backfill_started_dispatch_degraded"])
             )
             |> LazyHTML.attribute("title")
  end

  test "data_management_badge renders source watermark event direct data-link controls" do
    html =
      render_component(&WidgetDataManagementComponents.data_management_badge/1,
        badge: source_watermark_badge()
      )

    document = LazyHTML.from_fragment(html)

    assert ["open_data_link"] =
             document
             |> LazyHTML.query(~s(button[data-data-management-badge="advanced"]))
             |> LazyHTML.attribute("phx-click")

    assert ["direct:source_watermark_event:watermark-event-1"] =
             document
             |> LazyHTML.query(~s(button[data-data-management-badge="advanced"]))
             |> LazyHTML.attribute("phx-value-link-id")

    assert ["source_watermark_event"] =
             document
             |> LazyHTML.query(~s(button[data-data-management-badge="advanced"]))
             |> LazyHTML.attribute("phx-value-target")

    assert ["watermark-event-1"] =
             document
             |> LazyHTML.query(~s(button[data-data-management-badge="advanced"]))
             |> LazyHTML.attribute("phx-value-target-id")

    assert ["flight"] =
             document
             |> LazyHTML.query(~s(button[data-data-management-badge="advanced"]))
             |> LazyHTML.attribute("phx-value-realm")

    assert ["questdb-flight"] =
             document
             |> LazyHTML.query(~s(button[data-data-management-badge="advanced"]))
             |> LazyHTML.attribute("phx-value-data-source-id")

    assert ["binding-flight"] =
             document
             |> LazyHTML.query(~s(button[data-data-management-badge="advanced"]))
             |> LazyHTML.attribute("phx-value-source-binding-id")
  end

  test "data_management_badge renders passive badge without link target" do
    html =
      render_component(&WidgetDataManagementComponents.data_management_badge/1,
        badge: %{
          kind: :data_view,
          value: "all_revisions",
          code: nil,
          label: "All revisions",
          status: :info,
          summary: "Multiple revisions included"
        }
      )

    document = LazyHTML.from_fragment(html)

    assert ["all_revisions"] =
             document
             |> LazyHTML.query(~s(span[data-data-management-badge="all_revisions"]))
             |> LazyHTML.attribute("data-data-management-badge")

    assert [] =
             document
             |> LazyHTML.query(~s(button[data-data-management-badge="all_revisions"]))
             |> LazyHTML.attribute("phx-click")
  end

  test "data_management_badge renders late-data execution summaries" do
    html =
      render_component(&WidgetDataManagementComponents.data_management_badge/1,
        badge: late_data_accepted_badge()
      )

    document = LazyHTML.from_fragment(html)

    assert "Late data accepted" ==
             document
             |> LazyHTML.query(~s([data-data-management-badge="late_data_accepted"]))
             |> LazyHTML.text()
             |> String.trim()

    assert [
             "2 selected samples; writes canonical history; refreshes current/latest; effect canonical_history_and_current_projection"
           ] =
             document
             |> LazyHTML.query(~s([data-data-management-badge="late_data_accepted"]))
             |> LazyHTML.attribute("data-data-management-summary")

    assert [
             "Late data accepted - 2 selected samples; writes canonical history; refreshes current/latest; effect canonical_history_and_current_projection"
           ] =
             document
             |> LazyHTML.query(~s([data-data-management-badge="late_data_accepted"]))
             |> LazyHTML.attribute("title")
  end

  test "chart_data_management_strip combines primary and compare badges with view labels" do
    strip_actionable_badge =
      actionable_badge()
      |> Map.merge(%{placement_id: "badge-placement", timestamp_ms: 1_781_568_000_000})

    html =
      render_component(&WidgetDataManagementComponents.chart_data_management_strip/1,
        placement_id: "chart-strip",
        data: data_with_badges([data_view_badge("all_revisions"), data_view_badge("corrected")]),
        backfill: data_with_badges([strip_actionable_badge]),
        compare_data: data_with_badges([data_view_badge("recomputed")]),
        compare_backfill: data_with_badges([data_view_badge("backfill")]),
        data_view: "all_revisions",
        compare_data_view: "canonical"
      )

    vue = LiveVue.Test.get_vue(html, id: "chart-data-management-chart-strip-component")

    assert vue.component == "ChartDataManagementStrip"
    assert vue.id == "chart-data-management-chart-strip-component"
    assert vue.class == "contents"
    refute vue.ssr
    assert vue.handlers == %{}
    assert vue.props == Jason.decode!(Jason.encode!(vue.props))

    presentation = vue.props["presentation"]

    assert presentation["root"] == %{
             "class" => "flex flex-wrap gap-1",
             "attrs" => %{
               "data-chart-data-management-strip" => "",
               "data-chart-data-view" => "all_revisions",
               "data-chart-compare-data-view" => "canonical"
             }
           }

    assert presentation["comparison"] == %{
             "class" => "badge badge-xs badge-ghost border-base-300/80 font-mono",
             "attrs" => %{
               "data-chart-data-view-comparison" => "",
               "data-primary-data-view" => "all_revisions",
               "data-compare-data-view" => "canonical",
               "title" => "Primary All revisions compared with Canonical"
             },
             "text" => "All revisions vs Canonical"
           }

    assert presentation["badges"] == [
             %{
               "key" => "primary-0",
               "tag" => "span",
               "class" =>
                 "badge badge-xs badge-info badge-outline data-management-primary",
               "attrs" => %{
                 "data-data-management-badge" => "all_revisions",
                 "data-data-management-kind" => "data_view",
                 "data-data-management-code" => "",
                 "data-data-management-workflow-run-id" => "",
                 "data-data-management-workflow-job-id" => "",
                 "data-data-management-workflow-job-status" => "",
                 "data-data-management-workflow-job-failure" => "",
                 "data-data-management-summary" => "",
                 "title" => "all revisions"
               },
               "text" => "all revisions"
             },
             %{
               "key" => "primary-1",
               "tag" => "span",
               "class" =>
                 "badge badge-xs badge-info badge-outline data-management-primary",
               "attrs" => %{
                 "data-data-management-badge" => "corrected",
                 "data-data-management-kind" => "data_view",
                 "data-data-management-code" => "",
                 "data-data-management-workflow-run-id" => "",
                 "data-data-management-workflow-job-id" => "",
                 "data-data-management-workflow-job-status" => "",
                 "data-data-management-workflow-job-failure" => "",
                 "data-data-management-summary" => "",
                 "title" => "corrected"
               },
               "text" => "corrected"
             },
             %{
               "key" => "primary-2",
               "tag" => "button",
               "class" =>
                 "badge badge-xs cursor-pointer badge-warning data-management-primary",
               "attrs" => %{
                 "type" => "button",
                 "phx-click" => "open_data_link",
                 "phx-value-link-id" =>
                   "direct:telemetry_backfill_lifecycle_event:backfill-event-1",
                 "phx-value-target" => "telemetry_backfill_lifecycle_event",
                 "phx-value-target-id" => "backfill-event-1",
                 "phx-value-placement-id" => "badge-placement",
                 "phx-value-timestamp-ms" => "1781568000000",
                 "phx-value-realm" => "replay",
                 "phx-value-data-view" => "all_revisions",
                 "phx-value-data-source-id" => "questdb-replay",
                 "phx-value-source-binding-id" => "binding-replay",
                 "phx-value-time-mode" => "replay_run",
                 "phx-value-time-axis" => "generation_time",
                 "phx-value-replay-run-id" => "replay-run-1",
                 "data-data-management-badge" => "backfill_started",
                 "data-data-management-kind" => "workflow",
                 "data-data-management-code" => "telemetry_backfill_started",
                 "data-data-link-id" =>
                   "direct:telemetry_backfill_lifecycle_event:backfill-event-1",
                 "data-data-link-target" => "telemetry_backfill_lifecycle_event",
                 "data-data-link-target-id" => "backfill-event-1",
                 "data-data-link-realm" => "replay",
                 "data-data-link-data-view" => "all_revisions",
                 "data-data-link-data-source-id" => "questdb-replay",
                 "data-data-link-source-binding-id" => "binding-replay",
                 "data-data-link-time-mode" => "replay_run",
                 "data-data-link-time-axis" => "generation_time",
                 "data-data-link-replay-run-id" => "replay-run-1",
                 "data-data-management-workflow-run-id" => "",
                 "data-data-management-workflow-job-id" => "",
                 "data-data-management-workflow-job-status" => "",
                 "data-data-management-workflow-job-failure" => "",
                 "data-data-management-summary" => "Operator requested replay",
                 "title" => "Backfill started - Operator requested replay"
               },
               "text" => "Backfill started"
             },
             %{
               "key" => "compare-0",
               "tag" => "span",
               "class" =>
                 "badge badge-xs badge-info badge-outline data-management-compare",
               "attrs" => %{
                 "data-data-management-badge" => "recomputed",
                 "data-data-management-kind" => "data_view",
                 "data-data-management-code" => "",
                 "data-data-management-workflow-run-id" => "",
                 "data-data-management-workflow-job-id" => "",
                 "data-data-management-workflow-job-status" => "",
                 "data-data-management-workflow-job-failure" => "",
                 "data-data-management-summary" => "",
                 "title" => "recomputed"
               },
               "text" => "recomputed"
             },
             %{
               "key" => "compare-1",
               "tag" => "span",
               "class" =>
                 "badge badge-xs badge-info badge-outline data-management-compare",
               "attrs" => %{
                 "data-data-management-badge" => "backfill",
                 "data-data-management-kind" => "data_view",
                 "data-data-management-code" => "",
                 "data-data-management-workflow-run-id" => "",
                 "data-data-management-workflow-job-id" => "",
                 "data-data-management-workflow-job-status" => "",
                 "data-data-management-workflow-job-failure" => "",
                 "data-data-management-summary" => "",
                 "title" => "backfill"
               },
               "text" => "backfill"
             }
           ]
  end

  test "chart_data_management_strip omits the island when the original strip is hidden" do
    html =
      render_component(&WidgetDataManagementComponents.chart_data_management_strip/1,
        placement_id: "hidden",
        compare_data_view: "   "
      )

    assert [] =
             html
             |> LazyHTML.from_fragment()
             |> LazyHTML.query("#chart-data-management-hidden-component")
             |> LazyHTML.attribute("id")
  end

  test "chart_data_management_strip preserves raw and fallback HEEx scalar semantics" do
    html =
      render_component(&WidgetDataManagementComponents.chart_data_management_strip/1,
        placement_id: "scalars",
        data:
          data_with_badges([
            %{kind: true, value: false, code: false, label: false, status: :unknown},
            %{kind: 42, value: 7, code: 9, label: true, status: :unknown, summary: 11},
            %{kind: nil, value: nil, code: true, label: nil, status: :unknown}
          ]),
        data_view: false,
        compare_data_view: nil
      )

    vue = LiveVue.Test.get_vue(html, id: "chart-data-management-scalars-component")
    presentation = vue.props["presentation"]

    assert vue.props == Jason.decode!(Jason.encode!(vue.props))

    assert presentation["root"]["attrs"] == %{
             "data-chart-data-management-strip" => "",
             "data-chart-data-view" => "",
             "data-chart-compare-data-view" => ""
           }

    assert presentation["comparison"] == nil

    assert presentation["badges"] == [
             %{
               "key" => "primary-0",
               "tag" => "span",
               "class" => "badge badge-xs badge-ghost data-management-primary",
               "attrs" => %{
                 "data-data-management-kind" => "",
                 "data-data-management-code" => "",
                 "data-data-management-workflow-run-id" => "",
                 "data-data-management-workflow-job-id" => "",
                 "data-data-management-workflow-job-status" => "",
                 "data-data-management-workflow-job-failure" => "",
                 "data-data-management-summary" => "",
                 "title" => "false"
               },
               "text" => "false"
             },
             %{
               "key" => "primary-1",
               "tag" => "span",
               "class" => "badge badge-xs badge-ghost data-management-primary",
               "attrs" => %{
                 "data-data-management-badge" => "7",
                 "data-data-management-kind" => "42",
                 "data-data-management-code" => "9",
                 "data-data-management-workflow-run-id" => "",
                 "data-data-management-workflow-job-id" => "",
                 "data-data-management-workflow-job-status" => "",
                 "data-data-management-workflow-job-failure" => "",
                 "data-data-management-summary" => "11",
                 "title" => "true - 11"
               },
               "text" => "true"
             },
             %{
               "key" => "primary-2",
               "tag" => "span",
               "class" => "badge badge-xs badge-ghost data-management-primary",
               "attrs" => %{
                 "data-data-management-code" => "",
                 "data-data-management-workflow-run-id" => "",
                 "data-data-management-workflow-job-id" => "",
                 "data-data-management-workflow-job-status" => "",
                 "data-data-management-workflow-job-failure" => "",
                 "data-data-management-summary" => ""
               },
               "text" => ""
             }
           ]
  end

  test "badge code helpers summarize data-management values" do
    data = data_with_badges([data_view_badge("all_revisions"), data_view_badge("corrected")])
    backfill = data_with_badges([actionable_badge()])

    assert WidgetDataManagementComponents.data_management_badge_codes(data) ==
             "all_revisions,corrected"

    assert WidgetDataManagementComponents.widget_data_management_badge_codes([data, backfill]) ==
             "all_revisions,corrected,backfill_started"
  end

  defp data_with_badges(badges), do: %{data_management: %{badges: badges}}

  defp data_view_badge(value) do
    %{
      kind: :data_view,
      value: value,
      code: nil,
      label: String.replace(value, "_", " "),
      status: :info
    }
  end

  defp actionable_badge do
    %{
      kind: :workflow,
      value: "backfill_started",
      code: "telemetry_backfill_started",
      label: "Backfill started",
      status: :warning,
      summary: "Operator requested replay",
      data_link_target: :telemetry_backfill_lifecycle_event,
      data_link_id: "backfill-event-1",
      realm: "replay",
      data_view: "all_revisions",
      data_source_id: "questdb-replay",
      source_binding_id: "binding-replay",
      time_mode: "replay_run",
      time_axis: "generation_time",
      replay_run_id: "replay-run-1"
    }
  end

  defp late_data_accepted_badge do
    %{
      kind: :historical_workflow,
      value: "late_data_accepted",
      label: "Late data accepted",
      status: :info,
      code: "late_data_accepted",
      data_link_target: :telemetry_backfill_lifecycle_event,
      data_link_id: "late-data-event-1",
      summary:
        "2 selected samples; writes canonical history; refreshes current/latest; effect canonical_history_and_current_projection"
    }
  end

  defp workflow_job_badge do
    %{
      kind: :historical_workflow,
      value: "backfill_started_dispatch_degraded",
      code: "backfill_started_dispatch_degraded",
      label: "Backfill dispatch failed",
      status: :warning,
      summary: "workflow job failed: dispatcher unavailable",
      data_link_target: :telemetry_backfill_lifecycle_event,
      data_link_id: "backfill-event-1",
      workflow_run_id: "backfill-run-1",
      workflow_job_id: "job-1",
      workflow_job_status: "failed",
      workflow_job_failure: "dispatcher unavailable"
    }
  end

  defp source_watermark_badge do
    %{
      kind: :source_freshness,
      value: "advanced",
      code: "advanced",
      label: "Watermark advanced",
      status: :info,
      data_link_target: :source_watermark_event,
      data_link_id: "watermark-event-1",
      realm: "flight",
      data_source_id: "questdb-flight",
      source_binding_id: "binding-flight"
    }
  end
end
