defmodule CadenceWeb.OpsDashboardShowLive.OperationalObservableRenderingLiveTest do
  use CadenceWeb.ConnCase, async: false

  import Phoenix.LiveViewTest

  alias Phoenix.LiveViewTest.ClientProxy

  use Phoenix.VerifiedRoutes,
    endpoint: CadenceWeb.Endpoint,
    router: CadenceWeb.Router,
    statics: CadenceWeb.static_paths()

  alias Cadence.Comms.{GroundStation, Transport}
  alias Cadence.Contacts.{Path, ScheduledContact}
  alias Cadence.Dashboards.{Document, RenderItem}
  alias Cadence.OperationalEvents
  alias Cadence.OperationalEvents.Event
  alias Cadence.SourceEndpoints.SourceEndpoint
  alias CadenceWeb.TestFixtures

  defp signed_in_user_org_and_mission do
    user = TestFixtures.persist_user!()
    org = TestFixtures.persist_org!()
    _membership = TestFixtures.grant_membership!(user, org)
    mission = TestFixtures.persist_mission!(org, slug: "ops", display_name: "Ops Mission")
    {TestFixtures.member_conn(user), user, org, mission}
  end

  defp signed_in_org_and_mission do
    {conn, _user, org, mission} = signed_in_user_org_and_mission()
    {conn, org, mission}
  end

  defp contact_paths(source_endpoint_ref) do
    [
      Path.new(%{
        path_id: "dashboard-uplink-path",
        direction: :uplink,
        selection_role: :selected,
        source_endpoint_ref: source_endpoint_ref
      }),
      Path.new(%{
        path_id: "dashboard-downlink-path",
        direction: :downlink,
        selection_role: :selected,
        source_endpoint_ref: source_endpoint_ref
      })
    ]
  end

  defp show_path(mission, dashboard) do
    ~p"/missions/#{mission.mission_id}/ops/dashboards/#{dashboard.dashboard_id}"
  end

  defp fetch_dashboard_document!(org, mission, dashboard) do
    assert {:ok, document} =
             Cadence.Dashboards.fetch_document(
               org.organization_id,
               mission.mission_id,
               dashboard.dashboard_id
             )

    document
  end

  defp render_item_by_title(%Document{} = document, title) do
    document
    |> RenderItem.from_document()
    |> Enum.find(&(&1.widget.title == title))
  end

  defp render_dashboard_async(view) do
    track_dashboard_view(view)
    render_async(view, 5_000)
  end

  defp track_dashboard_view(%{pid: pid} = view) when is_pid(pid) do
    tracked_views = Process.get(:ops_dashboard_live_test_views, MapSet.new())

    unless MapSet.member?(tracked_views, pid) do
      Process.put(:ops_dashboard_live_test_views, MapSet.put(tracked_views, pid))

      on_exit({:ops_dashboard_live_view, pid}, fn ->
        stop_dashboard_view(view)
      end)
    end
  end

  defp stop_dashboard_view(view) do
    if Process.alive?(view.pid) do
      drain_dashboard_view(view)

      ref = Process.monitor(view.pid)
      {_proxy_ref, _topic, proxy_pid} = view.proxy
      ClientProxy.stop(proxy_pid, {:shutdown, :dashboard_test_cleanup})

      assert_receive {:DOWN, ^ref, :process, _pid, _reason}, 1_000
    end

    :ok
  end

  defp drain_dashboard_view(view) do
    render_async(view, 5_000)
    :ok
  catch
    :exit, _reason -> :ok
  end

  defp enable_dashboard_engine_inline_resolves! do
    previous_inline? = Application.get_env(:cadence_web, :dashboard_engine_resolve_inline?)
    Application.put_env(:cadence_web, :dashboard_engine_resolve_inline?, true)

    on_exit(fn ->
      case previous_inline? do
        nil ->
          Application.delete_env(:cadence_web, :dashboard_engine_resolve_inline?)

        value ->
          Application.put_env(:cadence_web, :dashboard_engine_resolve_inline?, value)
      end
    end)
  end

  describe "operational observable rendering" do
    test "renders contact phase operational observable rows with phase presentation" do
      enable_dashboard_engine_inline_resolves!()

      {conn, org, mission} = signed_in_org_and_mission()

      scheduled_contact =
        ScheduledContact.new(%{
          scheduled_contact_id: "dashboard-contact-phase-alpha",
          mission_id: mission.mission_id,
          source_endpoint_refs: ["source-endpoint-alpha"],
          paths: contact_paths("source-endpoint-alpha"),
          starts_at: DateTime.from_unix!(1_700_000_080, :second),
          ends_at: DateTime.from_unix!(1_700_000_220, :second)
        })

      assert {:ok, _scheduled_contact} =
               Cadence.persist_scheduled_contact(org.organization_id, scheduled_contact)

      dashboard =
        TestFixtures.persist_dashboard_document!(mission,
          name: "Contact Phase",
          widgets: [
            %{
              type: :status_matrix,
              title: "Contact Phase",
              binding: %{
                source: :operational_observables,
                observables: ["contacts.phase"]
              }
            }
          ]
        )

      document = fetch_dashboard_document!(org, mission, dashboard)
      matrix_widget = render_item_by_title(document, "Contact Phase").widget

      {:ok, view, _html} = live(conn, show_path(mission, dashboard))
      render_dashboard_async(view)

      row_selector =
        ~s(#widget-#{matrix_widget.widget_id} [data-status-matrix-row="contacts.phase:dashboard-contact-phase-alpha"])

      assert has_element?(
               view,
               row_selector <>
                 ~s([data-status-matrix-source="operational_observables"][data-status-matrix-status-policy="contact_phase"][data-status-matrix-contact-kind="scheduled"][data-status-matrix-phase="scheduled"])
             )

      assert has_element?(
               view,
               row_selector <> ~s( [data-status-matrix-field="value"]),
               "Scheduled"
             )

      assert has_element?(
               view,
               row_selector <> ~s( [data-status-matrix-field="quality"]),
               "Scheduled"
             )

      assert has_element?(
               view,
               row_selector <> ~s( [data-status-matrix-field="limit"]),
               "Scheduled"
             )

      assert has_element?(
               view,
               row_selector <> ~s( [data-status-matrix-field="time"]),
               scheduled_contact.scheduled_contact_id
             )

      assert has_element?(
               view,
               row_selector <>
                 ~s( [data-status-matrix-row-link-target="contact"][data-status-matrix-row-link-id="#{scheduled_contact.scheduled_contact_id}"])
             )

      stop_dashboard_view(view)
    end

    test "renders connection state operational observable rows with connection presentation" do
      enable_dashboard_engine_inline_resolves!()

      {conn, org, mission} = signed_in_org_and_mission()

      source_endpoint =
        SourceEndpoint.new(%{
          source_endpoint_id: "dashboard-source-endpoint-alpha",
          mission_id: mission.mission_id,
          display_name: "Goldstone DSS-14",
          metadata: %{"ground_station_id" => "dss-14"}
        })

      assert {:ok, _source_endpoint} =
               Cadence.persist_source_endpoint(org.organization_id, source_endpoint)

      transport =
        Transport.new(%{
          transport_id: "dashboard-transport-alpha",
          mission_id: mission.mission_id,
          display_name: "Lab TCP",
          transport_kind: :tcp_socket,
          direction_capability: :bidirectional,
          adapter_key: :tcp_socket,
          configuration: %{
            "mode" => "connect",
            "direction_capability" => "bidirectional",
            "host" => "ground.example",
            "port" => "5000",
            "framing_mode" => "raw",
            "tls_enabled" => "false"
          },
          metadata: %{
            "source_endpoint_id" => source_endpoint.source_endpoint_id,
            "ground_station_id" => "dss-14"
          }
        })

      assert {:ok, _transport} = Cadence.persist_transport(org.organization_id, transport)

      observed_at = ~U[2026-06-17 12:03:00Z]

      assert {:ok, _connection_event} =
               Event.from_operational_observable_state_snapshot(%{
                 snapshot_id: "dashboard-connection-state-live-alpha",
                 organization_id: org.organization_id,
                 mission_id: mission.mission_id,
                 observable_id: "comms.transport.connection_state",
                 resource_id: transport.transport_id,
                 scope_kind: :transport,
                 transport_id: transport.transport_id,
                 source_endpoint_id: source_endpoint.source_endpoint_id,
                 ground_station_id: "dss-14",
                 adapter_key: :tcp_socket,
                 connection_state: :connected,
                 state: :connected,
                 observed_at: observed_at
               })
               |> OperationalEvents.persist_event()

      [connection_interval] =
        Cadence.operational_connection_state_intervals(org.organization_id, mission.mission_id,
          observable_id: "comms.transport.connection_state",
          resource_id: transport.transport_id
        )

      dashboard =
        TestFixtures.persist_dashboard_document!(mission,
          name: "Connection State",
          widgets: [
            %{
              type: :status_matrix,
              title: "Connection State",
              binding: %{
                source: :operational_observables,
                observables: ["comms.transport.connection_state"]
              }
            }
          ]
        )

      document = fetch_dashboard_document!(org, mission, dashboard)
      matrix_widget = render_item_by_title(document, "Connection State").widget

      {:ok, view, _html} = live(conn, show_path(mission, dashboard))
      render_dashboard_async(view)

      row_selector =
        ~s(#widget-#{matrix_widget.widget_id} [data-status-matrix-row="comms.transport.connection_state:dashboard-transport-alpha"])

      assert has_element?(
               view,
               row_selector <>
                 ~s([data-status-matrix-source="operational_observables"][data-status-matrix-status-policy="connection_state"][data-status-matrix-resource-id="dashboard-transport-alpha"][data-status-matrix-transport-id="dashboard-transport-alpha"][data-status-matrix-source-endpoint-id="dashboard-source-endpoint-alpha"][data-status-matrix-ground-station-id="dss-14"][data-status-matrix-connection-state="connected"])
             )

      assert has_element?(
               view,
               row_selector <>
                 ~s([data-status-matrix-frame-observable-id="comms.transport.connection_state"][data-status-matrix-product-family="connection_state"][data-status-matrix-supported-capability="connection_state"][data-status-matrix-data-source-id="managed_operational_observables"])
             )

      assert has_element?(
               view,
               row_selector <>
                 ~s( [data-status-matrix-row-evidence="comms.transport.connection_state:dashboard-transport-alpha"][data-status-matrix-row-evidence-observable="comms.transport.connection_state"])
             )

      assert has_element?(
               view,
               row_selector <>
                 ~s( [data-status-matrix-row-link="comms.transport.connection_state:dashboard-transport-alpha"][data-status-matrix-row-link-target="transport"][data-status-matrix-row-link-id="dashboard-transport-alpha"][phx-value-target="transport"][phx-value-target-id="dashboard-transport-alpha"][phx-value-data-source-id="managed_operational_observables"][phx-value-source-binding-id="default_flight_operational_observables"])
             )

      view
      |> element(row_selector <> ~s( [data-status-matrix-row-evidence]))
      |> render_click()

      evidence_path = assert_patch(view)
      assert evidence_path =~ "panel=evidence"
      assert evidence_path =~ "selected_evidence_kind=frame"
      assert evidence_path =~ "selected_observable=comms.transport.connection_state"
      assert evidence_path =~ "selected_data_source=managed_operational_observables"
      assert evidence_path =~ "selected_source_binding=default_flight_operational_observables"

      assert has_element?(
               view,
               ~s(#dashboard-evidence-inspector[data-evidence-kind="frame"][data-evidence-status="resolved"])
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
               ~s(#dashboard-evidence-copy-link[data-clipboard-text*="panel=evidence"][data-clipboard-text*="selected_evidence_kind=frame"][data-clipboard-text*="selected_observable=comms.transport.connection_state"][data-clipboard-text*="selected_data_source=managed_operational_observables"][data-clipboard-text*="selected_source_binding=default_flight_operational_observables"])
             )

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
        "realm" => "flight",
        "time-mode" => "live",
        "data-source-id" => "managed_operational_observables",
        "source-binding-id" => "default_flight_operational_observables"
      })

      assert has_element?(
               view,
               ~s(#dashboard-data-link-inspector[data-data-link-target="operational_event"][data-data-link-target-id="#{connection_operational_event_id}"][data-data-link-status="resolved"][data-data-link-selected-data-source-id="managed_operational_observables"][data-data-link-selected-source-binding-id="default_flight_operational_observables"])
             )

      connection_event_path = assert_patch(view)
      assert connection_event_path =~ "panel=data_link"
      assert connection_event_path =~ "selected_target=operational_event"
      assert connection_event_path =~ "selected_id=#{connection_operational_event_route_id}"
      assert connection_event_path =~ "selected_time=#{connection_event_at_ms}"
      assert connection_event_path =~ "time_mode=live"

      assert has_element?(
               view,
               ~s(#dashboard-data-link-copy-link[data-clipboard-text*="panel=data_link"][data-clipboard-text*="selected_target=operational_event"][data-clipboard-text*="selected_id=#{connection_operational_event_route_id}"][data-clipboard-text*="data_source_id=managed_operational_observables"][data-clipboard-text*="source_binding_id=default_flight_operational_observables"])
             )

      connection_event_copied_path =
        view
        |> render()
        |> LazyHTML.from_fragment()
        |> LazyHTML.query("#dashboard-data-link-copy-link")
        |> LazyHTML.attribute("data-clipboard-text")
        |> List.first()

      assert connection_event_copied_path =~ "panel=data_link"
      assert connection_event_copied_path =~ "selected_target=operational_event"

      assert connection_event_copied_path =~
               "selected_id=#{connection_operational_event_route_id}"

      assert connection_event_copied_path =~ "selected_time=#{connection_event_at_ms}"
      assert connection_event_copied_path =~ "data_source_id=managed_operational_observables"

      assert connection_event_copied_path =~
               "source_binding_id=default_flight_operational_observables"

      {:ok, reopened_connection_event_view, _html} = live(conn, connection_event_copied_path)

      assert has_element?(
               reopened_connection_event_view,
               ~s(#dashboard-data-link-inspector[data-data-link-target="operational_event"][data-data-link-target-id="#{connection_operational_event_id}"][data-data-link-status="resolved"][data-data-link-selected-data-source-id="managed_operational_observables"][data-data-link-selected-source-binding-id="default_flight_operational_observables"])
             )

      assert has_element?(
               reopened_connection_event_view,
               ~s(#dashboard-data-link-copy-link[data-clipboard-text*="panel=data_link"][data-clipboard-text*="selected_target=operational_event"][data-clipboard-text*="selected_id=#{connection_operational_event_route_id}"][data-clipboard-text*="selected_time=#{connection_event_at_ms}"])
             )

      assert has_element?(
               reopened_connection_event_view,
               ~s(#dashboard-data-link-inspector [data-data-link-field="Connection state snapshot"]),
               "dashboard-connection-state-live-alpha"
             )

      assert has_element?(
               reopened_connection_event_view,
               ~s(#dashboard-data-link-inspector [data-data-link-field="Connection state"]),
               "connected"
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
               source_endpoint.source_endpoint_id
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
               "connected"
             )

      assert has_element?(
               view,
               row_selector <> ~s( [data-status-matrix-field="value"]),
               "Connected"
             )

      assert has_element?(
               view,
               row_selector <> ~s( [data-status-matrix-field="quality"]),
               "Tcp socket"
             )

      assert has_element?(
               view,
               row_selector <> ~s( [data-status-matrix-field="limit"]),
               "Connected"
             )

      assert has_element?(
               view,
               row_selector <> ~s( [data-status-matrix-field="time"]),
               "dashboard-transport-alpha"
             )

      transport_link_path =
        show_path(mission, dashboard) <>
          "?panel=data_link&selected_target=transport&selected_id=dashboard-transport-alpha&selected_transport_id=dashboard-transport-alpha&realm=flight&data_source_id=managed_operational_observables&source_binding_id=default_flight_operational_observables"

      {:ok, transport_link_view, _html} = live(conn, transport_link_path)
      render_dashboard_async(transport_link_view)

      assert has_element?(
               transport_link_view,
               ~s(#dashboard-data-link-inspector[data-data-link-target="transport"][data-data-link-status="resolved"])
             )

      assert has_element?(
               transport_link_view,
               ~s(#dashboard-data-link-inspector [data-data-link-context="Data source"]),
               "managed_operational_observables"
             )

      assert has_element?(
               transport_link_view,
               ~s(#dashboard-data-link-inspector [data-data-link-context="Source binding"]),
               "default_flight_operational_observables"
             )

      assert has_element?(
               transport_link_view,
               ~s(#dashboard-data-link-copy-link[data-clipboard-text*="panel=data_link"][data-clipboard-text*="selected_target=transport"][data-clipboard-text*="selected_id=dashboard-transport-alpha"][data-clipboard-text*="data_source_id=managed_operational_observables"][data-clipboard-text*="source_binding_id=default_flight_operational_observables"])
             )

      stop_dashboard_view(view)
      stop_dashboard_view(transport_link_view)
      stop_dashboard_view(reopened_connection_event_view)
    end

    test "opens live antenna-pointing operational-event copied route from rendered frame panel" do
      enable_dashboard_engine_inline_resolves!()

      {conn, org, mission} = signed_in_org_and_mission()

      ground_station =
        GroundStation.new(%{
          ground_station_id: "dss-14",
          mission_id: mission.mission_id,
          display_name: "Goldstone DSS-14",
          provider: "DSN",
          region: "California",
          metadata: %{
            "source_endpoint_id" => "dashboard-antenna-source-endpoint",
            "transport_id" => "dashboard-antenna-transport"
          }
        })

      assert {:ok, _ground_station} =
               Cadence.persist_ground_station(org.organization_id, ground_station)

      source_endpoint =
        SourceEndpoint.new(%{
          source_endpoint_id: "dashboard-antenna-source-endpoint",
          mission_id: mission.mission_id,
          display_name: "Goldstone DSS-14",
          metadata: %{
            "ground_station_id" => "dss-14",
            "antenna_id" => "dss-14"
          }
        })

      assert {:ok, _source_endpoint} =
               Cadence.persist_source_endpoint(org.organization_id, source_endpoint)

      transport =
        Transport.new(%{
          transport_id: "dashboard-antenna-transport",
          mission_id: mission.mission_id,
          display_name: "Antenna TCP",
          transport_kind: :tcp_socket,
          direction_capability: :bidirectional,
          adapter_key: :tcp_socket,
          configuration: %{
            "mode" => "connect",
            "direction_capability" => "bidirectional",
            "host" => "antenna.ground.example",
            "port" => "5002",
            "framing_mode" => "raw",
            "tls_enabled" => "false"
          },
          metadata: %{
            "source_endpoint_id" => source_endpoint.source_endpoint_id,
            "ground_station_id" => "dss-14",
            "antenna_id" => "dss-14"
          }
        })

      assert {:ok, _transport} = Cadence.persist_transport(org.organization_id, transport)

      observed_at = ~U[2026-06-17 12:04:00Z]

      assert {:ok, _antenna_pointing_event} =
               Event.from_operational_observable_state_snapshot(%{
                 snapshot_id: "dashboard-antenna-pointing-live-dss-14",
                 organization_id: org.organization_id,
                 mission_id: mission.mission_id,
                 observable_id: "ground.station.antenna_pointing_state",
                 resource_id: "dss-14",
                 scope_kind: :ground_station,
                 transport_id: transport.transport_id,
                 source_endpoint_id: source_endpoint.source_endpoint_id,
                 ground_station_id: "dss-14",
                 antenna_pointing_state: :tracking,
                 state: :tracking,
                 observed_at: observed_at
               })
               |> OperationalEvents.persist_event()

      [antenna_pointing_interval] =
        Cadence.operational_observable_state_intervals(org.organization_id, mission.mission_id,
          observable_id: "ground.station.antenna_pointing_state",
          resource_id: "dss-14"
        )

      dashboard =
        TestFixtures.persist_dashboard_document!(mission,
          name: "Antenna Pointing State",
          widgets: [
            %{
              type: :status_matrix,
              title: "Antenna Pointing",
              binding: %{
                source: :operational_observables,
                observables: ["ground.station.antenna_pointing_state"]
              }
            }
          ]
        )

      document = fetch_dashboard_document!(org, mission, dashboard)
      matrix_widget = render_item_by_title(document, "Antenna Pointing").widget

      {:ok, view, _html} =
        live(conn, show_path(mission, dashboard) <> "?scope_kind=ground_station&scope_id=dss-14")

      render_dashboard_async(view)

      assert has_element?(
               view,
               ~s(#ops-dashboard-show-page[data-dashboard-scope-kind="ground_station"][data-dashboard-scope-id="dss-14"])
             )

      row_selector =
        ~s(#widget-#{matrix_widget.widget_id} [data-status-matrix-row="ground.station.antenna_pointing_state:dss-14"])

      assert has_element?(
               view,
               row_selector <>
                 ~s([data-status-matrix-source="operational_observables"][data-status-matrix-status-policy="antenna_pointing_state"][data-status-matrix-resource-id="dss-14"][data-status-matrix-scope-kind="ground_station"][data-status-matrix-ground-station-id="dss-14"][data-status-matrix-transport-id="#{transport.transport_id}"][data-status-matrix-source-endpoint-id="#{source_endpoint.source_endpoint_id}"])
             )

      assert has_element?(
               view,
               row_selector <>
                 ~s([data-status-matrix-frame-observable-id="ground.station.antenna_pointing_state"][data-status-matrix-product-family="ground_station"][data-status-matrix-supported-capability="ground_station_antenna_pointing_state"][data-status-matrix-data-source-id="managed_operational_observables"][data-status-matrix-source-binding-id="default_flight_operational_observables"])
             )

      view
      |> element(row_selector <> ~s( [data-status-matrix-row-evidence]))
      |> render_click()

      evidence_path = assert_patch(view)
      assert evidence_path =~ "panel=evidence"
      assert evidence_path =~ "selected_evidence_kind=frame"

      assert evidence_path =~
               "selected_observable=#{URI.encode_www_form("ground.station.antenna_pointing_state")}"

      assert evidence_path =~ "selected_data_source=managed_operational_observables"
      assert evidence_path =~ "selected_source_binding=default_flight_operational_observables"
      assert evidence_path =~ "scope_kind=ground_station"
      assert evidence_path =~ "scope_id=dss-14"

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
               ~s(#dashboard-evidence-copy-link[data-clipboard-text*="panel=evidence"][data-clipboard-text*="selected_evidence_kind=frame"][data-clipboard-text*="selected_observable=#{URI.encode_www_form("ground.station.antenna_pointing_state")}"][data-clipboard-text*="selected_data_source=managed_operational_observables"][data-clipboard-text*="selected_source_binding=default_flight_operational_observables"][data-clipboard-text*="scope_kind=ground_station"][data-clipboard-text*="scope_id=dss-14"])
             )

      antenna_pointing_event_id = antenna_pointing_interval.source_event_id

      antenna_pointing_event_route_id =
        URI.encode_www_form(antenna_pointing_event_id)

      antenna_pointing_event_at_ms = DateTime.to_unix(observed_at, :millisecond)

      antenna_pointing_event_selector =
        ~s(#dashboard-evidence-inspector [data-evidence-ref-kind="operational interval"][data-evidence-ref-id="#{antenna_pointing_event_id}"][data-evidence-ref-link-target="operational_event"])

      antenna_pointing_event_evidence =
        view
        |> render()
        |> LazyHTML.from_fragment()
        |> LazyHTML.query(antenna_pointing_event_selector)

      assert ["operational_event"] =
               LazyHTML.attribute(antenna_pointing_event_evidence, "phx-value-target")

      assert [^antenna_pointing_event_id] =
               LazyHTML.attribute(antenna_pointing_event_evidence, "phx-value-target-id")

      assert ["evidence-ref:operational_event:" <> _] =
               LazyHTML.attribute(antenna_pointing_event_evidence, "phx-value-link-id")

      view
      |> element(antenna_pointing_event_selector)
      |> render_click(%{
        "link-id" => "evidence-ref:operational_event:#{antenna_pointing_event_id}",
        "target" => "operational_event",
        "target-id" => antenna_pointing_event_id,
        "timestamp-ms" => antenna_pointing_event_at_ms,
        "realm" => "flight",
        "time-mode" => "live",
        "data-source-id" => "managed_operational_observables",
        "source-binding-id" => "default_flight_operational_observables"
      })

      assert has_element?(
               view,
               ~s(#dashboard-data-link-inspector[data-data-link-target="operational_event"][data-data-link-target-id="#{antenna_pointing_event_id}"][data-data-link-status="resolved"][data-data-link-selected-data-source-id="managed_operational_observables"][data-data-link-selected-source-binding-id="default_flight_operational_observables"])
             )

      antenna_pointing_event_path = assert_patch(view)
      assert antenna_pointing_event_path =~ "panel=data_link"
      assert antenna_pointing_event_path =~ "selected_target=operational_event"
      assert antenna_pointing_event_path =~ "selected_id=#{antenna_pointing_event_route_id}"
      assert antenna_pointing_event_path =~ "selected_time=#{antenna_pointing_event_at_ms}"
      assert antenna_pointing_event_path =~ "time_mode=live"
      assert antenna_pointing_event_path =~ "scope_kind=ground_station"
      assert antenna_pointing_event_path =~ "scope_id=dss-14"

      assert has_element?(
               view,
               ~s(#dashboard-data-link-copy-link[data-clipboard-text*="panel=data_link"][data-clipboard-text*="selected_target=operational_event"][data-clipboard-text*="selected_id=#{antenna_pointing_event_route_id}"][data-clipboard-text*="data_source_id=managed_operational_observables"][data-clipboard-text*="source_binding_id=default_flight_operational_observables"][data-clipboard-text*="scope_kind=ground_station"][data-clipboard-text*="scope_id=dss-14"])
             )

      antenna_pointing_event_copied_path =
        view
        |> render()
        |> LazyHTML.from_fragment()
        |> LazyHTML.query("#dashboard-data-link-copy-link")
        |> LazyHTML.attribute("data-clipboard-text")
        |> List.first()

      assert antenna_pointing_event_copied_path =~ "panel=data_link"
      assert antenna_pointing_event_copied_path =~ "selected_target=operational_event"

      assert antenna_pointing_event_copied_path =~
               "selected_id=#{antenna_pointing_event_route_id}"

      assert antenna_pointing_event_copied_path =~ "selected_time=#{antenna_pointing_event_at_ms}"

      assert antenna_pointing_event_copied_path =~
               "data_source_id=managed_operational_observables"

      assert antenna_pointing_event_copied_path =~
               "source_binding_id=default_flight_operational_observables"

      assert antenna_pointing_event_copied_path =~ "scope_kind=ground_station"
      assert antenna_pointing_event_copied_path =~ "scope_id=dss-14"

      {:ok, reopened_antenna_pointing_event_view, _html} =
        live(conn, antenna_pointing_event_copied_path)

      assert has_element?(
               reopened_antenna_pointing_event_view,
               ~s(#dashboard-data-link-inspector[data-data-link-target="operational_event"][data-data-link-target-id="#{antenna_pointing_event_id}"][data-data-link-status="resolved"][data-data-link-selected-data-source-id="managed_operational_observables"][data-data-link-selected-source-binding-id="default_flight_operational_observables"])
             )

      assert has_element?(
               reopened_antenna_pointing_event_view,
               ~s(#dashboard-data-link-copy-link[data-clipboard-text*="panel=data_link"][data-clipboard-text*="selected_target=operational_event"][data-clipboard-text*="selected_id=#{antenna_pointing_event_route_id}"][data-clipboard-text*="selected_time=#{antenna_pointing_event_at_ms}"])
             )

      assert has_element?(
               reopened_antenna_pointing_event_view,
               ~s(#dashboard-data-link-inspector [data-data-link-field="Operational observable snapshot"]),
               "dashboard-antenna-pointing-live-dss-14"
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
               source_endpoint.source_endpoint_id
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

      stop_dashboard_view(view)
      stop_dashboard_view(reopened_antenna_pointing_event_view)
    end
  end
end
