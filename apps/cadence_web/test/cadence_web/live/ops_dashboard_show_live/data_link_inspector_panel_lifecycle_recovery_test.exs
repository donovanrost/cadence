defmodule CadenceWeb.OpsDashboardShowLive.DataLinkInspectorPanelLifecycleRecoveryTest do
  use ExUnit.Case, async: true

  import Phoenix.LiveViewTest, only: [render_component: 2]

  alias Cadence.Dashboards.{DataLink, Document}
  alias CadenceWeb.OpsDashboardShowLive.DataLinkInspectorPanelComponents

  test "data_link_panel explains failed lifecycle events that require correction" do
    html =
      render_component(&DataLinkInspectorPanelComponents.data_link_panel/1,
        inspector: %{
          status: :resolved,
          status_text: "resolved",
          title: "Telemetry backfill lifecycle event",
          target: :telemetry_backfill_lifecycle_event,
          target_text: "telemetry backfill lifecycle event",
          target_id: "failed-event-1",
          link_label: "Telemetry backfill lifecycle event",
          source: :frame,
          source_text: "frame",
          message: nil,
          rows: [
            %{label: "Backfill lifecycle event", value: "failed-event-1"},
            %{label: "Backfill run", value: "failed-run-1"},
            %{label: "Event type", value: "backfill_failed"},
            %{label: "Workflow", value: "backfill"},
            %{label: "Workflow stage", value: "failed"},
            %{label: "Workflow run", value: "failed-run-1"},
            %{label: "Dashboard context", value: "dashboard-1"},
            %{label: "Dashboard context version", value: "7"},
            %{label: "Dashboard context time mode", value: "replay_run"},
            %{label: "Dashboard context replay run", value: "replay-1"},
            %{label: "Dashboard context data view", value: "all_revisions"},
            %{label: "Dashboard context limit mode", value: "observed"},
            %{label: "Realm", value: "backfill"},
            %{label: "Data source", value: "managed_questdb_backfill"},
            %{label: "Source binding", value: "backfill_telemetry"},
            %{label: "Workflow failure code", value: "missing_field:point_id"},
            %{label: "Workflow retryable", value: "false"},
            %{label: "Workflow retry blockers", value: "missing point_id"},
            %{label: "Workflow recovery action", value: "correct_workflow_request"},
            %{label: "Workflow source data source", value: "managed_questdb_backfill"},
            %{label: "Workflow source binding", value: "backfill_telemetry"},
            %{label: "Workflow source from", value: "2026-06-22T10:00:00Z"},
            %{label: "Workflow source to", value: "2026-06-22T11:00:00Z"},
            %{label: "Request group", value: "group-1"},
            %{label: "Request group state", value: "failed"},
            %{label: "Request group progress", value: "0/1"},
            %{label: "Workflow job", value: "job-1"},
            %{label: "Workflow job status", value: "failed"}
          ],
          context_rows: [],
          related_links: [],
          actions: []
        },
        mission_id: "mission-1",
        dashboard_document: %Document{dashboard_id: "dashboard-1", name: "Dashboard"},
        dashboard_current_path: "/missions/mission-1/ops/dashboards/dashboard-1?panel=data_link"
      )

    document = LazyHTML.from_fragment(html)

    assert ["failed_correction_required"] =
             document
             |> LazyHTML.query("#dashboard-workflow-explanation")
             |> LazyHTML.attribute("data-workflow-explanation-state")

    assert ["error"] =
             document
             |> LazyHTML.query("#dashboard-workflow-explanation")
             |> LazyHTML.attribute("data-workflow-explanation-severity")

    assert document
           |> LazyHTML.query("#dashboard-workflow-explanation-summary")
           |> selected_text() =~ "needs a corrected request"

    assert "correct_workflow_request" =
             document
             |> LazyHTML.query(~s([data-workflow-explanation-field="Recovery"]))
             |> selected_text()

    assert "group-1 failed" =
             document
             |> LazyHTML.query(~s([data-workflow-explanation-field="Group"]))
             |> selected_text()

    assert ["dashboard-1"] =
             document
             |> LazyHTML.query("#dashboard-historical-workflow-correction-dashboard-id")
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

  defp data_link(target, target_id, label, opts) do
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

  defp selected_text(lazy_html) do
    lazy_html
    |> LazyHTML.text()
    |> String.trim()
  end
end
