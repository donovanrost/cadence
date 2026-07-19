defmodule CadenceWeb.OpsDashboardShowLive.RuntimeReplayIntervalEvidenceLiveTest do
  use CadenceWeb.ConnCase, async: false

  import Phoenix.LiveViewTest
  import CadenceWeb.OpsDashboardShowLive.RuntimeReplaySourceFamilyFixtures
  import CadenceWeb.OpsDashboardShowLive.RuntimeReplayEvidenceFixtures

  use Phoenix.VerifiedRoutes,
    endpoint: CadenceWeb.Endpoint,
    router: CadenceWeb.Router,
    statics: CadenceWeb.static_paths()

  alias Cadence.Dashboards.Document
  alias Cadence.OperationalEvents
  alias Cadence.OperationalEvents.Event
  alias CadenceWeb.TestFixtures

  defp setup_ground_station_interval_evidence! do
    observed_at = ~U[2026-06-17 12:02:00Z]
    replay_run_id = "replay_run_ground_station_connection_ops"

    enable_dashboard_engine_inline_resolves!()
    configure_dashboard_source_health!(DateTime.add(observed_at, 60, :second))

    {conn, org, mission} = signed_in_org_and_mission()
    _telemetry_replay_source = persist_dashboard_realm!(mission, :replay)
    replay_sources = persist_replay_event_and_operational_sources!(mission)
    persist_replay_run!(mission, replay_run_id)
    {_source_endpoint, transport} = persist_replay_connection_state_resources!(org, mission)

    assert {:ok, _connection_event} =
             operational_observable_state_event(
               org.organization_id,
               mission.mission_id,
               "ground-station-connection-replay-source-health-1",
               :connected,
               observed_at,
               replay_run_id: replay_run_id,
               observable_id: "ground.station.connection_state",
               resource_id: "dss-14",
               scope_kind: :ground_station,
               transport_id: transport.transport_id
             )
             |> OperationalEvents.persist_event()

    [ground_station_interval] =
      Cadence.operational_connection_state_intervals(org.organization_id, mission.mission_id,
        observable_id: "ground.station.connection_state",
        resource_id: "dss-14",
        replay_run_id: replay_run_id
      )

    {source_health_event, source_health_interval} =
      record_replay_operational_source_health!(
        org,
        mission,
        replay_sources,
        observed_at,
        replay_run_id
      )

    {
      conn,
      org,
      mission,
      replay_sources,
      transport,
      ground_station_interval,
      source_health_event,
      source_health_interval,
      observed_at,
      replay_run_id
    }
  end

  defp setup_transport_execution_interval_evidence! do
    observed_at = ~U[2026-06-17 12:02:00Z]
    replay_run_id = "replay_run_transport_execution_ops"

    enable_dashboard_engine_inline_resolves!()
    configure_dashboard_source_health!(DateTime.add(observed_at, 60, :second))

    {conn, org, mission} = signed_in_org_and_mission()
    _telemetry_replay_source = persist_dashboard_realm!(mission, :replay)
    replay_sources = persist_replay_event_and_operational_sources!(mission)
    persist_replay_run!(mission, replay_run_id)
    {_source_endpoint, transport} = persist_replay_connection_state_resources!(org, mission)

    assert {:ok, _transport_execution_event} =
             transport_capability_record(
               mission.mission_id,
               "transport-execution-replay-source-health-1",
               transport.transport_id,
               :initialized,
               observed_at,
               state_snapshot: %{active?: true, heartbeat_count: 1}
             )
             |> Event.from_transport_capability_record(replay_run_id)
             |> OperationalEvents.persist_event()

    [transport_execution_interval] =
      Cadence.operational_transport_execution_intervals(org.organization_id, mission.mission_id,
        capability_instance_id: transport.transport_id,
        replay_run_id: replay_run_id,
        order: :asc
      )

    {source_health_event, source_health_interval} =
      record_replay_operational_source_health!(
        org,
        mission,
        replay_sources,
        observed_at,
        replay_run_id
      )

    {
      conn,
      org,
      mission,
      replay_sources,
      transport,
      transport_execution_interval,
      source_health_event,
      source_health_interval,
      observed_at,
      replay_run_id
    }
  end

  defp assert_transport_execution_details(view, transport, replay_run_id) do
    for {field, value} <- [
          {"Transport capability record", "transport-execution-replay-source-health-1"},
          {"Event kind", "initialized"},
          {"Capability instance", transport.transport_id},
          {"Contact", "replay-contact-alpha"},
          {"Path", "replay-uplink-path"},
          {"Family", "heartbeat_monitor"},
          {"Binding set", "replay-binding-set-1"},
          {"Binding set version", "1"},
          {"Activation", "replay-activation-1"},
          {"Partition affinity", "source_endpoint"},
          {"Partition value", "replay-source-health-endpoint"},
          {"State snapshot", "heartbeat_count"},
          {"Replay run", replay_run_id}
        ] do
      assert has_element?(
               view,
               ~s(#dashboard-data-link-inspector [data-data-link-field="#{field}"]),
               value
             )
    end
  end

  test "opens replay source-health and ground-station connection interval evidence from rendered operational observable frame panel" do
    {
      conn,
      org,
      mission,
      replay_sources,
      transport,
      ground_station_interval,
      source_health_event,
      source_health_interval,
      observed_at,
      replay_run_id
    } = setup_ground_station_interval_evidence!()

    dashboard =
      TestFixtures.persist_dashboard_document!(mission,
        name: "Replay Ground Station Connection Evidence",
        widgets: [
          %{
            type: :status_matrix,
            title: "Replay Ground Station Connection",
            binding: %{
              source: :operational_observables,
              observables: ["ground.station.connection_state"]
            }
          }
        ]
      )

    document =
      org
      |> fetch_dashboard_document!(mission, dashboard)
      |> then(fn %Document{} = document ->
        %Document{
          document
          | defaults: %{
              "data" => %{
                "realm" => "replay",
                "source_mode" => "specific",
                "source_contexts" => %{
                  "operational_observables" => %{
                    "source_binding_id" => replay_sources.operational_binding_id
                  }
                }
              }
            }
        }
      end)
      |> then(&replace_dashboard_row_document!(org, mission, &1))

    matrix_widget = render_item_by_title(document, "Replay Ground Station Connection").widget
    matrix_widget_id = matrix_widget.widget_id

    {:ok, view, _html} =
      live(
        conn,
        show_path(mission, dashboard) <>
          "?time_mode=replay_run&replay_run_id=#{replay_run_id}&scope_kind=ground_station&scope_id=dss-14"
      )

    render_dashboard_async(view)

    root_selector =
      ~s(#ops-dashboard-show-page[data-dashboard-time-mode="replay_run"][data-engine-time-mode="replay_run"][data-engine-replay-run-id="#{replay_run_id}"])

    assert has_element?(view, root_selector)

    row_selector =
      ~s(#widget-#{matrix_widget_id} [data-status-matrix-row="ground.station.connection_state:dss-14"])

    assert has_element?(
             view,
             row_selector <>
               ~s([data-status-matrix-source="operational_observables"][data-status-matrix-status-policy="connection_state"][data-status-matrix-realm="replay"][data-status-matrix-data-source-id="#{source_health_event.data_source_id}"][data-status-matrix-source-binding-id="#{source_health_event.source_binding_id}"][data-status-matrix-replay-run-id="#{replay_run_id}"][data-status-matrix-dataset="operational_observables_replay"][data-status-matrix-resource-id="dss-14"][data-status-matrix-scope-kind="ground_station"][data-status-matrix-ground-station-id="dss-14"][data-status-matrix-connection-state="connected"])
           )

    view
    |> element(row_selector <> ~s( [data-status-matrix-row-evidence]))
    |> render_click()

    evidence_path = assert_patch(view)
    assert evidence_path =~ "panel=evidence"
    assert evidence_path =~ "selected_evidence_kind=frame"
    assert evidence_path =~ "selected_placement=#{URI.encode_www_form(matrix_widget_id)}"

    assert evidence_path =~
             "selected_observable=#{URI.encode_www_form("ground.station.connection_state")}"

    assert evidence_path =~ "selected_data_source=#{source_health_event.data_source_id}"
    assert evidence_path =~ "selected_source_binding=#{source_health_event.source_binding_id}"
    assert evidence_path =~ "replay_run_id=#{replay_run_id}"
    assert evidence_path =~ "time_mode=replay_run"

    assert has_element?(
             view,
             ~s(#dashboard-evidence-inspector[data-evidence-kind="frame"][data-evidence-status="resolved"])
           )

    assert has_element?(
             view,
             ~s(#dashboard-evidence-inspector [data-evidence-ref-kind="source health interval"][data-evidence-ref-id="#{source_health_interval.interval_id}"])
           )

    assert has_element?(
             view,
             ~s(#dashboard-evidence-inspector [data-evidence-ref-kind="ground station connection state interval"][data-evidence-ref-id="#{ground_station_interval.interval_id}"])
           )

    assert has_element?(
             view,
             ~s(#dashboard-evidence-inspector [data-evidence-ref-kind="operational interval"][data-evidence-ref-id="#{ground_station_interval.source_event_id}"][data-evidence-ref-link-target="operational_event"])
           )

    assert has_element?(
             view,
             ~s(#dashboard-evidence-inspector [data-evidence-ref-kind="operational interval"][data-evidence-ref-id="#{source_health_interval.source_event_id}"][data-evidence-ref-link-target="operational_event"])
           )

    assert has_element?(
             view,
             ~s(#dashboard-evidence-inspector [data-evidence-ref-kind="source health event"][data-evidence-ref-id="#{source_health_event.source_health_event_id}"])
           )

    assert has_element?(
             view,
             ~s(#dashboard-evidence-copy-link[data-clipboard-text*="panel=evidence"][data-clipboard-text*="selected_evidence_kind=frame"][data-clipboard-text*="selected_observable=#{URI.encode_www_form("ground.station.connection_state")}"][data-clipboard-text*="selected_data_source=#{source_health_event.data_source_id}"][data-clipboard-text*="selected_source_binding=#{source_health_event.source_binding_id}"][data-clipboard-text*="replay_run_id=#{replay_run_id}"])
           )

    ground_station_event_selector =
      ~s(#dashboard-evidence-inspector [data-evidence-ref-kind="operational interval"][data-evidence-ref-id="#{ground_station_interval.source_event_id}"][data-evidence-ref-link-target="operational_event"])

    ground_station_operational_event_id = ground_station_interval.source_event_id

    ground_station_operational_event_route_id =
      URI.encode_www_form(ground_station_operational_event_id)

    ground_station_event_at_ms = DateTime.to_unix(observed_at, :millisecond)

    ground_station_operational_event_evidence =
      view
      |> render()
      |> LazyHTML.from_fragment()
      |> LazyHTML.query(ground_station_event_selector)

    assert ["operational_event"] =
             LazyHTML.attribute(ground_station_operational_event_evidence, "phx-value-target")

    assert [^ground_station_operational_event_id] =
             LazyHTML.attribute(ground_station_operational_event_evidence, "phx-value-target-id")

    assert ["evidence-ref:operational_event:" <> _] =
             LazyHTML.attribute(ground_station_operational_event_evidence, "phx-value-link-id")

    view
    |> element(ground_station_event_selector)
    |> render_click(%{
      "link-id" => "evidence-ref:operational_event:#{ground_station_operational_event_id}",
      "target" => "operational_event",
      "target-id" => ground_station_operational_event_id,
      "timestamp-ms" => ground_station_event_at_ms,
      "realm" => "replay",
      "time-mode" => "replay_run",
      "replay-run-id" => replay_run_id,
      "data-source-id" => source_health_event.data_source_id,
      "source-binding-id" => source_health_event.source_binding_id
    })

    assert has_element?(
             view,
             ~s(#dashboard-data-link-inspector[data-data-link-target="operational_event"][data-data-link-target-id="#{ground_station_operational_event_id}"][data-data-link-status="resolved"][data-data-link-selected-replay-run-id="#{replay_run_id}"][data-data-link-selected-data-source-id="#{source_health_event.data_source_id}"][data-data-link-selected-source-binding-id="#{source_health_event.source_binding_id}"])
           )

    ground_station_event_path = assert_patch(view)
    assert ground_station_event_path =~ "panel=data_link"
    assert ground_station_event_path =~ "selected_target=operational_event"
    assert ground_station_event_path =~ "selected_id=#{ground_station_operational_event_route_id}"
    assert ground_station_event_path =~ "selected_time=#{ground_station_event_at_ms}"
    assert ground_station_event_path =~ "replay_run_id=#{replay_run_id}"

    assert has_element?(
             view,
             ~s(#dashboard-data-link-copy-link[data-clipboard-text*="panel=data_link"][data-clipboard-text*="selected_target=operational_event"][data-clipboard-text*="selected_id=#{ground_station_operational_event_route_id}"][data-clipboard-text*="replay_run_id=#{replay_run_id}"][data-clipboard-text*="data_source_id=#{source_health_event.data_source_id}"][data-clipboard-text*="source_binding_id=#{source_health_event.source_binding_id}"])
           )

    ground_station_event_copied_path =
      view
      |> render()
      |> element_attribute("#dashboard-data-link-copy-link", "data-clipboard-text")

    assert ground_station_event_copied_path =~ "panel=data_link"
    assert ground_station_event_copied_path =~ "selected_target=operational_event"

    assert ground_station_event_copied_path =~
             "selected_id=#{ground_station_operational_event_route_id}"

    assert ground_station_event_copied_path =~ "selected_time=#{ground_station_event_at_ms}"
    assert ground_station_event_copied_path =~ "replay_run_id=#{replay_run_id}"

    assert ground_station_event_copied_path =~
             "data_source_id=#{source_health_event.data_source_id}"

    assert ground_station_event_copied_path =~
             "source_binding_id=#{source_health_event.source_binding_id}"

    {:ok, reopened_ground_station_event_view, _html} =
      live(conn, ground_station_event_copied_path)

    assert has_element?(
             reopened_ground_station_event_view,
             ~s(#dashboard-data-link-inspector[data-data-link-target="operational_event"][data-data-link-target-id="#{ground_station_operational_event_id}"][data-data-link-status="resolved"][data-data-link-selected-replay-run-id="#{replay_run_id}"][data-data-link-selected-data-source-id="#{source_health_event.data_source_id}"][data-data-link-selected-source-binding-id="#{source_health_event.source_binding_id}"])
           )

    assert has_element?(
             reopened_ground_station_event_view,
             ~s(#dashboard-data-link-copy-link[data-clipboard-text*="panel=data_link"][data-clipboard-text*="selected_target=operational_event"][data-clipboard-text*="selected_id=#{ground_station_operational_event_route_id}"][data-clipboard-text*="selected_time=#{ground_station_event_at_ms}"][data-clipboard-text*="replay_run_id=#{replay_run_id}"])
           )

    assert has_element?(
             reopened_ground_station_event_view,
             ~s(#dashboard-data-link-inspector [data-data-link-field="Connection state snapshot"]),
             "ground-station-connection-replay-source-health-1"
           )

    assert has_element?(
             reopened_ground_station_event_view,
             ~s(#dashboard-data-link-inspector [data-data-link-field="Connection state"]),
             "connected"
           )

    assert has_element?(
             reopened_ground_station_event_view,
             ~s(#dashboard-data-link-inspector [data-data-link-field="Observable"]),
             "ground.station.connection_state"
           )

    assert has_element?(
             reopened_ground_station_event_view,
             ~s(#dashboard-data-link-inspector [data-data-link-field="Resource"]),
             "dss-14"
           )

    assert has_element?(
             reopened_ground_station_event_view,
             ~s(#dashboard-data-link-inspector [data-data-link-field="Scope kind"]),
             "ground_station"
           )

    assert has_element?(
             reopened_ground_station_event_view,
             ~s(#dashboard-data-link-inspector [data-data-link-field="Transport"]),
             transport.transport_id
           )

    assert has_element?(
             reopened_ground_station_event_view,
             ~s(#dashboard-data-link-inspector [data-data-link-field="Source endpoint"]),
             "replay-source-health-endpoint"
           )

    assert has_element?(
             reopened_ground_station_event_view,
             ~s(#dashboard-data-link-inspector [data-data-link-field="Ground station"]),
             "dss-14"
           )

    assert has_element?(
             reopened_ground_station_event_view,
             ~s(#dashboard-data-link-inspector [data-data-link-field="Adapter"]),
             "tcp_socket"
           )

    assert has_element?(
             reopened_ground_station_event_view,
             ~s(#dashboard-data-link-inspector [data-data-link-field="State"]),
             "connected"
           )

    assert has_element?(
             reopened_ground_station_event_view,
             ~s(#dashboard-data-link-inspector [data-data-link-field="Replay run"]),
             replay_run_id
           )

    assert has_element?(
             view,
             ~s(#dashboard-data-link-inspector [data-data-link-field="Connection state snapshot"]),
             "ground-station-connection-replay-source-health-1"
           )

    stop_dashboard_view(reopened_ground_station_event_view)
    stop_dashboard_view(view)
  end

  test "opens replay source-health and transport execution interval evidence from rendered operational observable frame panel" do
    {
      conn,
      org,
      mission,
      replay_sources,
      transport,
      transport_execution_interval,
      source_health_event,
      source_health_interval,
      observed_at,
      replay_run_id
    } = setup_transport_execution_interval_evidence!()

    dashboard =
      TestFixtures.persist_dashboard_document!(mission,
        name: "Replay Transport Execution Evidence",
        widgets: [
          %{
            type: :state_timeline,
            title: "Replay Transport Execution",
            binding: %{
              source: :operational_observables,
              observables: ["comms.transport.execution_state"]
            }
          }
        ]
      )

    document =
      org
      |> fetch_dashboard_document!(mission, dashboard)
      |> then(fn %Document{} = document ->
        %Document{
          document
          | defaults: %{
              "data" => %{
                "realm" => "replay",
                "source_mode" => "specific",
                "source_contexts" => %{
                  "operational_observables" => %{
                    "source_binding_id" => replay_sources.operational_binding_id
                  }
                }
              }
            }
        }
      end)
      |> then(&replace_dashboard_row_document!(org, mission, &1))

    timeline_widget = render_item_by_title(document, "Replay Transport Execution").widget
    timeline_widget_id = timeline_widget.widget_id

    {:ok, view, _html} =
      live(
        conn,
        show_path(mission, dashboard) <>
          "?time_mode=replay_run&replay_run_id=#{replay_run_id}"
      )

    render_dashboard_async(view)

    root_selector =
      ~s(#ops-dashboard-show-page[data-dashboard-time-mode="replay_run"][data-engine-time-mode="replay_run"][data-engine-replay-run-id="#{replay_run_id}"])

    assert has_element?(view, root_selector)

    row_id =
      "state:comms.transport.execution_state:#{DateTime.to_unix(observed_at, :millisecond)}:0"

    row_selector = ~s(#widget-#{timeline_widget_id} [data-state-timeline-row="#{row_id}"])

    assert has_element?(
             view,
             row_selector <>
               ~s([data-state-timeline-observable="comms.transport.execution_state"][data-state-timeline-state="Initialized"][data-state-timeline-realm="replay"][data-state-timeline-data-source-id="#{source_health_event.data_source_id}"][data-state-timeline-source-binding-id="#{source_health_event.source_binding_id}"][data-state-timeline-replay-run-id="#{replay_run_id}"][data-state-timeline-dataset="operational_observables_replay"])
           )

    view
    |> element(row_selector <> ~s( [data-state-timeline-row-evidence]))
    |> render_click()

    evidence_path = assert_patch(view)
    assert evidence_path =~ "panel=evidence"
    assert evidence_path =~ "selected_evidence_kind=frame"
    assert evidence_path =~ "selected_placement=#{URI.encode_www_form(timeline_widget_id)}"
    assert evidence_path =~ "selected_observable=comms.transport.execution_state"
    assert evidence_path =~ "selected_data_source=#{source_health_event.data_source_id}"
    assert evidence_path =~ "selected_source_binding=#{source_health_event.source_binding_id}"
    assert evidence_path =~ "replay_run_id=#{replay_run_id}"
    assert evidence_path =~ "time_mode=replay_run"

    assert has_element?(
             view,
             ~s(#dashboard-evidence-inspector[data-evidence-kind="frame"][data-evidence-status="resolved"])
           )

    assert has_element?(
             view,
             ~s(#dashboard-evidence-inspector [data-evidence-ref-kind="source health interval"][data-evidence-ref-id="#{source_health_interval.interval_id}"])
           )

    assert has_element?(
             view,
             ~s(#dashboard-evidence-inspector [data-evidence-ref-kind="transport execution interval"][data-evidence-ref-id="#{transport_execution_interval.interval_id}"])
           )

    assert has_element?(
             view,
             ~s(#dashboard-evidence-inspector [data-evidence-ref-kind="operational interval"][data-evidence-ref-id="#{transport_execution_interval.source_event_id}"][data-evidence-ref-link-target="operational_event"])
           )

    assert has_element?(
             view,
             ~s(#dashboard-evidence-inspector [data-evidence-ref-kind="operational interval"][data-evidence-ref-id="#{source_health_interval.source_event_id}"][data-evidence-ref-link-target="operational_event"])
           )

    assert has_element?(
             view,
             ~s(#dashboard-evidence-inspector [data-evidence-ref-kind="source health event"][data-evidence-ref-id="#{source_health_event.source_health_event_id}"])
           )

    assert has_element?(
             view,
             ~s(#dashboard-evidence-copy-link[data-clipboard-text*="panel=evidence"][data-clipboard-text*="selected_evidence_kind=frame"][data-clipboard-text*="selected_observable=comms.transport.execution_state"][data-clipboard-text*="selected_data_source=#{source_health_event.data_source_id}"][data-clipboard-text*="selected_source_binding=#{source_health_event.source_binding_id}"][data-clipboard-text*="replay_run_id=#{replay_run_id}"])
           )

    transport_execution_event_selector =
      ~s(#dashboard-evidence-inspector [data-evidence-ref-kind="operational interval"][data-evidence-ref-id="#{transport_execution_interval.source_event_id}"][data-evidence-ref-link-target="operational_event"])

    transport_execution_operational_event_id = transport_execution_interval.source_event_id

    transport_execution_operational_event_route_id =
      URI.encode_www_form(transport_execution_operational_event_id)

    transport_execution_event_at_ms = DateTime.to_unix(observed_at, :millisecond)

    transport_execution_operational_event_evidence =
      view
      |> render()
      |> LazyHTML.from_fragment()
      |> LazyHTML.query(transport_execution_event_selector)

    assert ["operational_event"] =
             LazyHTML.attribute(
               transport_execution_operational_event_evidence,
               "phx-value-target"
             )

    assert [^transport_execution_operational_event_id] =
             LazyHTML.attribute(
               transport_execution_operational_event_evidence,
               "phx-value-target-id"
             )

    assert ["evidence-ref:operational_event:" <> _] =
             LazyHTML.attribute(
               transport_execution_operational_event_evidence,
               "phx-value-link-id"
             )

    view
    |> element(transport_execution_event_selector)
    |> render_click(%{
      "link-id" => "evidence-ref:operational_event:#{transport_execution_operational_event_id}",
      "target" => "operational_event",
      "target-id" => transport_execution_operational_event_id,
      "timestamp-ms" => transport_execution_event_at_ms,
      "realm" => "replay",
      "time-mode" => "replay_run",
      "replay-run-id" => replay_run_id,
      "data-source-id" => source_health_event.data_source_id,
      "source-binding-id" => source_health_event.source_binding_id
    })

    assert has_element?(
             view,
             ~s(#dashboard-data-link-inspector[data-data-link-target="operational_event"][data-data-link-target-id="#{transport_execution_operational_event_id}"][data-data-link-status="resolved"][data-data-link-selected-replay-run-id="#{replay_run_id}"][data-data-link-selected-data-source-id="#{source_health_event.data_source_id}"][data-data-link-selected-source-binding-id="#{source_health_event.source_binding_id}"])
           )

    transport_execution_event_path = assert_patch(view)
    assert transport_execution_event_path =~ "panel=data_link"
    assert transport_execution_event_path =~ "selected_target=operational_event"

    assert transport_execution_event_path =~
             "selected_id=#{transport_execution_operational_event_route_id}"

    assert transport_execution_event_path =~ "selected_time=#{transport_execution_event_at_ms}"
    assert transport_execution_event_path =~ "replay_run_id=#{replay_run_id}"

    assert has_element?(
             view,
             ~s(#dashboard-data-link-copy-link[data-clipboard-text*="panel=data_link"][data-clipboard-text*="selected_target=operational_event"][data-clipboard-text*="selected_id=#{transport_execution_operational_event_route_id}"][data-clipboard-text*="replay_run_id=#{replay_run_id}"][data-clipboard-text*="data_source_id=#{source_health_event.data_source_id}"][data-clipboard-text*="source_binding_id=#{source_health_event.source_binding_id}"])
           )

    transport_execution_event_copied_path =
      view
      |> render()
      |> element_attribute("#dashboard-data-link-copy-link", "data-clipboard-text")

    assert transport_execution_event_copied_path =~ "panel=data_link"
    assert transport_execution_event_copied_path =~ "selected_target=operational_event"

    assert transport_execution_event_copied_path =~
             "selected_id=#{transport_execution_operational_event_route_id}"

    assert transport_execution_event_copied_path =~
             "selected_time=#{transport_execution_event_at_ms}"

    assert transport_execution_event_copied_path =~ "replay_run_id=#{replay_run_id}"

    assert transport_execution_event_copied_path =~
             "data_source_id=#{source_health_event.data_source_id}"

    assert transport_execution_event_copied_path =~
             "source_binding_id=#{source_health_event.source_binding_id}"

    {:ok, reopened_transport_execution_event_view, _html} =
      live(conn, transport_execution_event_copied_path)

    assert has_element?(
             reopened_transport_execution_event_view,
             ~s(#dashboard-data-link-inspector[data-data-link-target="operational_event"][data-data-link-target-id="#{transport_execution_operational_event_id}"][data-data-link-status="resolved"][data-data-link-selected-replay-run-id="#{replay_run_id}"][data-data-link-selected-data-source-id="#{source_health_event.data_source_id}"][data-data-link-selected-source-binding-id="#{source_health_event.source_binding_id}"])
           )

    assert has_element?(
             reopened_transport_execution_event_view,
             ~s(#dashboard-data-link-copy-link[data-clipboard-text*="panel=data_link"][data-clipboard-text*="selected_target=operational_event"][data-clipboard-text*="selected_id=#{transport_execution_operational_event_route_id}"][data-clipboard-text*="selected_time=#{transport_execution_event_at_ms}"][data-clipboard-text*="replay_run_id=#{replay_run_id}"])
           )

    assert_transport_execution_details(
      reopened_transport_execution_event_view,
      transport,
      replay_run_id
    )

    assert has_element?(
             view,
             ~s(#dashboard-data-link-inspector [data-data-link-field="Transport capability record"]),
             "transport-execution-replay-source-health-1"
           )

    stop_dashboard_view(reopened_transport_execution_event_view)
    stop_dashboard_view(view)
  end

  test "opens replay RF state interval evidence from rendered operational observable frame panel" do
    observed_at = ~U[2026-06-17 12:02:00Z]
    replay_run_id = "replay_run_rf_state_ops"

    enable_dashboard_engine_inline_resolves!()
    configure_dashboard_source_health!(DateTime.add(observed_at, 60, :second))

    {conn, org, mission} = signed_in_org_and_mission()
    _telemetry_replay_source = persist_dashboard_realm!(mission, :replay)
    replay_sources = persist_replay_event_and_operational_sources!(mission)
    persist_replay_run!(mission, replay_run_id)
    {_source_endpoint, transport} = persist_replay_connection_state_resources!(org, mission)

    assert {:ok, _rf_lock_event} =
             operational_observable_state_event(
               org.organization_id,
               mission.mission_id,
               "rf-lock-replay-rendered-1",
               :locked,
               observed_at,
               replay_run_id: replay_run_id,
               observable_id: "link.rf_lock_state",
               resource_id: "link-alpha",
               scope_kind: :link,
               transport_id: transport.transport_id,
               link_id: "link-alpha"
             )
             |> OperationalEvents.persist_event()

    assert {:ok, _frame_sync_event} =
             operational_observable_state_event(
               org.organization_id,
               mission.mission_id,
               "frame-sync-replay-rendered-1",
               :synchronized,
               DateTime.add(observed_at, 1, :second),
               replay_run_id: replay_run_id,
               observable_id: "link.frame_sync_state",
               resource_id: "link-alpha",
               scope_kind: :link,
               transport_id: transport.transport_id,
               link_id: "link-alpha"
             )
             |> OperationalEvents.persist_event()

    [rf_lock_interval] =
      Cadence.operational_link_rf_state_intervals(org.organization_id, mission.mission_id,
        observable_id: "link.rf_lock_state",
        resource_id: "link-alpha",
        replay_run_id: replay_run_id
      )

    [frame_sync_interval] =
      Cadence.operational_link_rf_state_intervals(org.organization_id, mission.mission_id,
        observable_id: "link.frame_sync_state",
        resource_id: "link-alpha",
        replay_run_id: replay_run_id
      )

    dashboard =
      TestFixtures.persist_dashboard_document!(mission,
        name: "Replay RF Evidence",
        widgets: [
          %{
            type: :status_matrix,
            title: "Replay RF Lock",
            binding: %{
              source: :operational_observables,
              observables: ["link.rf_lock_state"]
            }
          },
          %{
            type: :status_matrix,
            title: "Replay Frame Sync",
            binding: %{
              source: :operational_observables,
              observables: ["link.frame_sync_state"]
            }
          }
        ]
      )

    document =
      org
      |> fetch_dashboard_document!(mission, dashboard)
      |> then(fn %Document{} = document ->
        %Document{
          document
          | defaults: %{
              "data" => %{
                "realm" => "replay",
                "source_mode" => "specific",
                "source_contexts" => %{
                  "operational_observables" => %{
                    "source_binding_id" => replay_sources.operational_binding_id
                  }
                }
              }
            }
        }
      end)
      |> then(&replace_dashboard_row_document!(org, mission, &1))

    rf_lock_widget = render_item_by_title(document, "Replay RF Lock").widget
    frame_sync_widget = render_item_by_title(document, "Replay Frame Sync").widget

    {:ok, view, _html} =
      live(
        conn,
        show_path(mission, dashboard) <>
          "?time_mode=replay_run&replay_run_id=#{replay_run_id}"
      )

    render_dashboard_async(view)

    root_selector =
      ~s(#ops-dashboard-show-page[data-dashboard-time-mode="replay_run"][data-engine-time-mode="replay_run"][data-engine-replay-run-id="#{replay_run_id}"])

    assert has_element?(view, root_selector)

    rf_lock_row_selector =
      ~s(#widget-#{rf_lock_widget.widget_id} [data-status-matrix-row="link.rf_lock_state:link-alpha"])

    assert has_element?(
             view,
             rf_lock_row_selector <>
               ~s([data-status-matrix-source="operational_observables"][data-status-matrix-realm="replay"][data-status-matrix-data-source-id="#{replay_sources.operational_data_source_id}"][data-status-matrix-source-binding-id="#{replay_sources.operational_binding_id}"][data-status-matrix-replay-run-id="#{replay_run_id}"][data-status-matrix-dataset="operational_observables_replay"][data-status-matrix-link-id="link-alpha"][data-status-matrix-transport-id="#{transport.transport_id}"])
           )

    open_and_assert_replay_rf_evidence!(
      view,
      conn,
      %{
        row_selector: rf_lock_row_selector,
        widget_id: rf_lock_widget.widget_id,
        observable_id: "link.rf_lock_state",
        replay_sources: replay_sources,
        replay_run_id: replay_run_id,
        interval: rf_lock_interval,
        expected_snapshot_id: "rf-lock-replay-rendered-1",
        expected_state: "locked",
        expected_transport_id: transport.transport_id
      }
    )

    frame_sync_row_selector =
      ~s(#widget-#{frame_sync_widget.widget_id} [data-status-matrix-row="link.frame_sync_state:link-alpha"])

    assert has_element?(
             view,
             frame_sync_row_selector <>
               ~s([data-status-matrix-source="operational_observables"][data-status-matrix-realm="replay"][data-status-matrix-data-source-id="#{replay_sources.operational_data_source_id}"][data-status-matrix-source-binding-id="#{replay_sources.operational_binding_id}"][data-status-matrix-replay-run-id="#{replay_run_id}"][data-status-matrix-dataset="operational_observables_replay"][data-status-matrix-link-id="link-alpha"][data-status-matrix-transport-id="#{transport.transport_id}"])
           )

    open_and_assert_replay_rf_evidence!(
      view,
      conn,
      %{
        row_selector: frame_sync_row_selector,
        widget_id: frame_sync_widget.widget_id,
        observable_id: "link.frame_sync_state",
        replay_sources: replay_sources,
        replay_run_id: replay_run_id,
        interval: frame_sync_interval,
        expected_snapshot_id: "frame-sync-replay-rendered-1",
        expected_state: "synchronized",
        expected_transport_id: transport.transport_id
      }
    )

    stop_dashboard_view(view)
  end
end
