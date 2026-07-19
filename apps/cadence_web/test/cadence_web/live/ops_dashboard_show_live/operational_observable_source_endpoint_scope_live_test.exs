defmodule CadenceWeb.OpsDashboardShowLive.OperationalObservableSourceEndpointScopeLiveTest do
  use CadenceWeb.ConnCase, async: false

  @moduletag :config

  import Phoenix.LiveViewTest
  import CadenceWeb.OpsDashboardShowLive.OperationalObservableSourceEndpointScopeFixtures

  use Phoenix.VerifiedRoutes,
    endpoint: CadenceWeb.Endpoint,
    router: CadenceWeb.Router,
    statics: CadenceWeb.static_paths()

  alias Cadence.Comms.TransportStore

  alias Cadence.Comms.Transport
  alias Cadence.OperationalEvents
  alias Cadence.OperationalEvents.Event
  alias Cadence.SourceEndpoints.SourceEndpoint

  alias CadenceWeb.OpsDashboardShowLive.OperationalObservableSourceEndpointCommandQueueScenario
  alias CadenceWeb.TestFixtures

  describe "source endpoint operational observable scope rendering" do
    test "filters operational observable transport rows and preserves DataLink context" do
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
               Cadence.persist_source_endpoint(org.organization_id, alpha_endpoint)

      assert {:ok, _source_endpoint} =
               Cadence.persist_source_endpoint(org.organization_id, beta_endpoint)

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
          name: "Source Endpoint Connection State",
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
            "?scope_kind=source_endpoint&scope_id=#{alpha_endpoint.source_endpoint_id}"
        )

      render_dashboard_async(view)

      assert has_element?(
               view,
               ~s(#ops-dashboard-show-page[data-dashboard-scope-kind="source_endpoint"][data-dashboard-scope-id="#{alpha_endpoint.source_endpoint_id}"])
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
                 ~s( [data-status-matrix-row-link="comms.transport.connection_state:dashboard-transport-alpha"][data-status-matrix-row-link-target="transport"][data-status-matrix-row-link-id="dashboard-transport-alpha"][phx-value-data-source-id="managed_operational_observables"][phx-value-source-binding-id="default_flight_operational_observables"])
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
      assert transport_link_path =~ "scope_kind=source_endpoint"
      assert transport_link_path =~ "scope_id=#{alpha_endpoint.source_endpoint_id}"
      assert transport_link_path =~ "realm=flight"
      assert transport_link_path =~ "data_source_id=managed_operational_observables"
      assert transport_link_path =~ "source_binding_id=default_flight_operational_observables"

      assert has_element?(
               view,
               ~s(#dashboard-data-link-inspector[data-data-link-target="transport"][data-data-link-status="resolved"])
             )

      assert has_element?(
               view,
               ~s(#dashboard-data-link-inspector [data-data-link-context="Data source"]),
               "managed_operational_observables"
             )

      assert has_element?(
               view,
               ~s(#dashboard-data-link-copy-link[data-clipboard-text*="scope_kind=source_endpoint"][data-clipboard-text*="scope_id=dashboard-source-endpoint-alpha"][data-clipboard-text*="selected_target=transport"][data-clipboard-text*="selected_id=dashboard-transport-alpha"][data-clipboard-text*="data_source_id=managed_operational_observables"][data-clipboard-text*="source_binding_id=default_flight_operational_observables"])
             )

      stop_dashboard_view(view)
    end

    test "opens live source-endpoint ingress-latency operational-event copied route from frame evidence" do
      enable_dashboard_engine_inline_resolves!()

      {conn, org, mission} = signed_in_org_and_mission()

      source_endpoint =
        SourceEndpoint.new(%{
          source_endpoint_id: "ingress-latency-source-endpoint-alpha",
          mission_id: mission.mission_id,
          display_name: "Ingress latency endpoint",
          metadata: %{"spacecraft_id" => "spacecraft-alpha"}
        })

      assert {:ok, _source_endpoint} =
               Cadence.persist_source_endpoint(org.organization_id, source_endpoint)

      observed_at =
        DateTime.utc_now()
        |> DateTime.truncate(:second)

      metric_event =
        %{
          sample_id: "ingress-latency-live-rendered-alpha",
          organization_id: org.organization_id,
          mission_id: mission.mission_id,
          observable_id: "ingress.processing_latency_ms",
          resource_id: source_endpoint.source_endpoint_id,
          scope_kind: :source_endpoint,
          source_endpoint_id: source_endpoint.source_endpoint_id,
          spacecraft_id: "spacecraft-alpha",
          value: 4.5,
          processing_latency_ms: 4.5,
          unit: "ms",
          observed_at: observed_at
        }
        |> Event.from_operational_observable_metric_sample()
        |> OperationalEvents.persist_event()
        |> then(fn {:ok, event} -> event end)

      dashboard =
        TestFixtures.persist_dashboard_document!(mission,
          name: "Live Ingress Latency Evidence",
          widgets: [
            %{
              type: :time_series,
              title: "Live Ingress Latency",
              binding: %{
                source: :operational_observables,
                observables: ["ingress.processing_latency_ms"]
              }
            }
          ]
        )

      document = fetch_dashboard_document!(org, mission, dashboard)
      latency_widget = render_item_by_title(document, "Live Ingress Latency").widget
      latency_widget_id = latency_widget.widget_id

      {:ok, view, _html} =
        live(
          conn,
          show_path(mission, dashboard) <>
            "?scope_kind=source_endpoint&scope_id=#{source_endpoint.source_endpoint_id}"
        )

      render_dashboard_async(view)

      assert has_element?(
               view,
               ~s(#ops-dashboard-show-page[data-dashboard-time-mode="live"][data-dashboard-scope-kind="source_endpoint"][data-dashboard-scope-id="#{source_endpoint.source_endpoint_id}"])
             )

      frame_button_selector =
        ~s(#widget-#{latency_widget_id} [data-widget-frame-evidence][phx-value-observable-id="ingress.processing_latency_ms"][phx-value-data-source-id="managed_operational_observables"][phx-value-source-binding-id="default_flight_operational_observables"][phx-value-scope-kind="source_endpoint"][phx-value-scope-id="#{source_endpoint.source_endpoint_id}"])

      assert has_element?(view, frame_button_selector)

      view
      |> element(frame_button_selector)
      |> render_click()

      evidence_path = assert_patch(view)
      assert evidence_path =~ "panel=evidence"
      assert evidence_path =~ "selected_evidence_kind=frame"
      assert evidence_path =~ "selected_placement=#{URI.encode_www_form(latency_widget_id)}"

      assert evidence_path =~
               "selected_observable=#{URI.encode_www_form("ingress.processing_latency_ms")}"

      assert evidence_path =~ "selected_data_source=managed_operational_observables"
      assert evidence_path =~ "selected_source_binding=default_flight_operational_observables"
      assert evidence_path =~ "selected_realm=flight"
      assert evidence_path =~ "scope_kind=source_endpoint"
      assert evidence_path =~ "scope_id=#{source_endpoint.source_endpoint_id}"

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
               ~s(#dashboard-evidence-copy-link[data-clipboard-text*="panel=evidence"][data-clipboard-text*="selected_evidence_kind=frame"][data-clipboard-text*="selected_observable=#{URI.encode_www_form("ingress.processing_latency_ms")}"][data-clipboard-text*="selected_data_source=managed_operational_observables"][data-clipboard-text*="selected_source_binding=default_flight_operational_observables"][data-clipboard-text*="scope_kind=source_endpoint"][data-clipboard-text*="scope_id=#{source_endpoint.source_endpoint_id}"])
             )

      metric_operational_event_evidence =
        view
        |> render()
        |> LazyHTML.from_fragment()
        |> LazyHTML.query(metric_event_selector)

      assert ["operational_event"] =
               LazyHTML.attribute(metric_operational_event_evidence, "phx-value-target")

      assert [^metric_event_id] =
               LazyHTML.attribute(metric_operational_event_evidence, "phx-value-target-id")

      assert ["evidence-ref:operational_event:" <> _] =
               LazyHTML.attribute(metric_operational_event_evidence, "phx-value-link-id")

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
        "scope-kind" => "source_endpoint",
        "scope-id" => source_endpoint.source_endpoint_id,
        "resource-id" => source_endpoint.source_endpoint_id,
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
      assert metric_event_path =~ "scope_kind=source_endpoint"
      assert metric_event_path =~ "scope_id=#{source_endpoint.source_endpoint_id}"

      assert has_element?(
               view,
               ~s(#dashboard-data-link-copy-link[data-clipboard-text*="panel=data_link"][data-clipboard-text*="selected_target=operational_event"][data-clipboard-text*="selected_id=#{metric_event_route_id}"][data-clipboard-text*="selected_time=#{metric_event_at_ms}"][data-clipboard-text*="data_source_id=managed_operational_observables"][data-clipboard-text*="source_binding_id=default_flight_operational_observables"][data-clipboard-text*="scope_kind=source_endpoint"][data-clipboard-text*="scope_id=#{source_endpoint.source_endpoint_id}"])
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

      assert metric_event_copied_path =~ "scope_kind=source_endpoint"
      assert metric_event_copied_path =~ "scope_id=#{source_endpoint.source_endpoint_id}"

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
               "ingress-latency-live-rendered-alpha"
             )

      assert has_element?(
               reopened_metric_event_view,
               ~s(#dashboard-data-link-inspector [data-data-link-field="Observable"]),
               "ingress.processing_latency_ms"
             )

      assert has_element?(
               reopened_metric_event_view,
               ~s(#dashboard-data-link-inspector [data-data-link-field="Resource"]),
               source_endpoint.source_endpoint_id
             )

      assert has_element?(
               reopened_metric_event_view,
               ~s(#dashboard-data-link-inspector [data-data-link-field="Scope kind"]),
               "source_endpoint"
             )

      assert has_element?(
               reopened_metric_event_view,
               ~s(#dashboard-data-link-inspector [data-data-link-field="Source endpoint"]),
               source_endpoint.source_endpoint_id
             )

      stop_dashboard_view(reopened_metric_event_view)
      stop_dashboard_view(view)
    end

    test "opens live source-endpoint command queue entry evidence from frame panel copied route" do
      OperationalObservableSourceEndpointCommandQueueScenario.run()
    end
  end
end
