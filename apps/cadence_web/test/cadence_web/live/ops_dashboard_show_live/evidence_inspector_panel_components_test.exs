defmodule CadenceWeb.OpsDashboardShowLive.EvidenceInspectorPanelComponentsTest do
  use ExUnit.Case, async: true

  import CadenceWeb.DashboardReviewFixtures
  import Phoenix.LiveViewTest, only: [render_component: 2]

  alias Cadence.Dashboards.{DashboardAction, Document}
  alias CadenceWeb.OpsDashboardShowLive.EvidenceInspectorPanelComponents

  test "evidence_panel renders subject details, evidence links, and actions" do
    link = evidence_link(:telemetry_point, "HK.counter", "Telemetry point")

    html =
      render_component(&EvidenceInspectorPanelComponents.evidence_panel/1,
        inspector: %{
          kind: :source,
          kind_text: "source",
          subject: "request-1",
          status: :resolved,
          status_text: "resolved",
          title: "Source evidence",
          message: nil,
          subject_rows: [%{label: "Source request", value: "request-1"}],
          detail_rows: [
            %{label: "Data source", value: "questdb-flight"},
            %{label: "Source binding", value: "binding-flight"}
          ],
          evidence: [],
          links: [link],
          actions: [telemetry_explore_action(), source_inventory_action()]
        },
        mission_id: "mission-1",
        dashboard_document: %Document{dashboard_id: "dashboard-1", name: "Dashboard"},
        dashboard_current_path: "/missions/mission-1/ops/dashboards/dashboard-1?panel=evidence",
        dashboard_lifecycle_events: []
      )

    document = LazyHTML.from_fragment(html)

    assert ["source"] =
             document
             |> LazyHTML.query("#dashboard-evidence-inspector")
             |> LazyHTML.attribute("data-evidence-kind")

    assert ["request-1"] =
             document
             |> LazyHTML.query("#dashboard-evidence-inspector")
             |> LazyHTML.attribute("data-evidence-subject")

    assert ["/missions/mission-1/ops/dashboards/dashboard-1?panel=evidence"] =
             document
             |> LazyHTML.query("#dashboard-evidence-copy-link")
             |> LazyHTML.attribute("data-clipboard-text")

    assert "questdb-flight" =
             document
             |> LazyHTML.query(~s([data-evidence-detail="Data source"]))
             |> selected_text()

    assert ["telemetry point"] =
             document
             |> LazyHTML.query("[data-evidence-link-target]")
             |> LazyHTML.attribute("data-evidence-link-target")

    assert ["questdb-flight"] =
             document
             |> LazyHTML.query("[data-evidence-link-ref]")
             |> LazyHTML.attribute("phx-value-data-source-id")

    assert ["evidence_panel"] =
             document
             |> LazyHTML.query("#dashboard-evidence-explore")
             |> LazyHTML.attribute("data-dashboard-action-source")

    assert [explore_href] =
             document
             |> LazyHTML.query("#dashboard-evidence-explore")
             |> LazyHTML.attribute("href")

    assert explore_href =~ "/missions/mission-1/ops/telemetry/explore"
    assert explore_href =~ "source_dashboard_id=dashboard-1"

    assert ["source_inventory"] =
             document
             |> LazyHTML.query("#dashboard-evidence-source-inventory")
             |> LazyHTML.attribute("data-dashboard-action-target")

    assert [source_inventory_href] =
             document
             |> LazyHTML.query("#dashboard-evidence-source-inventory")
             |> LazyHTML.attribute("href")

    assert source_inventory_href =~ "/missions/mission-1/ops/data-sources"
    assert source_inventory_href =~ "source_dashboard_id=dashboard-1"
  end

  test "evidence_panel renders dashboard health activity link" do
    event =
      lifecycle_event(
        "dashboard-lifecycle-event-health",
        :health_snapshot_captured,
        payload: %{
          "schema" => "dashboard_health_snapshot_capture.v1",
          "snapshot_id" => "dashboard_health_snapshot_abc123",
          "snapshot_schema" => "dashboard_health_snapshot.v1"
        }
      )

    html =
      render_component(&EvidenceInspectorPanelComponents.evidence_panel/1,
        inspector: %{
          kind: :dashboard_health,
          kind_text: "dashboard health",
          subject: "dashboard health blocked",
          status: :blocked,
          status_text: "blocked",
          title: "Dashboard Health Evidence",
          message: "Captured dashboard health rollup for sharing and investigation.",
          subject_rows: [
            %{label: "Health snapshot schema", value: "dashboard_health_snapshot.v1"},
            %{label: "Health snapshot", value: "dashboard_health_snapshot_abc123"}
          ],
          detail_rows: [%{label: "Affected widgets", value: "3"}],
          evidence: [],
          links: [],
          actions: []
        },
        mission_id: "mission-1",
        dashboard_document: %Document{dashboard_id: "dashboard-1", name: "Dashboard"},
        dashboard_current_path:
          "/missions/mission-1/ops/dashboards/dashboard-1?scope_kind=mission&scope_id=mission-1&selected_placement=placement-stale",
        dashboard_lifecycle_events: [event]
      )

    document = LazyHTML.from_fragment(html)

    assert ["dashboard-lifecycle-event-health"] =
             document
             |> LazyHTML.query("#dashboard-evidence-health-activity-link")
             |> LazyHTML.attribute("data-dashboard-health-activity-link")

    assert ["dashboard_health_snapshot_abc123"] =
             document
             |> LazyHTML.query("#dashboard-evidence-health-activity-link")
             |> LazyHTML.attribute("data-dashboard-health-activity-snapshot-id")

    assert [href] =
             document
             |> LazyHTML.query("#dashboard-evidence-health-activity-link")
             |> LazyHTML.attribute("href")

    assert URI.parse(href).path == "/missions/mission-1/ops/dashboards/dashboard-1"
    assert URI.decode_query(URI.parse(href).query)["activity_filter"] == "health_snapshots"
  end

  test "evidence_panel turns resolvable evidence refs into data link handoffs" do
    html =
      render_component(&EvidenceInspectorPanelComponents.evidence_panel/1,
        inspector: %{
          kind: :frame,
          kind_text: "frame",
          subject: "source-request-1:HK.counter",
          status: :resolved,
          status_text: "resolved",
          title: "Frame Evidence",
          message: nil,
          subject_rows: [
            %{label: "Realm", value: "replay"},
            %{label: "Data source", value: "managed_operational_observables"},
            %{label: "Source binding", value: "default_flight_operational_observables"}
          ],
          detail_rows: [
            %{label: "Replay run", value: "replay-run-1"},
            %{
              label: "Limit definition interval",
              value: "limit-def-1 v3 / ops (2026-06-21T20:00:00Z -> open)"
            },
            %{label: "Limit definition interval lifecycle event", value: "limit-lifecycle-1"},
            %{
              label: "Catalog revision interval",
              value: "catalog-revision-limits (2026-06-21T20:00:00Z -> open)"
            },
            %{
              label: "Catalog revision interval source event",
              value: "operational-event-catalog-limits"
            }
          ],
          evidence: [
            %{
              kind: :operational_interval,
              kind_text: "operational interval",
              id: "operational-event-binding-set",
              source_text: "events",
              confidence: :direct,
              confidence_text: "direct",
              observed_at_text: "2026-06-21T20:00:00Z"
            },
            %{
              kind: :binding_set_interval,
              kind_text: "binding set interval",
              id: "binding-set-interval-runtime-apps-a",
              source_text: "events",
              confidence: :projected,
              confidence_text: "projected",
              observed_at_text: "2026-06-21T20:00:00Z"
            },
            %{
              kind: :application_binding_interval,
              kind_text: "application binding interval",
              id: "application-binding-interval-runtime-apps-a-packet-counter",
              source_text: "telemetry",
              confidence: :projected,
              confidence_text: "projected",
              observed_at_text: "2026-06-21T20:00:00Z"
            },
            %{
              kind: :catalog_revision_interval,
              kind_text: "catalog revision interval",
              id: "catalog-revision-interval-fsw-3-6",
              source_text: "telemetry",
              confidence: :projected,
              confidence_text: "projected",
              observed_at_text: "2026-06-21T20:00:00Z"
            },
            %{
              kind: :limit_definition_interval,
              kind_text: "limit definition interval",
              id: "effective_interval:limit_definition:activation-key-1",
              source_text: "limits",
              confidence: :projected,
              confidence_text: "projected",
              observed_at_text: "2026-06-21T20:00:00Z"
            },
            %{
              kind: :source_binding_interval,
              kind_text: "source binding interval",
              id: "effective_interval:source_binding:source-binding-event-1",
              source_text: "telemetry",
              confidence: :projected,
              confidence_text: "projected",
              observed_at_text: "2026-06-21T20:00:00Z"
            },
            %{
              kind: :transport_execution_interval,
              kind_text: "transport execution interval",
              id: "transport-execution-interval-uplink-heartbeat",
              source_text: "operational observables",
              confidence: :projected,
              confidence_text: "projected",
              observed_at_text: "2026-06-21T20:00:00Z"
            },
            %{
              kind: :transport_connection_state_interval,
              kind_text: "transport connection state interval",
              id: "effective_interval:transport_connection_state:event-transport-connected",
              source_text: "operational observables",
              confidence: :projected,
              confidence_text: "projected",
              observed_at_text: "2026-06-21T20:00:00Z"
            },
            %{
              kind: :ground_station_connection_state_interval,
              kind_text: "ground station connection state interval",
              id: "effective_interval:ground_station_connection_state:event-ground-connected",
              source_text: "operational observables",
              confidence: :projected,
              confidence_text: "projected",
              observed_at_text: "2026-06-21T20:00:00Z"
            },
            %{
              kind: :link_rf_lock_state_interval,
              kind_text: "link rf lock state interval",
              id: "effective_interval:link_rf_lock_state:event-rf-locked",
              source_text: "operational observables",
              confidence: :projected,
              confidence_text: "projected",
              observed_at_text: "2026-06-21T20:00:00Z"
            },
            %{
              kind: :link_frame_sync_state_interval,
              kind_text: "link frame sync state interval",
              id: "effective_interval:link_frame_sync_state:event-frame-sync",
              source_text: "operational observables",
              confidence: :projected,
              confidence_text: "projected",
              observed_at_text: "2026-06-21T20:00:00Z"
            },
            %{
              kind: :source_binding_event,
              kind_text: "source binding event",
              id: "source-binding-event-1",
              source_text: "telemetry",
              confidence: :direct,
              confidence_text: "direct",
              observed_at_text: "2026-06-21T20:00:00Z"
            },
            %{
              kind: :limit_definition_lifecycle_event,
              kind_text: "limit definition lifecycle event",
              id: "limit-lifecycle-1",
              source_text: "limits",
              confidence: :direct,
              confidence_text: "direct",
              observed_at_text: "2026-06-21T20:00:00Z"
            }
          ],
          links: [],
          actions: []
        },
        mission_id: "mission-1",
        dashboard_document: %Document{dashboard_id: "dashboard-1", name: "Dashboard"},
        dashboard_current_path: "/missions/mission-1/ops/dashboards/dashboard-1?panel=evidence",
        dashboard_lifecycle_events: []
      )

    document = LazyHTML.from_fragment(html)

    assert "limit-def-1 v3 / ops (2026-06-21T20:00:00Z -> open)" =
             document
             |> LazyHTML.query(~s([data-evidence-detail="Limit definition interval"]))
             |> selected_text()

    assert "limit-lifecycle-1" =
             document
             |> LazyHTML.query(
               ~s([data-evidence-detail="Limit definition interval lifecycle event"])
             )
             |> selected_text()

    assert "catalog-revision-limits (2026-06-21T20:00:00Z -> open)" =
             document
             |> LazyHTML.query(~s([data-evidence-detail="Catalog revision interval"]))
             |> selected_text()

    assert "operational-event-catalog-limits" =
             document
             |> LazyHTML.query(
               ~s([data-evidence-detail="Catalog revision interval source event"])
             )
             |> selected_text()

    assert ["operational_event"] =
             document
             |> LazyHTML.query(~s([data-evidence-ref-id="operational-event-binding-set"]))
             |> LazyHTML.attribute("data-evidence-ref-link-target")

    assert ["open_data_link"] =
             document
             |> LazyHTML.query(~s([data-evidence-ref-id="operational-event-binding-set"]))
             |> LazyHTML.attribute("phx-click")

    assert ["operational_event"] =
             document
             |> LazyHTML.query(~s([data-evidence-ref-id="operational-event-binding-set"]))
             |> LazyHTML.attribute("phx-value-target")

    assert ["operational-event-binding-set"] =
             document
             |> LazyHTML.query(~s([data-evidence-ref-id="operational-event-binding-set"]))
             |> LazyHTML.attribute("phx-value-target-id")

    assert [
             "operational_event",
             "binding_set_interval",
             "application_binding_interval",
             "catalog_revision_interval",
             "limit_definition_interval",
             "source_binding_interval",
             "transport_execution_interval",
             "transport_connection_state_interval",
             "ground_station_connection_state_interval",
             "link_rf_lock_state_interval",
             "link_frame_sync_state_interval",
             "source_binding_event",
             "limit_definition_lifecycle_event"
           ] =
             document
             |> LazyHTML.query("[data-evidence-ref-link-target]")
             |> LazyHTML.attribute("data-evidence-ref-link-target")

    assert [
             "operational-event-binding-set",
             "binding-set-interval-runtime-apps-a",
             "application-binding-interval-runtime-apps-a-packet-counter",
             "catalog-revision-interval-fsw-3-6",
             "effective_interval:limit_definition:activation-key-1",
             "effective_interval:source_binding:source-binding-event-1",
             "transport-execution-interval-uplink-heartbeat",
             "effective_interval:transport_connection_state:event-transport-connected",
             "effective_interval:ground_station_connection_state:event-ground-connected",
             "effective_interval:link_rf_lock_state:event-rf-locked",
             "effective_interval:link_frame_sync_state:event-frame-sync",
             "source-binding-event-1",
             "limit-lifecycle-1"
           ] =
             document
             |> LazyHTML.query("[data-evidence-ref-id]")
             |> LazyHTML.attribute("data-evidence-ref-id")

    assert ["application_binding_interval"] =
             document
             |> LazyHTML.query(
               ~s([data-evidence-ref-id="application-binding-interval-runtime-apps-a-packet-counter"])
             )
             |> LazyHTML.attribute("phx-value-target")

    assert ["catalog_revision_interval"] =
             document
             |> LazyHTML.query(~s([data-evidence-ref-id="catalog-revision-interval-fsw-3-6"]))
             |> LazyHTML.attribute("phx-value-target")

    assert ["transport_execution_interval"] =
             document
             |> LazyHTML.query(
               ~s([data-evidence-ref-id="transport-execution-interval-uplink-heartbeat"])
             )
             |> LazyHTML.attribute("phx-value-target")

    assert ["transport_connection_state_interval"] =
             document
             |> LazyHTML.query(
               ~s([data-evidence-ref-id="effective_interval:transport_connection_state:event-transport-connected"])
             )
             |> LazyHTML.attribute("phx-value-target")

    assert ["ground_station_connection_state_interval"] =
             document
             |> LazyHTML.query(
               ~s([data-evidence-ref-id="effective_interval:ground_station_connection_state:event-ground-connected"])
             )
             |> LazyHTML.attribute("phx-value-target")

    assert ["link_rf_lock_state_interval"] =
             document
             |> LazyHTML.query(
               ~s([data-evidence-ref-id="effective_interval:link_rf_lock_state:event-rf-locked"])
             )
             |> LazyHTML.attribute("phx-value-target")

    assert ["link_frame_sync_state_interval"] =
             document
             |> LazyHTML.query(
               ~s([data-evidence-ref-id="effective_interval:link_frame_sync_state:event-frame-sync"])
             )
             |> LazyHTML.attribute("phx-value-target")

    assert ["managed_operational_observables"] =
             document
             |> LazyHTML.query(
               ~s([data-evidence-ref-id="effective_interval:link_frame_sync_state:event-frame-sync"])
             )
             |> LazyHTML.attribute("phx-value-data-source-id")

    assert ["default_flight_operational_observables"] =
             document
             |> LazyHTML.query(
               ~s([data-evidence-ref-id="effective_interval:link_frame_sync_state:event-frame-sync"])
             )
             |> LazyHTML.attribute("phx-value-source-binding-id")

    assert ["replay"] =
             document
             |> LazyHTML.query(
               ~s([data-evidence-ref-id="effective_interval:link_frame_sync_state:event-frame-sync"])
             )
             |> LazyHTML.attribute("phx-value-realm")

    assert ["replay-run-1"] =
             document
             |> LazyHTML.query(
               ~s([data-evidence-ref-id="effective_interval:link_frame_sync_state:event-frame-sync"])
             )
             |> LazyHTML.attribute("phx-value-replay-run-id")

    assert ["source_binding_event"] =
             document
             |> LazyHTML.query(~s([data-evidence-ref-id="source-binding-event-1"]))
             |> LazyHTML.attribute("phx-value-target")

    assert ["limit_definition_lifecycle_event"] =
             document
             |> LazyHTML.query(~s([data-evidence-ref-id="limit-lifecycle-1"]))
             |> LazyHTML.attribute("phx-value-target")
  end

  defp evidence_link(target, target_id, label) do
    %{
      link_id: "#{target}:#{target_id}:request-1",
      label: label,
      target_text: target |> Atom.to_string() |> String.replace("_", " "),
      target_id: target_id,
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

  defp source_inventory_action do
    %DashboardAction{
      action_id: "source-inventory",
      label: "Source inventory",
      target: :source_inventory,
      kind: :invoke,
      query: %{
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
