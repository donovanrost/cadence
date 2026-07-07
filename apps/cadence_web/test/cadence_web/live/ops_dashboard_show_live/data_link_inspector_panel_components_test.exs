defmodule CadenceWeb.OpsDashboardShowLive.DataLinkInspectorPanelComponentsTest do
  use ExUnit.Case, async: true

  import Phoenix.LiveViewTest, only: [render_component: 2]

  alias Cadence.Dashboards.{DashboardAction, DataLink, Document}
  alias CadenceWeb.OpsDashboardShowLive.DataLinkInspectorPanelComponents
  alias CadenceWeb.OpsDashboardShowLive.HistoricalWorkflowActionOutcome

  test "data_link_panel renders inspector identity, rows, related links, and actions" do
    related_link = data_link(:telemetry_sample, "sample-1", "Telemetry sample")

    html =
      render_component(&DataLinkInspectorPanelComponents.data_link_panel/1,
        inspector: %{
          status: :context_only,
          status_text: "context_only",
          title: "Telemetry point",
          target: :telemetry_point,
          target_text: "telemetry point",
          target_id: "HK.counter",
          link_id: "telemetry_point:HK.counter:request-1",
          link_label: "Counter point",
          source: :frame,
          source_text: "frame",
          message: "Telemetry point is not present in the active operator point catalog.",
          rows: [%{label: "Point", value: "HK.counter"}],
          context_rows: [
            %{label: "Data realm", value: "flight"},
            %{label: "Data view", value: "all_revisions"},
            %{label: "Data source", value: "questdb-flight"},
            %{label: "Source binding", value: "binding-flight"},
            %{label: "Time mode", value: "replay_run"},
            %{label: "Time axis", value: "generation_time"},
            %{label: "Replay run", value: "replay-run-1"},
            %{label: "Scope", value: "spacecraft:single:sc-1"},
            %{label: "Limit mode", value: "operational"}
          ],
          related_links: [related_link],
          actions: [telemetry_explore_action()]
        },
        mission_id: "mission-1",
        dashboard_document: %Document{dashboard_id: "dashboard-1", name: "Dashboard"},
        dashboard_current_path: "/missions/mission-1/ops/dashboards/dashboard-1?panel=data_link"
      )

    document = LazyHTML.from_fragment(html)

    assert ["telemetry_point"] =
             document
             |> LazyHTML.query("#dashboard-data-link-inspector")
             |> LazyHTML.attribute("data-data-link-target")

    assert ["HK.counter"] =
             document
             |> LazyHTML.query("#dashboard-data-link-inspector")
             |> LazyHTML.attribute("data-data-link-target-id")

    assert ["telemetry_point:HK.counter:request-1"] =
             document
             |> LazyHTML.query("#dashboard-data-link-inspector")
             |> LazyHTML.attribute("data-data-link-selected-link")

    assert ["all_revisions"] =
             document
             |> LazyHTML.query("#dashboard-data-link-inspector")
             |> LazyHTML.attribute("data-data-link-selected-data-view")

    assert ["questdb-flight"] =
             document
             |> LazyHTML.query("#dashboard-data-link-inspector")
             |> LazyHTML.attribute("data-data-link-selected-data-source-id")

    assert ["binding-flight"] =
             document
             |> LazyHTML.query("#dashboard-data-link-inspector")
             |> LazyHTML.attribute("data-data-link-selected-source-binding-id")

    assert ["replay_run"] =
             document
             |> LazyHTML.query("#dashboard-data-link-inspector")
             |> LazyHTML.attribute("data-data-link-selected-time-mode")

    assert ["generation_time"] =
             document
             |> LazyHTML.query("#dashboard-data-link-inspector")
             |> LazyHTML.attribute("data-data-link-selected-time-axis")

    assert ["replay-run-1"] =
             document
             |> LazyHTML.query("#dashboard-data-link-inspector")
             |> LazyHTML.attribute("data-data-link-selected-replay-run-id")

    assert ["/missions/mission-1/ops/dashboards/dashboard-1?panel=data_link"] =
             document
             |> LazyHTML.query("#dashboard-data-link-copy-link")
             |> LazyHTML.attribute("data-clipboard-text")

    assert "context_only" =
             document
             |> LazyHTML.query(~s([data-data-link-selection-field="State"]))
             |> selected_text()

    assert "telemetry point" =
             document
             |> LazyHTML.query(~s([data-data-link-selection-field="Target"]))
             |> selected_text()

    assert "telemetry_point:HK.counter:request-1" =
             document
             |> LazyHTML.query(~s([data-data-link-selection-field="Link"]))
             |> selected_text()

    assert "all_revisions" =
             document
             |> LazyHTML.query(~s([data-data-link-selection-field="Data view"]))
             |> selected_text()

    assert "replay_run" =
             document
             |> LazyHTML.query(~s([data-data-link-selection-field="Time mode"]))
             |> selected_text()

    assert "replay-run-1" =
             document
             |> LazyHTML.query(~s([data-data-link-selection-field="Replay run"]))
             |> selected_text()

    assert "HK.counter" =
             document
             |> LazyHTML.query(~s([data-data-link-field="Point"]))
             |> selected_text()

    assert "questdb-flight" =
             document
             |> LazyHTML.query(~s([data-data-link-context="Data source"]))
             |> selected_text()

    assert ["telemetry sample"] =
             document
             |> LazyHTML.query("[data-data-link-related-target]")
             |> LazyHTML.attribute("data-data-link-related-target")

    assert ["questdb-flight"] =
             document
             |> LazyHTML.query("[data-data-link-related-ref]")
             |> LazyHTML.attribute("phx-value-data-source-id")

    assert ["binding-flight"] =
             document
             |> LazyHTML.query("[data-data-link-related-ref]")
             |> LazyHTML.attribute("phx-value-source-binding-id")

    assert ["telemetry_point"] =
             document
             |> LazyHTML.query("[data-data-link-related-ref]")
             |> LazyHTML.attribute("phx-value-nav-from-target")

    assert ["HK.counter"] =
             document
             |> LazyHTML.query("[data-data-link-related-ref]")
             |> LazyHTML.attribute("phx-value-nav-from-target-id")

    assert [%{"target_id" => "HK.counter"}] =
             document
             |> LazyHTML.query("[data-data-link-related-ref]")
             |> LazyHTML.attribute("phx-value-nav-trail")
             |> List.first()
             |> Jason.decode!()

    assert ["data_link_panel"] =
             document
             |> LazyHTML.query("#dashboard-data-link-explore")
             |> LazyHTML.attribute("data-dashboard-action-source")

    assert [explore_href] =
             document
             |> LazyHTML.query("#dashboard-data-link-explore")
             |> LazyHTML.attribute("href")

    assert explore_href =~ "/missions/mission-1/ops/telemetry/explore"
    assert explore_href =~ "point_id=HK.counter"
    assert explore_href =~ "source_dashboard_id=dashboard-1"
  end

  test "data_link_panel groups lifecycle recovery related links" do
    html =
      render_component(&DataLinkInspectorPanelComponents.data_link_panel/1,
        inspector: %{
          status: :resolved,
          status_text: "resolved",
          title: "Backfill lifecycle event",
          target: :telemetry_backfill_lifecycle_event,
          target_text: "telemetry backfill lifecycle event",
          target_id: "source-event-1",
          link_id: "telemetry_backfill_lifecycle_event:source-event-1:request-1",
          link_label: "Backfill lifecycle event",
          source: :frame,
          source_text: "frame",
          message: nil,
          navigation: %{
            from: %{
              link_id: "source-link-1",
              target: "telemetry_backfill_lifecycle_event",
              target_id: "previous-event-1",
              label: "Previous event",
              relationship_kind: "retry_event",
              relationship_label: "Retry event HK.counter"
            },
            trail: [
              %{
                link_id: "root-link-1",
                target: "telemetry_backfill_lifecycle_event",
                target_id: "root-event-1",
                label: "Root event",
                relationship_kind: "source_event",
                relationship_label: "Source event HK.counter"
              },
              %{
                link_id: "source-link-1",
                target: "telemetry_backfill_lifecycle_event",
                target_id: "previous-event-1",
                label: "Previous event",
                relationship_kind: "retry_event",
                relationship_label: "Retry event HK.counter"
              }
            ]
          },
          rows: [%{label: "Backfill lifecycle event", value: "source-event-1"}],
          context_rows: [],
          related_links: [
            data_link(
              :telemetry_backfill_lifecycle_event,
              "failed-event-1",
              "Retry source event",
              relationship_kind: :source_event
            ),
            data_link(
              :telemetry_backfill_lifecycle_event,
              "retry-event-1",
              "Retry event HK.counter",
              relationship_kind: :retry_event
            ),
            data_link(
              :telemetry_backfill_lifecycle_event,
              "correction-event-1",
              "Correction request HK.counter",
              relationship_kind: :correction_request
            ),
            data_link(
              :telemetry_backfill_lifecycle_event,
              "transition-event-1",
              "Correction transition event HK.counter",
              relationship_kind: :correction_transition
            ),
            data_link(:telemetry_sample, "sample-1", "Telemetry sample",
              relationship_kind: :evidence
            )
          ],
          actions: []
        },
        mission_id: "mission-1",
        dashboard_document: %Document{dashboard_id: "dashboard-1", name: "Dashboard"},
        dashboard_current_path: "/missions/mission-1/ops/dashboards/dashboard-1?panel=data_link"
      )

    document = LazyHTML.from_fragment(html)

    assert ["root-event-1", "previous-event-1"] =
             document
             |> LazyHTML.query("[data-data-link-navigation] [data-data-link-nav-entry-id]")
             |> LazyHTML.attribute("data-data-link-nav-entry-id")

    assert ["telemetry_backfill_lifecycle_event", "telemetry_backfill_lifecycle_event"] =
             document
             |> LazyHTML.query("[data-data-link-navigation] [phx-value-target]")
             |> LazyHTML.attribute("phx-value-target")

    assert ["source-event-1", "source-event-1"] =
             document
             |> LazyHTML.query("[data-data-link-navigation] [phx-value-nav-from-target-id]")
             |> LazyHTML.attribute("phx-value-nav-from-target-id")

    assert [breadcrumb_trail | _] =
             document
             |> LazyHTML.query("[data-data-link-navigation] [phx-value-nav-trail]")
             |> LazyHTML.attribute("phx-value-nav-trail")

    assert [
             %{"target_id" => "root-event-1"},
             %{"target_id" => "previous-event-1"},
             %{
               "target_id" => "source-event-1",
               "relationship_label" => "Root event"
             }
           ] = Jason.decode!(breadcrumb_trail)

    assert ["source", "recovery", "follow-up", "evidence"] =
             document
             |> LazyHTML.query("[data-data-link-related-group]")
             |> LazyHTML.attribute("data-data-link-related-group")

    assert [
             "source_event",
             "retry_event",
             "correction_request",
             "correction_transition",
             "evidence"
           ] =
             document
             |> LazyHTML.query("[data-data-link-related-kind]")
             |> LazyHTML.attribute("data-data-link-related-kind")

    assert ["failed-event-1"] =
             document
             |> LazyHTML.query(
               ~s([data-data-link-related-group="source"] [data-data-link-related-id])
             )
             |> LazyHTML.attribute("data-data-link-related-id")

    assert ["source-event-1"] =
             document
             |> LazyHTML.query(
               ~s([data-data-link-related-group="source"] [phx-value-nav-from-target-id])
             )
             |> LazyHTML.attribute("phx-value-nav-from-target-id")

    assert [source_related_trail] =
             document
             |> LazyHTML.query(~s([data-data-link-related-group="source"] [phx-value-nav-trail]))
             |> LazyHTML.attribute("phx-value-nav-trail")

    assert [
             %{"target_id" => "root-event-1"},
             %{"target_id" => "previous-event-1"},
             %{
               "target_id" => "source-event-1",
               "relationship_kind" => "source_event",
               "relationship_label" => "Retry source event",
               "data_source_id" => "questdb-flight",
               "source_binding_id" => "binding-flight",
               "time_mode" => "archive",
               "time_axis" => "receipt_time"
             }
           ] = Jason.decode!(source_related_trail)

    assert ["retry-event-1", "correction-event-1"] =
             document
             |> LazyHTML.query(
               ~s([data-data-link-related-group="recovery"] [data-data-link-related-id])
             )
             |> LazyHTML.attribute("data-data-link-related-id")

    assert ["transition-event-1"] =
             document
             |> LazyHTML.query(
               ~s([data-data-link-related-group="follow-up"] [data-data-link-related-id])
             )
             |> LazyHTML.attribute("data-data-link-related-id")

    assert ["sample-1"] =
             document
             |> LazyHTML.query(
               ~s([data-data-link-related-group="evidence"] [data-data-link-related-id])
             )
             |> LazyHTML.attribute("data-data-link-related-id")
  end

  test "data_link_panel renders source watermark event inspector rows" do
    html =
      render_component(&DataLinkInspectorPanelComponents.data_link_panel/1,
        inspector: %{
          status: :resolved,
          status_text: "resolved",
          title: "Source watermark event",
          target: :source_watermark_event,
          target_text: "source watermark event",
          target_id: "watermark-event-1",
          link_id: "source_watermark_event:watermark-event-1:events-request-1",
          link_label: "Source watermark event",
          source: :frame,
          source_text: "frame",
          message: nil,
          rows: [
            %{label: "Source watermark event", value: "watermark-event-1"},
            %{label: "Source watermark key", value: "source_watermark:mission-1:telemetry"},
            %{label: "Logical source", value: "telemetry"},
            %{label: "Data source", value: "questdb-flight"},
            %{label: "Source binding", value: "binding-flight"},
            %{label: "Complete through", value: "2026-06-21T12:05:00.000000Z"},
            %{label: "Latest receipt time", value: "2026-06-21T12:05:30.000000Z"},
            %{label: "Reason", value: "telemetry_storage_write"}
          ],
          context_rows: [
            %{label: "Data realm", value: "flight"},
            %{label: "Data source", value: "events-questdb"},
            %{label: "Source binding", value: "events-binding"},
            %{label: "Time mode", value: "archive"},
            %{label: "Logical source", value: "events"}
          ],
          related_links: [],
          actions: []
        },
        mission_id: "mission-1",
        dashboard_document: %Document{dashboard_id: "dashboard-1", name: "Dashboard"},
        dashboard_current_path:
          "/missions/mission-1/ops/dashboards/dashboard-1?panel=data_link&selected_target=source_watermark_event"
      )

    document = LazyHTML.from_fragment(html)

    assert ["source_watermark_event"] =
             document
             |> LazyHTML.query("#dashboard-data-link-inspector")
             |> LazyHTML.attribute("data-data-link-target")

    assert ["watermark-event-1"] =
             document
             |> LazyHTML.query("#dashboard-data-link-inspector")
             |> LazyHTML.attribute("data-data-link-target-id")

    assert ["source_watermark_event:watermark-event-1:events-request-1"] =
             document
             |> LazyHTML.query("#dashboard-data-link-inspector")
             |> LazyHTML.attribute("data-data-link-selected-link")

    assert "source watermark event" =
             document
             |> LazyHTML.query(~s([data-data-link-selection-field="Target"]))
             |> selected_text()

    assert "watermark-event-1" =
             document
             |> LazyHTML.query(~s([data-data-link-field="Source watermark event"]))
             |> selected_text()

    assert "source_watermark:mission-1:telemetry" =
             document
             |> LazyHTML.query(~s([data-data-link-field="Source watermark key"]))
             |> selected_text()

    assert "telemetry_storage_write" =
             document
             |> LazyHTML.query(~s([data-data-link-field="Reason"]))
             |> selected_text()

    assert "events-questdb" =
             document
             |> LazyHTML.query(~s([data-data-link-context="Data source"]))
             |> selected_text()
  end

  test "data_link_panel presents degraded workflow dispatch with retry controls" do
    html =
      render_component(&DataLinkInspectorPanelComponents.data_link_panel/1,
        inspector: %{
          status: :resolved,
          status_text: "resolved",
          title: "Telemetry backfill lifecycle event",
          target: :telemetry_backfill_lifecycle_event,
          target_text: "telemetry backfill lifecycle event",
          target_id: "backfill-event-1",
          link_id: "telemetry_backfill_lifecycle_event:backfill-event-1:events-request-1",
          link_label: "Telemetry backfill lifecycle event",
          source: :frame,
          source_text: "frame",
          message: nil,
          rows: [
            %{label: "Backfill lifecycle event", value: "backfill-event-1"},
            %{label: "Backfill run", value: "backfill-run-1"},
            %{label: "Event type", value: "backfill_started"},
            %{label: "Workflow", value: "backfill"},
            %{label: "Workflow stage", value: "started"},
            %{label: "Workflow run", value: "backfill-run-1"},
            %{label: "Dashboard context", value: "dashboard-1"},
            %{label: "Dashboard context version", value: "7"},
            %{label: "Dashboard context time mode", value: "replay_run"},
            %{label: "Dashboard context replay run", value: "replay-1"},
            %{label: "Dashboard context data view", value: "all_revisions"},
            %{label: "Dashboard context limit mode", value: "observed"},
            %{label: "Occurred", value: "2026-06-22T12:21:00Z"},
            %{label: "Realm", value: "flight"},
            %{label: "Data source", value: "questdb-flight"},
            %{label: "Source binding", value: "binding-flight"},
            %{label: "Point", value: "HK.counter"},
            %{label: "Source from", value: "2026-06-22T11:00:00Z"},
            %{label: "Source to", value: "2026-06-22T12:00:00Z"},
            %{label: "Reason", value: "operator_started_backfill"},
            %{label: "Workflow job", value: "job-1"},
            %{label: "Workflow job status", value: "failed"},
            %{label: "Workflow job attempts", value: "1"},
            %{label: "Workflow job failure", value: "dispatcher unavailable"},
            %{label: "Workflow retryable", value: "true"}
          ],
          context_rows: [
            %{label: "Data realm", value: "flight"},
            %{label: "Data source", value: "events-questdb"},
            %{label: "Source binding", value: "events-binding"},
            %{label: "Time mode", value: "archive"},
            %{label: "Logical source", value: "events"}
          ],
          related_links: [],
          actions: []
        },
        mission_id: "mission-1",
        dashboard_document: %Document{dashboard_id: "dashboard-1", name: "Dashboard"},
        dashboard_current_path:
          "/missions/mission-1/ops/dashboards/dashboard-1?panel=data_link&selected_target=telemetry_backfill_lifecycle_event",
        data_link_action_outcome:
          HistoricalWorkflowActionOutcome.new(
            action: :retry_job,
            status: :ok,
            kind: :info,
            reason: :retry_job_queued,
            job_id: "job-1",
            count: 2,
            retried: 1,
            retry_nonretryable: 1,
            retry_skipped: 3,
            retry_errors: 0,
            retry_scope: "replacement_jobs",
            retry_run_ids: "run-004-corrected,run-005-corrected",
            retry_nonretryable_run_ids: "run-nonretryable",
            retry_nonretryable_event_ids: "failed-event-nonretryable",
            retry_nonretryable_items:
              "run=run-nonretryable event=failed-event-nonretryable action=correct_workflow_request reason=correction_required",
            retry_skipped_run_ids: "run-skipped",
            retry_skipped_event_ids: "failed-event-skipped",
            retry_skipped_items:
              "run=run-skipped event=failed-event-skipped job=job-skipped status=running reason=job_not_failed",
            retry_error_run_ids: "run-004-corrected",
            retry_error_event_ids: "failed-event-4",
            retry_error_items:
              "run=run-004-corrected event=failed-event-4 job=job-4 reason=queue_down",
            queued_jobs: 2,
            failed_jobs: 0,
            result_event_ids: "retry-event-1",
            target_event_id: "backfill-event-1",
            target_run_id: "backfill-run-1",
            message: "Historical workflow job retry queued."
          )
      )

    document = LazyHTML.from_fragment(html)

    [metadata_json] =
      document
      |> LazyHTML.query("#dashboard-data-link-action-outcome")
      |> LazyHTML.attribute("data-data-link-action-outcome-metadata")

    metadata =
      metadata_json
      |> Jason.decode!()
      |> Map.take([
        "job_id",
        "count",
        "retried",
        "retry_nonretryable",
        "retry_skipped",
        "retry_errors",
        "retry_scope",
        "retry_run_ids",
        "retry_nonretryable_run_ids",
        "retry_nonretryable_event_ids",
        "retry_nonretryable_items",
        "retry_skipped_run_ids",
        "retry_skipped_event_ids",
        "retry_skipped_items",
        "retry_error_run_ids",
        "retry_error_event_ids",
        "retry_error_items",
        "queued_jobs",
        "failed_jobs"
      ])

    assert metadata == %{
             "count" => "2",
             "failed_jobs" => "0",
             "job_id" => "job-1",
             "queued_jobs" => "2",
             "retried" => "1",
             "retry_error_event_ids" => "failed-event-4",
             "retry_error_items" =>
               "run=run-004-corrected event=failed-event-4 job=job-4 reason=queue_down",
             "retry_error_run_ids" => "run-004-corrected",
             "retry_errors" => "0",
             "retry_nonretryable" => "1",
             "retry_nonretryable_event_ids" => "failed-event-nonretryable",
             "retry_nonretryable_items" =>
               "run=run-nonretryable event=failed-event-nonretryable action=correct_workflow_request reason=correction_required",
             "retry_nonretryable_run_ids" => "run-nonretryable",
             "retry_run_ids" => "run-004-corrected,run-005-corrected",
             "retry_scope" => "replacement_jobs",
             "retry_skipped" => "3",
             "retry_skipped_event_ids" => "failed-event-skipped",
             "retry_skipped_items" =>
               "run=run-skipped event=failed-event-skipped job=job-skipped status=running reason=job_not_failed",
             "retry_skipped_run_ids" => "run-skipped"
           }

    assert ["replacement_jobs"] =
             document
             |> LazyHTML.query("#dashboard-historical-workflow-action-outcome")
             |> LazyHTML.attribute("data-workflow-action-retry-scope")

    assert ["info"] =
             document
             |> LazyHTML.query("#dashboard-historical-workflow-action-outcome")
             |> LazyHTML.attribute("data-workflow-action-kind")

    assert ["run-nonretryable"] =
             document
             |> LazyHTML.query("#dashboard-historical-workflow-action-outcome")
             |> LazyHTML.attribute("data-workflow-action-retry-nonretryable-run-ids")

    assert ["failed-event-skipped"] =
             document
             |> LazyHTML.query("#dashboard-historical-workflow-action-outcome")
             |> LazyHTML.attribute("data-workflow-action-retry-skipped-event-ids")

    assert ["run-004-corrected"] =
             document
             |> LazyHTML.query("#dashboard-historical-workflow-action-outcome")
             |> LazyHTML.attribute("data-workflow-action-retry-error-run-ids")

    assert ["2"] =
             document
             |> LazyHTML.query("#dashboard-historical-workflow-action-outcome")
             |> LazyHTML.attribute("data-workflow-action-queued-jobs")

    assert ["retry-event-1"] =
             document
             |> LazyHTML.query("#dashboard-historical-workflow-action-outcome")
             |> LazyHTML.attribute("data-workflow-action-result-event-ids")

    assert ["dispatch_failed"] =
             document
             |> LazyHTML.query("#dashboard-workflow-explanation")
             |> LazyHTML.attribute("data-workflow-explanation-state")

    assert ["warning"] =
             document
             |> LazyHTML.query("#dashboard-workflow-explanation")
             |> LazyHTML.attribute("data-workflow-explanation-severity")

    assert "This workflow was started, but the backing job failed before completion." =
             document
             |> LazyHTML.query("#dashboard-workflow-explanation-summary")
             |> selected_text()

    assert ["job-1"] =
             document
             |> LazyHTML.query("#dashboard-historical-workflow-job-status")
             |> LazyHTML.attribute("data-historical-workflow-job-id")

    assert ["failed"] =
             document
             |> LazyHTML.query("#dashboard-historical-workflow-job-status")
             |> LazyHTML.attribute("data-historical-workflow-job-status")

    assert document
           |> LazyHTML.query("#dashboard-historical-workflow-job-status")
           |> LazyHTML.text()
           |> String.contains?("dispatcher unavailable")

    assert ["retry_historical_workflow_job"] =
             document
             |> LazyHTML.query("#dashboard-historical-workflow-retry-job")
             |> LazyHTML.attribute("phx-click")

    assert ["job-1"] =
             document
             |> LazyHTML.query("#dashboard-historical-workflow-retry-job")
             |> LazyHTML.attribute("phx-value-job-id")

    assert ["backfill-event-1"] =
             document
             |> LazyHTML.query("#dashboard-historical-workflow-retry-job")
             |> LazyHTML.attribute("phx-value-event-id")

    assert ["dashboard-1"] =
             document
             |> LazyHTML.query("#dashboard-historical-workflow-dashboard-id")
             |> LazyHTML.attribute("value")

    assert ["replay-1"] =
             document
             |> LazyHTML.query("#dashboard-historical-workflow-dashboard-replay-run-id")
             |> LazyHTML.attribute("value")

    assert ["observed"] =
             document
             |> LazyHTML.query("#dashboard-historical-workflow-dashboard-limit-mode")
             |> LazyHTML.attribute("value")

    assert ["true"] =
             document
             |> LazyHTML.query("#dashboard-historical-workflow-retry-job")
             |> LazyHTML.attribute("data-workflow-action-eligible")

    assert [
             "job job-1; status failed; retryable true; recovery unknown"
           ] =
             document
             |> LazyHTML.query(~s([data-workflow-action-explanation-id="correction_request"]))
             |> LazyHTML.attribute("data-workflow-action-explanation-state")

    assert document
           |> LazyHTML.query(~s([data-workflow-action-explanation-id="correction_request"]))
           |> LazyHTML.text()
           |> String.contains?("job job-1; status failed; retryable true; recovery unknown")

    assert ["retry_job"] =
             document
             |> LazyHTML.query("#dashboard-data-link-action-outcome")
             |> LazyHTML.attribute("data-data-link-action-outcome-action")

    assert ["retry-event-1"] =
             document
             |> LazyHTML.query("#dashboard-data-link-action-outcome")
             |> LazyHTML.attribute("data-data-link-action-outcome-result-event-ids")

    assert ["backfill-event-1"] =
             document
             |> LazyHTML.query("#dashboard-data-link-action-outcome")
             |> LazyHTML.attribute("data-data-link-action-outcome-target-event-id")

    assert ["backfill-run-1"] =
             document
             |> LazyHTML.query("#dashboard-data-link-action-outcome")
             |> LazyHTML.attribute("data-data-link-action-outcome-target-run-id")

    assert ["job-1"] =
             document
             |> LazyHTML.query("#dashboard-historical-workflow-latest-action")
             |> LazyHTML.attribute("data-workflow-latest-action-job-id")

    assert ["retry-event-1"] =
             document
             |> LazyHTML.query("#dashboard-historical-workflow-latest-action")
             |> LazyHTML.attribute("data-workflow-latest-action-result-event-ids")

    assert ["backfill-event-1"] =
             document
             |> LazyHTML.query("#dashboard-historical-workflow-latest-action")
             |> LazyHTML.attribute("data-workflow-latest-action-target-event-id")

    assert ["backfill-run-1"] =
             document
             |> LazyHTML.query("#dashboard-historical-workflow-latest-action")
             |> LazyHTML.attribute("data-workflow-latest-action-target-run-id")

    assert document
           |> LazyHTML.query("#dashboard-historical-workflow-latest-action")
           |> LazyHTML.text()
           |> String.contains?("retry-event-1")

    assert %{
             "job_id" => "job-1",
             "result_event_ids" => "retry-event-1",
             "target_event_id" => "backfill-event-1",
             "target_run_id" => "backfill-run-1"
           } =
             document
             |> LazyHTML.query("#dashboard-data-link-action-outcome")
             |> LazyHTML.attribute("data-data-link-action-outcome-metadata")
             |> List.first()
             |> Jason.decode!()
  end

  defp data_link(target, target_id, label, opts \\ []) do
    %DataLink{
      link_id: "#{target}:#{target_id}:request-1",
      label: label,
      target: target,
      target_id: target_id,
      relationship_kind: Keyword.get(opts, :relationship_kind),
      source: :frame,
      context: %{
        data: %{
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

  defp telemetry_explore_action do
    %DashboardAction{
      action_id: "explore",
      label: "Explore telemetry",
      target: :telemetry_explore,
      kind: :invoke,
      query: %{
        "point_id" => "HK.counter",
        "sample_id" => "sample-1",
        "realm" => "flight",
        "data_source_id" => "questdb-flight",
        "source_binding_id" => "binding-flight"
      },
      source: :frame
    }
  end

  defp selected_text(lazy_html) do
    lazy_html
    |> LazyHTML.text()
    |> String.trim()
  end
end
