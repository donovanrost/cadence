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

    document = LazyHTML.from_fragment(html)

    assert ["event-1"] =
             document
             |> LazyHTML.query("[data-event-timeline-row]")
             |> LazyHTML.attribute("data-event-timeline-row")

    assert ["Warning"] =
             document
             |> LazyHTML.query("[data-event-timeline-row]")
             |> LazyHTML.attribute("data-event-timeline-severity")

    assert ["backfill_started"] =
             document
             |> LazyHTML.query("[data-event-timeline-row]")
             |> LazyHTML.attribute("data-data-management-badges")

    assert ["backfill_started"] =
             document
             |> LazyHTML.query("[data-data-management-badge]")
             |> LazyHTML.attribute("data-data-management-badge")

    assert ["open_data_link"] =
             document
             |> LazyHTML.query(
               ~s(button[data-data-management-badge="backfill_started"][data-data-link-target="telemetry_backfill_lifecycle_event"])
             )
             |> LazyHTML.attribute("phx-click")

    assert ["backfill-event-1"] =
             document
             |> LazyHTML.query(~s(button[data-data-management-badge="backfill_started"]))
             |> LazyHTML.attribute("phx-value-target-id")

    assert ["direct:telemetry_backfill_lifecycle_event:backfill-event-1"] =
             document
             |> LazyHTML.query(~s(button[data-data-management-badge="backfill_started"]))
             |> LazyHTML.attribute("phx-value-link-id")

    assert html =~ "10m"

    assert ["open_data_link"] =
             document
             |> LazyHTML.query("[data-event-timeline-row-link-ref]")
             |> LazyHTML.attribute("phx-click")

    assert ["1781697600000"] =
             document
             |> LazyHTML.query("[data-event-timeline-row-link-ref]")
             |> LazyHTML.attribute("phx-value-timestamp-ms")
  end

  test "event_timeline renders historical workflow job execution evidence" do
    html =
      render_component(&WidgetRowComponents.event_timeline/1,
        data: %{rows: [failed_workflow_event_row()]},
        placement_id: "placement-1"
      )

    document = LazyHTML.from_fragment(html)

    assert ["backfill_started_dispatch_degraded"] =
             document
             |> LazyHTML.query("[data-event-timeline-row]")
             |> LazyHTML.attribute("data-data-management-badges")

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

  test "event_timeline renders source watermark audit details" do
    html =
      render_component(&WidgetRowComponents.event_timeline/1,
        data: %{rows: [source_watermark_event_row()]},
        placement_id: "placement-1"
      )

    document = LazyHTML.from_fragment(html)

    assert ["2026-06-17T12:04:00Z"] =
             document
             |> LazyHTML.query("[data-event-timeline-row]")
             |> LazyHTML.attribute("data-event-timeline-complete-through")

    assert ["Source watermark event"] =
             document
             |> LazyHTML.query("[data-event-timeline-row]")
             |> LazyHTML.attribute("data-event-timeline-target")

    assert ["watermark-event-1"] =
             document
             |> LazyHTML.query("[data-event-timeline-row]")
             |> LazyHTML.attribute("data-event-timeline-target-id")

    assert ["2026-06-17T12:04:30Z"] =
             document
             |> LazyHTML.query("[data-event-timeline-row]")
             |> LazyHTML.attribute("data-event-timeline-latest-receipt-time")

    assert ["Best effort"] =
             document
             |> LazyHTML.query("[data-event-timeline-row]")
             |> LazyHTML.attribute("data-event-timeline-confidence")

    assert ["Source watermark observed"] =
             document
             |> LazyHTML.query("[data-event-timeline-row]")
             |> LazyHTML.attribute("data-event-timeline-reason")

    assert ["advanced"] =
             document
             |> LazyHTML.query("[data-event-timeline-row]")
             |> LazyHTML.attribute("data-data-management-badges")

    assert html =~ "complete 12:04:00"
    assert html =~ "latest 12:04:30"

    assert ["open_data_link"] =
             document
             |> LazyHTML.query("[data-event-timeline-row-link-ref]")
             |> LazyHTML.attribute("phx-click")
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
