defmodule CadenceWeb.OpsDashboardShowLive.EvidenceInspectorPanelDataLinkHandoffTest do
  use ExUnit.Case, async: true

  import Phoenix.LiveViewTest, only: [render_component: 2]

  alias Cadence.Dashboards.Document
  alias CadenceWeb.OpsDashboardShowLive.EvidenceInspectorPanelComponents

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
        dashboard_current_path:
          "/missions/mission-1/ops/dashboards/dashboard-1?panel=evidence&scope_kind=mission&scope_id=mission-1",
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

    assert ["1782072000000"] =
             document
             |> LazyHTML.query(~s([data-evidence-ref-id="operational-event-binding-set"]))
             |> LazyHTML.attribute("phx-value-timestamp-ms")

    assert ["mission"] =
             document
             |> LazyHTML.query(~s([data-evidence-ref-id="operational-event-binding-set"]))
             |> LazyHTML.attribute("phx-value-scope-kind")

    assert ["mission-1"] =
             document
             |> LazyHTML.query(~s([data-evidence-ref-id="operational-event-binding-set"]))
             |> LazyHTML.attribute("phx-value-scope-id")

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

  test "evidence_panel data links fall back to warning source context" do
    link = evidence_link_without_context(:telemetry_point, "HK.counter", "Telemetry point")

    html =
      render_component(&EvidenceInspectorPanelComponents.evidence_panel/1,
        inspector: %{
          kind: :warning,
          kind_text: "warning",
          subject: "source_degraded",
          status: :warning,
          status_text: "warning",
          title: "Source degraded",
          message: nil,
          subject_rows: [%{label: "Warning", value: "source_degraded"}],
          detail_rows: [],
          source_context: %{
            realm: "flight",
            data_view: "canonical",
            data_source_id: "questdb-flight",
            source_binding_id: "binding-flight",
            time_mode: "archive",
            time_axis: "receipt_time",
            replay_run_id: "replay-1"
          },
          evidence: [],
          links: [link],
          actions: []
        },
        mission_id: "mission-1",
        dashboard_document: %Document{dashboard_id: "dashboard-1", name: "Dashboard"},
        dashboard_current_path: "/missions/mission-1/ops/dashboards/dashboard-1?panel=evidence",
        dashboard_lifecycle_events: []
      )

    document = LazyHTML.from_fragment(html)

    assert ["flight"] =
             document
             |> LazyHTML.query("[data-evidence-link-ref]")
             |> LazyHTML.attribute("phx-value-realm")

    assert ["canonical"] =
             document
             |> LazyHTML.query("[data-evidence-link-ref]")
             |> LazyHTML.attribute("phx-value-data-view")

    assert ["questdb-flight"] =
             document
             |> LazyHTML.query("[data-evidence-link-ref]")
             |> LazyHTML.attribute("phx-value-data-source-id")

    assert ["binding-flight"] =
             document
             |> LazyHTML.query("[data-evidence-link-ref]")
             |> LazyHTML.attribute("phx-value-source-binding-id")

    assert ["archive"] =
             document
             |> LazyHTML.query("[data-evidence-link-ref]")
             |> LazyHTML.attribute("phx-value-time-mode")

    assert ["receipt_time"] =
             document
             |> LazyHTML.query("[data-evidence-link-ref]")
             |> LazyHTML.attribute("phx-value-time-axis")

    assert ["replay-1"] =
             document
             |> LazyHTML.query("[data-evidence-link-ref]")
             |> LazyHTML.attribute("phx-value-replay-run-id")
  end

  defp evidence_link_without_context(target, target_id, label) do
    %{
      link_id: "#{target}:#{target_id}:request-1",
      label: label,
      target_text: target |> Atom.to_string() |> String.replace("_", " "),
      target_id: target_id,
      context: %{}
    }
  end

  defp selected_text(lazy_html) do
    lazy_html
    |> LazyHTML.text()
    |> String.trim()
  end
end
