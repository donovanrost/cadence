defmodule CadenceWeb.OpsDashboardShowLive.OperationalObservableGroundStationScopeLiveTest do
  use CadenceWeb.ConnCase, async: false

  @moduletag :config

  import Phoenix.LiveViewTest

  alias Cadence.Comms.{GroundStationStore, TransportStore}

  alias Phoenix.LiveViewTest.ClientProxy

  use Phoenix.VerifiedRoutes,
    endpoint: CadenceWeb.Endpoint,
    router: CadenceWeb.Router,
    statics: CadenceWeb.static_paths()

  alias Cadence.Comms.{GroundStation, Transport}
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

  defp persist_ground_station_scope_fixture(org, mission) do
    dss_14 =
      GroundStation.new(%{
        ground_station_id: "dss-14",
        mission_id: mission.mission_id,
        display_name: "Goldstone DSS-14",
        provider: "DSN",
        region: "California",
        metadata: %{
          "source_endpoint_id" => "dashboard-source-endpoint-alpha",
          "transport_id" => "dashboard-transport-alpha"
        }
      })

    dss_63 =
      GroundStation.new(%{
        ground_station_id: "dss-63",
        mission_id: mission.mission_id,
        display_name: "Madrid DSS-63",
        provider: "DSN",
        region: "Madrid",
        metadata: %{
          "source_endpoint_id" => "dashboard-source-endpoint-beta",
          "transport_id" => "dashboard-transport-beta"
        }
      })

    assert {:ok, _ground_station} =
             GroundStationStore.persist_ground_station(org.organization_id, dss_14)

    assert {:ok, _ground_station} =
             GroundStationStore.persist_ground_station(org.organization_id, dss_63)

    alpha_endpoint =
      SourceEndpoint.new(%{
        source_endpoint_id: "dashboard-source-endpoint-alpha",
        mission_id: mission.mission_id,
        display_name: "Goldstone DSS-14",
        metadata: %{"ground_station_id" => dss_14.ground_station_id}
      })

    beta_endpoint =
      SourceEndpoint.new(%{
        source_endpoint_id: "dashboard-source-endpoint-beta",
        mission_id: mission.mission_id,
        display_name: "Madrid DSS-63",
        metadata: %{"ground_station_id" => dss_63.ground_station_id}
      })

    assert {:ok, _source_endpoint} =
             Cadence.SourceEndpoints.persist_source_endpoint(org.organization_id, alpha_endpoint)

    assert {:ok, _source_endpoint} =
             Cadence.SourceEndpoints.persist_source_endpoint(org.organization_id, beta_endpoint)

    alpha_transport =
      Transport.new(%{
        transport_id: "dashboard-transport-alpha",
        mission_id: mission.mission_id,
        display_name: "Alpha TCP",
        transport_kind: :tcp_socket,
        direction_capability: :bidirectional,
        adapter_key: :tcp_socket,
        configuration: %{
          "mode" => "connect",
          "direction_capability" => "bidirectional",
          "host" => "alpha.ground.example",
          "port" => "5000",
          "framing_mode" => "raw",
          "tls_enabled" => "false"
        },
        metadata: %{
          "source_endpoint_id" => alpha_endpoint.source_endpoint_id,
          "ground_station_id" => dss_14.ground_station_id
        }
      })

    beta_transport =
      Transport.new(%{
        transport_id: "dashboard-transport-beta",
        mission_id: mission.mission_id,
        display_name: "Beta TCP",
        transport_kind: :tcp_socket,
        direction_capability: :bidirectional,
        adapter_key: :tcp_socket,
        configuration: %{
          "mode" => "connect",
          "direction_capability" => "bidirectional",
          "host" => "beta.ground.example",
          "port" => "5001",
          "framing_mode" => "raw",
          "tls_enabled" => "false"
        },
        metadata: %{
          "source_endpoint_id" => beta_endpoint.source_endpoint_id,
          "ground_station_id" => dss_63.ground_station_id
        }
      })

    assert {:ok, _transport} =
             TransportStore.persist_transport(org.organization_id, alpha_transport)

    assert {:ok, _transport} =
             TransportStore.persist_transport(org.organization_id, beta_transport)

    observed_at = ~U[2026-06-17 12:05:00Z]

    assert {:ok, _connection_event} =
             Event.from_operational_observable_state_snapshot(%{
               snapshot_id: "dashboard-ground-station-connection-live-dss-14",
               organization_id: org.organization_id,
               mission_id: mission.mission_id,
               observable_id: "ground.station.connection_state",
               resource_id: dss_14.ground_station_id,
               scope_kind: :ground_station,
               transport_id: alpha_transport.transport_id,
               source_endpoint_id: alpha_endpoint.source_endpoint_id,
               ground_station_id: dss_14.ground_station_id,
               adapter_key: :tcp_socket,
               connection_state: :connected,
               state: :connected,
               observed_at: observed_at
             })
             |> OperationalEvents.persist_event()

    [ground_station_interval] =
      Cadence.OperationalEvents.connection_state_intervals(
        org.organization_id,
        mission.mission_id,
        observable_id: "ground.station.connection_state",
        resource_id: dss_14.ground_station_id
      )

    dashboard =
      TestFixtures.persist_dashboard_document!(mission,
        name: "Ground Station Connection State",
        widgets: [
          %{
            type: :status_matrix,
            title: "Connection State",
            binding: %{
              source: :operational_observables,
              observables: [
                "comms.transport.connection_state",
                "ground.station.connection_state"
              ]
            }
          }
        ]
      )

    document = fetch_dashboard_document!(org, mission, dashboard)
    matrix_widget = render_item_by_title(document, "Connection State").widget

    %{
      alpha_endpoint: alpha_endpoint,
      alpha_transport: alpha_transport,
      dashboard: dashboard,
      dss_14: dss_14,
      ground_station_interval: ground_station_interval,
      matrix_widget: matrix_widget,
      observed_at: observed_at
    }
  end

  describe "ground station operational observable scope rendering" do
    test "filters operational observable rows and resolves setup DataLink" do
      enable_dashboard_engine_inline_resolves!()

      {conn, org, mission} = signed_in_org_and_mission()

      %{
        alpha_endpoint: alpha_endpoint,
        alpha_transport: alpha_transport,
        dashboard: dashboard,
        dss_14: dss_14,
        ground_station_interval: ground_station_interval,
        matrix_widget: matrix_widget,
        observed_at: observed_at
      } = persist_ground_station_scope_fixture(org, mission)

      {:ok, view, _html} =
        live(
          conn,
          show_path(mission, dashboard) <>
            "?scope_kind=ground_station&scope_id=#{dss_14.ground_station_id}"
        )

      render_dashboard_async(view)

      assert has_element?(
               view,
               ~s(#ops-dashboard-show-page[data-dashboard-scope-kind="ground_station"][data-dashboard-scope-id="#{dss_14.ground_station_id}"])
             )

      ground_station_row_selector =
        ~s(#widget-#{matrix_widget.widget_id} [data-status-matrix-row="ground.station.connection_state:dss-14"])

      alpha_transport_row_selector =
        ~s(#widget-#{matrix_widget.widget_id} [data-status-matrix-row="comms.transport.connection_state:dashboard-transport-alpha"])

      beta_transport_row_selector =
        ~s(#widget-#{matrix_widget.widget_id} [data-status-matrix-row="comms.transport.connection_state:dashboard-transport-beta"])

      beta_ground_station_row_selector =
        ~s(#widget-#{matrix_widget.widget_id} [data-status-matrix-row="ground.station.connection_state:dss-63"])

      assert has_element?(
               view,
               ground_station_row_selector <>
                 ~s([data-status-matrix-source="operational_observables"][data-status-matrix-status-policy="connection_state"][data-status-matrix-resource-id="dss-14"][data-status-matrix-scope-kind="ground_station"][data-status-matrix-source-endpoint-id="#{alpha_endpoint.source_endpoint_id}"][data-status-matrix-ground-station-id="dss-14"])
             )

      view
      |> element(ground_station_row_selector <> ~s( [data-status-matrix-row-evidence]))
      |> render_click()

      evidence_path = assert_patch(view)
      assert evidence_path =~ "panel=evidence"
      assert evidence_path =~ "selected_evidence_kind=frame"
      assert evidence_path =~ "selected_observable=ground.station.connection_state"
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
               ~s(#dashboard-evidence-inspector [data-evidence-ref-kind="ground station connection state interval"][data-evidence-ref-id="#{ground_station_interval.interval_id}"])
             )

      assert has_element?(
               view,
               ~s(#dashboard-evidence-inspector [data-evidence-ref-kind="operational interval"][data-evidence-ref-id="#{ground_station_interval.source_event_id}"][data-evidence-ref-link-target="operational_event"])
             )

      assert has_element?(
               view,
               ~s(#dashboard-evidence-copy-link[data-clipboard-text*="panel=evidence"][data-clipboard-text*="selected_evidence_kind=frame"][data-clipboard-text*="selected_observable=ground.station.connection_state"][data-clipboard-text*="selected_data_source=managed_operational_observables"][data-clipboard-text*="selected_source_binding=default_flight_operational_observables"][data-clipboard-text*="scope_kind=ground_station"][data-clipboard-text*="scope_id=dss-14"])
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
               LazyHTML.attribute(
                 ground_station_operational_event_evidence,
                 "phx-value-target-id"
               )

      assert ["evidence-ref:operational_event:" <> _] =
               LazyHTML.attribute(ground_station_operational_event_evidence, "phx-value-link-id")

      view
      |> element(ground_station_event_selector)
      |> render_click(%{
        "link-id" => "evidence-ref:operational_event:#{ground_station_operational_event_id}",
        "target" => "operational_event",
        "target-id" => ground_station_operational_event_id,
        "timestamp-ms" => ground_station_event_at_ms,
        "realm" => "flight",
        "time-mode" => "live",
        "data-source-id" => "managed_operational_observables",
        "source-binding-id" => "default_flight_operational_observables"
      })

      assert has_element?(
               view,
               ~s(#dashboard-data-link-inspector[data-data-link-target="operational_event"][data-data-link-target-id="#{ground_station_operational_event_id}"][data-data-link-status="resolved"][data-data-link-selected-data-source-id="managed_operational_observables"][data-data-link-selected-source-binding-id="default_flight_operational_observables"])
             )

      ground_station_event_path = assert_patch(view)
      assert ground_station_event_path =~ "panel=data_link"
      assert ground_station_event_path =~ "selected_target=operational_event"

      assert ground_station_event_path =~
               "selected_id=#{ground_station_operational_event_route_id}"

      assert ground_station_event_path =~ "selected_time=#{ground_station_event_at_ms}"
      assert ground_station_event_path =~ "time_mode=live"
      assert ground_station_event_path =~ "scope_kind=ground_station"
      assert ground_station_event_path =~ "scope_id=dss-14"

      assert has_element?(
               view,
               ~s(#dashboard-data-link-copy-link[data-clipboard-text*="panel=data_link"][data-clipboard-text*="selected_target=operational_event"][data-clipboard-text*="selected_id=#{ground_station_operational_event_route_id}"][data-clipboard-text*="data_source_id=managed_operational_observables"][data-clipboard-text*="source_binding_id=default_flight_operational_observables"][data-clipboard-text*="scope_kind=ground_station"][data-clipboard-text*="scope_id=dss-14"])
             )

      ground_station_event_copied_path =
        view
        |> render()
        |> LazyHTML.from_fragment()
        |> LazyHTML.query("#dashboard-data-link-copy-link")
        |> LazyHTML.attribute("data-clipboard-text")
        |> List.first()

      assert ground_station_event_copied_path =~ "panel=data_link"
      assert ground_station_event_copied_path =~ "selected_target=operational_event"

      assert ground_station_event_copied_path =~
               "selected_id=#{ground_station_operational_event_route_id}"

      assert ground_station_event_copied_path =~ "selected_time=#{ground_station_event_at_ms}"
      assert ground_station_event_copied_path =~ "data_source_id=managed_operational_observables"

      assert ground_station_event_copied_path =~
               "source_binding_id=default_flight_operational_observables"

      assert ground_station_event_copied_path =~ "scope_kind=ground_station"
      assert ground_station_event_copied_path =~ "scope_id=dss-14"

      {:ok, reopened_ground_station_event_view, _html} =
        live(conn, ground_station_event_copied_path)

      assert has_element?(
               reopened_ground_station_event_view,
               ~s(#dashboard-data-link-inspector[data-data-link-target="operational_event"][data-data-link-target-id="#{ground_station_operational_event_id}"][data-data-link-status="resolved"][data-data-link-selected-data-source-id="managed_operational_observables"][data-data-link-selected-source-binding-id="default_flight_operational_observables"])
             )

      assert has_element?(
               reopened_ground_station_event_view,
               ~s(#dashboard-data-link-copy-link[data-clipboard-text*="panel=data_link"][data-clipboard-text*="selected_target=operational_event"][data-clipboard-text*="selected_id=#{ground_station_operational_event_route_id}"][data-clipboard-text*="selected_time=#{ground_station_event_at_ms}"])
             )

      assert has_element?(
               reopened_ground_station_event_view,
               ~s(#dashboard-data-link-inspector [data-data-link-field="Connection state snapshot"]),
               "dashboard-ground-station-connection-live-dss-14"
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
               alpha_transport.transport_id
             )

      assert has_element?(
               reopened_ground_station_event_view,
               ~s(#dashboard-data-link-inspector [data-data-link-field="Source endpoint"]),
               alpha_endpoint.source_endpoint_id
             )

      assert has_element?(
               reopened_ground_station_event_view,
               ~s(#dashboard-data-link-inspector [data-data-link-field="Ground station"]),
               dss_14.ground_station_id
             )

      assert has_element?(
               reopened_ground_station_event_view,
               ~s(#dashboard-data-link-inspector [data-data-link-field="Adapter"]),
               "tcp_socket"
             )

      assert has_element?(
               reopened_ground_station_event_view,
               ~s(#dashboard-data-link-inspector [data-data-link-field="Connection state"]),
               "connected"
             )

      assert has_element?(
               reopened_ground_station_event_view,
               ~s(#dashboard-data-link-inspector [data-data-link-field="State"]),
               "connected"
             )

      assert has_element?(
               view,
               alpha_transport_row_selector <>
                 ~s([data-status-matrix-resource-id="dashboard-transport-alpha"][data-status-matrix-scope-kind="transport"][data-status-matrix-source-endpoint-id="#{alpha_endpoint.source_endpoint_id}"][data-status-matrix-ground-station-id="dss-14"])
             )

      refute has_element?(view, beta_transport_row_selector)
      refute has_element?(view, beta_ground_station_row_selector)

      assert has_element?(
               view,
               ground_station_row_selector <>
                 ~s( [data-status-matrix-row-link="ground.station.connection_state:dss-14"][data-status-matrix-row-link-target="ground station"][data-status-matrix-row-link-id="dss-14"][phx-value-target="ground_station"][phx-value-target-id="dss-14"][phx-value-data-source-id="managed_operational_observables"][phx-value-source-binding-id="default_flight_operational_observables"])
             )

      view
      |> element(
        ground_station_row_selector <>
          ~s( [data-status-matrix-row-link="ground.station.connection_state:dss-14"][data-status-matrix-row-link-target="ground station"])
      )
      |> render_click()

      ground_station_link_path = assert_patch(view)
      assert ground_station_link_path =~ "panel=data_link"
      assert ground_station_link_path =~ "selected_target=ground_station"
      assert ground_station_link_path =~ "selected_id=dss-14"
      assert ground_station_link_path =~ "scope_kind=ground_station"
      assert ground_station_link_path =~ "scope_id=dss-14"
      assert ground_station_link_path =~ "realm=flight"
      assert ground_station_link_path =~ "data_source_id=managed_operational_observables"

      assert ground_station_link_path =~
               "source_binding_id=default_flight_operational_observables"

      assert has_element?(
               view,
               ~s(#dashboard-data-link-inspector[data-data-link-target="ground_station"][data-data-link-status="resolved"])
             )

      assert has_element?(
               view,
               ~s(#dashboard-data-link-inspector [data-data-link-field="Display name"]),
               "Goldstone DSS-14"
             )

      assert has_element?(
               view,
               ~s(#dashboard-data-link-copy-link[data-clipboard-text*="scope_kind=ground_station"][data-clipboard-text*="scope_id=dss-14"][data-clipboard-text*="selected_target=ground_station"][data-clipboard-text*="selected_id=dss-14"][data-clipboard-text*="data_source_id=managed_operational_observables"][data-clipboard-text*="source_binding_id=default_flight_operational_observables"])
             )

      stop_dashboard_view(reopened_ground_station_event_view)
      stop_dashboard_view(view)
    end
  end
end
