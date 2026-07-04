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

  test "chart_data_management_strip combines primary and compare badges with view labels" do
    html =
      render_component(&WidgetDataManagementComponents.chart_data_management_strip/1,
        data: data_with_badges([data_view_badge("all_revisions"), data_view_badge("corrected")]),
        backfill: data_with_badges([actionable_badge()]),
        compare_data: data_with_badges([data_view_badge("recomputed")]),
        compare_backfill: data_with_badges([data_view_badge("backfill")]),
        data_view: "all_revisions",
        compare_data_view: "canonical"
      )

    document = LazyHTML.from_fragment(html)

    assert ["all_revisions"] =
             document
             |> LazyHTML.query("[data-chart-data-view-comparison]")
             |> LazyHTML.attribute("data-primary-data-view")

    assert ["canonical"] =
             document
             |> LazyHTML.query("[data-chart-data-view-comparison]")
             |> LazyHTML.attribute("data-compare-data-view")

    assert ["all_revisions", "corrected", "backfill_started", "recomputed", "backfill"] =
             document
             |> LazyHTML.query("[data-chart-data-management-strip] [data-data-management-badge]")
             |> LazyHTML.attribute("data-data-management-badge")
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
