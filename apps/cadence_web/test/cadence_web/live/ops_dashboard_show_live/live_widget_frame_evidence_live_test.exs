defmodule CadenceWeb.OpsDashboardShowLive.LiveWidgetFrameEvidenceLiveTest do
  alias Cadence.Runtime.Persistence, as: RuntimePersistence

  alias Cadence.Reads.Telemetry, as: TelemetryReads
  use CadenceWeb.ConnCase, async: false

  @moduletag :config

  import Phoenix.LiveViewTest
  import CadenceWeb.OpsDashboardShowLive.ViewTestSupport

  alias Cadence.Comms.TransportStore

  use Phoenix.VerifiedRoutes,
    endpoint: CadenceWeb.Endpoint,
    router: CadenceWeb.Router,
    statics: CadenceWeb.static_paths()

  alias Cadence.ApplicationDispatch.{BindingRule, BindingSet, CapabilityInstance}

  alias Cadence.Dashboards.{Document, RenderItem}

  alias Cadence.Projections.DataSources.Health, as: SourceHealth

  alias Cadence.Management.DataSources

  alias Cadence.Comms.Transport
  alias Cadence.Ingress.RawEvidence
  alias Cadence.SourceEndpoints.SourceEndpoint
  alias Cadence.Telemetry.PacketDefinition
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

  defp persist_binding_set!(org, mission) do
    packet_definition =
      PacketDefinition.new(%{
        mission_id: mission.mission_id,
        packet_definition_id: "hk-counter",
        packet_name: "HK",
        apid: 42,
        fields: [%{name: "counter", offset_bits: 0, size_bits: 16, data_type: :uint}]
      })

    binding_set =
      BindingSet.new(%{
        mission_id: mission.mission_id,
        binding_set_id: mission.mission_id <> "-binding-set",
        version: 1,
        capability_instances: [
          CapabilityInstance.new(%{
            capability_instance_id: mission.mission_id <> "-hk-counter-instance",
            family_key: :definition_bound_telemetry,
            target_scope: :mission,
            runtime_configuration: packet_definition
          })
        ],
        rules: [
          BindingRule.new(%{
            binding_rule_id: mission.mission_id <> "-hk-counter-rule",
            capability_instance_id: mission.mission_id <> "-hk-counter-instance",
            handler_key: :definition_bound_telemetry,
            packet_kind: :space_packet,
            apid: 42,
            handler_configuration: packet_definition
          })
        ]
      })

    {:ok, persisted} = Cadence.Governance.persist_binding_set(org.organization_id, binding_set)
    persisted
  end

  defp ingest!(mission, binding_set, spacecraft_id, value, unix_seconds, opts \\ []) do
    evidence =
      RawEvidence.new(%{
        mission_id: mission.mission_id,
        spacecraft_id: spacecraft_id,
        receipt_time: DateTime.from_unix!(unix_seconds, :second),
        raw: build_space_packet(42, 1, <<value::16>>)
      })

    with {:ok, result} <-
           Cadence.process_telemetry_ingress(
             evidence,
             binding_set.binding_set_id,
             binding_set.version
           ) do
      RuntimePersistence.persist_processing_result(result, opts)
    end
  end

  defp build_space_packet(apid, sequence_count, packet_data) do
    packet_length = byte_size(packet_data) - 1

    <<0::3, 0::1, 0::1, apid::11, 3::2, sequence_count::14, packet_length::16,
      packet_data::binary>>
  end

  defp time_series_widget(spacecraft_id) do
    %{
      type: :time_series,
      title: "Counter Trend",
      binding: %{
        mode: :fixed,
        spacecraft_id: spacecraft_id,
        point_id: "HK.counter"
      },
      layout: %{x: 0, y: 0, w: 6, h: 3}
    }
  end

  defp connection_state_widget do
    %{
      type: :status_matrix,
      title: "Connection State",
      binding: %{
        source: :operational_observables,
        observables: ["comms.transport.connection_state"]
      },
      layout: %{x: 0, y: 0, w: 6, h: 3}
    }
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

  defp configure_dashboard_source_health!(now) do
    previous = Application.get_env(:cadence_web, :dashboard_engine_source_execution, [])

    Application.put_env(
      :cadence_web,
      :dashboard_engine_source_execution,
      previous
      |> Keyword.put(:source_health_events?, true)
      |> Keyword.put(:record_source_health_events?, false)
      |> Keyword.put(:now, now)
      |> Keyword.put(:source_health_freshness, %{default_max_age_ms: 86_400_000})
    )

    on_exit(fn ->
      Application.put_env(:cadence_web, :dashboard_engine_source_execution, previous)
    end)
  end

  defp persist_connection_state_resources!(org, mission) do
    source_endpoint =
      SourceEndpoint.new(%{
        source_endpoint_id: "dashboard-source-health-endpoint",
        mission_id: mission.mission_id,
        display_name: "Goldstone Source Health",
        metadata: %{"ground_station_id" => "dss-14"}
      })

    assert {:ok, source_endpoint} =
             Cadence.SourceEndpoints.persist_source_endpoint(org.organization_id, source_endpoint)

    transport =
      Transport.new(%{
        transport_id: "dashboard-source-health-transport",
        mission_id: mission.mission_id,
        display_name: "Source Health Transport",
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

    assert {:ok, transport} =
             TransportStore.persist_transport(org.organization_id, transport)

    {source_endpoint, transport}
  end

  defp record_operational_source_health!(org, mission, observed_at) do
    assert {:ok, event, _status} =
             SourceHealth.record_source_health(
               %{
                 source_health_event_id: "source-health-rendered-operational-observables",
                 organization_id: org.organization_id,
                 mission_id: mission.mission_id,
                 logical_source: :operational_observables,
                 data_source_id:
                   DataSources.default_operational_observables_data_source().data_source_id,
                 source_binding_id:
                   DataSources.default_flight_operational_observables_binding().binding_id,
                 realm: :flight,
                 dataset: "operational_observables",
                 source_health: :degraded,
                 reason: :source_probe_failed,
                 observed_at: observed_at,
                 payload: %{
                   probe_kind: :connection_test,
                   probe_message: "Operational observables source probe degraded"
                 }
               },
               invalidate_runtime_cache?: false
             )

    intervals =
      Cadence.OperationalEvents.source_health_intervals(org.organization_id, mission.mission_id,
        data_source_id: event.data_source_id,
        source_binding_id: event.source_binding_id,
        realm: event.realm,
        dataset: event.dataset,
        at: observed_at,
        order: :asc
      )

    interval =
      case intervals do
        [interval] ->
          interval

        other ->
          flunk("expected one filtered source-health interval, got #{inspect(other)}")
      end

    {event, interval}
  end

  describe "live widget frame evidence" do
    test "opens operational observable source-health interval evidence from rendered frame panel" do
      observed_at = ~U[2026-06-26 12:00:00Z]
      configure_dashboard_source_health!(DateTime.add(observed_at, 60, :second))

      {conn, org, mission} = signed_in_org_and_mission()
      {_source_endpoint, transport} = persist_connection_state_resources!(org, mission)

      {source_health_event, source_health_interval} =
        record_operational_source_health!(org, mission, observed_at)

      dashboard =
        TestFixtures.persist_dashboard_document!(mission,
          name: "Rendered Source Health Evidence",
          widgets: [connection_state_widget()]
        )

      document = fetch_dashboard_document!(org, mission, dashboard)
      matrix_widget = render_item_by_title(document, "Connection State").widget
      matrix_widget_id = matrix_widget.widget_id

      {:ok, view, _html} = live(conn, show_path(mission, dashboard))
      await_dashboard_resolved(view)

      row_selector =
        ~s(#widget-#{matrix_widget_id} [data-status-matrix-row="comms.transport.connection_state:#{transport.transport_id}"])

      assert has_element?(
               view,
               row_selector <>
                 ~s([data-status-matrix-source="operational_observables"][data-status-matrix-data-source-id="#{source_health_event.data_source_id}"][data-status-matrix-source-binding-id="#{source_health_event.source_binding_id}"])
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
               ~s(#dashboard-evidence-inspector [data-evidence-ref-kind="operational interval"][data-evidence-ref-id="#{source_health_interval.source_event_id}"][data-evidence-ref-link-target="operational_event"])
             )

      assert has_element?(
               view,
               ~s(#dashboard-evidence-inspector [data-evidence-ref-kind="source health event"][data-evidence-ref-id="#{source_health_event.source_health_event_id}"])
             )

      assert has_element?(
               view,
               ~s(#dashboard-evidence-copy-link[data-clipboard-text*="panel=evidence"][data-clipboard-text*="selected_evidence_kind=frame"][data-clipboard-text*="selected_observable=comms.transport.connection_state"][data-clipboard-text*="selected_data_source=#{source_health_event.data_source_id}"][data-clipboard-text*="selected_source_binding=#{source_health_event.source_binding_id}"])
             )

      source_health_operational_event_id = source_health_interval.source_event_id

      source_health_operational_event_route_id =
        URI.encode_www_form(source_health_operational_event_id)

      source_health_event_at_ms = DateTime.to_unix(observed_at, :millisecond)

      source_health_event_selector =
        ~s(#dashboard-evidence-inspector [data-evidence-ref-kind="operational interval"][data-evidence-ref-id="#{source_health_operational_event_id}"][data-evidence-ref-link-target="operational_event"])

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
        "realm" => "flight",
        "time-mode" => "live",
        "data-source-id" => source_health_event.data_source_id,
        "source-binding-id" => source_health_event.source_binding_id
      })

      assert has_element?(
               view,
               ~s(#dashboard-data-link-inspector[data-data-link-target="operational_event"][data-data-link-target-id="#{source_health_operational_event_id}"][data-data-link-status="resolved"][data-data-link-selected-data-source-id="#{source_health_event.data_source_id}"][data-data-link-selected-source-binding-id="#{source_health_event.source_binding_id}"])
             )

      source_health_event_path = assert_patch(view)
      assert source_health_event_path =~ "panel=data_link"
      assert source_health_event_path =~ "selected_target=operational_event"
      assert source_health_event_path =~ "selected_id=#{source_health_operational_event_route_id}"
      assert source_health_event_path =~ "selected_time=#{source_health_event_at_ms}"
      assert source_health_event_path =~ "time_mode=live"

      assert has_element?(
               view,
               ~s(#dashboard-data-link-copy-link[data-clipboard-text*="panel=data_link"][data-clipboard-text*="selected_target=operational_event"][data-clipboard-text*="selected_id=#{source_health_operational_event_route_id}"][data-clipboard-text*="data_source_id=#{source_health_event.data_source_id}"][data-clipboard-text*="source_binding_id=#{source_health_event.source_binding_id}"])
             )

      source_health_event_copied_path =
        view
        |> render()
        |> LazyHTML.from_fragment()
        |> LazyHTML.query("#dashboard-data-link-copy-link")
        |> LazyHTML.attribute("data-clipboard-text")
        |> List.first()

      assert source_health_event_copied_path =~ "panel=data_link"
      assert source_health_event_copied_path =~ "selected_target=operational_event"

      assert source_health_event_copied_path =~
               "selected_id=#{source_health_operational_event_route_id}"

      assert source_health_event_copied_path =~ "selected_time=#{source_health_event_at_ms}"

      assert source_health_event_copied_path =~
               "data_source_id=#{source_health_event.data_source_id}"

      assert source_health_event_copied_path =~
               "source_binding_id=#{source_health_event.source_binding_id}"

      {:ok, reopened_source_health_event_view, _html} =
        live(conn, source_health_event_copied_path)

      await_dashboard_resolved(reopened_source_health_event_view)

      assert has_element?(
               reopened_source_health_event_view,
               ~s(#dashboard-data-link-inspector[data-data-link-target="operational_event"][data-data-link-target-id="#{source_health_operational_event_id}"][data-data-link-status="resolved"][data-data-link-selected-data-source-id="#{source_health_event.data_source_id}"][data-data-link-selected-source-binding-id="#{source_health_event.source_binding_id}"])
             )

      assert has_element?(
               reopened_source_health_event_view,
               ~s(#dashboard-data-link-copy-link[data-clipboard-text*="panel=data_link"][data-clipboard-text*="selected_target=operational_event"][data-clipboard-text*="selected_id=#{source_health_operational_event_route_id}"][data-clipboard-text*="selected_time=#{source_health_event_at_ms}"])
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
               "flight"
             )

      assert has_element?(
               reopened_source_health_event_view,
               ~s(#dashboard-data-link-inspector [data-data-link-field="Dataset"]),
               "operational_observables"
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
               "Operational observables source probe degraded"
             )

      stop_dashboard_view(reopened_source_health_event_view)
      stop_dashboard_view(view)
    end

    test "opens resolved, shared, and missing frame evidence panels" do
      {conn, org, mission} = signed_in_org_and_mission()
      spacecraft = TestFixtures.persist_spacecraft!(mission, display_name: "SC Alpha")
      binding_set = persist_binding_set!(org, mission)

      ingest!(mission, binding_set, spacecraft.spacecraft_id, 14, 1_700_000_090)
      ingest!(mission, binding_set, spacecraft.spacecraft_id, 15, 1_700_000_100)

      [_older_sample, latest_sample] =
        TelemetryReads.sample_history(
          org.organization_id,
          mission.mission_id,
          "HK.counter",
          spacecraft_id: spacecraft.spacecraft_id,
          order: :asc
        )

      dashboard =
        TestFixtures.persist_dashboard_document!(mission,
          name: "Frame Evidence",
          widgets: [time_series_widget(spacecraft.spacecraft_id)]
        )

      document = fetch_dashboard_document!(org, mission, dashboard)
      trend_widget = render_item_by_title(document, "Counter Trend").widget
      trend_widget_id = trend_widget.widget_id

      {:ok, view, _html} = live(conn, show_path(mission, dashboard))
      render_dashboard_async(view)

      view
      |> element(~s(#widget-#{trend_widget_id} [data-widget-frame-evidence]))
      |> render_click()

      evidence_path = assert_patch(view)
      assert evidence_path =~ "panel=evidence"
      assert evidence_path =~ "selected_evidence_kind=frame"
      assert evidence_path =~ "selected_placement=#{URI.encode_www_form(trend_widget_id)}"
      assert evidence_path =~ "selected_observable=HK.counter"
      refute evidence_path =~ "selected_link="

      assert has_element?(
               view,
               ~s(#dashboard-evidence-inspector[data-evidence-kind="frame"][data-evidence-status="resolved"])
             )

      assert has_element?(
               view,
               ~s(#ops-dashboard-show-page[data-dashboard-evidence-state="active"][data-dashboard-evidence-kind="frame"][data-dashboard-selection-state="none"])
             )

      assert has_element?(
               view,
               ~s(#ops-dashboard-show-page[data-dashboard-evidence-source-request])
             )

      assert has_element?(
               view,
               ~s(#dashboard-evidence-inspector [data-evidence-subject-field="Observable"]),
               "HK.counter"
             )

      assert has_element?(
               view,
               ~s(#dashboard-evidence-inspector [data-evidence-ref-kind="raw evidence"][data-evidence-ref-id="#{latest_sample.evidence_id}"])
             )

      assert has_element?(
               view,
               ~s(#dashboard-evidence-inspector [data-evidence-link-target="telemetry sample"][data-evidence-link-id="#{latest_sample.sample_id}"])
             )

      assert has_element?(
               view,
               ~s(#dashboard-evidence-copy-link[phx-hook="ClipboardButton"][data-clipboard-text*="/ops/dashboards/#{dashboard.dashboard_id}"][data-clipboard-text*="panel=evidence"][data-clipboard-text*="selected_evidence_kind=frame"][data-clipboard-text*="selected_placement=#{URI.encode_www_form(trend_widget_id)}"][data-clipboard-text*="selected_observable=HK.counter"])
             )

      refute has_element?(
               view,
               ~s(#dashboard-evidence-copy-link[data-clipboard-text*="selected_target="])
             )

      assert has_element?(
               view,
               ~s(#dashboard-evidence-explore[data-dashboard-action-target="telemetry_explore"][data-dashboard-action-source="evidence_panel"][href*="/ops/explore"][href*="point_id=HK.counter"][href*="sample_id="][href*="data_source_id="][href*="source_binding_id="][href*="source_dashboard_id=#{dashboard.dashboard_id}"])
             )

      assert has_element?(
               view,
               ~s(#dashboard-evidence-source-inventory[data-dashboard-action-target="source_inventory"][data-dashboard-action-source="evidence_panel"][href*="/ops/data-sources"][href*="data_source_id="][href*="source_binding_id="][href*="source_dashboard_id=#{dashboard.dashboard_id}"])
             )

      {:ok, evidence_view, _html} = live(conn, evidence_path)
      render_dashboard_async(evidence_view)

      assert has_element?(
               evidence_view,
               ~s(#dashboard-evidence-inspector[data-evidence-kind="frame"][data-evidence-subject])
             )

      assert has_element?(
               evidence_view,
               ~s(#ops-dashboard-show-page[data-dashboard-evidence-state="active"][data-dashboard-evidence-kind="frame"][data-dashboard-selection-state="none"])
             )

      assert has_element?(
               evidence_view,
               ~s(#dashboard-evidence-inspector [data-evidence-subject-field="Observable"]),
               "HK.counter"
             )

      missing_frame_path =
        ~p"/missions/#{mission.mission_id}/ops/dashboards/#{dashboard.dashboard_id}?#{%{panel: "evidence", selected_evidence_kind: "frame", selected_placement: trend_widget_id, selected_observable: "HK.missing", selected_target: "contact", selected_id: "ignored-contact"}}"

      {:ok, missing_frame_view, _html} = live(conn, missing_frame_path)
      render_dashboard_async(missing_frame_view)

      assert has_element?(
               missing_frame_view,
               ~s(#dashboard-evidence-inspector[data-evidence-kind="frame"][data-evidence-status="missing"][data-evidence-subject="HK.missing"])
             )

      assert has_element?(
               missing_frame_view,
               ~s(#ops-dashboard-show-page[data-dashboard-evidence-state="missing"][data-dashboard-evidence-kind="frame"][data-dashboard-selection-state="none"])
             )

      assert has_element?(
               missing_frame_view,
               ~s(#dashboard-evidence-inspector [data-evidence-subject-field="Observable"]),
               "HK.missing"
             )

      assert has_element?(
               missing_frame_view,
               ~s(#dashboard-evidence-copy-link[data-clipboard-text*="panel=evidence"][data-clipboard-text*="selected_evidence_kind=frame"][data-clipboard-text*="selected_observable=HK.missing"])
             )

      refute has_element?(
               missing_frame_view,
               ~s(#dashboard-evidence-copy-link[data-clipboard-text*="selected_target="])
             )

      view |> element(~s(#dashboard-panel button[aria-label="Close panel"])) |> render_click()
      cleared_evidence_path = assert_patch(view)
      refute cleared_evidence_path =~ "panel="
      refute cleared_evidence_path =~ "selected_evidence_kind="

      assert has_element?(
               view,
               ~s(#ops-dashboard-show-page[data-dashboard-evidence-state="none"])
             )
    end
  end
end
