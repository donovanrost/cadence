defmodule CadenceWeb.OpsDashboardShowLive.DataLinkInspectorPanelLifecycleRecoveryTest do
  use ExUnit.Case, async: true

  import Phoenix.LiveViewTest, only: [render_component: 2]

  alias Cadence.Dashboards.{DataLink, Document}
  alias CadenceWeb.OpsDashboardShowLive.DataLinkInspectorPanelComponents
  alias CadenceWeb.OpsDashboardShowLive.ViewTestSupport

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

    presentation = ViewTestSupport.data_link_inspector_presentation(html)
    workflow = presentation["workflow_explanation"]

    assert workflow["attrs"]["data-workflow-explanation-state"] ==
             "failed_correction_required"

    assert workflow["attrs"]["data-workflow-explanation-severity"] == "error"
    assert workflow["summary"]["text"] =~ "needs a corrected request"

    workflow_rows = Map.new(workflow["rows"], &{&1["label"]["text"], &1["value"]["text"]})
    assert workflow_rows["Recovery"] == "correct_workflow_request"
    assert workflow_rows["Group"] == "group-1 failed"

    data_operations_path = presentation["historical_workflow_navigation"]["attrs"]["href"]
    assert presentation["historical_workflow_navigation"]["attrs"]["data-phx-link"] == "redirect"

    assert presentation["historical_workflow_navigation"]["attrs"]["data-phx-link-state"] ==
             "push"

    uri = URI.parse(data_operations_path)
    query = URI.decode_query(uri.query)

    assert uri.path == "/missions/mission-1/ops/data-operations"
    assert query["dashboard_id"] == "dashboard-1"
    assert query["dashboard_replay_run_id"] == "replay-1"
    assert query["dashboard_limit_mode"] == "observed"
    assert query["group"] == "group-1"
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

    presentation = ViewTestSupport.data_link_inspector_presentation(html)
    navigation_entries = presentation["navigation"]["entries"]
    navigation_attrs = Enum.map(navigation_entries, & &1["attrs"])

    assert Enum.map(navigation_attrs, & &1["data-data-link-nav-entry-id"]) == [
             "root-event-1",
             "previous-event-1"
           ]

    assert Enum.map(navigation_attrs, & &1["phx-value-target"]) == [
             "telemetry_backfill_lifecycle_event",
             "telemetry_backfill_lifecycle_event"
           ]

    assert Enum.map(navigation_attrs, & &1["phx-value-nav-from-target-id"]) == [
             "source-event-1",
             "source-event-1"
           ]

    assert [breadcrumb_trail | _remaining_trails] =
             Enum.map(navigation_attrs, & &1["phx-value-nav-trail"])

    assert [
             %{"target_id" => "root-event-1"},
             %{"target_id" => "previous-event-1"},
             %{
               "target_id" => "source-event-1",
               "relationship_label" => "Root event"
             }
           ] = Jason.decode!(breadcrumb_trail)

    groups = presentation["related"]["groups"]

    assert Enum.map(groups, & &1["attrs"]["data-data-link-related-group"]) == [
             "source",
             "recovery",
             "follow-up",
             "evidence"
           ]

    links = Enum.flat_map(groups, & &1["links"])

    assert [
             "source_event",
             "retry_event",
             "correction_request",
             "correction_transition",
             "evidence"
           ] == Enum.map(links, & &1["attrs"]["data-data-link-related-kind"])

    source_link = groups |> Enum.at(0) |> Map.fetch!("links") |> List.first()
    assert source_link["attrs"]["data-data-link-related-id"] == "failed-event-1"
    assert source_link["attrs"]["phx-value-nav-from-target-id"] == "source-event-1"
    source_related_trail = source_link["attrs"]["phx-value-nav-trail"]

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

    assert related_ids(Enum.at(groups, 1)) == ["retry-event-1", "correction-event-1"]
    assert related_ids(Enum.at(groups, 2)) == ["transition-event-1"]
    assert related_ids(Enum.at(groups, 3)) == ["sample-1"]
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

  defp related_ids(group),
    do: Enum.map(group["links"], & &1["attrs"]["data-data-link-related-id"])
end
