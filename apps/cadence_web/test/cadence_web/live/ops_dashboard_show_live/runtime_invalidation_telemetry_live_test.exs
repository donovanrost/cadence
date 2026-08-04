defmodule CadenceWeb.OpsDashboardShowLive.RuntimeInvalidationTelemetryLiveTest do
  use CadenceWeb.ConnCase, async: false

  import Phoenix.LiveViewTest

  alias Cadence.Runtime.Persistence, as: RuntimePersistence

  alias Phoenix.LiveViewTest.ClientProxy

  use Phoenix.VerifiedRoutes,
    endpoint: CadenceWeb.Endpoint,
    router: CadenceWeb.Router,
    statics: CadenceWeb.static_paths()

  alias Cadence.ApplicationDispatch.{BindingRule, BindingSet, CapabilityInstance}
  alias Cadence.Dashboards.{Document, RenderItem, RuntimeInvalidation}
  alias Cadence.Ingress.RawEvidence
  alias Cadence.Management.DataSources
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

  defp chart_dom_id(html, widget_id) do
    [id] =
      html
      |> LazyHTML.from_fragment()
      |> LazyHTML.query(~s([id^="tlm-chart-#{widget_id}-"]))
      |> LazyHTML.attribute("id")

    id
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

  describe "runtime invalidation telemetry surfaces" do
    test "data source binding runtime invalidation refreshes live telemetry widgets" do
      {conn, org, mission} = signed_in_org_and_mission()
      spacecraft = TestFixtures.persist_spacecraft!(mission, display_name: "SC Source Binding")
      binding_set = persist_binding_set!(org, mission)
      ingest!(mission, binding_set, spacecraft.spacecraft_id, 15, 1_700_000_100)

      dashboard =
        TestFixtures.persist_dashboard_document!(mission,
          name: "Telemetry Binding Refresh",
          widgets: [value_tile("HK.counter", :fixed, spacecraft.spacecraft_id)]
        )

      {:ok, view, _html} = live(conn, show_path(mission, dashboard))
      render_dashboard_async(view)

      assert %{plans: _plans, source_results: _source_results, frames: _frames} =
               RuntimeInvalidation.data_source_binding_changed(%{
                 organization_id: org.organization_id,
                 mission_id: mission.mission_id,
                 logical_source: :telemetry,
                 observable: "HK.counter",
                 data_source_id: "flight-questdb-v2"
               })

      render_dashboard_async(view)

      assert has_element?(
               view,
               ~s(#ops-dashboard-show-page[data-engine-resolve-mode="context_change"][data-runtime-last-invalidation-boundary="data_source_binding_changed"][data-runtime-last-invalidation-refresh-reason="runtime_invalidation"])
             )
    end

    test "data source binding runtime invalidation follows overlay source relevance" do
      {conn, org, mission} = signed_in_org_and_mission()
      spacecraft = TestFixtures.persist_spacecraft!(mission, display_name: "SC Overlay Binding")
      binding_set = persist_binding_set!(org, mission)
      ingest!(mission, binding_set, spacecraft.spacecraft_id, 15, 1_700_000_100)

      dashboard =
        TestFixtures.persist_dashboard_document!(mission,
          name: "Overlay Binding Refresh",
          widgets: [
            %{
              type: :time_series,
              title: "Counter Trend",
              binding: %{
                mode: :fixed,
                spacecraft_id: spacecraft.spacecraft_id,
                point_id: "HK.counter"
              }
            }
          ]
        )

      document = fetch_dashboard_document!(org, mission, dashboard)
      trend_widget = render_item_by_title(document, "Counter Trend").widget

      {:ok, view, _html} = live(conn, show_path(mission, dashboard))
      initial_html = render_dashboard_async(view)
      initial_chart_id = chart_dom_id(initial_html, trend_widget.widget_id)

      assert %{plans: _plans, source_results: _source_results, frames: _frames} =
               RuntimeInvalidation.data_source_binding_changed(%{
                 organization_id: org.organization_id,
                 mission_id: mission.mission_id,
                 logical_source: :events,
                 data_source_id: "events-questdb-v2"
               })

      refreshed_html = render_dashboard_async(view)

      assert has_element?(
               view,
               ~s(#ops-dashboard-show-page[data-engine-resolve-mode="context_change"][data-runtime-last-invalidation-boundary="data_source_binding_changed"][data-runtime-last-invalidation-refresh-reason="runtime_invalidation"])
             )

      assert chart_dom_id(refreshed_html, trend_widget.widget_id) == initial_chart_id
    end

    test "source health runtime invalidation refreshes live telemetry widgets" do
      {conn, org, mission} = signed_in_org_and_mission()
      spacecraft = TestFixtures.persist_spacecraft!(mission, display_name: "SC Health")
      binding_set = persist_binding_set!(org, mission)
      ingest!(mission, binding_set, spacecraft.spacecraft_id, 15, 1_700_000_100)

      dashboard =
        TestFixtures.persist_dashboard_document!(mission,
          name: "Telemetry Health Refresh",
          widgets: [value_tile("HK.counter", :fixed, spacecraft.spacecraft_id)]
        )

      {:ok, view, _html} = live(conn, show_path(mission, dashboard))
      render_dashboard_async(view)

      assert %{plans: _plans, source_results: _source_results, frames: _frames} =
               RuntimeInvalidation.source_health_changed(%{
                 organization_id: org.organization_id,
                 mission_id: mission.mission_id,
                 logical_source: :telemetry,
                 data_source_id: DataSources.default_managed_data_source().data_source_id,
                 source_health: :degraded,
                 previous_source_health: :healthy,
                 reason: :source_probe_failed
               })

      render_dashboard_async(view)

      assert has_element?(
               view,
               ~s(#ops-dashboard-show-page[data-engine-resolve-mode="context_change"][data-runtime-last-invalidation-boundary="source_health_changed"][data-runtime-last-invalidation-refresh-reason="runtime_invalidation"][data-runtime-invalidation-boundaries*="source_health_changed:1"])
             )
    end

    test "source health runtime invalidation follows overlay source relevance" do
      {conn, org, mission} = signed_in_org_and_mission()
      spacecraft = TestFixtures.persist_spacecraft!(mission, display_name: "SC Event Health")
      binding_set = persist_binding_set!(org, mission)
      ingest!(mission, binding_set, spacecraft.spacecraft_id, 15, 1_700_000_100)

      dashboard =
        TestFixtures.persist_dashboard_document!(mission,
          name: "Overlay Health Refresh",
          widgets: [
            %{
              type: :time_series,
              title: "Counter Trend",
              binding: %{
                mode: :fixed,
                spacecraft_id: spacecraft.spacecraft_id,
                point_id: "HK.counter"
              }
            }
          ]
        )

      document = fetch_dashboard_document!(org, mission, dashboard)
      trend_widget = render_item_by_title(document, "Counter Trend").widget

      {:ok, view, _html} = live(conn, show_path(mission, dashboard))
      initial_html = render_dashboard_async(view)
      initial_chart_id = chart_dom_id(initial_html, trend_widget.widget_id)

      assert %{plans: _plans, source_results: _source_results, frames: _frames} =
               RuntimeInvalidation.source_health_changed(%{
                 organization_id: org.organization_id,
                 mission_id: mission.mission_id,
                 logical_source: :events,
                 data_source_id: DataSources.default_events_data_source().data_source_id,
                 source_health: :degraded,
                 previous_source_health: :healthy,
                 reason: :source_probe_failed
               })

      refreshed_html = render_dashboard_async(view)

      assert has_element?(
               view,
               ~s(#ops-dashboard-show-page[data-engine-resolve-mode="context_change"][data-runtime-last-invalidation-boundary="source_health_changed"][data-runtime-last-invalidation-refresh-reason="runtime_invalidation"])
             )

      assert chart_dom_id(refreshed_html, trend_widget.widget_id) == initial_chart_id
    end

    test "source watermark runtime invalidation refreshes live telemetry widgets" do
      {conn, org, mission} = signed_in_org_and_mission()
      spacecraft = TestFixtures.persist_spacecraft!(mission, display_name: "SC Watermark")
      binding_set = persist_binding_set!(org, mission)
      ingest!(mission, binding_set, spacecraft.spacecraft_id, 15, 1_700_000_100)

      dashboard =
        TestFixtures.persist_dashboard_document!(mission,
          name: "Telemetry Watermark Refresh",
          widgets: [value_tile("HK.counter", :fixed, spacecraft.spacecraft_id)]
        )

      {:ok, view, _html} = live(conn, show_path(mission, dashboard))
      render_dashboard_async(view)

      assert %{plans: _plans, source_results: _source_results, frames: _frames} =
               RuntimeInvalidation.source_watermark_changed(%{
                 organization_id: org.organization_id,
                 mission_id: mission.mission_id,
                 logical_source: :telemetry,
                 observable: "HK.counter",
                 data_source_id: DataSources.default_managed_data_source().data_source_id
               })

      render_dashboard_async(view)

      assert has_element?(
               view,
               ~s(#ops-dashboard-show-page[data-engine-resolve-mode="context_change"][data-runtime-last-invalidation-boundary="source_watermark_changed"][data-runtime-last-invalidation-refresh-reason="runtime_invalidation"][data-runtime-invalidation-boundaries*="source_watermark_changed"])
             )
    end

    test "source watermark runtime invalidation follows overlay source relevance" do
      {conn, org, mission} = signed_in_org_and_mission()
      spacecraft = TestFixtures.persist_spacecraft!(mission, display_name: "SC Event Watermark")
      binding_set = persist_binding_set!(org, mission)
      ingest!(mission, binding_set, spacecraft.spacecraft_id, 15, 1_700_000_100)

      dashboard =
        TestFixtures.persist_dashboard_document!(mission,
          name: "Overlay Watermark Refresh",
          widgets: [
            %{
              type: :time_series,
              title: "Counter Trend",
              binding: %{
                mode: :fixed,
                spacecraft_id: spacecraft.spacecraft_id,
                point_id: "HK.counter"
              }
            }
          ]
        )

      document = fetch_dashboard_document!(org, mission, dashboard)
      trend_widget = render_item_by_title(document, "Counter Trend").widget

      {:ok, view, _html} = live(conn, show_path(mission, dashboard))
      initial_html = render_dashboard_async(view)
      initial_chart_id = chart_dom_id(initial_html, trend_widget.widget_id)

      assert %{plans: _plans, source_results: _source_results, frames: _frames} =
               RuntimeInvalidation.source_watermark_changed(%{
                 organization_id: org.organization_id,
                 mission_id: mission.mission_id,
                 logical_source: :events,
                 data_source_id: DataSources.default_events_data_source().data_source_id
               })

      refreshed_html = render_dashboard_async(view)

      assert has_element?(
               view,
               ~s(#ops-dashboard-show-page[data-engine-resolve-mode="context_change"][data-runtime-last-invalidation-boundary="source_watermark_changed"][data-runtime-last-invalidation-refresh-reason="runtime_invalidation"])
             )

      assert chart_dom_id(refreshed_html, trend_widget.widget_id) == initial_chart_id
    end

    test "source watermark runtime invalidation skips unrelated observables" do
      {conn, org, mission} = signed_in_org_and_mission()
      spacecraft = TestFixtures.persist_spacecraft!(mission, display_name: "SC Other Watermark")
      binding_set = persist_binding_set!(org, mission)
      ingest!(mission, binding_set, spacecraft.spacecraft_id, 15, 1_700_000_100)

      dashboard =
        TestFixtures.persist_dashboard_document!(mission,
          name: "Watermark Observable Mismatch",
          widgets: [value_tile("HK.counter", :fixed, spacecraft.spacecraft_id)]
        )

      {:ok, view, _html} = live(conn, show_path(mission, dashboard))
      render_dashboard_async(view)

      assert %{plans: _plans, source_results: _source_results, frames: _frames} =
               RuntimeInvalidation.source_watermark_changed(%{
                 organization_id: org.organization_id,
                 mission_id: mission.mission_id,
                 logical_source: :telemetry,
                 observable: "HK.voltage",
                 data_source_id: DataSources.default_managed_data_source().data_source_id
               })

      render_dashboard_async(view)

      assert has_element?(
               view,
               ~s(#ops-dashboard-show-page[data-engine-resolve-mode="initial"])
             )

      refute has_element?(
               view,
               ~s(#ops-dashboard-show-page[data-runtime-last-invalidation-boundary="source_watermark_changed"])
             )
    end
  end
end
