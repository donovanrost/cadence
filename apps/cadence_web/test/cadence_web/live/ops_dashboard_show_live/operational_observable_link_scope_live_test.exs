defmodule CadenceWeb.OpsDashboardShowLive.OperationalObservableLinkScopeLiveTest do
  use CadenceWeb.ConnCase, async: false

  @moduletag :config

  import Phoenix.LiveViewTest

  alias Phoenix.LiveViewTest.ClientProxy

  use Phoenix.VerifiedRoutes,
    endpoint: CadenceWeb.Endpoint,
    router: CadenceWeb.Router,
    statics: CadenceWeb.static_paths()

  alias Cadence.Comms.Transport
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

  describe "link operational observable scope rendering" do
    test "filters operational observable rows and preserves setup DataLink context" do
      enable_dashboard_engine_inline_resolves!()

      {conn, org, mission} = signed_in_org_and_mission()

      alpha_endpoint =
        SourceEndpoint.new(%{
          source_endpoint_id: "dashboard-source-endpoint-alpha",
          mission_id: mission.mission_id,
          display_name: "Goldstone DSS-14",
          metadata: %{
            "ground_station_id" => "dss-14",
            "link_assignment_id" => "link-alpha"
          }
        })

      beta_endpoint =
        SourceEndpoint.new(%{
          source_endpoint_id: "dashboard-source-endpoint-beta",
          mission_id: mission.mission_id,
          display_name: "Madrid DSS-63",
          metadata: %{
            "ground_station_id" => "dss-63",
            "link_assignment_id" => "link-beta"
          }
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
            "ground_station_id" => "dss-14",
            "link_assignment_id" => "link-alpha"
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
            "ground_station_id" => "dss-63",
            "link_assignment_id" => "link-beta"
          }
        })

      assert {:ok, _transport} = Cadence.persist_transport(org.organization_id, alpha_transport)
      assert {:ok, _transport} = Cadence.persist_transport(org.organization_id, beta_transport)

      observed_at = ~U[2026-06-17 12:01:00Z]

      assert {:ok, _rf_lock_event} =
               Event.from_operational_observable_state_snapshot(%{
                 snapshot_id: "link-rf-lock-live-alpha",
                 organization_id: org.organization_id,
                 mission_id: mission.mission_id,
                 observable_id: "link.rf_lock_state",
                 resource_id: "link-alpha",
                 scope_kind: :link,
                 transport_id: alpha_transport.transport_id,
                 source_endpoint_id: alpha_endpoint.source_endpoint_id,
                 ground_station_id: "dss-14",
                 link_id: "link-alpha",
                 adapter_key: :tcp_socket,
                 rf_lock_state: :locked,
                 state: :locked,
                 observed_at: observed_at
               })
               |> OperationalEvents.persist_event()

      assert {:ok, _frame_sync_event} =
               Event.from_operational_observable_state_snapshot(%{
                 snapshot_id: "link-frame-sync-live-alpha",
                 organization_id: org.organization_id,
                 mission_id: mission.mission_id,
                 observable_id: "link.frame_sync_state",
                 resource_id: "link-alpha",
                 scope_kind: :link,
                 transport_id: alpha_transport.transport_id,
                 source_endpoint_id: alpha_endpoint.source_endpoint_id,
                 ground_station_id: "dss-14",
                 link_id: "link-alpha",
                 adapter_key: :tcp_socket,
                 frame_sync_state: :synchronized,
                 state: :synchronized,
                 observed_at: DateTime.add(observed_at, 1, :second)
               })
               |> OperationalEvents.persist_event()

      [rf_lock_interval] =
        Cadence.operational_link_rf_state_intervals(org.organization_id, mission.mission_id,
          observable_id: "link.rf_lock_state",
          resource_id: "link-alpha"
        )

      [frame_sync_interval] =
        Cadence.operational_link_rf_state_intervals(org.organization_id, mission.mission_id,
          observable_id: "link.frame_sync_state",
          resource_id: "link-alpha"
        )

      dashboard =
        TestFixtures.persist_dashboard_document!(mission,
          name: "Link RF State",
          widgets: [
            %{
              type: :status_matrix,
              title: "RF Lock",
              binding: %{
                source: :operational_observables,
                observables: ["link.rf_lock_state"]
              }
            },
            %{
              type: :status_matrix,
              title: "Frame Sync",
              binding: %{
                source: :operational_observables,
                observables: ["link.frame_sync_state"]
              }
            }
          ]
        )

      document = fetch_dashboard_document!(org, mission, dashboard)
      rf_lock_widget = render_item_by_title(document, "RF Lock").widget
      frame_sync_widget = render_item_by_title(document, "Frame Sync").widget

      {:ok, view, _html} =
        live(
          conn,
          show_path(mission, dashboard) <> "?scope_kind=link&scope_id=link-alpha"
        )

      render_dashboard_async(view)

      assert has_element?(
               view,
               ~s(#ops-dashboard-show-page[data-dashboard-scope-kind="link"][data-dashboard-scope-id="link-alpha"])
             )

      alpha_row_selector =
        ~s(#widget-#{rf_lock_widget.widget_id} [data-status-matrix-row="link.rf_lock_state:link-alpha"])

      beta_row_selector =
        ~s(#widget-#{rf_lock_widget.widget_id} [data-status-matrix-row="link.rf_lock_state:link-beta"])

      frame_sync_row_selector =
        ~s(#widget-#{frame_sync_widget.widget_id} [data-status-matrix-row="link.frame_sync_state:link-alpha"])

      assert has_element?(
               view,
               alpha_row_selector <>
                 ~s([data-status-matrix-source="operational_observables"][data-status-matrix-status-policy="lock_state"][data-status-matrix-resource-id="link-alpha"][data-status-matrix-scope-kind="link"][data-status-matrix-link-id="link-alpha"][data-status-matrix-transport-id="dashboard-transport-alpha"][data-status-matrix-source-endpoint-id="#{alpha_endpoint.source_endpoint_id}"][data-status-matrix-ground-station-id="dss-14"])
             )

      assert has_element?(
               view,
               alpha_row_selector <>
                 ~s([data-status-matrix-frame-observable-id="link.rf_lock_state"][data-status-matrix-product-family="link_rf"][data-status-matrix-supported-capability="link_rf_lock_state"][data-status-matrix-data-source-id="managed_operational_observables"][data-status-matrix-source-binding-id="default_flight_operational_observables"])
             )

      view
      |> element(alpha_row_selector <> ~s( [data-status-matrix-row-evidence]))
      |> render_click()

      evidence_path = assert_patch(view)
      assert evidence_path =~ "panel=evidence"
      assert evidence_path =~ "selected_evidence_kind=frame"
      assert evidence_path =~ "selected_observable=link.rf_lock_state"
      assert evidence_path =~ "selected_data_source=managed_operational_observables"
      assert evidence_path =~ "selected_source_binding=default_flight_operational_observables"
      assert evidence_path =~ "scope_kind=link"
      assert evidence_path =~ "scope_id=link-alpha"

      assert has_element?(
               view,
               ~s(#dashboard-evidence-inspector[data-evidence-kind="frame"][data-evidence-status="resolved"])
             )

      assert has_element?(
               view,
               ~s(#dashboard-evidence-inspector [data-evidence-ref-kind="link rf lock state interval"][data-evidence-ref-id="#{rf_lock_interval.interval_id}"])
             )

      assert has_element?(
               view,
               ~s(#dashboard-evidence-inspector [data-evidence-ref-kind="operational interval"][data-evidence-ref-id="#{rf_lock_interval.source_event_id}"][data-evidence-ref-link-target="operational_event"])
             )

      assert has_element?(
               view,
               ~s(#dashboard-evidence-copy-link[data-clipboard-text*="panel=evidence"][data-clipboard-text*="selected_evidence_kind=frame"][data-clipboard-text*="selected_observable=link.rf_lock_state"][data-clipboard-text*="selected_data_source=managed_operational_observables"][data-clipboard-text*="selected_source_binding=default_flight_operational_observables"][data-clipboard-text*="scope_kind=link"][data-clipboard-text*="scope_id=link-alpha"])
             )

      rf_operational_event_id = rf_lock_interval.source_event_id
      rf_operational_event_route_id = URI.encode_www_form(rf_operational_event_id)
      rf_event_at_ms = DateTime.to_unix(observed_at, :millisecond)

      rf_event_selector =
        ~s(#dashboard-evidence-inspector [data-evidence-ref-kind="operational interval"][data-evidence-ref-id="#{rf_operational_event_id}"][data-evidence-ref-link-target="operational_event"])

      rf_operational_event_evidence =
        view
        |> render()
        |> LazyHTML.from_fragment()
        |> LazyHTML.query(rf_event_selector)

      assert ["operational_event"] =
               LazyHTML.attribute(rf_operational_event_evidence, "phx-value-target")

      assert [^rf_operational_event_id] =
               LazyHTML.attribute(rf_operational_event_evidence, "phx-value-target-id")

      assert ["evidence-ref:operational_event:" <> _] =
               LazyHTML.attribute(rf_operational_event_evidence, "phx-value-link-id")

      view
      |> element(rf_event_selector)
      |> render_click(%{
        "link-id" => "evidence-ref:operational_event:#{rf_operational_event_id}",
        "target" => "operational_event",
        "target-id" => rf_operational_event_id,
        "timestamp-ms" => rf_event_at_ms,
        "realm" => "flight",
        "time-mode" => "live",
        "data-source-id" => "managed_operational_observables",
        "source-binding-id" => "default_flight_operational_observables"
      })

      assert has_element?(
               view,
               ~s(#dashboard-data-link-inspector[data-data-link-target="operational_event"][data-data-link-target-id="#{rf_operational_event_id}"][data-data-link-status="resolved"][data-data-link-selected-data-source-id="managed_operational_observables"][data-data-link-selected-source-binding-id="default_flight_operational_observables"])
             )

      rf_event_path = assert_patch(view)
      assert rf_event_path =~ "panel=data_link"
      assert rf_event_path =~ "selected_target=operational_event"
      assert rf_event_path =~ "selected_id=#{rf_operational_event_route_id}"
      assert rf_event_path =~ "selected_time=#{rf_event_at_ms}"
      assert rf_event_path =~ "time_mode=live"
      assert rf_event_path =~ "scope_kind=link"
      assert rf_event_path =~ "scope_id=link-alpha"

      assert has_element?(
               view,
               ~s(#dashboard-data-link-copy-link[data-clipboard-text*="panel=data_link"][data-clipboard-text*="selected_target=operational_event"][data-clipboard-text*="selected_id=#{rf_operational_event_route_id}"][data-clipboard-text*="data_source_id=managed_operational_observables"][data-clipboard-text*="source_binding_id=default_flight_operational_observables"][data-clipboard-text*="scope_kind=link"][data-clipboard-text*="scope_id=link-alpha"])
             )

      rf_event_copied_path =
        view
        |> render()
        |> LazyHTML.from_fragment()
        |> LazyHTML.query("#dashboard-data-link-copy-link")
        |> LazyHTML.attribute("data-clipboard-text")
        |> List.first()

      assert rf_event_copied_path =~ "panel=data_link"
      assert rf_event_copied_path =~ "selected_target=operational_event"
      assert rf_event_copied_path =~ "selected_id=#{rf_operational_event_route_id}"
      assert rf_event_copied_path =~ "selected_time=#{rf_event_at_ms}"
      assert rf_event_copied_path =~ "data_source_id=managed_operational_observables"

      assert rf_event_copied_path =~
               "source_binding_id=default_flight_operational_observables"

      assert rf_event_copied_path =~ "scope_kind=link"
      assert rf_event_copied_path =~ "scope_id=link-alpha"

      {:ok, reopened_rf_event_view, _html} = live(conn, rf_event_copied_path)

      assert has_element?(
               reopened_rf_event_view,
               ~s(#dashboard-data-link-inspector[data-data-link-target="operational_event"][data-data-link-target-id="#{rf_operational_event_id}"][data-data-link-status="resolved"][data-data-link-selected-data-source-id="managed_operational_observables"][data-data-link-selected-source-binding-id="default_flight_operational_observables"])
             )

      assert has_element?(
               reopened_rf_event_view,
               ~s(#dashboard-data-link-copy-link[data-clipboard-text*="panel=data_link"][data-clipboard-text*="selected_target=operational_event"][data-clipboard-text*="selected_id=#{rf_operational_event_route_id}"][data-clipboard-text*="selected_time=#{rf_event_at_ms}"])
             )

      assert has_element?(
               reopened_rf_event_view,
               ~s(#dashboard-data-link-inspector [data-data-link-field="RF state snapshot"]),
               "link-rf-lock-live-alpha"
             )

      assert has_element?(
               reopened_rf_event_view,
               ~s(#dashboard-data-link-inspector [data-data-link-field="Observable"]),
               "link.rf_lock_state"
             )

      assert has_element?(
               reopened_rf_event_view,
               ~s(#dashboard-data-link-inspector [data-data-link-field="Resource"]),
               "link-alpha"
             )

      assert has_element?(
               reopened_rf_event_view,
               ~s(#dashboard-data-link-inspector [data-data-link-field="Scope kind"]),
               "link"
             )

      assert has_element?(
               reopened_rf_event_view,
               ~s(#dashboard-data-link-inspector [data-data-link-field="Transport"]),
               alpha_transport.transport_id
             )

      assert has_element?(
               reopened_rf_event_view,
               ~s(#dashboard-data-link-inspector [data-data-link-field="Source endpoint"]),
               alpha_endpoint.source_endpoint_id
             )

      assert has_element?(
               reopened_rf_event_view,
               ~s(#dashboard-data-link-inspector [data-data-link-field="Ground station"]),
               "dss-14"
             )

      assert has_element?(
               reopened_rf_event_view,
               ~s(#dashboard-data-link-inspector [data-data-link-field="Link"]),
               "link-alpha"
             )

      assert has_element?(
               reopened_rf_event_view,
               ~s(#dashboard-data-link-inspector [data-data-link-field="RF state"]),
               "locked"
             )

      stop_dashboard_view(reopened_rf_event_view)

      assert has_element?(
               view,
               frame_sync_row_selector <>
                 ~s([data-status-matrix-source="operational_observables"][data-status-matrix-status-policy="frame_sync_state"][data-status-matrix-resource-id="link-alpha"][data-status-matrix-scope-kind="link"][data-status-matrix-link-id="link-alpha"][data-status-matrix-transport-id="dashboard-transport-alpha"][data-status-matrix-source-endpoint-id="#{alpha_endpoint.source_endpoint_id}"][data-status-matrix-ground-station-id="dss-14"])
             )

      assert has_element?(
               view,
               frame_sync_row_selector <>
                 ~s([data-status-matrix-frame-observable-id="link.frame_sync_state"][data-status-matrix-product-family="link_rf"][data-status-matrix-supported-capability="link_rf_frame_sync_state"][data-status-matrix-data-source-id="managed_operational_observables"][data-status-matrix-source-binding-id="default_flight_operational_observables"])
             )

      view
      |> element(frame_sync_row_selector <> ~s( [data-status-matrix-row-evidence]))
      |> render_click()

      frame_sync_evidence_path = assert_patch(view)
      assert frame_sync_evidence_path =~ "panel=evidence"
      assert frame_sync_evidence_path =~ "selected_evidence_kind=frame"
      assert frame_sync_evidence_path =~ "selected_observable=link.frame_sync_state"
      assert frame_sync_evidence_path =~ "selected_data_source=managed_operational_observables"

      assert frame_sync_evidence_path =~
               "selected_source_binding=default_flight_operational_observables"

      assert frame_sync_evidence_path =~ "scope_kind=link"
      assert frame_sync_evidence_path =~ "scope_id=link-alpha"

      assert has_element?(
               view,
               ~s(#dashboard-evidence-inspector[data-evidence-kind="frame"][data-evidence-status="resolved"])
             )

      assert has_element?(
               view,
               ~s(#dashboard-evidence-inspector [data-evidence-ref-kind="link frame sync state interval"][data-evidence-ref-id="#{frame_sync_interval.interval_id}"])
             )

      assert has_element?(
               view,
               ~s(#dashboard-evidence-inspector [data-evidence-ref-kind="operational interval"][data-evidence-ref-id="#{frame_sync_interval.source_event_id}"][data-evidence-ref-link-target="operational_event"])
             )

      assert has_element?(
               view,
               ~s(#dashboard-evidence-copy-link[data-clipboard-text*="panel=evidence"][data-clipboard-text*="selected_evidence_kind=frame"][data-clipboard-text*="selected_observable=link.frame_sync_state"][data-clipboard-text*="selected_data_source=managed_operational_observables"][data-clipboard-text*="selected_source_binding=default_flight_operational_observables"][data-clipboard-text*="scope_kind=link"][data-clipboard-text*="scope_id=link-alpha"])
             )

      assert has_element?(
               view,
               alpha_row_selector <>
                 ~s( [data-status-matrix-row-link="link.rf_lock_state:link-alpha"][data-status-matrix-row-link-target="transport"][data-status-matrix-row-link-id="dashboard-transport-alpha"][phx-value-target="transport"][phx-value-target-id="dashboard-transport-alpha"][phx-value-data-source-id="managed_operational_observables"][phx-value-source-binding-id="default_flight_operational_observables"])
             )

      refute has_element?(view, beta_row_selector)

      view
      |> element(
        alpha_row_selector <>
          ~s( [data-status-matrix-row-link="link.rf_lock_state:link-alpha"][data-status-matrix-row-link-target="transport"])
      )
      |> render_click()

      transport_link_path = assert_patch(view)
      assert transport_link_path =~ "panel=data_link"
      assert transport_link_path =~ "selected_target=transport"
      assert transport_link_path =~ "selected_id=dashboard-transport-alpha"
      assert transport_link_path =~ "scope_kind=link"
      assert transport_link_path =~ "scope_id=link-alpha"
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
               ~s(#dashboard-data-link-inspector [data-data-link-field="Link"]),
               "link-alpha"
             )

      assert has_element?(
               view,
               ~s(#dashboard-data-link-copy-link[data-clipboard-text*="scope_kind=link"][data-clipboard-text*="scope_id=link-alpha"][data-clipboard-text*="selected_target=transport"][data-clipboard-text*="selected_id=dashboard-transport-alpha"][data-clipboard-text*="data_source_id=managed_operational_observables"][data-clipboard-text*="source_binding_id=default_flight_operational_observables"])
             )

      stop_dashboard_view(view)
    end

    test "opens live metric sample operational-event copied route from metric-history frame evidence" do
      enable_dashboard_engine_inline_resolves!()

      {conn, org, mission} = signed_in_org_and_mission()

      source_endpoint =
        SourceEndpoint.new(%{
          source_endpoint_id: "metric-live-source-endpoint-alpha",
          mission_id: mission.mission_id,
          display_name: "Goldstone metric endpoint",
          metadata: %{
            "ground_station_id" => "dss-14",
            "link_assignment_id" => "link-alpha"
          }
        })

      assert {:ok, _source_endpoint} =
               Cadence.persist_source_endpoint(org.organization_id, source_endpoint)

      transport =
        Transport.new(%{
          transport_id: "metric-live-transport-alpha",
          mission_id: mission.mission_id,
          display_name: "Metric Link TCP",
          transport_kind: :tcp_socket,
          direction_capability: :bidirectional,
          adapter_key: :tcp_socket,
          configuration: %{
            "mode" => "connect",
            "direction_capability" => "bidirectional",
            "host" => "metric-link.ground.example",
            "port" => "5011",
            "framing_mode" => "raw",
            "tls_enabled" => "false"
          },
          metadata: %{
            "source_endpoint_id" => source_endpoint.source_endpoint_id,
            "ground_station_id" => "dss-14",
            "link_assignment_id" => "link-alpha"
          }
        })

      assert {:ok, _transport} = Cadence.persist_transport(org.organization_id, transport)

      observed_at =
        DateTime.utc_now()
        |> DateTime.truncate(:second)

      metric_event =
        %{
          sample_id: "metric-sample-live-rendered-1",
          organization_id: org.organization_id,
          mission_id: mission.mission_id,
          observable_id: "link.snr_db",
          resource_id: "link-alpha",
          scope_kind: :link,
          transport_id: transport.transport_id,
          source_endpoint_id: source_endpoint.source_endpoint_id,
          ground_station_id: "dss-14",
          link_id: "link-alpha",
          adapter_key: :tcp_socket,
          value: 13.75,
          snr_db: 13.75,
          unit: "dB",
          observed_at: observed_at
        }
        |> Event.from_operational_observable_metric_sample()
        |> OperationalEvents.persist_event()
        |> then(fn {:ok, event} -> event end)

      dashboard =
        TestFixtures.persist_dashboard_document!(mission,
          name: "Live Metric Sample Evidence",
          widgets: [
            %{
              type: :time_series,
              title: "Live SNR Metric",
              binding: %{
                source: :operational_observables,
                observables: ["link.snr_db"]
              }
            }
          ]
        )

      document = fetch_dashboard_document!(org, mission, dashboard)
      metric_widget = render_item_by_title(document, "Live SNR Metric").widget
      metric_widget_id = metric_widget.widget_id

      {:ok, view, _html} =
        live(
          conn,
          show_path(mission, dashboard) <> "?scope_kind=link&scope_id=link-alpha"
        )

      render_dashboard_async(view)

      assert has_element?(
               view,
               ~s(#ops-dashboard-show-page[data-dashboard-time-mode="live"][data-dashboard-scope-kind="link"][data-dashboard-scope-id="link-alpha"])
             )

      frame_button_selector =
        ~s(#widget-#{metric_widget_id} [data-widget-frame-evidence][phx-value-observable-id="link.snr_db"][phx-value-data-source-id="managed_operational_observables"][phx-value-source-binding-id="default_flight_operational_observables"][phx-value-scope-kind="link"][phx-value-scope-id="link-alpha"])

      assert has_element?(view, frame_button_selector)

      view
      |> element(frame_button_selector)
      |> render_click()

      evidence_path = assert_patch(view)
      assert evidence_path =~ "panel=evidence"
      assert evidence_path =~ "selected_evidence_kind=frame"
      assert evidence_path =~ "selected_placement=#{URI.encode_www_form(metric_widget_id)}"
      assert evidence_path =~ "selected_observable=#{URI.encode_www_form("link.snr_db")}"
      assert evidence_path =~ "selected_data_source=managed_operational_observables"
      assert evidence_path =~ "selected_source_binding=default_flight_operational_observables"
      assert evidence_path =~ "selected_realm=flight"
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
               ~s(#dashboard-evidence-copy-link[data-clipboard-text*="panel=evidence"][data-clipboard-text*="selected_evidence_kind=frame"][data-clipboard-text*="selected_observable=#{URI.encode_www_form("link.snr_db")}"][data-clipboard-text*="selected_data_source=managed_operational_observables"][data-clipboard-text*="selected_source_binding=default_flight_operational_observables"][data-clipboard-text*="scope_kind=link"][data-clipboard-text*="scope_id=link-alpha"])
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
        "scope-kind" => "link",
        "scope-id" => "link-alpha",
        "resource-id" => "link-alpha",
        "transport-id" => transport.transport_id,
        "source-endpoint-id" => source_endpoint.source_endpoint_id,
        "ground-station-id" => "dss-14",
        "scope-link-id" => "link-alpha"
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
      assert metric_event_path =~ "scope_kind=link"
      assert metric_event_path =~ "scope_id=link-alpha"

      assert has_element?(
               view,
               ~s(#dashboard-data-link-copy-link[data-clipboard-text*="panel=data_link"][data-clipboard-text*="selected_target=operational_event"][data-clipboard-text*="selected_id=#{metric_event_route_id}"][data-clipboard-text*="selected_time=#{metric_event_at_ms}"][data-clipboard-text*="data_source_id=managed_operational_observables"][data-clipboard-text*="source_binding_id=default_flight_operational_observables"][data-clipboard-text*="scope_kind=link"][data-clipboard-text*="scope_id=link-alpha"])
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

      assert metric_event_copied_path =~ "scope_kind=link"
      assert metric_event_copied_path =~ "scope_id=link-alpha"

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
               "metric-sample-live-rendered-1"
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
               "13.750"
             )

      assert has_element?(
               reopened_metric_event_view,
               ~s(#dashboard-data-link-inspector [data-data-link-field="Unit"]),
               "dB"
             )

      stop_dashboard_view(reopened_metric_event_view)
      stop_dashboard_view(view)
    end

    test "opens live RF symbol-rate operational-event copied route from metric-history frame evidence" do
      enable_dashboard_engine_inline_resolves!()

      {conn, org, mission} = signed_in_org_and_mission()

      source_endpoint =
        SourceEndpoint.new(%{
          source_endpoint_id: "symbol-rate-live-source-endpoint-alpha",
          mission_id: mission.mission_id,
          display_name: "Goldstone symbol-rate endpoint",
          metadata: %{
            "ground_station_id" => "dss-14",
            "link_assignment_id" => "link-alpha"
          }
        })

      assert {:ok, _source_endpoint} =
               Cadence.persist_source_endpoint(org.organization_id, source_endpoint)

      transport =
        Transport.new(%{
          transport_id: "symbol-rate-live-transport-alpha",
          mission_id: mission.mission_id,
          display_name: "Symbol Rate Link TCP",
          transport_kind: :tcp_socket,
          direction_capability: :bidirectional,
          adapter_key: :tcp_socket,
          configuration: %{
            "mode" => "connect",
            "direction_capability" => "bidirectional",
            "host" => "symbol-rate-link.ground.example",
            "port" => "5011",
            "framing_mode" => "raw",
            "tls_enabled" => "false"
          },
          metadata: %{
            "source_endpoint_id" => source_endpoint.source_endpoint_id,
            "ground_station_id" => "dss-14",
            "link_assignment_id" => "link-alpha"
          }
        })

      assert {:ok, _transport} = Cadence.persist_transport(org.organization_id, transport)

      observed_at =
        DateTime.utc_now()
        |> DateTime.truncate(:second)

      metric_event =
        %{
          sample_id: "rf-symbol-rate-live-rendered-alpha",
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
          observed_at: observed_at
        }
        |> Event.from_operational_observable_metric_sample()
        |> OperationalEvents.persist_event()
        |> then(fn {:ok, event} -> event end)

      dashboard =
        TestFixtures.persist_dashboard_document!(mission,
          name: "Live RF Symbol Rate Evidence",
          widgets: [
            %{
              type: :time_series,
              title: "Live Symbol Rate Metric",
              binding: %{
                source: :operational_observables,
                observables: ["link.symbol_rate_sps"]
              }
            }
          ]
        )

      document = fetch_dashboard_document!(org, mission, dashboard)
      metric_widget = render_item_by_title(document, "Live Symbol Rate Metric").widget
      metric_widget_id = metric_widget.widget_id

      {:ok, view, _html} =
        live(
          conn,
          show_path(mission, dashboard) <> "?scope_kind=link&scope_id=link-alpha"
        )

      render_dashboard_async(view)

      assert has_element?(
               view,
               ~s(#ops-dashboard-show-page[data-dashboard-time-mode="live"][data-dashboard-scope-kind="link"][data-dashboard-scope-id="link-alpha"])
             )

      frame_button_selector =
        ~s(#widget-#{metric_widget_id} [data-widget-frame-evidence][phx-value-observable-id="link.symbol_rate_sps"][phx-value-data-source-id="managed_operational_observables"][phx-value-source-binding-id="default_flight_operational_observables"][phx-value-scope-kind="link"][phx-value-scope-id="link-alpha"])

      assert has_element?(view, frame_button_selector)

      view
      |> element(frame_button_selector)
      |> render_click()

      evidence_path = assert_patch(view)
      assert evidence_path =~ "panel=evidence"
      assert evidence_path =~ "selected_evidence_kind=frame"
      assert evidence_path =~ "selected_placement=#{URI.encode_www_form(metric_widget_id)}"
      assert evidence_path =~ "selected_observable=#{URI.encode_www_form("link.symbol_rate_sps")}"
      assert evidence_path =~ "selected_data_source=managed_operational_observables"
      assert evidence_path =~ "selected_source_binding=default_flight_operational_observables"
      assert evidence_path =~ "selected_realm=flight"
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
               ~s(#dashboard-evidence-copy-link[data-clipboard-text*="panel=evidence"][data-clipboard-text*="selected_evidence_kind=frame"][data-clipboard-text*="selected_observable=#{URI.encode_www_form("link.symbol_rate_sps")}"][data-clipboard-text*="selected_data_source=managed_operational_observables"][data-clipboard-text*="selected_source_binding=default_flight_operational_observables"][data-clipboard-text*="scope_kind=link"][data-clipboard-text*="scope_id=link-alpha"])
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
        "scope-kind" => "link",
        "scope-id" => "link-alpha",
        "resource-id" => "link-alpha",
        "transport-id" => transport.transport_id,
        "source-endpoint-id" => source_endpoint.source_endpoint_id,
        "ground-station-id" => "dss-14",
        "scope-link-id" => "link-alpha"
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
      assert metric_event_path =~ "scope_kind=link"
      assert metric_event_path =~ "scope_id=link-alpha"

      assert has_element?(
               view,
               ~s(#dashboard-data-link-copy-link[data-clipboard-text*="panel=data_link"][data-clipboard-text*="selected_target=operational_event"][data-clipboard-text*="selected_id=#{metric_event_route_id}"][data-clipboard-text*="selected_time=#{metric_event_at_ms}"][data-clipboard-text*="data_source_id=managed_operational_observables"][data-clipboard-text*="source_binding_id=default_flight_operational_observables"][data-clipboard-text*="scope_kind=link"][data-clipboard-text*="scope_id=link-alpha"])
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

      assert metric_event_copied_path =~ "scope_kind=link"
      assert metric_event_copied_path =~ "scope_id=link-alpha"

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
               "rf-symbol-rate-live-rendered-alpha"
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

      stop_dashboard_view(reopened_metric_event_view)
      stop_dashboard_view(view)
    end

    test "opens live RF Doppler operational-event copied route from metric-history frame evidence" do
      enable_dashboard_engine_inline_resolves!()

      {conn, org, mission} = signed_in_org_and_mission()

      source_endpoint =
        SourceEndpoint.new(%{
          source_endpoint_id: "doppler-live-source-endpoint-alpha",
          mission_id: mission.mission_id,
          display_name: "Goldstone Doppler endpoint",
          metadata: %{
            "ground_station_id" => "dss-14",
            "link_assignment_id" => "link-alpha"
          }
        })

      assert {:ok, _source_endpoint} =
               Cadence.persist_source_endpoint(org.organization_id, source_endpoint)

      transport =
        Transport.new(%{
          transport_id: "doppler-live-transport-alpha",
          mission_id: mission.mission_id,
          display_name: "Doppler Link TCP",
          transport_kind: :tcp_socket,
          direction_capability: :bidirectional,
          adapter_key: :tcp_socket,
          configuration: %{
            "mode" => "connect",
            "direction_capability" => "bidirectional",
            "host" => "doppler-link.ground.example",
            "port" => "5011",
            "framing_mode" => "raw",
            "tls_enabled" => "false"
          },
          metadata: %{
            "source_endpoint_id" => source_endpoint.source_endpoint_id,
            "ground_station_id" => "dss-14",
            "link_assignment_id" => "link-alpha"
          }
        })

      assert {:ok, _transport} = Cadence.persist_transport(org.organization_id, transport)

      observed_at =
        DateTime.utc_now()
        |> DateTime.truncate(:second)

      metric_event =
        %{
          sample_id: "rf-doppler-live-rendered-alpha",
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
          unit: "Hz",
          observed_at: observed_at
        }
        |> Event.from_operational_observable_metric_sample()
        |> OperationalEvents.persist_event()
        |> then(fn {:ok, event} -> event end)

      dashboard =
        TestFixtures.persist_dashboard_document!(mission,
          name: "Live RF Doppler Evidence",
          widgets: [
            %{
              type: :time_series,
              title: "Live Doppler Metric",
              binding: %{
                source: :operational_observables,
                observables: ["link.doppler_hz"]
              }
            }
          ]
        )

      document = fetch_dashboard_document!(org, mission, dashboard)
      metric_widget = render_item_by_title(document, "Live Doppler Metric").widget
      metric_widget_id = metric_widget.widget_id

      {:ok, view, _html} =
        live(
          conn,
          show_path(mission, dashboard) <> "?scope_kind=link&scope_id=link-alpha"
        )

      render_dashboard_async(view)

      assert has_element?(
               view,
               ~s(#ops-dashboard-show-page[data-dashboard-time-mode="live"][data-dashboard-scope-kind="link"][data-dashboard-scope-id="link-alpha"])
             )

      frame_button_selector =
        ~s(#widget-#{metric_widget_id} [data-widget-frame-evidence][phx-value-observable-id="link.doppler_hz"][phx-value-data-source-id="managed_operational_observables"][phx-value-source-binding-id="default_flight_operational_observables"][phx-value-scope-kind="link"][phx-value-scope-id="link-alpha"])

      assert has_element?(view, frame_button_selector)

      view
      |> element(frame_button_selector)
      |> render_click()

      evidence_path = assert_patch(view)
      assert evidence_path =~ "panel=evidence"
      assert evidence_path =~ "selected_evidence_kind=frame"
      assert evidence_path =~ "selected_placement=#{URI.encode_www_form(metric_widget_id)}"
      assert evidence_path =~ "selected_observable=#{URI.encode_www_form("link.doppler_hz")}"
      assert evidence_path =~ "selected_data_source=managed_operational_observables"
      assert evidence_path =~ "selected_source_binding=default_flight_operational_observables"
      assert evidence_path =~ "selected_realm=flight"
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
               ~s(#dashboard-evidence-copy-link[data-clipboard-text*="panel=evidence"][data-clipboard-text*="selected_evidence_kind=frame"][data-clipboard-text*="selected_observable=#{URI.encode_www_form("link.doppler_hz")}"][data-clipboard-text*="selected_data_source=managed_operational_observables"][data-clipboard-text*="selected_source_binding=default_flight_operational_observables"][data-clipboard-text*="scope_kind=link"][data-clipboard-text*="scope_id=link-alpha"])
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
        "scope-kind" => "link",
        "scope-id" => "link-alpha",
        "resource-id" => "link-alpha",
        "transport-id" => transport.transport_id,
        "source-endpoint-id" => source_endpoint.source_endpoint_id,
        "ground-station-id" => "dss-14",
        "scope-link-id" => "link-alpha"
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
      assert metric_event_path =~ "scope_kind=link"
      assert metric_event_path =~ "scope_id=link-alpha"

      assert has_element?(
               view,
               ~s(#dashboard-data-link-copy-link[data-clipboard-text*="panel=data_link"][data-clipboard-text*="selected_target=operational_event"][data-clipboard-text*="selected_id=#{metric_event_route_id}"][data-clipboard-text*="selected_time=#{metric_event_at_ms}"][data-clipboard-text*="data_source_id=managed_operational_observables"][data-clipboard-text*="source_binding_id=default_flight_operational_observables"][data-clipboard-text*="scope_kind=link"][data-clipboard-text*="scope_id=link-alpha"])
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

      assert metric_event_copied_path =~ "scope_kind=link"
      assert metric_event_copied_path =~ "scope_id=link-alpha"

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
               "rf-doppler-live-rendered-alpha"
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

      stop_dashboard_view(reopened_metric_event_view)
      stop_dashboard_view(view)
    end

    test "opens live RF Eb/N0 operational-event copied route from metric-history frame evidence" do
      enable_dashboard_engine_inline_resolves!()

      {conn, org, mission} = signed_in_org_and_mission()

      source_endpoint =
        SourceEndpoint.new(%{
          source_endpoint_id: "ebn0-live-source-endpoint-alpha",
          mission_id: mission.mission_id,
          display_name: "Goldstone Eb/N0 endpoint",
          metadata: %{
            "ground_station_id" => "dss-14",
            "link_assignment_id" => "link-alpha"
          }
        })

      assert {:ok, _source_endpoint} =
               Cadence.persist_source_endpoint(org.organization_id, source_endpoint)

      transport =
        Transport.new(%{
          transport_id: "ebn0-live-transport-alpha",
          mission_id: mission.mission_id,
          display_name: "Eb/N0 Link TCP",
          transport_kind: :tcp_socket,
          direction_capability: :bidirectional,
          adapter_key: :tcp_socket,
          configuration: %{
            "mode" => "connect",
            "direction_capability" => "bidirectional",
            "host" => "ebn0-link.ground.example",
            "port" => "5011",
            "framing_mode" => "raw",
            "tls_enabled" => "false"
          },
          metadata: %{
            "source_endpoint_id" => source_endpoint.source_endpoint_id,
            "ground_station_id" => "dss-14",
            "link_assignment_id" => "link-alpha"
          }
        })

      assert {:ok, _transport} = Cadence.persist_transport(org.organization_id, transport)

      observed_at =
        DateTime.utc_now()
        |> DateTime.truncate(:second)

      metric_event =
        %{
          sample_id: "rf-ebn0-live-rendered-alpha",
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
          observed_at: observed_at
        }
        |> Event.from_operational_observable_metric_sample()
        |> OperationalEvents.persist_event()
        |> then(fn {:ok, event} -> event end)

      dashboard =
        TestFixtures.persist_dashboard_document!(mission,
          name: "Live RF Eb/N0 Evidence",
          widgets: [
            %{
              type: :time_series,
              title: "Live Eb/N0 Metric",
              binding: %{
                source: :operational_observables,
                observables: ["link.eb_n0_db"]
              }
            }
          ]
        )

      document = fetch_dashboard_document!(org, mission, dashboard)
      metric_widget = render_item_by_title(document, "Live Eb/N0 Metric").widget
      metric_widget_id = metric_widget.widget_id

      {:ok, view, _html} =
        live(
          conn,
          show_path(mission, dashboard) <> "?scope_kind=link&scope_id=link-alpha"
        )

      render_dashboard_async(view)

      assert has_element?(
               view,
               ~s(#ops-dashboard-show-page[data-dashboard-time-mode="live"][data-dashboard-scope-kind="link"][data-dashboard-scope-id="link-alpha"])
             )

      frame_button_selector =
        ~s(#widget-#{metric_widget_id} [data-widget-frame-evidence][phx-value-observable-id="link.eb_n0_db"][phx-value-data-source-id="managed_operational_observables"][phx-value-source-binding-id="default_flight_operational_observables"][phx-value-scope-kind="link"][phx-value-scope-id="link-alpha"])

      assert has_element?(view, frame_button_selector)

      view
      |> element(frame_button_selector)
      |> render_click()

      evidence_path = assert_patch(view)
      assert evidence_path =~ "panel=evidence"
      assert evidence_path =~ "selected_evidence_kind=frame"
      assert evidence_path =~ "selected_placement=#{URI.encode_www_form(metric_widget_id)}"
      assert evidence_path =~ "selected_observable=#{URI.encode_www_form("link.eb_n0_db")}"
      assert evidence_path =~ "selected_data_source=managed_operational_observables"
      assert evidence_path =~ "selected_source_binding=default_flight_operational_observables"
      assert evidence_path =~ "selected_realm=flight"
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
               ~s(#dashboard-evidence-copy-link[data-clipboard-text*="panel=evidence"][data-clipboard-text*="selected_evidence_kind=frame"][data-clipboard-text*="selected_observable=#{URI.encode_www_form("link.eb_n0_db")}"][data-clipboard-text*="selected_data_source=managed_operational_observables"][data-clipboard-text*="selected_source_binding=default_flight_operational_observables"][data-clipboard-text*="scope_kind=link"][data-clipboard-text*="scope_id=link-alpha"])
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
        "scope-kind" => "link",
        "scope-id" => "link-alpha",
        "resource-id" => "link-alpha",
        "transport-id" => transport.transport_id,
        "source-endpoint-id" => source_endpoint.source_endpoint_id,
        "ground-station-id" => "dss-14",
        "scope-link-id" => "link-alpha"
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
      assert metric_event_path =~ "scope_kind=link"
      assert metric_event_path =~ "scope_id=link-alpha"

      assert has_element?(
               view,
               ~s(#dashboard-data-link-copy-link[data-clipboard-text*="panel=data_link"][data-clipboard-text*="selected_target=operational_event"][data-clipboard-text*="selected_id=#{metric_event_route_id}"][data-clipboard-text*="selected_time=#{metric_event_at_ms}"][data-clipboard-text*="data_source_id=managed_operational_observables"][data-clipboard-text*="source_binding_id=default_flight_operational_observables"][data-clipboard-text*="scope_kind=link"][data-clipboard-text*="scope_id=link-alpha"])
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

      assert metric_event_copied_path =~ "scope_kind=link"
      assert metric_event_copied_path =~ "scope_id=link-alpha"

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
               "rf-ebn0-live-rendered-alpha"
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

      stop_dashboard_view(reopened_metric_event_view)
      stop_dashboard_view(view)
    end
  end
end
