defmodule CadenceWeb.OpsDashboardShowLive.RuntimeReplayConnectionEvidenceLiveTest do
  use CadenceWeb.ConnCase, async: false

  import Phoenix.LiveViewTest
  use CadenceWeb.OpsDashboardShowLive.ViewTestSupport
  import CadenceWeb.OpsDashboardShowLive.RuntimeReplaySourceFamilyFixtures
  import CadenceWeb.OpsDashboardShowLive.RuntimeReplayEvidenceFixtures

  use Phoenix.VerifiedRoutes,
    endpoint: CadenceWeb.Endpoint,
    router: CadenceWeb.Router,
    statics: CadenceWeb.static_paths()

  alias Cadence.Dashboards.Document
  alias Cadence.OperationalEvents
  alias CadenceWeb.TestFixtures

  defp assert_replay_connection_event_route(
         conn,
         evidence_path,
         connection_interval,
         observed_at,
         replay_run_id,
         source_health_event,
         transport
       ) do
    {:ok, view, _html} = live(conn, evidence_path)

    connection_event_selector =
      ~s(#dashboard-evidence-inspector [data-evidence-ref-kind="operational interval"][data-evidence-ref-id="#{connection_interval.source_event_id}"][data-evidence-ref-link-target="operational_event"])

    connection_operational_event_id = connection_interval.source_event_id
    connection_operational_event_route_id = URI.encode_www_form(connection_operational_event_id)
    connection_event_at_ms = DateTime.to_unix(observed_at, :millisecond)

    connection_operational_event_evidence =
      view
      |> render()
      |> LazyHTML.from_fragment()
      |> LazyHTML.query(connection_event_selector)

    assert ["operational_event"] =
             LazyHTML.attribute(connection_operational_event_evidence, "phx-value-target")

    assert [^connection_operational_event_id] =
             LazyHTML.attribute(connection_operational_event_evidence, "phx-value-target-id")

    assert ["evidence-ref:operational_event:" <> _] =
             LazyHTML.attribute(connection_operational_event_evidence, "phx-value-link-id")

    view
    |> element(connection_event_selector)
    |> render_click(%{
      "link-id" => "evidence-ref:operational_event:#{connection_operational_event_id}",
      "target" => "operational_event",
      "target-id" => connection_operational_event_id,
      "timestamp-ms" => connection_event_at_ms,
      "realm" => "replay",
      "time-mode" => "replay_run",
      "replay-run-id" => replay_run_id,
      "data-source-id" => source_health_event.data_source_id,
      "source-binding-id" => source_health_event.source_binding_id
    })

    assert has_element?(
             view,
             ~s(#dashboard-data-link-inspector[data-data-link-target="operational_event"][data-data-link-target-id="#{connection_operational_event_id}"][data-data-link-status="resolved"][data-data-link-selected-replay-run-id="#{replay_run_id}"][data-data-link-selected-data-source-id="#{source_health_event.data_source_id}"][data-data-link-selected-source-binding-id="#{source_health_event.source_binding_id}"])
           )

    connection_event_path = assert_patch(view)
    assert connection_event_path =~ "panel=data_link"
    assert connection_event_path =~ "selected_target=operational_event"
    assert connection_event_path =~ "selected_id=#{connection_operational_event_route_id}"
    assert connection_event_path =~ "selected_time=#{connection_event_at_ms}"
    assert connection_event_path =~ "replay_run_id=#{replay_run_id}"

    assert has_element?(
             view,
             ~s(#dashboard-data-link-copy-link[data-clipboard-text*="panel=data_link"][data-clipboard-text*="selected_target=operational_event"][data-clipboard-text*="selected_id=#{connection_operational_event_route_id}"][data-clipboard-text*="replay_run_id=#{replay_run_id}"][data-clipboard-text*="data_source_id=#{source_health_event.data_source_id}"][data-clipboard-text*="source_binding_id=#{source_health_event.source_binding_id}"])
           )

    connection_event_copied_path =
      view
      |> render()
      |> element_attribute("#dashboard-data-link-copy-link", "data-clipboard-text")

    assert connection_event_copied_path =~ "panel=data_link"
    assert connection_event_copied_path =~ "selected_target=operational_event"
    assert connection_event_copied_path =~ "selected_id=#{connection_operational_event_route_id}"
    assert connection_event_copied_path =~ "selected_time=#{connection_event_at_ms}"
    assert connection_event_copied_path =~ "replay_run_id=#{replay_run_id}"
    assert connection_event_copied_path =~ "data_source_id=#{source_health_event.data_source_id}"

    assert connection_event_copied_path =~
             "source_binding_id=#{source_health_event.source_binding_id}"

    {:ok, reopened_connection_event_view, _html} = live(conn, connection_event_copied_path)

    assert has_element?(
             reopened_connection_event_view,
             ~s(#dashboard-data-link-inspector[data-data-link-target="operational_event"][data-data-link-target-id="#{connection_operational_event_id}"][data-data-link-status="resolved"][data-data-link-selected-replay-run-id="#{replay_run_id}"][data-data-link-selected-data-source-id="#{source_health_event.data_source_id}"][data-data-link-selected-source-binding-id="#{source_health_event.source_binding_id}"])
           )

    assert has_element?(
             reopened_connection_event_view,
             ~s(#dashboard-data-link-copy-link[data-clipboard-text*="panel=data_link"][data-clipboard-text*="selected_target=operational_event"][data-clipboard-text*="selected_id=#{connection_operational_event_route_id}"][data-clipboard-text*="selected_time=#{connection_event_at_ms}"][data-clipboard-text*="replay_run_id=#{replay_run_id}"])
           )

    assert has_element?(
             reopened_connection_event_view,
             ~s(#dashboard-data-link-inspector [data-data-link-field="Connection state snapshot"]),
             "connection-replay-source-health-1"
           )

    assert has_element?(
             reopened_connection_event_view,
             ~s(#dashboard-data-link-inspector [data-data-link-field="Connection state"]),
             "degraded"
           )

    assert has_element?(
             reopened_connection_event_view,
             ~s(#dashboard-data-link-inspector [data-data-link-field="Observable"]),
             "comms.transport.connection_state"
           )

    assert has_element?(
             reopened_connection_event_view,
             ~s(#dashboard-data-link-inspector [data-data-link-field="Resource"]),
             transport.transport_id
           )

    assert has_element?(
             reopened_connection_event_view,
             ~s(#dashboard-data-link-inspector [data-data-link-field="Scope kind"]),
             "transport"
           )

    assert has_element?(
             reopened_connection_event_view,
             ~s(#dashboard-data-link-inspector [data-data-link-field="Transport"]),
             transport.transport_id
           )

    assert has_element?(
             reopened_connection_event_view,
             ~s(#dashboard-data-link-inspector [data-data-link-field="Source endpoint"]),
             "replay-source-health-endpoint"
           )

    assert has_element?(
             reopened_connection_event_view,
             ~s(#dashboard-data-link-inspector [data-data-link-field="Ground station"]),
             "dss-14"
           )

    assert has_element?(
             reopened_connection_event_view,
             ~s(#dashboard-data-link-inspector [data-data-link-field="Adapter"]),
             "tcp_socket"
           )

    assert has_element?(
             reopened_connection_event_view,
             ~s(#dashboard-data-link-inspector [data-data-link-field="State"]),
             "degraded"
           )

    assert has_element?(
             reopened_connection_event_view,
             ~s(#dashboard-data-link-inspector [data-data-link-field="Replay run"]),
             replay_run_id
           )

    assert has_element?(
             view,
             ~s(#dashboard-data-link-inspector [data-data-link-field="Connection state snapshot"]),
             "connection-replay-source-health-1"
           )

    stop_dashboard_view(reopened_connection_event_view)
    stop_dashboard_view(view)
  end

  defp assert_replay_source_health_event_route(
         conn,
         evidence_path,
         source_health_interval,
         observed_at,
         replay_run_id,
         source_health_event
       ) do
    {:ok, view, _html} = live(conn, evidence_path)

    source_health_event_selector =
      ~s(#dashboard-evidence-inspector [data-evidence-ref-kind="operational interval"][data-evidence-ref-id="#{source_health_interval.source_event_id}"][data-evidence-ref-link-target="operational_event"])

    source_health_operational_event_id = source_health_interval.source_event_id

    source_health_operational_event_route_id =
      URI.encode_www_form(source_health_operational_event_id)

    source_health_event_at_ms = DateTime.to_unix(observed_at, :millisecond)

    source_health_operational_event_evidence =
      view
      |> render()
      |> LazyHTML.from_fragment()
      |> LazyHTML.query(source_health_event_selector)

    assert ["operational_event"] =
             LazyHTML.attribute(source_health_operational_event_evidence, "phx-value-target")

    assert [^source_health_operational_event_id] =
             LazyHTML.attribute(source_health_operational_event_evidence, "phx-value-target-id")

    assert ["evidence-ref:operational_event:" <> _] =
             LazyHTML.attribute(source_health_operational_event_evidence, "phx-value-link-id")

    view
    |> element(source_health_event_selector)
    |> render_click(%{
      "link-id" => "evidence-ref:operational_event:#{source_health_operational_event_id}",
      "target" => "operational_event",
      "target-id" => source_health_operational_event_id,
      "timestamp-ms" => source_health_event_at_ms,
      "realm" => "replay",
      "time-mode" => "replay_run",
      "replay-run-id" => replay_run_id,
      "data-source-id" => source_health_event.data_source_id,
      "source-binding-id" => source_health_event.source_binding_id
    })

    assert has_element?(
             view,
             ~s(#dashboard-data-link-inspector[data-data-link-target="operational_event"][data-data-link-target-id="#{source_health_operational_event_id}"][data-data-link-status="resolved"][data-data-link-selected-replay-run-id="#{replay_run_id}"][data-data-link-selected-data-source-id="#{source_health_event.data_source_id}"][data-data-link-selected-source-binding-id="#{source_health_event.source_binding_id}"])
           )

    source_health_event_path = assert_patch(view)
    assert source_health_event_path =~ "panel=data_link"
    assert source_health_event_path =~ "selected_target=operational_event"
    assert source_health_event_path =~ "selected_id=#{source_health_operational_event_route_id}"
    assert source_health_event_path =~ "selected_time=#{source_health_event_at_ms}"
    assert source_health_event_path =~ "replay_run_id=#{replay_run_id}"

    assert has_element?(
             view,
             ~s(#dashboard-data-link-copy-link[data-clipboard-text*="panel=data_link"][data-clipboard-text*="selected_target=operational_event"][data-clipboard-text*="selected_id=#{source_health_operational_event_route_id}"][data-clipboard-text*="replay_run_id=#{replay_run_id}"][data-clipboard-text*="data_source_id=#{source_health_event.data_source_id}"][data-clipboard-text*="source_binding_id=#{source_health_event.source_binding_id}"])
           )

    source_health_event_copied_path =
      view
      |> render()
      |> element_attribute("#dashboard-data-link-copy-link", "data-clipboard-text")

    assert source_health_event_copied_path =~ "panel=data_link"
    assert source_health_event_copied_path =~ "selected_target=operational_event"

    assert source_health_event_copied_path =~
             "selected_id=#{source_health_operational_event_route_id}"

    assert source_health_event_copied_path =~ "selected_time=#{source_health_event_at_ms}"
    assert source_health_event_copied_path =~ "replay_run_id=#{replay_run_id}"

    assert source_health_event_copied_path =~
             "data_source_id=#{source_health_event.data_source_id}"

    assert source_health_event_copied_path =~
             "source_binding_id=#{source_health_event.source_binding_id}"

    {:ok, reopened_source_health_event_view, _html} = live(conn, source_health_event_copied_path)

    assert has_element?(
             reopened_source_health_event_view,
             ~s(#dashboard-data-link-inspector[data-data-link-target="operational_event"][data-data-link-target-id="#{source_health_operational_event_id}"][data-data-link-status="resolved"][data-data-link-selected-replay-run-id="#{replay_run_id}"][data-data-link-selected-data-source-id="#{source_health_event.data_source_id}"][data-data-link-selected-source-binding-id="#{source_health_event.source_binding_id}"])
           )

    assert has_element?(
             reopened_source_health_event_view,
             ~s(#dashboard-data-link-copy-link[data-clipboard-text*="panel=data_link"][data-clipboard-text*="selected_target=operational_event"][data-clipboard-text*="selected_id=#{source_health_operational_event_route_id}"][data-clipboard-text*="selected_time=#{source_health_event_at_ms}"][data-clipboard-text*="replay_run_id=#{replay_run_id}"])
           )

    assert has_element?(
             reopened_source_health_event_view,
             ~s(#dashboard-data-link-inspector [data-data-link-field="Source health event"]),
             source_health_event.source_health_event_id
           )

    assert has_element?(
             reopened_source_health_event_view,
             ~s(#dashboard-data-link-inspector [data-data-link-field="Logical source"]),
             "operational_observables"
           )

    assert has_element?(
             reopened_source_health_event_view,
             ~s(#dashboard-data-link-inspector [data-data-link-field="Data source"]),
             source_health_event.data_source_id
           )

    assert has_element?(
             reopened_source_health_event_view,
             ~s(#dashboard-data-link-inspector [data-data-link-field="Source binding"]),
             source_health_event.source_binding_id
           )

    assert has_element?(
             reopened_source_health_event_view,
             ~s(#dashboard-data-link-inspector [data-data-link-field="Realm"]),
             "replay"
           )

    assert has_element?(
             reopened_source_health_event_view,
             ~s(#dashboard-data-link-inspector [data-data-link-field="Dataset"]),
             "operational_observables_replay"
           )

    assert has_element?(
             reopened_source_health_event_view,
             ~s(#dashboard-data-link-inspector [data-data-link-field="Event type"]),
             "degraded"
           )

    assert has_element?(
             reopened_source_health_event_view,
             ~s(#dashboard-data-link-inspector [data-data-link-field="Source health"]),
             "degraded"
           )

    assert has_element?(
             reopened_source_health_event_view,
             ~s(#dashboard-data-link-inspector [data-data-link-field="Reason"]),
             "source_probe_failed"
           )

    assert has_element?(
             reopened_source_health_event_view,
             ~s(#dashboard-data-link-inspector [data-data-link-field="Source payload"]),
             "Replay operational observables source probe degraded"
           )

    assert has_element?(
             reopened_source_health_event_view,
             ~s(#dashboard-data-link-inspector [data-data-link-field="Replay run"]),
             replay_run_id
           )

    assert has_element?(
             view,
             ~s(#dashboard-data-link-inspector [data-data-link-field="Source health event"]),
             source_health_event.source_health_event_id
           )

    stop_dashboard_view(reopened_source_health_event_view)
    stop_dashboard_view(view)
  end

  test "opens replay source-health and connection interval evidence from rendered operational observable frame panel" do
    observed_at = ~U[2026-06-17 12:02:00Z]
    replay_run_id = "replay_run_source_health_ops"

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
               "connection-replay-source-health-1",
               :degraded,
               observed_at,
               replay_run_id: replay_run_id,
               transport_id: transport.transport_id
             )
             |> OperationalEvents.persist_event()

    [connection_interval] =
      Cadence.OperationalEvents.connection_state_intervals(
        org.organization_id,
        mission.mission_id,
        observable_id: "comms.transport.connection_state",
        resource_id: transport.transport_id,
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

    dashboard =
      TestFixtures.persist_dashboard_document!(mission,
        name: "Replay Source Health Evidence",
        widgets: [
          %{
            type: :status_matrix,
            title: "Replay Connection State",
            binding: %{
              source: :operational_observables,
              observables: ["comms.transport.connection_state"]
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

    matrix_widget = render_item_by_title(document, "Replay Connection State").widget
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
      ~s(#widget-#{matrix_widget_id} [data-status-matrix-row="comms.transport.connection_state:#{transport.transport_id}"])

    assert has_element?(
             view,
             row_selector <>
               ~s([data-status-matrix-source="operational_observables"][data-status-matrix-status-policy="connection_state"][data-status-matrix-realm="replay"][data-status-matrix-data-source-id="#{source_health_event.data_source_id}"][data-status-matrix-source-binding-id="#{source_health_event.source_binding_id}"][data-status-matrix-replay-run-id="#{replay_run_id}"][data-status-matrix-dataset="operational_observables_replay"][data-status-matrix-connection-state="degraded"])
           )

    view
    |> element(row_selector <> ~s( [data-status-matrix-row-evidence]))
    |> render_click()

    evidence_path = assert_patch(view)
    assert evidence_path =~ "panel=evidence"
    assert evidence_path =~ "selected_evidence_kind=frame"
    assert evidence_path =~ "selected_placement=#{URI.encode_www_form(matrix_widget_id)}"
    assert evidence_path =~ "selected_observable=comms.transport.connection_state"
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
             ~s(#dashboard-evidence-inspector [data-evidence-ref-kind="source health interval"][data-evidence-ref-id="#{source_health_interval.interval_id}"][data-evidence-ref-link-target="source_health_interval"])
           )

    assert has_element?(
             view,
             ~s(#dashboard-evidence-inspector [data-evidence-ref-kind="transport connection state interval"][data-evidence-ref-id="#{connection_interval.interval_id}"])
           )

    assert has_element?(
             view,
             ~s(#dashboard-evidence-inspector [data-evidence-ref-kind="operational interval"][data-evidence-ref-id="#{connection_interval.source_event_id}"][data-evidence-ref-link-target="operational_event"])
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
             ~s(#dashboard-evidence-copy-link[data-clipboard-text*="panel=evidence"][data-clipboard-text*="selected_evidence_kind=frame"][data-clipboard-text*="selected_observable=comms.transport.connection_state"][data-clipboard-text*="selected_data_source=#{source_health_event.data_source_id}"][data-clipboard-text*="selected_source_binding=#{source_health_event.source_binding_id}"][data-clipboard-text*="replay_run_id=#{replay_run_id}"])
           )

    source_health_interval_selector =
      ~s(#dashboard-evidence-inspector [data-evidence-ref-kind="source health interval"][data-evidence-ref-id="#{source_health_interval.interval_id}"][data-evidence-ref-link-target="source_health_interval"])

    view
    |> element(source_health_interval_selector)
    |> render_click()

    source_health_interval_route_id = URI.encode_www_form(source_health_interval.interval_id)
    source_health_interval_path = assert_patch(view)

    assert source_health_interval_path =~ "panel=data_link"
    assert source_health_interval_path =~ "selected_target=source_health_interval"
    assert source_health_interval_path =~ "selected_id=#{source_health_interval_route_id}"
    assert source_health_interval_path =~ "replay_run_id=#{replay_run_id}"

    assert has_element?(
             view,
             ~s(#dashboard-data-link-inspector[data-data-link-target="source_health_interval"][data-data-link-target-id="#{source_health_interval.interval_id}"][data-data-link-status="resolved"][data-data-link-selected-replay-run-id="#{replay_run_id}"][data-data-link-selected-data-source-id="#{source_health_event.data_source_id}"][data-data-link-selected-source-binding-id="#{source_health_event.source_binding_id}"])
           )

    source_health_interval_copied_path =
      view
      |> render()
      |> element_attribute("#dashboard-data-link-copy-link", "data-clipboard-text")

    {:ok, reopened_source_health_interval_view, _html} =
      live(conn, source_health_interval_copied_path)

    assert has_element?(
             reopened_source_health_interval_view,
             ~s(#dashboard-data-link-inspector[data-data-link-target="source_health_interval"][data-data-link-target-id="#{source_health_interval.interval_id}"][data-data-link-status="resolved"][data-data-link-selected-replay-run-id="#{replay_run_id}"])
           )

    assert has_element?(
             reopened_source_health_interval_view,
             ~s(#dashboard-data-link-inspector [data-data-link-field="Operational interval"]),
             source_health_interval.interval_id
           )

    assert has_element?(
             reopened_source_health_interval_view,
             ~s(#dashboard-data-link-inspector [data-data-link-field="Source event"]),
             source_health_interval.source_event_id
           )

    stop_dashboard_view(reopened_source_health_interval_view)
    stop_dashboard_view(view)

    assert_replay_connection_event_route(
      conn,
      evidence_path,
      connection_interval,
      observed_at,
      replay_run_id,
      source_health_event,
      transport
    )

    assert_replay_source_health_event_route(
      conn,
      evidence_path,
      source_health_interval,
      observed_at,
      replay_run_id,
      source_health_event
    )
  end

  test "reopens replay source-health interval copied from rendered frame evidence" do
    observed_at = ~U[2026-07-11 12:02:00Z]
    replay_run_id = "replay_run_source_health_interval_route"

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
               "connection-replay-source-health-interval-route",
               :degraded,
               observed_at,
               replay_run_id: replay_run_id,
               transport_id: transport.transport_id
             )
             |> OperationalEvents.persist_event()

    {source_health_event, source_health_interval} =
      record_replay_operational_source_health!(
        org,
        mission,
        replay_sources,
        observed_at,
        replay_run_id
      )

    dashboard =
      TestFixtures.persist_dashboard_document!(mission,
        name: "Replay Source Health Interval Route",
        widgets: [
          %{
            type: :status_matrix,
            title: "Replay Connection State",
            binding: %{
              source: :operational_observables,
              observables: ["comms.transport.connection_state"]
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

    matrix_widget_id =
      document
      |> render_item_by_title("Replay Connection State")
      |> Map.fetch!(:widget)
      |> Map.fetch!(:widget_id)

    {:ok, view, _html} =
      live(
        conn,
        show_path(mission, dashboard) <>
          "?time_mode=replay_run&replay_run_id=#{replay_run_id}&scope_kind=ground_station&scope_id=dss-14"
      )

    render_dashboard_async(view)

    row_selector =
      ~s(#widget-#{matrix_widget_id} [data-status-matrix-row="comms.transport.connection_state:#{transport.transport_id}"])

    view
    |> element(row_selector <> ~s( [data-status-matrix-row-evidence]))
    |> render_click()

    interval_selector =
      ~s(#dashboard-evidence-inspector [data-evidence-ref-kind="source health interval"][data-evidence-ref-id="#{source_health_interval.interval_id}"][data-evidence-ref-link-target="source_health_interval"])

    assert has_element?(view, interval_selector)

    view
    |> element(interval_selector)
    |> render_click()

    interval_route_id = URI.encode_www_form(source_health_interval.interval_id)

    assert has_element?(
             view,
             ~s(#dashboard-data-link-inspector[data-data-link-target="source_health_interval"][data-data-link-target-id="#{source_health_interval.interval_id}"][data-data-link-status="resolved"][data-data-link-selected-replay-run-id="#{replay_run_id}"][data-data-link-selected-data-source-id="#{source_health_event.data_source_id}"][data-data-link-selected-source-binding-id="#{source_health_event.source_binding_id}"])
           )

    copied_path =
      view
      |> render()
      |> element_attribute("#dashboard-data-link-copy-link", "data-clipboard-text")

    assert copied_path =~ "selected_target=source_health_interval"
    assert copied_path =~ "selected_id=#{interval_route_id}"
    assert copied_path =~ "replay_run_id=#{replay_run_id}"
    assert copied_path =~ "data_source_id=#{source_health_event.data_source_id}"
    assert copied_path =~ "source_binding_id=#{source_health_event.source_binding_id}"

    stop_dashboard_view(view)

    {:ok, reopened_view, _html} = live(conn, copied_path)

    assert has_element?(
             reopened_view,
             ~s(#dashboard-data-link-inspector[data-data-link-target="source_health_interval"][data-data-link-target-id="#{source_health_interval.interval_id}"][data-data-link-status="resolved"][data-data-link-selected-replay-run-id="#{replay_run_id}"][data-data-link-selected-data-source-id="#{source_health_event.data_source_id}"][data-data-link-selected-source-binding-id="#{source_health_event.source_binding_id}"])
           )

    assert has_element?(
             reopened_view,
             ~s(#dashboard-data-link-inspector [data-data-link-field="Operational interval"]),
             source_health_interval.interval_id
           )

    assert has_element?(
             reopened_view,
             ~s(#dashboard-data-link-inspector [data-data-link-field="Source event"]),
             source_health_interval.source_event_id
           )

    stop_dashboard_view(reopened_view)
  end

  test "opens replay antenna pointing operational-event copied route from rendered operational observable frame panel" do
    observed_at = ~U[2026-06-17 12:03:00Z]
    replay_run_id = "replay_run_antenna_pointing_ops"

    configure_dashboard_source_health!(DateTime.add(observed_at, 60, :second))

    {conn, org, mission} = signed_in_org_and_mission()
    _telemetry_replay_source = persist_dashboard_realm!(mission, :replay)
    replay_sources = persist_replay_event_and_operational_sources!(mission)
    persist_replay_run!(mission, replay_run_id)
    {_source_endpoint, transport} = persist_replay_connection_state_resources!(org, mission)

    assert {:ok, _antenna_pointing_event} =
             operational_observable_state_event(
               org.organization_id,
               mission.mission_id,
               "antenna-pointing-replay-rendered-1",
               :tracking,
               observed_at,
               replay_run_id: replay_run_id,
               observable_id: "ground.station.antenna_pointing_state",
               resource_id: "dss-14",
               scope_kind: :ground_station,
               transport_id: transport.transport_id
             )
             |> OperationalEvents.persist_event()

    [antenna_pointing_interval] =
      Cadence.OperationalEvents.operational_observable_state_intervals(
        org.organization_id,
        mission.mission_id,
        observable_id: "ground.station.antenna_pointing_state",
        resource_id: "dss-14",
        replay_run_id: replay_run_id
      )

    dashboard =
      TestFixtures.persist_dashboard_document!(mission,
        name: "Replay Antenna Pointing Evidence",
        widgets: [
          %{
            type: :status_matrix,
            title: "Replay Antenna Pointing",
            binding: %{
              source: :operational_observables,
              observables: ["ground.station.antenna_pointing_state"]
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

    matrix_widget = render_item_by_title(document, "Replay Antenna Pointing").widget
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
      ~s(#widget-#{matrix_widget_id} [data-status-matrix-row="ground.station.antenna_pointing_state:dss-14"])

    assert has_element?(
             view,
             row_selector <>
               ~s([data-status-matrix-source="operational_observables"][data-status-matrix-realm="replay"][data-status-matrix-data-source-id="#{replay_sources.operational_data_source_id}"][data-status-matrix-source-binding-id="#{replay_sources.operational_binding_id}"][data-status-matrix-replay-run-id="#{replay_run_id}"][data-status-matrix-dataset="operational_observables_replay"][data-status-matrix-resource-id="dss-14"][data-status-matrix-scope-kind="ground_station"][data-status-matrix-ground-station-id="dss-14"])
           )

    view
    |> element(row_selector <> ~s( [data-status-matrix-row-evidence]))
    |> render_click()

    evidence_path = assert_patch(view)
    assert evidence_path =~ "panel=evidence"
    assert evidence_path =~ "selected_evidence_kind=frame"
    assert evidence_path =~ "selected_placement=#{URI.encode_www_form(matrix_widget_id)}"

    assert evidence_path =~
             "selected_observable=#{URI.encode_www_form("ground.station.antenna_pointing_state")}"

    assert evidence_path =~ "selected_data_source=#{replay_sources.operational_data_source_id}"
    assert evidence_path =~ "selected_source_binding=#{replay_sources.operational_binding_id}"
    assert evidence_path =~ "replay_run_id=#{replay_run_id}"
    assert evidence_path =~ "time_mode=replay_run"

    assert has_element?(
             view,
             ~s(#dashboard-evidence-inspector[data-evidence-kind="frame"][data-evidence-status="resolved"])
           )

    assert has_element?(
             view,
             ~s(#dashboard-evidence-inspector [data-evidence-ref-kind="ground station antenna pointing state interval"][data-evidence-ref-id="#{antenna_pointing_interval.interval_id}"])
           )

    assert has_element?(
             view,
             ~s(#dashboard-evidence-inspector [data-evidence-ref-kind="operational interval"][data-evidence-ref-id="#{antenna_pointing_interval.source_event_id}"][data-evidence-ref-link-target="operational_event"])
           )

    assert has_element?(
             view,
             ~s(#dashboard-evidence-copy-link[data-clipboard-text*="panel=evidence"][data-clipboard-text*="selected_evidence_kind=frame"][data-clipboard-text*="selected_observable=#{URI.encode_www_form("ground.station.antenna_pointing_state")}"][data-clipboard-text*="selected_data_source=#{replay_sources.operational_data_source_id}"][data-clipboard-text*="selected_source_binding=#{replay_sources.operational_binding_id}"][data-clipboard-text*="replay_run_id=#{replay_run_id}"])
           )

    antenna_pointing_event_id = antenna_pointing_interval.source_event_id
    antenna_pointing_event_route_id = URI.encode_www_form(antenna_pointing_event_id)
    antenna_pointing_event_at_ms = DateTime.to_unix(observed_at, :millisecond)

    antenna_pointing_event_selector =
      ~s(#dashboard-evidence-inspector [data-evidence-ref-kind="operational interval"][data-evidence-ref-id="#{antenna_pointing_event_id}"][data-evidence-ref-link-target="operational_event"])

    view
    |> element(antenna_pointing_event_selector)
    |> render_click(%{
      "link-id" => "evidence-ref:operational_event:#{antenna_pointing_event_id}",
      "target" => "operational_event",
      "target-id" => antenna_pointing_event_id,
      "timestamp-ms" => antenna_pointing_event_at_ms,
      "realm" => "replay",
      "time-mode" => "replay_run",
      "replay-run-id" => replay_run_id,
      "data-source-id" => replay_sources.operational_data_source_id,
      "source-binding-id" => replay_sources.operational_binding_id
    })

    assert has_element?(
             view,
             ~s(#dashboard-data-link-inspector[data-data-link-target="operational_event"][data-data-link-target-id="#{antenna_pointing_event_id}"][data-data-link-status="resolved"][data-data-link-selected-replay-run-id="#{replay_run_id}"][data-data-link-selected-data-source-id="#{replay_sources.operational_data_source_id}"][data-data-link-selected-source-binding-id="#{replay_sources.operational_binding_id}"])
           )

    antenna_pointing_event_path = assert_patch(view)
    assert antenna_pointing_event_path =~ "panel=data_link"
    assert antenna_pointing_event_path =~ "selected_target=operational_event"
    assert antenna_pointing_event_path =~ "selected_id=#{antenna_pointing_event_route_id}"
    assert antenna_pointing_event_path =~ "selected_time=#{antenna_pointing_event_at_ms}"
    assert antenna_pointing_event_path =~ "replay_run_id=#{replay_run_id}"

    assert has_element?(
             view,
             ~s(#dashboard-data-link-copy-link[data-clipboard-text*="panel=data_link"][data-clipboard-text*="selected_target=operational_event"][data-clipboard-text*="selected_id=#{antenna_pointing_event_route_id}"][data-clipboard-text*="replay_run_id=#{replay_run_id}"][data-clipboard-text*="data_source_id=#{replay_sources.operational_data_source_id}"][data-clipboard-text*="source_binding_id=#{replay_sources.operational_binding_id}"])
           )

    antenna_pointing_event_copied_path =
      view
      |> render()
      |> element_attribute("#dashboard-data-link-copy-link", "data-clipboard-text")

    assert antenna_pointing_event_copied_path =~ "panel=data_link"
    assert antenna_pointing_event_copied_path =~ "selected_target=operational_event"

    assert antenna_pointing_event_copied_path =~
             "selected_id=#{antenna_pointing_event_route_id}"

    assert antenna_pointing_event_copied_path =~ "selected_time=#{antenna_pointing_event_at_ms}"
    assert antenna_pointing_event_copied_path =~ "replay_run_id=#{replay_run_id}"

    assert antenna_pointing_event_copied_path =~
             "data_source_id=#{replay_sources.operational_data_source_id}"

    assert antenna_pointing_event_copied_path =~
             "source_binding_id=#{replay_sources.operational_binding_id}"

    {:ok, reopened_antenna_pointing_event_view, _html} =
      live(conn, antenna_pointing_event_copied_path)

    assert has_element?(
             reopened_antenna_pointing_event_view,
             ~s(#dashboard-data-link-inspector[data-data-link-target="operational_event"][data-data-link-target-id="#{antenna_pointing_event_id}"][data-data-link-status="resolved"][data-data-link-selected-replay-run-id="#{replay_run_id}"][data-data-link-selected-data-source-id="#{replay_sources.operational_data_source_id}"][data-data-link-selected-source-binding-id="#{replay_sources.operational_binding_id}"])
           )

    assert has_element?(
             reopened_antenna_pointing_event_view,
             ~s(#dashboard-data-link-copy-link[data-clipboard-text*="panel=data_link"][data-clipboard-text*="selected_target=operational_event"][data-clipboard-text*="selected_id=#{antenna_pointing_event_route_id}"][data-clipboard-text*="selected_time=#{antenna_pointing_event_at_ms}"][data-clipboard-text*="replay_run_id=#{replay_run_id}"])
           )

    assert has_element?(
             reopened_antenna_pointing_event_view,
             ~s(#dashboard-data-link-inspector [data-data-link-field="Operational observable snapshot"]),
             "antenna-pointing-replay-rendered-1"
           )

    assert has_element?(
             reopened_antenna_pointing_event_view,
             ~s(#dashboard-data-link-inspector [data-data-link-field="Observable"]),
             "ground.station.antenna_pointing_state"
           )

    assert has_element?(
             reopened_antenna_pointing_event_view,
             ~s(#dashboard-data-link-inspector [data-data-link-field="Resource"]),
             "dss-14"
           )

    assert has_element?(
             reopened_antenna_pointing_event_view,
             ~s(#dashboard-data-link-inspector [data-data-link-field="Scope kind"]),
             "ground_station"
           )

    assert has_element?(
             reopened_antenna_pointing_event_view,
             ~s(#dashboard-data-link-inspector [data-data-link-field="Transport"]),
             transport.transport_id
           )

    assert has_element?(
             reopened_antenna_pointing_event_view,
             ~s(#dashboard-data-link-inspector [data-data-link-field="Source endpoint"]),
             "replay-source-health-endpoint"
           )

    assert has_element?(
             reopened_antenna_pointing_event_view,
             ~s(#dashboard-data-link-inspector [data-data-link-field="Ground station"]),
             "dss-14"
           )

    assert has_element?(
             reopened_antenna_pointing_event_view,
             ~s(#dashboard-data-link-inspector [data-data-link-field="State"]),
             "tracking"
           )

    assert has_element?(
             reopened_antenna_pointing_event_view,
             ~s(#dashboard-data-link-inspector [data-data-link-field="Replay run"]),
             replay_run_id
           )

    assert has_element?(
             view,
             ~s(#dashboard-data-link-inspector [data-data-link-field="Operational observable snapshot"]),
             "antenna-pointing-replay-rendered-1"
           )

    stop_dashboard_view(reopened_antenna_pointing_event_view)
    stop_dashboard_view(view)
  end
end
