defmodule CadenceWeb.OpsDashboardShowLive.RuntimeScopeLiveTest do
  use CadenceWeb.ConnCase, async: false

  import Phoenix.LiveViewTest

  alias Cadence.Runtime.Persistence, as: RuntimePersistence

  alias Phoenix.LiveViewTest.ClientProxy

  use Phoenix.VerifiedRoutes,
    endpoint: CadenceWeb.Endpoint,
    router: CadenceWeb.Router,
    statics: CadenceWeb.static_paths()

  alias Cadence.ApplicationDispatch.{BindingRule, BindingSet, CapabilityInstance}
  alias Cadence.Contacts.{Path, ScheduledContact}
  alias Cadence.Dashboards.{Document, RenderItem}
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

  defp value_tile(point_id, mode, spacecraft_id) do
    %{
      type: :value_tile,
      title: "Counter",
      binding: %{mode: mode, spacecraft_id: spacecraft_id, point_id: point_id}
    }
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

  defp ingest!(mission, binding_set, spacecraft_id, value, unix_seconds, opts) do
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

  defp chart_event_markers(html, widget_id) do
    chart_attribute(html, widget_id, "data-event-markers")
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

  defp chart_attribute(html, widget_id, attribute) do
    [value] =
      html
      |> LazyHTML.from_fragment()
      |> LazyHTML.query(~s([id^="tlm-chart-#{widget_id}-"]))
      |> LazyHTML.attribute(attribute)

    Jason.decode!(value)
  end

  test "explicit generic scope URL drives the dashboard runtime context" do
    {conn, org, mission} = signed_in_org_and_mission()
    spacecraft = TestFixtures.persist_spacecraft!(mission, display_name: "SC Alpha")
    other_spacecraft = TestFixtures.persist_spacecraft!(mission, display_name: "SC Beta")
    binding_set = persist_binding_set!(org, mission)

    scheduled_contact =
      ScheduledContact.new(%{
        scheduled_contact_id: "dashboard-runtime-scope-contact",
        mission_id: mission.mission_id,
        source_endpoint_refs: ["source-endpoint-alpha"],
        paths: contact_paths("source-endpoint-alpha"),
        starts_at: DateTime.from_unix!(1_700_000_080, :second),
        ends_at: DateTime.from_unix!(1_700_000_220, :second)
      })

    assert {:ok, _scheduled_contact} =
             Cadence.Contacts.persist_scheduled_contact(org.organization_id, scheduled_contact)

    ingest!(mission, binding_set, spacecraft.spacecraft_id, 15, 1_700_000_100,
      source_endpoint_id: "source-endpoint-alpha"
    )

    dashboard =
      TestFixtures.persist_dashboard_document!(mission,
        name: "Scoped Power",
        widgets: [
          %{
            type: :time_series,
            title: "Counter Trend",
            binding: %{
              mode: :fixed,
              spacecraft_id: spacecraft.spacecraft_id,
              point_id: "HK.counter"
            },
            layout: %{x: 0, y: 0, w: 6, h: 3}
          }
        ]
      )

    document = fetch_dashboard_document!(org, mission, dashboard)
    trend_widget = render_item_by_title(document, "Counter Trend").widget

    {:ok, view, _html} =
      live(
        conn,
        ~p"/missions/#{mission.mission_id}/ops/dashboards/#{dashboard.dashboard_id}?#{%{scope_kind: "contact", scope_id: scheduled_contact.scheduled_contact_id, spacecraft_id: other_spacecraft.spacecraft_id}}"
      )

    html = render_dashboard_async(view)

    assert has_element?(
             view,
             ~s(#ops-dashboard-show-page[data-dashboard-scope-kind="contact"][data-dashboard-scope-id="#{scheduled_contact.scheduled_contact_id}"])
           )

    refute Enum.any?(
             chart_event_markers(html, trend_widget.widget_id),
             &(&1["marker_type"] == "contact_interval")
           )
  end

  test "source-endpoint-scoped telemetry no-data exposes endpoint filter diagnostics" do
    {conn, org, mission} = signed_in_org_and_mission()
    spacecraft = TestFixtures.persist_spacecraft!(mission, display_name: "SC Alpha")
    binding_set = persist_binding_set!(org, mission)

    source_endpoint =
      SourceEndpoint.new(%{
        source_endpoint_id: "dashboard-runtime-empty-endpoint",
        mission_id: mission.mission_id,
        display_name: "Empty Endpoint",
        metadata: %{"ground_station_id" => "dss-empty"}
      })

    assert {:ok, _source_endpoint} =
             Cadence.SourceEndpoints.persist_source_endpoint(org.organization_id, source_endpoint)

    ingest!(mission, binding_set, spacecraft.spacecraft_id, 15, 1_700_000_100,
      source_endpoint_id: "source-endpoint-beta"
    )

    dashboard =
      TestFixtures.persist_dashboard_document!(mission,
        name: "Endpoint Empty Power",
        widgets: [
          %{
            type: :time_series,
            title: "Counter Trend",
            binding: %{
              mode: :fixed,
              spacecraft_id: spacecraft.spacecraft_id,
              point_id: "HK.counter"
            },
            layout: %{x: 0, y: 0, w: 6, h: 3}
          }
        ]
      )

    document = fetch_dashboard_document!(org, mission, dashboard)
    trend_item = render_item_by_title(document, "Counter Trend")

    {:ok, view, _html} =
      live(
        conn,
        ~p"/missions/#{mission.mission_id}/ops/dashboards/#{dashboard.dashboard_id}?#{%{scope_kind: "source_endpoint", scope_id: source_endpoint.source_endpoint_id}}"
      )

    render_dashboard_async(view)

    widget_selector = "#widget-#{trend_item.placement_id}"

    assert has_element?(
             view,
             ~s(#ops-dashboard-show-page[data-dashboard-scope-kind="source_endpoint"][data-dashboard-scope-id="#{source_endpoint.source_endpoint_id}"])
           )

    assert has_element?(
             view,
             ~s(#{widget_selector}[data-widget-source-data-state="no_data"][data-widget-source-empty-reason="source_endpoint_scope_no_data"])
           )

    assert has_element?(
             view,
             ~s(#{widget_selector}[data-widget-source-scope-kinds="spacecraft"][data-widget-source-source-endpoint-ids="#{source_endpoint.source_endpoint_id}"])
           )

    assert has_element?(
             view,
             ~s(#{widget_selector}[data-widget-source-contact-ids=""])
           )

    assert has_element?(
             view,
             ~s(#{widget_selector} button[data-widget-source-badge="unknown"][data-widget-source-badge-inventory-action="source_inventory"][data-widget-source-badge-inventory-href*="/ops/data-sources"][data-widget-source-badge-inventory-href*="source_endpoint_id=#{source_endpoint.source_endpoint_id}"])
           )

    assert has_element?(
             view,
             ~s(#{widget_selector} [data-widget-query-diagnostics][data-widget-query-source-state="unknown"][data-widget-query-data-view="canonical"][data-widget-query-time-modes="live"][data-widget-query-source-endpoint-ids="#{source_endpoint.source_endpoint_id}"])
           )

    view
    |> element(~s(#{widget_selector} [data-widget-query-evidence-open]))
    |> render_click()

    query_evidence_path = assert_patch(view)
    assert query_evidence_path =~ "panel=evidence"
    assert query_evidence_path =~ "selected_evidence_kind=query"
    assert query_evidence_path =~ "selected_widget_title=Counter+Trend"
    assert query_evidence_path =~ "selected_source_evidence_state=unknown"

    assert query_evidence_path =~
             "selected_source_endpoint_id=#{source_endpoint.source_endpoint_id}"

    assert query_evidence_path =~ "selected_contact_id=nil"

    assert has_element?(
             view,
             ~s(#dashboard-evidence-inspector[data-evidence-kind="query"][data-evidence-status="unknown"][data-evidence-subject="Counter Trend"])
           )

    assert has_element?(
             view,
             ~s(#dashboard-evidence-inspector [data-evidence-detail="Source endpoint"]),
             source_endpoint.source_endpoint_id
           )

    assert has_element?(
             view,
             ~s(#dashboard-evidence-copy-link[data-clipboard-text*="panel=evidence"][data-clipboard-text*="selected_evidence_kind=query"][data-clipboard-text*="selected_widget_title=Counter+Trend"][data-clipboard-text*="selected_source_endpoint_id=#{source_endpoint.source_endpoint_id}"])
           )

    assert has_element?(
             view,
             ~s(#dashboard-evidence-source-inventory[href*="source_endpoint_id=#{source_endpoint.source_endpoint_id}"][href*="source_dashboard_id=#{dashboard.dashboard_id}"])
           )

    view
    |> element(~s(#{widget_selector} button[data-widget-source-badge="unknown"]))
    |> render_click()

    assert has_element?(
             view,
             ~s(#dashboard-evidence-inspector[data-evidence-kind="source"][data-evidence-status="unknown"])
           )

    assert has_element?(
             view,
             ~s(#dashboard-evidence-inspector [data-evidence-detail="Source endpoint"]),
             source_endpoint.source_endpoint_id
           )

    assert render(view) =~
             "Widget source status is unknown; source health or watermark evidence could not prove freshness for this value."

    assert has_element?(
             view,
             ~s(#dashboard-evidence-source-health[href*="source_endpoint_id=#{source_endpoint.source_endpoint_id}"][href*="source_dashboard_id=#{dashboard.dashboard_id}"])
           )
  end

  test "mission scope URL drives the dashboard runtime context" do
    {conn, _org, mission} = signed_in_org_and_mission()
    spacecraft = TestFixtures.persist_spacecraft!(mission, display_name: "SC Alpha")

    dashboard =
      TestFixtures.persist_dashboard_document!(mission,
        name: "Validated Scope",
        widgets: [value_tile("HK.counter", :fixed, spacecraft.spacecraft_id)]
      )

    {:ok, mission_scope_view, _html} =
      live(
        conn,
        ~p"/missions/#{mission.mission_id}/ops/dashboards/#{dashboard.dashboard_id}?#{%{scope_kind: "mission", scope_id: mission.mission_id}}"
      )

    render_dashboard_async(mission_scope_view)

    assert has_element?(
             mission_scope_view,
             ~s(#ops-dashboard-show-page[data-dashboard-scope-kind="mission"][data-dashboard-scope-id="#{mission.mission_id}"])
           )
  end
end
