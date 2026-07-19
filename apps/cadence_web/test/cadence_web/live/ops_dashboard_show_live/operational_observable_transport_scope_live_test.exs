defmodule CadenceWeb.OpsDashboardShowLive.OperationalObservableTransportScopeLiveTest do
  use CadenceWeb.ConnCase, async: false

  @moduletag :config

  import Phoenix.LiveViewTest

  alias Cadence.Comms.TransportStore

  alias Phoenix.LiveViewTest.ClientProxy

  use Phoenix.VerifiedRoutes,
    endpoint: CadenceWeb.Endpoint,
    router: CadenceWeb.Router,
    statics: CadenceWeb.static_paths()

  alias Cadence.Comms.Transport
  alias Cadence.Dashboards.{Document, RenderItem}
  alias Cadence.OperationalEvents
  alias Cadence.OperationalEvents.Event
  alias Cadence.Runtime.TransportCapabilityRecord
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

  defp persist_transport_execution_fixture!(org, mission) do
    source_endpoint =
      SourceEndpoint.new(%{
        source_endpoint_id: "dashboard-transport-execution-source-endpoint",
        mission_id: mission.mission_id,
        display_name: "Transport execution endpoint",
        metadata: %{"ground_station_id" => "dss-14"}
      })

    assert {:ok, _source_endpoint} =
             Cadence.SourceEndpoints.persist_source_endpoint(org.organization_id, source_endpoint)

    transport =
      Transport.new(%{
        transport_id: "dashboard-transport-execution-alpha",
        mission_id: mission.mission_id,
        display_name: "Transport Execution TCP",
        transport_kind: :tcp_socket,
        direction_capability: :bidirectional,
        adapter_key: :tcp_socket,
        configuration: %{
          "mode" => "connect",
          "direction_capability" => "bidirectional",
          "host" => "transport-execution.ground.example",
          "port" => "5010",
          "framing_mode" => "raw",
          "tls_enabled" => "false"
        },
        metadata: %{
          "source_endpoint_id" => source_endpoint.source_endpoint_id,
          "ground_station_id" => "dss-14"
        }
      })

    assert {:ok, _transport} =
             TransportStore.persist_transport(org.organization_id, transport)

    observed_at = ~U[2026-06-17 12:06:00Z]

    transport_record =
      %TransportCapabilityRecord{
        transport_record_id: "transport-execution-live-alpha-1",
        mission_id: mission.mission_id,
        realized_contact_id: "live-contact-alpha",
        path_id: "live-uplink-path",
        capability_instance_id: transport.transport_id,
        family_key: :heartbeat_monitor,
        activation_id: "live-activation-1",
        binding_set_id: "live-binding-set-1",
        binding_set_version: 1,
        partition_affinity: :source_endpoint,
        partition_value: source_endpoint.source_endpoint_id,
        event_kind: :initialized,
        timer_key: nil,
        emitted_record_kinds: [:transport_status],
        emitted_record_count: 1,
        action_request_count: 0,
        state_snapshot: %{active?: true, heartbeat_count: 1},
        recorded_at: observed_at,
        metadata: %{"source" => "live-transport-execution-test"}
      }

    assert {:ok, _transport_execution_event} =
             transport_record
             |> Event.from_transport_capability_record()
             |> OperationalEvents.persist_event()

    [transport_execution_interval] =
      Cadence.operational_transport_execution_intervals(org.organization_id, mission.mission_id,
        capability_instance_id: transport.transport_id,
        order: :asc
      )

    dashboard =
      TestFixtures.persist_dashboard_document!(mission,
        name: "Live Transport Execution Evidence",
        widgets: [
          %{
            type: :state_timeline,
            title: "Live Transport Execution",
            binding: %{
              source: :operational_observables,
              observables: ["comms.transport.execution_state"]
            }
          }
        ]
      )

    document = fetch_dashboard_document!(org, mission, dashboard)
    timeline_widget = render_item_by_title(document, "Live Transport Execution").widget

    {source_endpoint, transport, observed_at, transport_execution_interval, dashboard,
     timeline_widget.widget_id}
  end

  describe "transport operational observable scope rendering" do
    test "filters operational observable rows and resolves setup DataLink" do
      enable_dashboard_engine_inline_resolves!()

      {conn, org, mission} = signed_in_org_and_mission()

      alpha_endpoint =
        SourceEndpoint.new(%{
          source_endpoint_id: "dashboard-source-endpoint-alpha",
          mission_id: mission.mission_id,
          display_name: "Goldstone DSS-14",
          metadata: %{"ground_station_id" => "dss-14"}
        })

      beta_endpoint =
        SourceEndpoint.new(%{
          source_endpoint_id: "dashboard-source-endpoint-beta",
          mission_id: mission.mission_id,
          display_name: "Madrid DSS-63",
          metadata: %{"ground_station_id" => "dss-63"}
        })

      assert {:ok, _source_endpoint} =
               Cadence.SourceEndpoints.persist_source_endpoint(
                 org.organization_id,
                 alpha_endpoint
               )

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
            "ground_station_id" => "dss-14"
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
            "ground_station_id" => "dss-63"
          }
        })

      assert {:ok, _transport} =
               TransportStore.persist_transport(
                 org.organization_id,
                 alpha_transport
               )

      assert {:ok, _transport} =
               TransportStore.persist_transport(org.organization_id, beta_transport)

      dashboard =
        TestFixtures.persist_dashboard_document!(mission,
          name: "Transport Connection State",
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

      {:ok, view, _html} =
        live(
          conn,
          show_path(mission, dashboard) <>
            "?scope_kind=transport&scope_id=#{alpha_transport.transport_id}"
        )

      render_dashboard_async(view)

      assert has_element?(
               view,
               ~s(#ops-dashboard-show-page[data-dashboard-scope-kind="transport"][data-dashboard-scope-id="#{alpha_transport.transport_id}"])
             )

      alpha_row_selector =
        ~s(#widget-#{matrix_widget.widget_id} [data-status-matrix-row="comms.transport.connection_state:dashboard-transport-alpha"])

      beta_row_selector =
        ~s(#widget-#{matrix_widget.widget_id} [data-status-matrix-row="comms.transport.connection_state:dashboard-transport-beta"])

      assert has_element?(
               view,
               alpha_row_selector <>
                 ~s([data-status-matrix-source="operational_observables"][data-status-matrix-status-policy="connection_state"][data-status-matrix-resource-id="dashboard-transport-alpha"][data-status-matrix-scope-kind="transport"][data-status-matrix-source-endpoint-id="#{alpha_endpoint.source_endpoint_id}"][data-status-matrix-ground-station-id="dss-14"])
             )

      assert has_element?(
               view,
               alpha_row_selector <>
                 ~s([data-status-matrix-data-source-id="managed_operational_observables"][data-status-matrix-source-binding-id="default_flight_operational_observables"][data-status-matrix-supported-capability="connection_state"])
             )

      assert has_element?(
               view,
               alpha_row_selector <>
                 ~s( [data-status-matrix-row-link="comms.transport.connection_state:dashboard-transport-alpha"][data-status-matrix-row-link-target="transport"][data-status-matrix-row-link-id="dashboard-transport-alpha"][phx-value-target="transport"][phx-value-target-id="dashboard-transport-alpha"][phx-value-data-source-id="managed_operational_observables"][phx-value-source-binding-id="default_flight_operational_observables"])
             )

      refute has_element?(view, beta_row_selector)

      view
      |> element(
        alpha_row_selector <>
          ~s( [data-status-matrix-row-link="comms.transport.connection_state:dashboard-transport-alpha"][data-status-matrix-row-link-target="transport"])
      )
      |> render_click()

      transport_link_path = assert_patch(view)
      assert transport_link_path =~ "panel=data_link"
      assert transport_link_path =~ "selected_target=transport"
      assert transport_link_path =~ "selected_id=dashboard-transport-alpha"
      assert transport_link_path =~ "scope_kind=transport"
      assert transport_link_path =~ "scope_id=dashboard-transport-alpha"
      assert transport_link_path =~ "realm=flight"
      assert transport_link_path =~ "data_source_id=managed_operational_observables"

      assert transport_link_path =~
               "source_binding_id=default_flight_operational_observables"

      assert has_element?(
               view,
               ~s(#dashboard-data-link-inspector[data-data-link-target="transport"][data-data-link-status="resolved"])
             )

      assert has_element?(
               view,
               ~s(#dashboard-data-link-inspector [data-data-link-field="Display name"]),
               "Alpha TCP"
             )

      assert has_element?(
               view,
               ~s(#dashboard-data-link-copy-link[data-clipboard-text*="scope_kind=transport"][data-clipboard-text*="scope_id=dashboard-transport-alpha"][data-clipboard-text*="selected_target=transport"][data-clipboard-text*="selected_id=dashboard-transport-alpha"][data-clipboard-text*="data_source_id=managed_operational_observables"][data-clipboard-text*="source_binding_id=default_flight_operational_observables"])
             )

      stop_dashboard_view(view)
    end

    test "opens live transport execution operational-event copied route from frame evidence" do
      enable_dashboard_engine_inline_resolves!()

      {conn, org, mission} = signed_in_org_and_mission()

      {source_endpoint, transport, observed_at, transport_execution_interval, dashboard,
       timeline_widget_id} = persist_transport_execution_fixture!(org, mission)

      {:ok, view, _html} =
        live(
          conn,
          show_path(mission, dashboard) <>
            "?scope_kind=transport&scope_id=#{transport.transport_id}"
        )

      render_dashboard_async(view)

      row_id =
        "state:comms.transport.execution_state:#{DateTime.to_unix(observed_at, :millisecond)}:0"

      row_selector = ~s(#widget-#{timeline_widget_id} [data-state-timeline-row="#{row_id}"])

      assert has_element?(
               view,
               row_selector <>
                 ~s([data-state-timeline-observable="comms.transport.execution_state"][data-state-timeline-state="Initialized"][data-state-timeline-realm="flight"][data-state-timeline-data-source-id="managed_operational_observables"][data-state-timeline-source-binding-id="default_flight_operational_observables"])
             )

      view
      |> element(row_selector <> ~s( [data-state-timeline-row-evidence]))
      |> render_click()

      evidence_path = assert_patch(view)
      assert evidence_path =~ "panel=evidence"
      assert evidence_path =~ "selected_evidence_kind=frame"
      assert evidence_path =~ "selected_placement=#{URI.encode_www_form(timeline_widget_id)}"
      assert evidence_path =~ "selected_observable=comms.transport.execution_state"
      assert evidence_path =~ "selected_data_source=managed_operational_observables"
      assert evidence_path =~ "selected_source_binding=default_flight_operational_observables"
      assert evidence_path =~ "selected_realm=flight"
      assert evidence_path =~ "scope_kind=transport"
      assert evidence_path =~ "scope_id=#{transport.transport_id}"

      assert has_element?(
               view,
               ~s(#dashboard-evidence-inspector[data-evidence-kind="frame"][data-evidence-status="resolved"])
             )

      assert has_element?(
               view,
               ~s(#dashboard-evidence-inspector [data-evidence-ref-kind="transport execution interval"][data-evidence-ref-id="#{transport_execution_interval.interval_id}"])
             )

      assert has_element?(
               view,
               ~s(#dashboard-evidence-inspector [data-evidence-ref-kind="operational interval"][data-evidence-ref-id="#{transport_execution_interval.source_event_id}"][data-evidence-ref-link-target="operational_event"])
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
        "realm" => "flight",
        "time-mode" => "live",
        "data-source-id" => "managed_operational_observables",
        "source-binding-id" => "default_flight_operational_observables"
      })

      assert has_element?(
               view,
               ~s(#dashboard-data-link-inspector[data-data-link-target="operational_event"][data-data-link-target-id="#{transport_execution_operational_event_id}"][data-data-link-status="resolved"][data-data-link-selected-data-source-id="managed_operational_observables"][data-data-link-selected-source-binding-id="default_flight_operational_observables"])
             )

      transport_execution_event_path = assert_patch(view)
      assert transport_execution_event_path =~ "panel=data_link"
      assert transport_execution_event_path =~ "selected_target=operational_event"

      assert transport_execution_event_path =~
               "selected_id=#{transport_execution_operational_event_route_id}"

      assert transport_execution_event_path =~ "selected_time=#{transport_execution_event_at_ms}"
      assert transport_execution_event_path =~ "time_mode=live"
      assert transport_execution_event_path =~ "scope_kind=transport"
      assert transport_execution_event_path =~ "scope_id=#{transport.transport_id}"

      assert has_element?(
               view,
               ~s(#dashboard-data-link-copy-link[data-clipboard-text*="panel=data_link"][data-clipboard-text*="selected_target=operational_event"][data-clipboard-text*="selected_id=#{transport_execution_operational_event_route_id}"][data-clipboard-text*="data_source_id=managed_operational_observables"][data-clipboard-text*="source_binding_id=default_flight_operational_observables"][data-clipboard-text*="scope_kind=transport"][data-clipboard-text*="scope_id=#{transport.transport_id}"])
             )

      transport_execution_event_copied_path =
        view
        |> render()
        |> LazyHTML.from_fragment()
        |> LazyHTML.query("#dashboard-data-link-copy-link")
        |> LazyHTML.attribute("data-clipboard-text")
        |> List.first()

      assert transport_execution_event_copied_path =~ "panel=data_link"
      assert transport_execution_event_copied_path =~ "selected_target=operational_event"

      assert transport_execution_event_copied_path =~
               "selected_id=#{transport_execution_operational_event_route_id}"

      assert transport_execution_event_copied_path =~
               "selected_time=#{transport_execution_event_at_ms}"

      assert transport_execution_event_copied_path =~
               "data_source_id=managed_operational_observables"

      assert transport_execution_event_copied_path =~
               "source_binding_id=default_flight_operational_observables"

      assert transport_execution_event_copied_path =~ "scope_kind=transport"
      assert transport_execution_event_copied_path =~ "scope_id=#{transport.transport_id}"

      {:ok, reopened_transport_execution_event_view, _html} =
        live(conn, transport_execution_event_copied_path)

      assert has_element?(
               reopened_transport_execution_event_view,
               ~s(#dashboard-data-link-inspector[data-data-link-target="operational_event"][data-data-link-target-id="#{transport_execution_operational_event_id}"][data-data-link-status="resolved"][data-data-link-selected-data-source-id="managed_operational_observables"][data-data-link-selected-source-binding-id="default_flight_operational_observables"])
             )

      assert has_element?(
               reopened_transport_execution_event_view,
               ~s(#dashboard-data-link-copy-link[data-clipboard-text*="panel=data_link"][data-clipboard-text*="selected_target=operational_event"][data-clipboard-text*="selected_id=#{transport_execution_operational_event_route_id}"][data-clipboard-text*="selected_time=#{transport_execution_event_at_ms}"])
             )

      assert has_element?(
               reopened_transport_execution_event_view,
               ~s(#dashboard-data-link-inspector [data-data-link-field="Transport capability record"]),
               "transport-execution-live-alpha-1"
             )

      assert has_element?(
               reopened_transport_execution_event_view,
               ~s(#dashboard-data-link-inspector [data-data-link-field="Event kind"]),
               "initialized"
             )

      assert has_element?(
               reopened_transport_execution_event_view,
               ~s(#dashboard-data-link-inspector [data-data-link-field="Capability instance"]),
               transport.transport_id
             )

      assert has_element?(
               reopened_transport_execution_event_view,
               ~s(#dashboard-data-link-inspector [data-data-link-field="Contact"]),
               "live-contact-alpha"
             )

      assert has_element?(
               reopened_transport_execution_event_view,
               ~s(#dashboard-data-link-inspector [data-data-link-field="Path"]),
               "live-uplink-path"
             )

      assert has_element?(
               reopened_transport_execution_event_view,
               ~s(#dashboard-data-link-inspector [data-data-link-field="Family"]),
               "heartbeat_monitor"
             )

      assert has_element?(
               reopened_transport_execution_event_view,
               ~s(#dashboard-data-link-inspector [data-data-link-field="Binding set"]),
               "live-binding-set-1"
             )

      assert has_element?(
               reopened_transport_execution_event_view,
               ~s(#dashboard-data-link-inspector [data-data-link-field="Binding set version"]),
               "1"
             )

      assert has_element?(
               reopened_transport_execution_event_view,
               ~s(#dashboard-data-link-inspector [data-data-link-field="Activation"]),
               "live-activation-1"
             )

      assert has_element?(
               reopened_transport_execution_event_view,
               ~s(#dashboard-data-link-inspector [data-data-link-field="Partition affinity"]),
               "source_endpoint"
             )

      assert has_element?(
               reopened_transport_execution_event_view,
               ~s(#dashboard-data-link-inspector [data-data-link-field="Partition value"]),
               source_endpoint.source_endpoint_id
             )

      assert has_element?(
               reopened_transport_execution_event_view,
               ~s(#dashboard-data-link-inspector [data-data-link-field="State snapshot"]),
               "heartbeat_count"
             )

      stop_dashboard_view(reopened_transport_execution_event_view)
      stop_dashboard_view(view)
    end

    test "opens live transport-bitrate operational-event copied route from frame evidence" do
      enable_dashboard_engine_inline_resolves!()

      {conn, org, mission} = signed_in_org_and_mission()

      source_endpoint =
        SourceEndpoint.new(%{
          source_endpoint_id: "live-transport-bitrate-source-endpoint",
          mission_id: mission.mission_id,
          display_name: "Live transport bitrate endpoint",
          metadata: %{"ground_station_id" => "dss-14"}
        })

      assert {:ok, _source_endpoint} =
               Cadence.SourceEndpoints.persist_source_endpoint(
                 org.organization_id,
                 source_endpoint
               )

      transport =
        Transport.new(%{
          transport_id: "live-transport-bitrate-alpha",
          mission_id: mission.mission_id,
          display_name: "Live Transport Bitrate TCP",
          transport_kind: :tcp_socket,
          direction_capability: :bidirectional,
          adapter_key: :tcp_socket,
          configuration: %{
            "mode" => "connect",
            "direction_capability" => "bidirectional",
            "host" => "live-bitrate.ground.example",
            "port" => "5012",
            "framing_mode" => "raw",
            "tls_enabled" => "false"
          },
          metadata: %{
            "source_endpoint_id" => source_endpoint.source_endpoint_id,
            "ground_station_id" => "dss-14"
          }
        })

      assert {:ok, _transport} =
               TransportStore.persist_transport(org.organization_id, transport)

      observed_at = ~U[2026-06-17 12:07:00Z]

      metric_event =
        %{
          sample_id: "transport-bitrate-live-rendered-alpha",
          organization_id: org.organization_id,
          mission_id: mission.mission_id,
          observable_id: "comms.transport.downlink_bitrate",
          resource_id: transport.transport_id,
          scope_kind: :transport,
          transport_id: transport.transport_id,
          source_endpoint_id: source_endpoint.source_endpoint_id,
          ground_station_id: "dss-14",
          value: 72_000.0,
          downlink_bitrate: 72_000.0,
          unit: "bit/s",
          observed_at: observed_at
        }
        |> Event.from_operational_observable_metric_sample()
        |> OperationalEvents.persist_event()
        |> then(fn {:ok, event} -> event end)

      dashboard =
        TestFixtures.persist_dashboard_document!(mission,
          name: "Live Transport Bitrate Evidence",
          widgets: [
            %{
              type: :time_series,
              title: "Live Downlink Bitrate",
              binding: %{
                source: :operational_observables,
                observables: ["comms.transport.downlink_bitrate"]
              }
            }
          ]
        )

      document = fetch_dashboard_document!(org, mission, dashboard)
      bitrate_widget = render_item_by_title(document, "Live Downlink Bitrate").widget
      bitrate_widget_id = bitrate_widget.widget_id

      {:ok, view, _html} =
        live(
          conn,
          show_path(mission, dashboard) <>
            "?scope_kind=transport&scope_id=#{transport.transport_id}"
        )

      render_dashboard_async(view)

      assert has_element?(
               view,
               ~s(#ops-dashboard-show-page[data-dashboard-time-mode="live"][data-dashboard-scope-kind="transport"][data-dashboard-scope-id="#{transport.transport_id}"])
             )

      frame_button_selector =
        ~s(#widget-#{bitrate_widget_id} [data-widget-frame-evidence][phx-value-observable-id="comms.transport.downlink_bitrate"][phx-value-data-source-id="managed_operational_observables"][phx-value-source-binding-id="default_flight_operational_observables"][phx-value-scope-kind="transport"][phx-value-scope-id="#{transport.transport_id}"])

      assert has_element?(view, frame_button_selector)

      view
      |> element(frame_button_selector)
      |> render_click()

      evidence_path = assert_patch(view)
      assert evidence_path =~ "panel=evidence"
      assert evidence_path =~ "selected_evidence_kind=frame"
      assert evidence_path =~ "selected_placement=#{URI.encode_www_form(bitrate_widget_id)}"

      assert evidence_path =~
               "selected_observable=#{URI.encode_www_form("comms.transport.downlink_bitrate")}"

      assert evidence_path =~ "selected_data_source=managed_operational_observables"
      assert evidence_path =~ "selected_source_binding=default_flight_operational_observables"
      assert evidence_path =~ "selected_realm=flight"
      assert evidence_path =~ "scope_kind=transport"
      assert evidence_path =~ "scope_id=#{transport.transport_id}"

      assert has_element?(
               view,
               ~s(#dashboard-evidence-inspector[data-evidence-kind="frame"][data-evidence-status="resolved"])
             )

      metric_event_id = metric_event.event_id
      metric_event_route_id = URI.encode_www_form(metric_event_id)
      metric_event_at_ms = DateTime.to_unix(observed_at, :millisecond)

      metric_event_selector =
        ~s(#dashboard-evidence-inspector [data-evidence-ref-kind="operational event"][data-evidence-ref-id="#{metric_event_id}"][data-evidence-ref-link-target="operational_event"])

      assert has_element?(view, metric_event_selector)

      assert has_element?(
               view,
               ~s(#dashboard-evidence-copy-link[data-clipboard-text*="panel=evidence"][data-clipboard-text*="selected_evidence_kind=frame"][data-clipboard-text*="selected_observable=#{URI.encode_www_form("comms.transport.downlink_bitrate")}"][data-clipboard-text*="selected_data_source=managed_operational_observables"][data-clipboard-text*="selected_source_binding=default_flight_operational_observables"])
             )

      view
      |> element(metric_event_selector)
      |> render_click(%{
        "link-id" => "evidence-ref:operational_event:#{metric_event_id}",
        "target" => "operational_event",
        "target-id" => metric_event_id,
        "timestamp-ms" => metric_event_at_ms,
        "realm" => "flight",
        "time-mode" => "live",
        "data-source-id" => "managed_operational_observables",
        "source-binding-id" => "default_flight_operational_observables",
        "scope-kind" => "transport",
        "scope-id" => transport.transport_id,
        "resource-id" => transport.transport_id,
        "transport-id" => transport.transport_id,
        "source-endpoint-id" => source_endpoint.source_endpoint_id
      })

      assert has_element?(
               view,
               ~s(#dashboard-data-link-inspector[data-data-link-target="operational_event"][data-data-link-target-id="#{metric_event_id}"][data-data-link-status="resolved"][data-data-link-selected-data-source-id="managed_operational_observables"][data-data-link-selected-source-binding-id="default_flight_operational_observables"])
             )

      metric_event_path = assert_patch(view)
      assert metric_event_path =~ "panel=data_link"
      assert metric_event_path =~ "selected_target=operational_event"
      assert metric_event_path =~ "selected_id=#{metric_event_route_id}"
      assert metric_event_path =~ "selected_time=#{metric_event_at_ms}"
      assert metric_event_path =~ "time_mode=live"
      assert metric_event_path =~ "scope_kind=transport"
      assert metric_event_path =~ "scope_id=#{transport.transport_id}"

      assert has_element?(
               view,
               ~s(#dashboard-data-link-copy-link[data-clipboard-text*="panel=data_link"][data-clipboard-text*="selected_target=operational_event"][data-clipboard-text*="selected_id=#{metric_event_route_id}"][data-clipboard-text*="selected_time=#{metric_event_at_ms}"][data-clipboard-text*="data_source_id=managed_operational_observables"][data-clipboard-text*="source_binding_id=default_flight_operational_observables"][data-clipboard-text*="scope_kind=transport"][data-clipboard-text*="scope_id=#{transport.transport_id}"])
             )

      metric_event_copied_path =
        view
        |> render()
        |> LazyHTML.from_fragment()
        |> LazyHTML.query("#dashboard-data-link-copy-link")
        |> LazyHTML.attribute("data-clipboard-text")
        |> List.first()

      assert metric_event_copied_path =~ "panel=data_link"
      assert metric_event_copied_path =~ "selected_target=operational_event"
      assert metric_event_copied_path =~ "selected_id=#{metric_event_route_id}"
      assert metric_event_copied_path =~ "selected_time=#{metric_event_at_ms}"
      assert metric_event_copied_path =~ "data_source_id=managed_operational_observables"

      assert metric_event_copied_path =~
               "source_binding_id=default_flight_operational_observables"

      assert metric_event_copied_path =~ "scope_kind=transport"
      assert metric_event_copied_path =~ "scope_id=#{transport.transport_id}"

      {:ok, reopened_metric_event_view, _html} = live(conn, metric_event_copied_path)

      assert has_element?(
               reopened_metric_event_view,
               ~s(#dashboard-data-link-inspector[data-data-link-target="operational_event"][data-data-link-target-id="#{metric_event_id}"][data-data-link-status="resolved"][data-data-link-selected-data-source-id="managed_operational_observables"][data-data-link-selected-source-binding-id="default_flight_operational_observables"])
             )

      assert has_element?(
               reopened_metric_event_view,
               ~s(#dashboard-data-link-copy-link[data-clipboard-text*="panel=data_link"][data-clipboard-text*="selected_target=operational_event"][data-clipboard-text*="selected_id=#{metric_event_route_id}"][data-clipboard-text*="selected_time=#{metric_event_at_ms}"])
             )

      assert has_element?(
               reopened_metric_event_view,
               ~s(#dashboard-data-link-inspector [data-data-link-field="Operational metric sample"]),
               "transport-bitrate-live-rendered-alpha"
             )

      assert has_element?(
               reopened_metric_event_view,
               ~s(#dashboard-data-link-inspector [data-data-link-field="Observable"]),
               "comms.transport.downlink_bitrate"
             )

      assert has_element?(
               reopened_metric_event_view,
               ~s(#dashboard-data-link-inspector [data-data-link-field="Resource"]),
               transport.transport_id
             )

      assert has_element?(
               reopened_metric_event_view,
               ~s(#dashboard-data-link-inspector [data-data-link-field="Value"]),
               "72000"
             )

      assert has_element?(
               reopened_metric_event_view,
               ~s(#dashboard-data-link-inspector [data-data-link-field="Unit"]),
               "bit/s"
             )

      assert has_element?(
               reopened_metric_event_view,
               ~s(#dashboard-data-link-inspector [data-data-link-field="Transport"]),
               transport.transport_id
             )

      assert has_element?(
               reopened_metric_event_view,
               ~s(#dashboard-data-link-inspector [data-data-link-field="Source endpoint"]),
               source_endpoint.source_endpoint_id
             )

      stop_dashboard_view(reopened_metric_event_view)
      stop_dashboard_view(view)
    end

    test "opens live transport-uplink-bitrate operational-event copied route from frame evidence" do
      enable_dashboard_engine_inline_resolves!()

      {conn, org, mission} = signed_in_org_and_mission()

      source_endpoint =
        SourceEndpoint.new(%{
          source_endpoint_id: "live-transport-uplink-bitrate-source-endpoint",
          mission_id: mission.mission_id,
          display_name: "Live transport uplink bitrate endpoint",
          metadata: %{"ground_station_id" => "dss-14"}
        })

      assert {:ok, _source_endpoint} =
               Cadence.SourceEndpoints.persist_source_endpoint(
                 org.organization_id,
                 source_endpoint
               )

      transport =
        Transport.new(%{
          transport_id: "live-transport-uplink-bitrate-alpha",
          mission_id: mission.mission_id,
          display_name: "Live Transport Uplink Bitrate TCP",
          transport_kind: :tcp_socket,
          direction_capability: :bidirectional,
          adapter_key: :tcp_socket,
          configuration: %{
            "mode" => "connect",
            "direction_capability" => "bidirectional",
            "host" => "live-uplink-bitrate.ground.example",
            "port" => "5013",
            "framing_mode" => "raw",
            "tls_enabled" => "false"
          },
          metadata: %{
            "source_endpoint_id" => source_endpoint.source_endpoint_id,
            "ground_station_id" => "dss-14"
          }
        })

      assert {:ok, _transport} =
               TransportStore.persist_transport(org.organization_id, transport)

      observed_at = ~U[2026-06-17 12:08:00Z]

      metric_event =
        %{
          sample_id: "transport-uplink-bitrate-live-rendered-alpha",
          organization_id: org.organization_id,
          mission_id: mission.mission_id,
          observable_id: "comms.transport.uplink_bitrate",
          resource_id: transport.transport_id,
          scope_kind: :transport,
          transport_id: transport.transport_id,
          source_endpoint_id: source_endpoint.source_endpoint_id,
          ground_station_id: "dss-14",
          value: 44_000.0,
          uplink_bitrate: 44_000.0,
          unit: "bit/s",
          observed_at: observed_at
        }
        |> Event.from_operational_observable_metric_sample()
        |> OperationalEvents.persist_event()
        |> then(fn {:ok, event} -> event end)

      dashboard =
        TestFixtures.persist_dashboard_document!(mission,
          name: "Live Transport Uplink Bitrate Evidence",
          widgets: [
            %{
              type: :time_series,
              title: "Live Uplink Bitrate",
              binding: %{
                source: :operational_observables,
                observables: ["comms.transport.uplink_bitrate"]
              }
            }
          ]
        )

      document = fetch_dashboard_document!(org, mission, dashboard)
      bitrate_widget = render_item_by_title(document, "Live Uplink Bitrate").widget
      bitrate_widget_id = bitrate_widget.widget_id

      {:ok, view, _html} =
        live(
          conn,
          show_path(mission, dashboard) <>
            "?scope_kind=transport&scope_id=#{transport.transport_id}"
        )

      render_dashboard_async(view)

      assert has_element?(
               view,
               ~s(#ops-dashboard-show-page[data-dashboard-time-mode="live"][data-dashboard-scope-kind="transport"][data-dashboard-scope-id="#{transport.transport_id}"])
             )

      frame_button_selector =
        ~s(#widget-#{bitrate_widget_id} [data-widget-frame-evidence][phx-value-observable-id="comms.transport.uplink_bitrate"][phx-value-data-source-id="managed_operational_observables"][phx-value-source-binding-id="default_flight_operational_observables"][phx-value-scope-kind="transport"][phx-value-scope-id="#{transport.transport_id}"])

      assert has_element?(view, frame_button_selector)

      view
      |> element(frame_button_selector)
      |> render_click()

      evidence_path = assert_patch(view)
      assert evidence_path =~ "panel=evidence"
      assert evidence_path =~ "selected_evidence_kind=frame"
      assert evidence_path =~ "selected_placement=#{URI.encode_www_form(bitrate_widget_id)}"

      assert evidence_path =~
               "selected_observable=#{URI.encode_www_form("comms.transport.uplink_bitrate")}"

      assert evidence_path =~ "selected_data_source=managed_operational_observables"
      assert evidence_path =~ "selected_source_binding=default_flight_operational_observables"
      assert evidence_path =~ "selected_realm=flight"
      assert evidence_path =~ "scope_kind=transport"
      assert evidence_path =~ "scope_id=#{transport.transport_id}"

      assert has_element?(
               view,
               ~s(#dashboard-evidence-inspector[data-evidence-kind="frame"][data-evidence-status="resolved"])
             )

      metric_event_id = metric_event.event_id
      metric_event_route_id = URI.encode_www_form(metric_event_id)
      metric_event_at_ms = DateTime.to_unix(observed_at, :millisecond)

      metric_event_selector =
        ~s(#dashboard-evidence-inspector [data-evidence-ref-kind="operational event"][data-evidence-ref-id="#{metric_event_id}"][data-evidence-ref-link-target="operational_event"])

      assert has_element?(view, metric_event_selector)

      assert has_element?(
               view,
               ~s(#dashboard-evidence-copy-link[data-clipboard-text*="panel=evidence"][data-clipboard-text*="selected_evidence_kind=frame"][data-clipboard-text*="selected_observable=#{URI.encode_www_form("comms.transport.uplink_bitrate")}"][data-clipboard-text*="selected_data_source=managed_operational_observables"][data-clipboard-text*="selected_source_binding=default_flight_operational_observables"])
             )

      view
      |> element(metric_event_selector)
      |> render_click(%{
        "link-id" => "evidence-ref:operational_event:#{metric_event_id}",
        "target" => "operational_event",
        "target-id" => metric_event_id,
        "timestamp-ms" => metric_event_at_ms,
        "realm" => "flight",
        "time-mode" => "live",
        "data-source-id" => "managed_operational_observables",
        "source-binding-id" => "default_flight_operational_observables",
        "scope-kind" => "transport",
        "scope-id" => transport.transport_id,
        "resource-id" => transport.transport_id,
        "transport-id" => transport.transport_id,
        "source-endpoint-id" => source_endpoint.source_endpoint_id
      })

      assert has_element?(
               view,
               ~s(#dashboard-data-link-inspector[data-data-link-target="operational_event"][data-data-link-target-id="#{metric_event_id}"][data-data-link-status="resolved"][data-data-link-selected-data-source-id="managed_operational_observables"][data-data-link-selected-source-binding-id="default_flight_operational_observables"])
             )

      metric_event_path = assert_patch(view)
      assert metric_event_path =~ "panel=data_link"
      assert metric_event_path =~ "selected_target=operational_event"
      assert metric_event_path =~ "selected_id=#{metric_event_route_id}"
      assert metric_event_path =~ "selected_time=#{metric_event_at_ms}"
      assert metric_event_path =~ "time_mode=live"
      assert metric_event_path =~ "scope_kind=transport"
      assert metric_event_path =~ "scope_id=#{transport.transport_id}"

      assert has_element?(
               view,
               ~s(#dashboard-data-link-copy-link[data-clipboard-text*="panel=data_link"][data-clipboard-text*="selected_target=operational_event"][data-clipboard-text*="selected_id=#{metric_event_route_id}"][data-clipboard-text*="selected_time=#{metric_event_at_ms}"][data-clipboard-text*="data_source_id=managed_operational_observables"][data-clipboard-text*="source_binding_id=default_flight_operational_observables"][data-clipboard-text*="scope_kind=transport"][data-clipboard-text*="scope_id=#{transport.transport_id}"])
             )

      metric_event_copied_path =
        view
        |> render()
        |> LazyHTML.from_fragment()
        |> LazyHTML.query("#dashboard-data-link-copy-link")
        |> LazyHTML.attribute("data-clipboard-text")
        |> List.first()

      assert metric_event_copied_path =~ "panel=data_link"
      assert metric_event_copied_path =~ "selected_target=operational_event"
      assert metric_event_copied_path =~ "selected_id=#{metric_event_route_id}"
      assert metric_event_copied_path =~ "selected_time=#{metric_event_at_ms}"
      assert metric_event_copied_path =~ "data_source_id=managed_operational_observables"

      assert metric_event_copied_path =~
               "source_binding_id=default_flight_operational_observables"

      assert metric_event_copied_path =~ "scope_kind=transport"
      assert metric_event_copied_path =~ "scope_id=#{transport.transport_id}"

      {:ok, reopened_metric_event_view, _html} = live(conn, metric_event_copied_path)

      assert has_element?(
               reopened_metric_event_view,
               ~s(#dashboard-data-link-inspector[data-data-link-target="operational_event"][data-data-link-target-id="#{metric_event_id}"][data-data-link-status="resolved"][data-data-link-selected-data-source-id="managed_operational_observables"][data-data-link-selected-source-binding-id="default_flight_operational_observables"])
             )

      assert has_element?(
               reopened_metric_event_view,
               ~s(#dashboard-data-link-copy-link[data-clipboard-text*="panel=data_link"][data-clipboard-text*="selected_target=operational_event"][data-clipboard-text*="selected_id=#{metric_event_route_id}"][data-clipboard-text*="selected_time=#{metric_event_at_ms}"])
             )

      assert has_element?(
               reopened_metric_event_view,
               ~s(#dashboard-data-link-inspector [data-data-link-field="Operational metric sample"]),
               "transport-uplink-bitrate-live-rendered-alpha"
             )

      assert has_element?(
               reopened_metric_event_view,
               ~s(#dashboard-data-link-inspector [data-data-link-field="Observable"]),
               "comms.transport.uplink_bitrate"
             )

      assert has_element?(
               reopened_metric_event_view,
               ~s(#dashboard-data-link-inspector [data-data-link-field="Resource"]),
               transport.transport_id
             )

      assert has_element?(
               reopened_metric_event_view,
               ~s(#dashboard-data-link-inspector [data-data-link-field="Value"]),
               "44000"
             )

      assert has_element?(
               reopened_metric_event_view,
               ~s(#dashboard-data-link-inspector [data-data-link-field="Unit"]),
               "bit/s"
             )

      assert has_element?(
               reopened_metric_event_view,
               ~s(#dashboard-data-link-inspector [data-data-link-field="Transport"]),
               transport.transport_id
             )

      assert has_element?(
               reopened_metric_event_view,
               ~s(#dashboard-data-link-inspector [data-data-link-field="Source endpoint"]),
               source_endpoint.source_endpoint_id
             )

      stop_dashboard_view(reopened_metric_event_view)
      stop_dashboard_view(view)
    end
  end
end
