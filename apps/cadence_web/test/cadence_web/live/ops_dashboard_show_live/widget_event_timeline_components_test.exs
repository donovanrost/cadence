defmodule CadenceWeb.OpsDashboardShowLive.WidgetEventTimelineComponentsTest do
  use ExUnit.Case, async: true

  import Phoenix.LiveViewTest, only: [render_component: 2]

  alias CadenceWeb.OpsDashboardShowLive.WidgetRowComponents

  test "event_timeline renders event metadata, badges, duration, and row links" do
    html =
      render_component(&WidgetRowComponents.event_timeline/1,
        data: %{rows: [event_timeline_row()]},
        placement_id: "placement-1"
      )

    presentation = widget_rows_presentation(html)
    row = hd(presentation["rows"])
    [row_link] = row["link_menu"]["items"]

    badge =
      Enum.find(
        row["badges"],
        &(&1["attrs"]["data-data-management-badge"] == "backfill_started")
      )

    assert row["attrs"]["data-event-timeline-row"] == "event-1"

    assert row["attrs"]["data-event-timeline-severity"] == "Warning"

    assert row["attrs"]["data-data-management-badges"] == "backfill_started"

    assert badge["attrs"]["data-data-management-badge"] == "backfill_started"

    assert badge["attrs"]["data-data-link-target"] == "telemetry_backfill_lifecycle_event"
    assert badge["attrs"]["phx-click"] == "open_data_link"
    assert badge["attrs"]["phx-value-target-id"] == "backfill-event-1"

    assert badge["attrs"]["phx-value-link-id"] ==
             "direct:telemetry_backfill_lifecycle_event:backfill-event-1"

    assert "10m" in row["metadata"]

    assert row_link["attrs"]["phx-click"] == "open_data_link"

    assert row_link["attrs"]["phx-value-timestamp-ms"] == "1781697600000"
  end

  test "event_timeline renders historical workflow job execution evidence" do
    html =
      render_component(&WidgetRowComponents.event_timeline/1,
        data: %{rows: [failed_workflow_event_row()]},
        placement_id: "placement-1"
      )

    row = html |> widget_rows_presentation() |> Map.fetch!("rows") |> hd()

    badge =
      Enum.find(
        row["badges"],
        &(&1["attrs"]["data-data-management-badge"] ==
            "backfill_started_dispatch_degraded")
      )

    assert row["attrs"]["data-data-management-badges"] ==
             "backfill_started_dispatch_degraded"

    assert badge["attrs"]["data-data-management-workflow-run-id"] == "backfill-run-1"

    assert badge["attrs"]["data-data-management-workflow-job-id"] == "job-1"

    assert badge["attrs"]["data-data-management-workflow-job-status"] == "failed"

    assert badge["attrs"]["data-data-management-workflow-job-failure"] ==
             "dispatcher unavailable"

    assert badge["attrs"]["title"] ==
             "Backfill dispatch failed - workflow job failed: dispatcher unavailable"
  end

  test "event_timeline renders source watermark audit details" do
    html =
      render_component(&WidgetRowComponents.event_timeline/1,
        data: %{rows: [source_watermark_event_row()]},
        placement_id: "placement-1"
      )

    row = html |> widget_rows_presentation() |> Map.fetch!("rows") |> hd()
    [row_link] = row["link_menu"]["items"]

    assert row["attrs"]["data-event-timeline-complete-through"] == "2026-06-17T12:04:00Z"

    assert row["attrs"]["data-event-timeline-target"] == "Source watermark event"

    assert row["attrs"]["data-event-timeline-target-id"] == "watermark-event-1"

    assert row["attrs"]["data-event-timeline-latest-receipt-time"] ==
             "2026-06-17T12:04:30Z"

    assert row["attrs"]["data-event-timeline-confidence"] == "Best effort"

    assert row["attrs"]["data-event-timeline-reason"] == "Source watermark observed"

    assert row["attrs"]["data-data-management-badges"] == "advanced"

    assert "complete 12:04:00" in row["metadata"]
    assert "latest 12:04:30" in row["metadata"]

    assert row_link["attrs"]["phx-click"] == "open_data_link"
  end

  defp widget_rows_presentation(html) do
    component_id = "widget-rows-event-timeline-placement-1-component"
    vue = LiveVue.Test.get_vue(html, id: component_id)
    assert vue.component == "WidgetRows"
    assert vue.ssr == false
    assert vue.class == "contents"
    assert vue.handlers == %{}
    assert vue.props == Jason.decode!(Jason.encode!(vue.props))
    assert vue.props["presentation"]["kind"] == "event_timeline"
    assert vue.props["presentation"]["component_id"] == component_id
    vue.props["presentation"]
  end

  defp event_timeline_row do
    %{
      row_id: "event-1",
      title: "Backfill started",
      category: :workflow,
      kind: :telemetry_backfill,
      severity: :warning,
      source_record_id: "backfill-event-1",
      logical_source: "telemetry",
      data_source_id: "questdb-flight",
      source_binding_id: "binding-flight",
      realm: :flight,
      dataset: "samples",
      occurred_at: ~U[2026-06-17 12:00:00Z],
      starts_at: ~U[2026-06-17 12:00:00Z],
      ends_at: ~U[2026-06-17 12:10:00Z],
      data_management: %{badges: [workflow_badge("backfill_started")]},
      links: [data_link()]
    }
  end

  defp failed_workflow_event_row do
    %{
      row_id: "backfill-event-1",
      title: "Backfill dispatch failed",
      category: :telemetry_backfill,
      kind: :backfill_started,
      severity: :warning,
      source_record_id: "backfill-event-1",
      logical_source: "telemetry",
      data_source_id: "questdb-flight",
      source_binding_id: "binding-flight",
      realm: :flight,
      dataset: "samples",
      occurred_at: ~U[2026-06-17 12:00:00Z],
      data_management: %{
        badges: [
          %{
            kind: :historical_workflow,
            value: "backfill_started_dispatch_degraded",
            label: "Backfill dispatch failed",
            status: :warning,
            code: "backfill_started_dispatch_degraded",
            summary: "workflow job failed: dispatcher unavailable",
            data_link_target: :telemetry_backfill_lifecycle_event,
            data_link_id: "backfill-event-1",
            workflow_run_id: "backfill-run-1",
            workflow_job_id: "job-1",
            workflow_job_status: "failed",
            workflow_job_failure: "dispatcher unavailable"
          }
        ]
      },
      links: [data_link()]
    }
  end

  defp source_watermark_event_row do
    %{
      row_id: "watermark-event-1",
      title: "telemetry watermark advanced",
      category: :source_watermark,
      kind: :advanced,
      severity: :info,
      source_record_id: "watermark-event-1",
      target: :source_watermark_event,
      target_id: "watermark-event-1",
      logical_source: :telemetry,
      data_source_id: "questdb-flight",
      source_binding_id: "binding-flight",
      realm: :flight,
      dataset: "samples",
      occurred_at: ~U[2026-06-17 12:05:00Z],
      complete_through: ~U[2026-06-17 12:04:00Z],
      latest_receipt_time: ~U[2026-06-17 12:04:30Z],
      confidence: :best_effort,
      reason: :source_watermark_observed,
      data_management: %{badges: [badge("advanced")]},
      links: [
        %{
          link_id: "source-watermark:watermark-event-1",
          label: "Watermark event",
          target: :source_watermark_event,
          target_text: "source_watermark_event",
          target_id: "watermark-event-1",
          context: %{}
        }
      ]
    }
  end

  defp badge(value) do
    %{
      kind: :data_view,
      value: value,
      code: nil,
      label: String.replace(value, "_", " "),
      status: :info
    }
  end

  defp workflow_badge(value) do
    %{
      kind: :historical_workflow,
      value: value,
      code: value,
      label: String.replace(value, "_", " "),
      status: :attention,
      data_link_target: :telemetry_backfill_lifecycle_event,
      data_link_id: "backfill-event-1"
    }
  end

  defp data_link do
    %{
      link_id: "link-1",
      label: "Telemetry sample",
      target_text: "telemetry_sample",
      target_id: "sample-1",
      context: %{
        data: %{
          realm: :flight,
          view: "canonical",
          data_source_id: "questdb-flight",
          source_binding_id: "binding-flight"
        },
        time: %{
          mode: "archive",
          axis: "receipt_time"
        }
      }
    }
  end
end
