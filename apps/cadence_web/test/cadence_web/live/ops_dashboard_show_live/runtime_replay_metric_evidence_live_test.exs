defmodule CadenceWeb.OpsDashboardShowLive.RuntimeReplayMetricEvidenceLiveTest do
  use CadenceWeb.ConnCase, async: false

  import Phoenix.LiveViewTest
  import CadenceWeb.OpsDashboardShowLive.ViewTestSupport
  import CadenceWeb.OpsDashboardShowLive.RuntimeReplaySourceFamilyFixtures
  import CadenceWeb.OpsDashboardShowLive.RuntimeReplayEvidenceFixtures

  use Phoenix.VerifiedRoutes,
    endpoint: CadenceWeb.Endpoint,
    router: CadenceWeb.Router,
    statics: CadenceWeb.static_paths()

  alias Cadence.Dashboards.Document
  alias Cadence.OperationalEvents.Event
  alias CadenceWeb.TestFixtures

  test "opens replay metric sample operational-event copied route from rendered metric-history frame evidence" do
    replay_run_id = "replay_run_metric_sample_ops"
    observed_at = ~U[2026-06-17 12:04:00Z]

    enable_dashboard_engine_inline_resolves!()

    {conn, org, mission} = signed_in_org_and_mission()
    _telemetry_replay_source = persist_dashboard_realm!(mission, :replay)
    replay_sources = persist_replay_event_and_operational_sources!(mission)
    persist_replay_run!(mission, replay_run_id)
    {_source_endpoint, transport} = persist_replay_connection_state_resources!(org, mission)

    metric_event =
      %{
        sample_id: "metric-sample-replay-rendered-1",
        organization_id: org.organization_id,
        mission_id: mission.mission_id,
        observable_id: "link.snr_db",
        resource_id: "link-alpha",
        scope_kind: :link,
        transport_id: transport.transport_id,
        source_endpoint_id: "replay-source-health-endpoint",
        ground_station_id: "dss-14",
        link_id: "link-alpha",
        adapter_key: :tcp_socket,
        value: 12.25,
        snr_db: 12.25,
        unit: "dB",
        replay_run_id: replay_run_id,
        observed_at: observed_at
      }
      |> Event.from_operational_observable_metric_sample()
      |> persist_operational_event!()

    dashboard =
      TestFixtures.persist_dashboard_document!(mission,
        name: "Replay Metric Sample Evidence",
        widgets: [
          %{
            type: :time_series,
            title: "Replay SNR Metric",
            binding: %{
              source: :operational_observables,
              observables: ["link.snr_db"]
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

    metric_widget = render_item_by_title(document, "Replay SNR Metric").widget
    metric_widget_id = metric_widget.widget_id

    {:ok, view, _html} =
      live(
        conn,
        show_path(mission, dashboard) <>
          "?time_mode=replay_run&replay_run_id=#{replay_run_id}&scope_kind=link&scope_id=link-alpha"
      )

    render_dashboard_async(view)

    root_selector =
      ~s(#ops-dashboard-show-page[data-dashboard-time-mode="replay_run"][data-engine-time-mode="replay_run"][data-engine-replay-run-id="#{replay_run_id}"])

    assert has_element?(view, root_selector)

    frame_button_selector =
      ~s(#widget-#{metric_widget_id} [data-widget-frame-evidence][phx-value-observable-id="link.snr_db"][phx-value-data-source-id="#{replay_sources.operational_data_source_id}"][phx-value-source-binding-id="#{replay_sources.operational_binding_id}"][phx-value-replay-run-id="#{replay_run_id}"][phx-value-requested-dataset="operational_observables_replay"][phx-value-scope-kind="link"][phx-value-scope-id="link-alpha"])

    assert has_element?(view, frame_button_selector)

    view
    |> element(frame_button_selector)
    |> render_click()

    evidence_path = assert_patch(view)
    assert evidence_path =~ "panel=evidence"
    assert evidence_path =~ "selected_evidence_kind=frame"
    assert evidence_path =~ "selected_placement=#{URI.encode_www_form(metric_widget_id)}"
    assert evidence_path =~ "selected_observable=#{URI.encode_www_form("link.snr_db")}"
    assert evidence_path =~ "selected_data_source=#{replay_sources.operational_data_source_id}"
    assert evidence_path =~ "selected_source_binding=#{replay_sources.operational_binding_id}"
    assert evidence_path =~ "replay_run_id=#{replay_run_id}"
    assert evidence_path =~ "time_mode=replay_run"

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
             ~s(#dashboard-evidence-copy-link[data-clipboard-text*="panel=evidence"][data-clipboard-text*="selected_evidence_kind=frame"][data-clipboard-text*="selected_observable=#{URI.encode_www_form("link.snr_db")}"][data-clipboard-text*="selected_data_source=#{replay_sources.operational_data_source_id}"][data-clipboard-text*="selected_source_binding=#{replay_sources.operational_binding_id}"][data-clipboard-text*="replay_run_id=#{replay_run_id}"])
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
      "scope-kind" => "link",
      "scope-id" => "link-alpha",
      "resource-id" => "link-alpha",
      "transport-id" => transport.transport_id,
      "scope-link-id" => "link-alpha"
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

    assert has_element?(
             view,
             ~s(#dashboard-data-link-copy-link[data-clipboard-text*="panel=data_link"][data-clipboard-text*="selected_target=operational_event"][data-clipboard-text*="selected_id=#{metric_event_route_id}"][data-clipboard-text*="selected_time=#{metric_event_at_ms}"][data-clipboard-text*="replay_run_id=#{replay_run_id}"][data-clipboard-text*="data_source_id=#{replay_sources.operational_data_source_id}"][data-clipboard-text*="source_binding_id=#{replay_sources.operational_binding_id}"])
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
             "metric-sample-replay-rendered-1"
           )

    assert has_element?(
             reopened_metric_event_view,
             ~s(#dashboard-data-link-inspector [data-data-link-field="Observable"]),
             "link.snr_db"
           )

    assert has_element?(
             reopened_metric_event_view,
             ~s(#dashboard-data-link-inspector [data-data-link-field="Resource"]),
             "link-alpha"
           )

    assert has_element?(
             reopened_metric_event_view,
             ~s(#dashboard-data-link-inspector [data-data-link-field="Value"]),
             "12.250"
           )

    assert has_element?(
             reopened_metric_event_view,
             ~s(#dashboard-data-link-inspector [data-data-link-field="Unit"]),
             "dB"
           )

    assert has_element?(
             reopened_metric_event_view,
             ~s(#dashboard-data-link-inspector [data-data-link-field="Replay run"]),
             replay_run_id
           )

    stop_dashboard_view(reopened_metric_event_view)
    stop_dashboard_view(view)
  end

  test "opens replay RF Eb/N0 operational-event copied route from rendered metric-history frame evidence" do
    replay_run_id = "replay_run_rf_eb_n0_ops"
    observed_at = ~U[2026-06-17 12:04:55Z]

    enable_dashboard_engine_inline_resolves!()

    {conn, org, mission} = signed_in_org_and_mission()
    _telemetry_replay_source = persist_dashboard_realm!(mission, :replay)
    replay_sources = persist_replay_event_and_operational_sources!(mission)
    persist_replay_run!(mission, replay_run_id)
    {source_endpoint, transport} = persist_replay_connection_state_resources!(org, mission)

    metric_event =
      %{
        sample_id: "rf-ebn0-replay-rendered-alpha",
        organization_id: org.organization_id,
        mission_id: mission.mission_id,
        observable_id: "link.eb_n0_db",
        resource_id: "link-alpha",
        scope_kind: :link,
        transport_id: transport.transport_id,
        source_endpoint_id: source_endpoint.source_endpoint_id,
        ground_station_id: "dss-14",
        link_id: "link-alpha",
        adapter_key: :tcp_socket,
        value: 9.25,
        eb_n0_db: 9.25,
        unit: "dB",
        replay_run_id: replay_run_id,
        observed_at: observed_at
      }
      |> Event.from_operational_observable_metric_sample()
      |> persist_operational_event!()

    dashboard =
      TestFixtures.persist_dashboard_document!(mission,
        name: "Replay RF Eb/N0 Evidence",
        widgets: [
          %{
            type: :time_series,
            title: "Replay Eb/N0 Metric",
            binding: %{
              source: :operational_observables,
              observables: ["link.eb_n0_db"]
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

    metric_widget = render_item_by_title(document, "Replay Eb/N0 Metric").widget
    metric_widget_id = metric_widget.widget_id

    {:ok, view, _html} =
      live(
        conn,
        show_path(mission, dashboard) <>
          "?time_mode=replay_run&replay_run_id=#{replay_run_id}&scope_kind=link&scope_id=link-alpha"
      )

    render_dashboard_async(view)

    root_selector =
      ~s(#ops-dashboard-show-page[data-dashboard-time-mode="replay_run"][data-engine-time-mode="replay_run"][data-engine-replay-run-id="#{replay_run_id}"][data-dashboard-scope-kind="link"][data-dashboard-scope-id="link-alpha"])

    assert has_element?(view, root_selector)

    frame_button_selector =
      ~s(#widget-#{metric_widget_id} [data-widget-frame-evidence][phx-value-observable-id="link.eb_n0_db"][phx-value-data-source-id="#{replay_sources.operational_data_source_id}"][phx-value-source-binding-id="#{replay_sources.operational_binding_id}"][phx-value-replay-run-id="#{replay_run_id}"][phx-value-requested-dataset="operational_observables_replay"][phx-value-scope-kind="link"][phx-value-scope-id="link-alpha"])

    assert has_element?(view, frame_button_selector)

    view
    |> element(frame_button_selector)
    |> render_click()

    evidence_path = assert_patch(view)
    assert evidence_path =~ "panel=evidence"
    assert evidence_path =~ "selected_evidence_kind=frame"
    assert evidence_path =~ "selected_placement=#{URI.encode_www_form(metric_widget_id)}"
    assert evidence_path =~ "selected_observable=#{URI.encode_www_form("link.eb_n0_db")}"
    assert evidence_path =~ "selected_data_source=#{replay_sources.operational_data_source_id}"
    assert evidence_path =~ "selected_source_binding=#{replay_sources.operational_binding_id}"
    assert evidence_path =~ "replay_run_id=#{replay_run_id}"
    assert evidence_path =~ "time_mode=replay_run"
    assert evidence_path =~ "scope_kind=link"
    assert evidence_path =~ "scope_id=link-alpha"

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
             ~s(#dashboard-evidence-copy-link[data-clipboard-text*="panel=evidence"][data-clipboard-text*="selected_evidence_kind=frame"][data-clipboard-text*="selected_observable=#{URI.encode_www_form("link.eb_n0_db")}"][data-clipboard-text*="selected_data_source=#{replay_sources.operational_data_source_id}"][data-clipboard-text*="selected_source_binding=#{replay_sources.operational_binding_id}"][data-clipboard-text*="replay_run_id=#{replay_run_id}"])
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
      "scope-kind" => "link",
      "scope-id" => "link-alpha",
      "resource-id" => "link-alpha",
      "transport-id" => transport.transport_id,
      "source-endpoint-id" => source_endpoint.source_endpoint_id,
      "scope-link-id" => "link-alpha"
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
    assert metric_event_path =~ "scope_kind=link"
    assert metric_event_path =~ "scope_id=link-alpha"

    assert has_element?(
             view,
             ~s(#dashboard-data-link-copy-link[data-clipboard-text*="panel=data_link"][data-clipboard-text*="selected_target=operational_event"][data-clipboard-text*="selected_id=#{metric_event_route_id}"][data-clipboard-text*="selected_time=#{metric_event_at_ms}"][data-clipboard-text*="replay_run_id=#{replay_run_id}"][data-clipboard-text*="data_source_id=#{replay_sources.operational_data_source_id}"][data-clipboard-text*="source_binding_id=#{replay_sources.operational_binding_id}"][data-clipboard-text*="scope_kind=link"][data-clipboard-text*="scope_id=link-alpha"])
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
    assert metric_event_copied_path =~ "scope_kind=link"
    assert metric_event_copied_path =~ "scope_id=link-alpha"

    assert metric_event_copied_path =~
             "data_source_id=#{replay_sources.operational_data_source_id}"

    assert metric_event_copied_path =~
             "source_binding_id=#{replay_sources.operational_binding_id}"

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
             "rf-ebn0-replay-rendered-alpha"
           )

    assert has_element?(
             reopened_metric_event_view,
             ~s(#dashboard-data-link-inspector [data-data-link-field="Observable"]),
             "link.eb_n0_db"
           )

    assert has_element?(
             reopened_metric_event_view,
             ~s(#dashboard-data-link-inspector [data-data-link-field="Resource"]),
             "link-alpha"
           )

    assert has_element?(
             reopened_metric_event_view,
             ~s(#dashboard-data-link-inspector [data-data-link-field="Scope kind"]),
             "link"
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

    assert has_element?(
             reopened_metric_event_view,
             ~s(#dashboard-data-link-inspector [data-data-link-field="Ground station"]),
             "dss-14"
           )

    assert has_element?(
             reopened_metric_event_view,
             ~s(#dashboard-data-link-inspector [data-data-link-field="Link"]),
             "link-alpha"
           )

    assert has_element?(
             reopened_metric_event_view,
             ~s(#dashboard-data-link-inspector [data-data-link-field="Value"]),
             "9.250"
           )

    assert has_element?(
             reopened_metric_event_view,
             ~s(#dashboard-data-link-inspector [data-data-link-field="Unit"]),
             "dB"
           )

    assert has_element?(
             reopened_metric_event_view,
             ~s(#dashboard-data-link-inspector [data-data-link-field="Replay run"]),
             replay_run_id
           )

    stop_dashboard_view(reopened_metric_event_view)
    stop_dashboard_view(view)
  end

  test "opens replay RF Doppler operational-event copied route from rendered metric-history frame evidence" do
    replay_run_id = "replay_run_rf_doppler_ops"
    observed_at = ~U[2026-06-17 12:05:05Z]

    enable_dashboard_engine_inline_resolves!()

    {conn, org, mission} = signed_in_org_and_mission()
    _telemetry_replay_source = persist_dashboard_realm!(mission, :replay)
    replay_sources = persist_replay_event_and_operational_sources!(mission)
    persist_replay_run!(mission, replay_run_id)
    {source_endpoint, transport} = persist_replay_connection_state_resources!(org, mission)

    metric_event =
      %{
        sample_id: "rf-doppler-replay-rendered-alpha",
        organization_id: org.organization_id,
        mission_id: mission.mission_id,
        observable_id: "link.doppler_hz",
        resource_id: "link-alpha",
        scope_kind: :link,
        transport_id: transport.transport_id,
        source_endpoint_id: source_endpoint.source_endpoint_id,
        ground_station_id: "dss-14",
        link_id: "link-alpha",
        adapter_key: :tcp_socket,
        value: -42.5,
        doppler_hz: -42.5,
        frequency_offset_hz: -42.5,
        carrier_frequency_offset_hz: -42.5,
        unit: "Hz",
        replay_run_id: replay_run_id,
        observed_at: observed_at
      }
      |> Event.from_operational_observable_metric_sample()
      |> persist_operational_event!()

    dashboard =
      TestFixtures.persist_dashboard_document!(mission,
        name: "Replay RF Doppler Evidence",
        widgets: [
          %{
            type: :time_series,
            title: "Replay Doppler Metric",
            binding: %{
              source: :operational_observables,
              observables: ["link.doppler_hz"]
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

    metric_widget = render_item_by_title(document, "Replay Doppler Metric").widget
    metric_widget_id = metric_widget.widget_id

    {:ok, view, _html} =
      live(
        conn,
        show_path(mission, dashboard) <>
          "?time_mode=replay_run&replay_run_id=#{replay_run_id}&scope_kind=link&scope_id=link-alpha"
      )

    render_dashboard_async(view)

    root_selector =
      ~s(#ops-dashboard-show-page[data-dashboard-time-mode="replay_run"][data-engine-time-mode="replay_run"][data-engine-replay-run-id="#{replay_run_id}"][data-dashboard-scope-kind="link"][data-dashboard-scope-id="link-alpha"])

    assert has_element?(view, root_selector)

    frame_button_selector =
      ~s(#widget-#{metric_widget_id} [data-widget-frame-evidence][phx-value-observable-id="link.doppler_hz"][phx-value-data-source-id="#{replay_sources.operational_data_source_id}"][phx-value-source-binding-id="#{replay_sources.operational_binding_id}"][phx-value-replay-run-id="#{replay_run_id}"][phx-value-requested-dataset="operational_observables_replay"][phx-value-scope-kind="link"][phx-value-scope-id="link-alpha"])

    assert has_element?(view, frame_button_selector)

    view
    |> element(frame_button_selector)
    |> render_click()

    evidence_path = assert_patch(view)
    assert evidence_path =~ "panel=evidence"
    assert evidence_path =~ "selected_evidence_kind=frame"
    assert evidence_path =~ "selected_placement=#{URI.encode_www_form(metric_widget_id)}"
    assert evidence_path =~ "selected_observable=#{URI.encode_www_form("link.doppler_hz")}"
    assert evidence_path =~ "selected_data_source=#{replay_sources.operational_data_source_id}"
    assert evidence_path =~ "selected_source_binding=#{replay_sources.operational_binding_id}"
    assert evidence_path =~ "replay_run_id=#{replay_run_id}"
    assert evidence_path =~ "time_mode=replay_run"
    assert evidence_path =~ "scope_kind=link"
    assert evidence_path =~ "scope_id=link-alpha"

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
             ~s(#dashboard-evidence-copy-link[data-clipboard-text*="panel=evidence"][data-clipboard-text*="selected_evidence_kind=frame"][data-clipboard-text*="selected_observable=#{URI.encode_www_form("link.doppler_hz")}"][data-clipboard-text*="selected_data_source=#{replay_sources.operational_data_source_id}"][data-clipboard-text*="selected_source_binding=#{replay_sources.operational_binding_id}"][data-clipboard-text*="replay_run_id=#{replay_run_id}"])
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
      "scope-kind" => "link",
      "scope-id" => "link-alpha",
      "resource-id" => "link-alpha",
      "transport-id" => transport.transport_id,
      "source-endpoint-id" => source_endpoint.source_endpoint_id,
      "scope-link-id" => "link-alpha"
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
    assert metric_event_path =~ "scope_kind=link"
    assert metric_event_path =~ "scope_id=link-alpha"

    assert has_element?(
             view,
             ~s(#dashboard-data-link-copy-link[data-clipboard-text*="panel=data_link"][data-clipboard-text*="selected_target=operational_event"][data-clipboard-text*="selected_id=#{metric_event_route_id}"][data-clipboard-text*="selected_time=#{metric_event_at_ms}"][data-clipboard-text*="replay_run_id=#{replay_run_id}"][data-clipboard-text*="data_source_id=#{replay_sources.operational_data_source_id}"][data-clipboard-text*="source_binding_id=#{replay_sources.operational_binding_id}"][data-clipboard-text*="scope_kind=link"][data-clipboard-text*="scope_id=link-alpha"])
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
    assert metric_event_copied_path =~ "scope_kind=link"
    assert metric_event_copied_path =~ "scope_id=link-alpha"

    assert metric_event_copied_path =~
             "data_source_id=#{replay_sources.operational_data_source_id}"

    assert metric_event_copied_path =~
             "source_binding_id=#{replay_sources.operational_binding_id}"

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
             "rf-doppler-replay-rendered-alpha"
           )

    assert has_element?(
             reopened_metric_event_view,
             ~s(#dashboard-data-link-inspector [data-data-link-field="Observable"]),
             "link.doppler_hz"
           )

    assert has_element?(
             reopened_metric_event_view,
             ~s(#dashboard-data-link-inspector [data-data-link-field="Resource"]),
             "link-alpha"
           )

    assert has_element?(
             reopened_metric_event_view,
             ~s(#dashboard-data-link-inspector [data-data-link-field="Scope kind"]),
             "link"
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

    assert has_element?(
             reopened_metric_event_view,
             ~s(#dashboard-data-link-inspector [data-data-link-field="Ground station"]),
             "dss-14"
           )

    assert has_element?(
             reopened_metric_event_view,
             ~s(#dashboard-data-link-inspector [data-data-link-field="Link"]),
             "link-alpha"
           )

    assert has_element?(
             reopened_metric_event_view,
             ~s(#dashboard-data-link-inspector [data-data-link-field="Value"]),
             "-42.500"
           )

    assert has_element?(
             reopened_metric_event_view,
             ~s(#dashboard-data-link-inspector [data-data-link-field="Unit"]),
             "Hz"
           )

    assert has_element?(
             reopened_metric_event_view,
             ~s(#dashboard-data-link-inspector [data-data-link-field="Replay run"]),
             replay_run_id
           )

    stop_dashboard_view(reopened_metric_event_view)
    stop_dashboard_view(view)
  end

  test "opens replay RF symbol-rate operational-event copied route from rendered metric-history frame evidence" do
    replay_run_id = "replay_run_rf_symbol_rate_ops"
    observed_at = ~U[2026-06-17 12:05:15Z]

    enable_dashboard_engine_inline_resolves!()

    {conn, org, mission} = signed_in_org_and_mission()
    _telemetry_replay_source = persist_dashboard_realm!(mission, :replay)
    replay_sources = persist_replay_event_and_operational_sources!(mission)
    persist_replay_run!(mission, replay_run_id)
    {source_endpoint, transport} = persist_replay_connection_state_resources!(org, mission)

    metric_event =
      %{
        sample_id: "rf-symbol-rate-replay-rendered-alpha",
        organization_id: org.organization_id,
        mission_id: mission.mission_id,
        observable_id: "link.symbol_rate_sps",
        resource_id: "link-alpha",
        scope_kind: :link,
        transport_id: transport.transport_id,
        source_endpoint_id: source_endpoint.source_endpoint_id,
        ground_station_id: "dss-14",
        link_id: "link-alpha",
        adapter_key: :tcp_socket,
        value: 1_048_000.0,
        symbol_rate_sps: 1_048_000.0,
        symbol_rate: 1_048_000.0,
        symbols_per_second: 1_048_000.0,
        unit: "sym/s",
        replay_run_id: replay_run_id,
        observed_at: observed_at
      }
      |> Event.from_operational_observable_metric_sample()
      |> persist_operational_event!()

    dashboard =
      TestFixtures.persist_dashboard_document!(mission,
        name: "Replay RF Symbol Rate Evidence",
        widgets: [
          %{
            type: :time_series,
            title: "Replay Symbol Rate Metric",
            binding: %{
              source: :operational_observables,
              observables: ["link.symbol_rate_sps"]
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

    metric_widget = render_item_by_title(document, "Replay Symbol Rate Metric").widget
    metric_widget_id = metric_widget.widget_id

    {:ok, view, _html} =
      live(
        conn,
        show_path(mission, dashboard) <>
          "?time_mode=replay_run&replay_run_id=#{replay_run_id}&scope_kind=link&scope_id=link-alpha"
      )

    render_dashboard_async(view)

    root_selector =
      ~s(#ops-dashboard-show-page[data-dashboard-time-mode="replay_run"][data-engine-time-mode="replay_run"][data-engine-replay-run-id="#{replay_run_id}"][data-dashboard-scope-kind="link"][data-dashboard-scope-id="link-alpha"])

    assert has_element?(view, root_selector)

    frame_button_selector =
      ~s(#widget-#{metric_widget_id} [data-widget-frame-evidence][phx-value-observable-id="link.symbol_rate_sps"][phx-value-data-source-id="#{replay_sources.operational_data_source_id}"][phx-value-source-binding-id="#{replay_sources.operational_binding_id}"][phx-value-replay-run-id="#{replay_run_id}"][phx-value-requested-dataset="operational_observables_replay"][phx-value-scope-kind="link"][phx-value-scope-id="link-alpha"])

    assert has_element?(view, frame_button_selector)

    view
    |> element(frame_button_selector)
    |> render_click()

    evidence_path = assert_patch(view)
    assert evidence_path =~ "panel=evidence"
    assert evidence_path =~ "selected_evidence_kind=frame"
    assert evidence_path =~ "selected_placement=#{URI.encode_www_form(metric_widget_id)}"
    assert evidence_path =~ "selected_observable=#{URI.encode_www_form("link.symbol_rate_sps")}"
    assert evidence_path =~ "selected_data_source=#{replay_sources.operational_data_source_id}"
    assert evidence_path =~ "selected_source_binding=#{replay_sources.operational_binding_id}"
    assert evidence_path =~ "replay_run_id=#{replay_run_id}"
    assert evidence_path =~ "time_mode=replay_run"
    assert evidence_path =~ "scope_kind=link"
    assert evidence_path =~ "scope_id=link-alpha"

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
             ~s(#dashboard-evidence-copy-link[data-clipboard-text*="panel=evidence"][data-clipboard-text*="selected_evidence_kind=frame"][data-clipboard-text*="selected_observable=#{URI.encode_www_form("link.symbol_rate_sps")}"][data-clipboard-text*="selected_data_source=#{replay_sources.operational_data_source_id}"][data-clipboard-text*="selected_source_binding=#{replay_sources.operational_binding_id}"][data-clipboard-text*="replay_run_id=#{replay_run_id}"])
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
      "scope-kind" => "link",
      "scope-id" => "link-alpha",
      "resource-id" => "link-alpha",
      "transport-id" => transport.transport_id,
      "source-endpoint-id" => source_endpoint.source_endpoint_id,
      "scope-link-id" => "link-alpha"
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
    assert metric_event_path =~ "scope_kind=link"
    assert metric_event_path =~ "scope_id=link-alpha"

    assert has_element?(
             view,
             ~s(#dashboard-data-link-copy-link[data-clipboard-text*="panel=data_link"][data-clipboard-text*="selected_target=operational_event"][data-clipboard-text*="selected_id=#{metric_event_route_id}"][data-clipboard-text*="selected_time=#{metric_event_at_ms}"][data-clipboard-text*="replay_run_id=#{replay_run_id}"][data-clipboard-text*="data_source_id=#{replay_sources.operational_data_source_id}"][data-clipboard-text*="source_binding_id=#{replay_sources.operational_binding_id}"][data-clipboard-text*="scope_kind=link"][data-clipboard-text*="scope_id=link-alpha"])
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
    assert metric_event_copied_path =~ "scope_kind=link"
    assert metric_event_copied_path =~ "scope_id=link-alpha"

    assert metric_event_copied_path =~
             "data_source_id=#{replay_sources.operational_data_source_id}"

    assert metric_event_copied_path =~
             "source_binding_id=#{replay_sources.operational_binding_id}"

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
             "rf-symbol-rate-replay-rendered-alpha"
           )

    assert has_element?(
             reopened_metric_event_view,
             ~s(#dashboard-data-link-inspector [data-data-link-field="Observable"]),
             "link.symbol_rate_sps"
           )

    assert has_element?(
             reopened_metric_event_view,
             ~s(#dashboard-data-link-inspector [data-data-link-field="Resource"]),
             "link-alpha"
           )

    assert has_element?(
             reopened_metric_event_view,
             ~s(#dashboard-data-link-inspector [data-data-link-field="Scope kind"]),
             "link"
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

    assert has_element?(
             reopened_metric_event_view,
             ~s(#dashboard-data-link-inspector [data-data-link-field="Ground station"]),
             "dss-14"
           )

    assert has_element?(
             reopened_metric_event_view,
             ~s(#dashboard-data-link-inspector [data-data-link-field="Link"]),
             "link-alpha"
           )

    assert has_element?(
             reopened_metric_event_view,
             ~s(#dashboard-data-link-inspector [data-data-link-field="Value"]),
             "1048000"
           )

    assert has_element?(
             reopened_metric_event_view,
             ~s(#dashboard-data-link-inspector [data-data-link-field="Unit"]),
             "sym/s"
           )

    assert has_element?(
             reopened_metric_event_view,
             ~s(#dashboard-data-link-inspector [data-data-link-field="Replay run"]),
             replay_run_id
           )

    stop_dashboard_view(reopened_metric_event_view)
    stop_dashboard_view(view)
  end
end
