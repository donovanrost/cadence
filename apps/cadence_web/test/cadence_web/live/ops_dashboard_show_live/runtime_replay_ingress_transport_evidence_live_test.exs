defmodule CadenceWeb.OpsDashboardShowLive.RuntimeReplayIngressTransportEvidenceLiveTest do
  use CadenceWeb.ConnCase, async: false

  import Phoenix.LiveViewTest
  import CadenceWeb.OpsDashboardShowLive.RuntimeReplaySourceFamilyFixtures
  import CadenceWeb.OpsDashboardShowLive.RuntimeReplayEvidenceFixtures

  use Phoenix.VerifiedRoutes,
    endpoint: CadenceWeb.Endpoint,
    router: CadenceWeb.Router,
    statics: CadenceWeb.static_paths()

  alias Cadence.Dashboards.Document
  alias Cadence.OperationalEvents.Event
  alias Cadence.SourceEndpoints.SourceEndpoint
  alias CadenceWeb.TestFixtures

  test "opens replay source-endpoint ingress-latency operational-event copied route from frame evidence" do
    replay_run_id = "replay_run_ingress_latency_ops"
    observed_at = ~U[2026-06-17 12:04:30Z]

    enable_dashboard_engine_inline_resolves!()

    {conn, org, mission} = signed_in_org_and_mission()
    _telemetry_replay_source = persist_dashboard_realm!(mission, :replay)
    replay_sources = persist_replay_event_and_operational_sources!(mission)
    persist_replay_run!(mission, replay_run_id)

    source_endpoint =
      SourceEndpoint.new(%{
        source_endpoint_id: "replay-ingress-latency-endpoint-alpha",
        mission_id: mission.mission_id,
        display_name: "Replay ingress latency endpoint",
        metadata: %{"spacecraft_id" => "spacecraft-alpha"}
      })

    assert {:ok, _source_endpoint} =
             Cadence.SourceEndpoints.persist_source_endpoint(org.organization_id, source_endpoint)

    metric_event =
      %{
        sample_id: "ingress-latency-replay-rendered-alpha",
        organization_id: org.organization_id,
        mission_id: mission.mission_id,
        observable_id: "ingress.processing_latency_ms",
        resource_id: source_endpoint.source_endpoint_id,
        scope_kind: :source_endpoint,
        source_endpoint_id: source_endpoint.source_endpoint_id,
        spacecraft_id: "spacecraft-alpha",
        value: 8.75,
        processing_latency_ms: 8.75,
        unit: "ms",
        replay_run_id: replay_run_id,
        observed_at: observed_at
      }
      |> Event.from_operational_observable_metric_sample()
      |> persist_operational_event!()

    dashboard =
      TestFixtures.persist_dashboard_document!(mission,
        name: "Replay Ingress Latency Evidence",
        widgets: [
          %{
            type: :time_series,
            title: "Replay Ingress Latency",
            binding: %{
              source: :operational_observables,
              observables: ["ingress.processing_latency_ms"]
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

    latency_widget = render_item_by_title(document, "Replay Ingress Latency").widget
    latency_widget_id = latency_widget.widget_id

    {:ok, view, _html} =
      live(
        conn,
        show_path(mission, dashboard) <>
          "?time_mode=replay_run&replay_run_id=#{replay_run_id}&scope_kind=source_endpoint&scope_id=#{source_endpoint.source_endpoint_id}"
      )

    render_dashboard_async(view)

    root_selector =
      ~s(#ops-dashboard-show-page[data-dashboard-time-mode="replay_run"][data-engine-time-mode="replay_run"][data-engine-replay-run-id="#{replay_run_id}"][data-dashboard-scope-kind="source_endpoint"][data-dashboard-scope-id="#{source_endpoint.source_endpoint_id}"])

    assert has_element?(view, root_selector)

    frame_button_selector =
      ~s(#widget-#{latency_widget_id} [data-widget-frame-evidence][phx-value-observable-id="ingress.processing_latency_ms"][phx-value-data-source-id="#{replay_sources.operational_data_source_id}"][phx-value-source-binding-id="#{replay_sources.operational_binding_id}"][phx-value-replay-run-id="#{replay_run_id}"][phx-value-requested-dataset="operational_observables_replay"][phx-value-scope-kind="source_endpoint"][phx-value-scope-id="#{source_endpoint.source_endpoint_id}"])

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

    assert evidence_path =~ "selected_data_source=#{replay_sources.operational_data_source_id}"
    assert evidence_path =~ "selected_source_binding=#{replay_sources.operational_binding_id}"
    assert evidence_path =~ "replay_run_id=#{replay_run_id}"
    assert evidence_path =~ "time_mode=replay_run"
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
             ~s(#dashboard-evidence-copy-link[data-clipboard-text*="panel=evidence"][data-clipboard-text*="selected_evidence_kind=frame"][data-clipboard-text*="selected_observable=#{URI.encode_www_form("ingress.processing_latency_ms")}"][data-clipboard-text*="selected_data_source=#{replay_sources.operational_data_source_id}"][data-clipboard-text*="selected_source_binding=#{replay_sources.operational_binding_id}"][data-clipboard-text*="replay_run_id=#{replay_run_id}"])
           )

    view
    |> element(metric_event_selector)
    |> render_click(%{
      "link-id" => "evidence-ref:operational_event:#{metric_event_id}",
      "target" => "operational_event",
      "target-id" => metric_event_id,
      "timestamp-ms" => metric_event_at_ms,
      "realm" => "replay",
      "time-mode" => "replay_run",
      "replay-run-id" => replay_run_id,
      "data-source-id" => replay_sources.operational_data_source_id,
      "source-binding-id" => replay_sources.operational_binding_id,
      "scope-kind" => "source_endpoint",
      "scope-id" => source_endpoint.source_endpoint_id,
      "resource-id" => source_endpoint.source_endpoint_id,
      "source-endpoint-id" => source_endpoint.source_endpoint_id
    })

    assert has_element?(
             view,
             ~s(#dashboard-data-link-inspector[data-data-link-target="operational_event"][data-data-link-target-id="#{metric_event_id}"][data-data-link-status="resolved"][data-data-link-selected-replay-run-id="#{replay_run_id}"][data-data-link-selected-data-source-id="#{replay_sources.operational_data_source_id}"][data-data-link-selected-source-binding-id="#{replay_sources.operational_binding_id}"])
           )

    metric_event_path = assert_patch(view)
    assert metric_event_path =~ "panel=data_link"
    assert metric_event_path =~ "selected_target=operational_event"
    assert metric_event_path =~ "selected_id=#{metric_event_route_id}"
    assert metric_event_path =~ "selected_time=#{metric_event_at_ms}"
    assert metric_event_path =~ "replay_run_id=#{replay_run_id}"
    assert metric_event_path =~ "scope_kind=source_endpoint"
    assert metric_event_path =~ "scope_id=#{source_endpoint.source_endpoint_id}"

    assert has_element?(
             view,
             ~s(#dashboard-data-link-copy-link[data-clipboard-text*="panel=data_link"][data-clipboard-text*="selected_target=operational_event"][data-clipboard-text*="selected_id=#{metric_event_route_id}"][data-clipboard-text*="selected_time=#{metric_event_at_ms}"][data-clipboard-text*="replay_run_id=#{replay_run_id}"][data-clipboard-text*="data_source_id=#{replay_sources.operational_data_source_id}"][data-clipboard-text*="source_binding_id=#{replay_sources.operational_binding_id}"][data-clipboard-text*="scope_kind=source_endpoint"][data-clipboard-text*="scope_id=#{source_endpoint.source_endpoint_id}"])
           )

    metric_event_copied_path =
      view
      |> render()
      |> element_attribute("#dashboard-data-link-copy-link", "data-clipboard-text")

    assert metric_event_copied_path =~ "panel=data_link"
    assert metric_event_copied_path =~ "selected_target=operational_event"
    assert metric_event_copied_path =~ "selected_id=#{metric_event_route_id}"
    assert metric_event_copied_path =~ "selected_time=#{metric_event_at_ms}"
    assert metric_event_copied_path =~ "replay_run_id=#{replay_run_id}"

    assert metric_event_copied_path =~
             "data_source_id=#{replay_sources.operational_data_source_id}"

    assert metric_event_copied_path =~
             "source_binding_id=#{replay_sources.operational_binding_id}"

    assert metric_event_copied_path =~ "scope_kind=source_endpoint"
    assert metric_event_copied_path =~ "scope_id=#{source_endpoint.source_endpoint_id}"

    {:ok, reopened_metric_event_view, _html} = live(conn, metric_event_copied_path)

    assert has_element?(
             reopened_metric_event_view,
             ~s(#dashboard-data-link-inspector[data-data-link-target="operational_event"][data-data-link-target-id="#{metric_event_id}"][data-data-link-status="resolved"][data-data-link-selected-replay-run-id="#{replay_run_id}"][data-data-link-selected-data-source-id="#{replay_sources.operational_data_source_id}"][data-data-link-selected-source-binding-id="#{replay_sources.operational_binding_id}"])
           )

    assert has_element?(
             reopened_metric_event_view,
             ~s(#dashboard-data-link-copy-link[data-clipboard-text*="panel=data_link"][data-clipboard-text*="selected_target=operational_event"][data-clipboard-text*="selected_id=#{metric_event_route_id}"][data-clipboard-text*="selected_time=#{metric_event_at_ms}"][data-clipboard-text*="replay_run_id=#{replay_run_id}"])
           )

    assert has_element?(
             reopened_metric_event_view,
             ~s(#dashboard-data-link-inspector [data-data-link-field="Operational metric sample"]),
             "ingress-latency-replay-rendered-alpha"
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
             ~s(#dashboard-data-link-inspector [data-data-link-field="Value"]),
             "8.750"
           )

    assert has_element?(
             reopened_metric_event_view,
             ~s(#dashboard-data-link-inspector [data-data-link-field="Unit"]),
             "ms"
           )

    assert has_element?(
             reopened_metric_event_view,
             ~s(#dashboard-data-link-inspector [data-data-link-field="Replay run"]),
             replay_run_id
           )

    assert has_element?(
             reopened_metric_event_view,
             ~s(#dashboard-data-link-inspector [data-data-link-field="Source endpoint"]),
             source_endpoint.source_endpoint_id
           )

    stop_dashboard_view(reopened_metric_event_view)
    stop_dashboard_view(view)
  end

  test "opens replay transport-bitrate operational-event copied route from frame evidence" do
    replay_run_id = "replay_run_transport_bitrate_ops"
    observed_at = ~U[2026-06-17 12:04:45Z]

    enable_dashboard_engine_inline_resolves!()

    {conn, org, mission} = signed_in_org_and_mission()
    _telemetry_replay_source = persist_dashboard_realm!(mission, :replay)
    replay_sources = persist_replay_event_and_operational_sources!(mission)
    persist_replay_run!(mission, replay_run_id)
    {source_endpoint, transport} = persist_replay_connection_state_resources!(org, mission)

    metric_event =
      %{
        sample_id: "transport-bitrate-replay-rendered-alpha",
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
        replay_run_id: replay_run_id,
        observed_at: observed_at
      }
      |> Event.from_operational_observable_metric_sample()
      |> persist_operational_event!()

    dashboard =
      TestFixtures.persist_dashboard_document!(mission,
        name: "Replay Transport Bitrate Evidence",
        widgets: [
          %{
            type: :time_series,
            title: "Replay Downlink Bitrate",
            binding: %{
              source: :operational_observables,
              observables: ["comms.transport.downlink_bitrate"]
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

    bitrate_widget = render_item_by_title(document, "Replay Downlink Bitrate").widget
    bitrate_widget_id = bitrate_widget.widget_id

    {:ok, view, _html} =
      live(
        conn,
        show_path(mission, dashboard) <>
          "?time_mode=replay_run&replay_run_id=#{replay_run_id}&scope_kind=transport&scope_id=#{transport.transport_id}"
      )

    render_dashboard_async(view)

    root_selector =
      ~s(#ops-dashboard-show-page[data-dashboard-time-mode="replay_run"][data-engine-time-mode="replay_run"][data-engine-replay-run-id="#{replay_run_id}"][data-dashboard-scope-kind="transport"][data-dashboard-scope-id="#{transport.transport_id}"])

    assert has_element?(view, root_selector)

    frame_button_selector =
      ~s(#widget-#{bitrate_widget_id} [data-widget-frame-evidence][phx-value-observable-id="comms.transport.downlink_bitrate"][phx-value-data-source-id="#{replay_sources.operational_data_source_id}"][phx-value-source-binding-id="#{replay_sources.operational_binding_id}"][phx-value-replay-run-id="#{replay_run_id}"][phx-value-requested-dataset="operational_observables_replay"][phx-value-scope-kind="transport"][phx-value-scope-id="#{transport.transport_id}"])

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

    assert evidence_path =~ "selected_data_source=#{replay_sources.operational_data_source_id}"
    assert evidence_path =~ "selected_source_binding=#{replay_sources.operational_binding_id}"
    assert evidence_path =~ "replay_run_id=#{replay_run_id}"
    assert evidence_path =~ "time_mode=replay_run"
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
             ~s(#dashboard-evidence-copy-link[data-clipboard-text*="panel=evidence"][data-clipboard-text*="selected_evidence_kind=frame"][data-clipboard-text*="selected_observable=#{URI.encode_www_form("comms.transport.downlink_bitrate")}"][data-clipboard-text*="selected_data_source=#{replay_sources.operational_data_source_id}"][data-clipboard-text*="selected_source_binding=#{replay_sources.operational_binding_id}"][data-clipboard-text*="replay_run_id=#{replay_run_id}"])
           )

    view
    |> element(metric_event_selector)
    |> render_click(%{
      "link-id" => "evidence-ref:operational_event:#{metric_event_id}",
      "target" => "operational_event",
      "target-id" => metric_event_id,
      "timestamp-ms" => metric_event_at_ms,
      "realm" => "replay",
      "time-mode" => "replay_run",
      "replay-run-id" => replay_run_id,
      "data-source-id" => replay_sources.operational_data_source_id,
      "source-binding-id" => replay_sources.operational_binding_id,
      "scope-kind" => "transport",
      "scope-id" => transport.transport_id,
      "resource-id" => transport.transport_id,
      "transport-id" => transport.transport_id,
      "source-endpoint-id" => source_endpoint.source_endpoint_id
    })

    assert has_element?(
             view,
             ~s(#dashboard-data-link-inspector[data-data-link-target="operational_event"][data-data-link-target-id="#{metric_event_id}"][data-data-link-status="resolved"][data-data-link-selected-replay-run-id="#{replay_run_id}"][data-data-link-selected-data-source-id="#{replay_sources.operational_data_source_id}"][data-data-link-selected-source-binding-id="#{replay_sources.operational_binding_id}"])
           )

    metric_event_path = assert_patch(view)
    assert metric_event_path =~ "panel=data_link"
    assert metric_event_path =~ "selected_target=operational_event"
    assert metric_event_path =~ "selected_id=#{metric_event_route_id}"
    assert metric_event_path =~ "selected_time=#{metric_event_at_ms}"
    assert metric_event_path =~ "replay_run_id=#{replay_run_id}"
    assert metric_event_path =~ "scope_kind=transport"
    assert metric_event_path =~ "scope_id=#{transport.transport_id}"

    assert has_element?(
             view,
             ~s(#dashboard-data-link-copy-link[data-clipboard-text*="panel=data_link"][data-clipboard-text*="selected_target=operational_event"][data-clipboard-text*="selected_id=#{metric_event_route_id}"][data-clipboard-text*="selected_time=#{metric_event_at_ms}"][data-clipboard-text*="replay_run_id=#{replay_run_id}"][data-clipboard-text*="data_source_id=#{replay_sources.operational_data_source_id}"][data-clipboard-text*="source_binding_id=#{replay_sources.operational_binding_id}"][data-clipboard-text*="scope_kind=transport"][data-clipboard-text*="scope_id=#{transport.transport_id}"])
           )

    metric_event_copied_path =
      view
      |> render()
      |> element_attribute("#dashboard-data-link-copy-link", "data-clipboard-text")

    assert metric_event_copied_path =~ "panel=data_link"
    assert metric_event_copied_path =~ "selected_target=operational_event"
    assert metric_event_copied_path =~ "selected_id=#{metric_event_route_id}"
    assert metric_event_copied_path =~ "selected_time=#{metric_event_at_ms}"
    assert metric_event_copied_path =~ "replay_run_id=#{replay_run_id}"

    assert metric_event_copied_path =~
             "data_source_id=#{replay_sources.operational_data_source_id}"

    assert metric_event_copied_path =~
             "source_binding_id=#{replay_sources.operational_binding_id}"

    assert metric_event_copied_path =~ "scope_kind=transport"
    assert metric_event_copied_path =~ "scope_id=#{transport.transport_id}"

    {:ok, reopened_metric_event_view, _html} = live(conn, metric_event_copied_path)

    assert has_element?(
             reopened_metric_event_view,
             ~s(#dashboard-data-link-inspector[data-data-link-target="operational_event"][data-data-link-target-id="#{metric_event_id}"][data-data-link-status="resolved"][data-data-link-selected-replay-run-id="#{replay_run_id}"][data-data-link-selected-data-source-id="#{replay_sources.operational_data_source_id}"][data-data-link-selected-source-binding-id="#{replay_sources.operational_binding_id}"])
           )

    assert has_element?(
             reopened_metric_event_view,
             ~s(#dashboard-data-link-copy-link[data-clipboard-text*="panel=data_link"][data-clipboard-text*="selected_target=operational_event"][data-clipboard-text*="selected_id=#{metric_event_route_id}"][data-clipboard-text*="selected_time=#{metric_event_at_ms}"][data-clipboard-text*="replay_run_id=#{replay_run_id}"])
           )

    assert has_element?(
             reopened_metric_event_view,
             ~s(#dashboard-data-link-inspector [data-data-link-field="Operational metric sample"]),
             "transport-bitrate-replay-rendered-alpha"
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
             ~s(#dashboard-data-link-inspector [data-data-link-field="Replay run"]),
             replay_run_id
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

  test "opens replay transport-uplink-bitrate operational-event copied route from frame evidence" do
    replay_run_id = "replay_run_transport_uplink_bitrate_ops"
    observed_at = ~U[2026-06-17 12:04:50Z]

    enable_dashboard_engine_inline_resolves!()

    {conn, org, mission} = signed_in_org_and_mission()
    _telemetry_replay_source = persist_dashboard_realm!(mission, :replay)
    replay_sources = persist_replay_event_and_operational_sources!(mission)
    persist_replay_run!(mission, replay_run_id)
    {source_endpoint, transport} = persist_replay_connection_state_resources!(org, mission)

    metric_event =
      %{
        sample_id: "transport-uplink-bitrate-replay-rendered-alpha",
        organization_id: org.organization_id,
        mission_id: mission.mission_id,
        observable_id: "comms.transport.uplink_bitrate",
        resource_id: transport.transport_id,
        scope_kind: :transport,
        transport_id: transport.transport_id,
        source_endpoint_id: source_endpoint.source_endpoint_id,
        ground_station_id: "dss-14",
        value: 5_600.0,
        uplink_bitrate: 5_600.0,
        unit: "bit/s",
        replay_run_id: replay_run_id,
        observed_at: observed_at
      }
      |> Event.from_operational_observable_metric_sample()
      |> persist_operational_event!()

    dashboard =
      TestFixtures.persist_dashboard_document!(mission,
        name: "Replay Transport Uplink Bitrate Evidence",
        widgets: [
          %{
            type: :time_series,
            title: "Replay Uplink Bitrate",
            binding: %{
              source: :operational_observables,
              observables: ["comms.transport.uplink_bitrate"]
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

    bitrate_widget = render_item_by_title(document, "Replay Uplink Bitrate").widget
    bitrate_widget_id = bitrate_widget.widget_id

    {:ok, view, _html} =
      live(
        conn,
        show_path(mission, dashboard) <>
          "?time_mode=replay_run&replay_run_id=#{replay_run_id}&scope_kind=transport&scope_id=#{transport.transport_id}"
      )

    render_dashboard_async(view)

    root_selector =
      ~s(#ops-dashboard-show-page[data-dashboard-time-mode="replay_run"][data-engine-time-mode="replay_run"][data-engine-replay-run-id="#{replay_run_id}"][data-dashboard-scope-kind="transport"][data-dashboard-scope-id="#{transport.transport_id}"])

    assert has_element?(view, root_selector)

    frame_button_selector =
      ~s(#widget-#{bitrate_widget_id} [data-widget-frame-evidence][phx-value-observable-id="comms.transport.uplink_bitrate"][phx-value-data-source-id="#{replay_sources.operational_data_source_id}"][phx-value-source-binding-id="#{replay_sources.operational_binding_id}"][phx-value-replay-run-id="#{replay_run_id}"][phx-value-requested-dataset="operational_observables_replay"][phx-value-scope-kind="transport"][phx-value-scope-id="#{transport.transport_id}"])

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

    assert evidence_path =~ "selected_data_source=#{replay_sources.operational_data_source_id}"
    assert evidence_path =~ "selected_source_binding=#{replay_sources.operational_binding_id}"
    assert evidence_path =~ "replay_run_id=#{replay_run_id}"
    assert evidence_path =~ "time_mode=replay_run"
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
             ~s(#dashboard-evidence-copy-link[data-clipboard-text*="panel=evidence"][data-clipboard-text*="selected_evidence_kind=frame"][data-clipboard-text*="selected_observable=#{URI.encode_www_form("comms.transport.uplink_bitrate")}"][data-clipboard-text*="selected_data_source=#{replay_sources.operational_data_source_id}"][data-clipboard-text*="selected_source_binding=#{replay_sources.operational_binding_id}"][data-clipboard-text*="replay_run_id=#{replay_run_id}"])
           )

    view
    |> element(metric_event_selector)
    |> render_click(%{
      "link-id" => "evidence-ref:operational_event:#{metric_event_id}",
      "target" => "operational_event",
      "target-id" => metric_event_id,
      "timestamp-ms" => metric_event_at_ms,
      "realm" => "replay",
      "time-mode" => "replay_run",
      "replay-run-id" => replay_run_id,
      "data-source-id" => replay_sources.operational_data_source_id,
      "source-binding-id" => replay_sources.operational_binding_id,
      "scope-kind" => "transport",
      "scope-id" => transport.transport_id,
      "resource-id" => transport.transport_id,
      "transport-id" => transport.transport_id,
      "source-endpoint-id" => source_endpoint.source_endpoint_id
    })

    assert has_element?(
             view,
             ~s(#dashboard-data-link-inspector[data-data-link-target="operational_event"][data-data-link-target-id="#{metric_event_id}"][data-data-link-status="resolved"][data-data-link-selected-replay-run-id="#{replay_run_id}"][data-data-link-selected-data-source-id="#{replay_sources.operational_data_source_id}"][data-data-link-selected-source-binding-id="#{replay_sources.operational_binding_id}"])
           )

    metric_event_path = assert_patch(view)
    assert metric_event_path =~ "panel=data_link"
    assert metric_event_path =~ "selected_target=operational_event"
    assert metric_event_path =~ "selected_id=#{metric_event_route_id}"
    assert metric_event_path =~ "selected_time=#{metric_event_at_ms}"
    assert metric_event_path =~ "replay_run_id=#{replay_run_id}"
    assert metric_event_path =~ "scope_kind=transport"
    assert metric_event_path =~ "scope_id=#{transport.transport_id}"

    assert has_element?(
             view,
             ~s(#dashboard-data-link-copy-link[data-clipboard-text*="panel=data_link"][data-clipboard-text*="selected_target=operational_event"][data-clipboard-text*="selected_id=#{metric_event_route_id}"][data-clipboard-text*="selected_time=#{metric_event_at_ms}"][data-clipboard-text*="replay_run_id=#{replay_run_id}"][data-clipboard-text*="data_source_id=#{replay_sources.operational_data_source_id}"][data-clipboard-text*="source_binding_id=#{replay_sources.operational_binding_id}"][data-clipboard-text*="scope_kind=transport"][data-clipboard-text*="scope_id=#{transport.transport_id}"])
           )

    metric_event_copied_path =
      view
      |> render()
      |> element_attribute("#dashboard-data-link-copy-link", "data-clipboard-text")

    assert metric_event_copied_path =~ "panel=data_link"
    assert metric_event_copied_path =~ "selected_target=operational_event"
    assert metric_event_copied_path =~ "selected_id=#{metric_event_route_id}"
    assert metric_event_copied_path =~ "selected_time=#{metric_event_at_ms}"
    assert metric_event_copied_path =~ "replay_run_id=#{replay_run_id}"

    assert metric_event_copied_path =~
             "data_source_id=#{replay_sources.operational_data_source_id}"

    assert metric_event_copied_path =~
             "source_binding_id=#{replay_sources.operational_binding_id}"

    assert metric_event_copied_path =~ "scope_kind=transport"
    assert metric_event_copied_path =~ "scope_id=#{transport.transport_id}"

    {:ok, reopened_metric_event_view, _html} = live(conn, metric_event_copied_path)

    assert has_element?(
             reopened_metric_event_view,
             ~s(#dashboard-data-link-inspector[data-data-link-target="operational_event"][data-data-link-target-id="#{metric_event_id}"][data-data-link-status="resolved"][data-data-link-selected-replay-run-id="#{replay_run_id}"][data-data-link-selected-data-source-id="#{replay_sources.operational_data_source_id}"][data-data-link-selected-source-binding-id="#{replay_sources.operational_binding_id}"])
           )

    assert has_element?(
             reopened_metric_event_view,
             ~s(#dashboard-data-link-copy-link[data-clipboard-text*="panel=data_link"][data-clipboard-text*="selected_target=operational_event"][data-clipboard-text*="selected_id=#{metric_event_route_id}"][data-clipboard-text*="selected_time=#{metric_event_at_ms}"][data-clipboard-text*="replay_run_id=#{replay_run_id}"])
           )

    assert has_element?(
             reopened_metric_event_view,
             ~s(#dashboard-data-link-inspector [data-data-link-field="Operational metric sample"]),
             "transport-uplink-bitrate-replay-rendered-alpha"
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
             "5600"
           )

    assert has_element?(
             reopened_metric_event_view,
             ~s(#dashboard-data-link-inspector [data-data-link-field="Unit"]),
             "bit/s"
           )

    assert has_element?(
             reopened_metric_event_view,
             ~s(#dashboard-data-link-inspector [data-data-link-field="Replay run"]),
             replay_run_id
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
