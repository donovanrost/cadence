defmodule CadenceWeb.OpsDashboardShowLive.LiveWidgetRawEvidenceNavigationLiveTest do
  use CadenceWeb.ConnCase, async: false

  import Phoenix.LiveViewTest

  alias Phoenix.LiveViewTest.ClientProxy

  use Phoenix.VerifiedRoutes,
    endpoint: CadenceWeb.Endpoint,
    router: CadenceWeb.Router,
    statics: CadenceWeb.static_paths()

  alias Cadence.ApplicationDispatch.{BindingRule, BindingSet}
  alias Cadence.Dashboards.{DataSources, Document, RenderItem}
  alias Cadence.Ingress.RawEvidence
  alias Cadence.Telemetry.PacketDefinition
  alias CadenceWeb.TestFixtures

  defp signed_in_org_and_mission do
    user = TestFixtures.persist_user!()
    org = TestFixtures.persist_org!()
    _membership = TestFixtures.grant_membership!(user, org)
    mission = TestFixtures.persist_mission!(org, slug: "ops", display_name: "Ops Mission")
    {TestFixtures.member_conn(user), org, mission}
  end

  defp persist_binding_set!(org, mission) do
    packet_definition =
      PacketDefinition.new(%{
        mission_id: mission.mission_id,
        packet_definition_id: "hk-raw-evidence",
        packet_name: "HK",
        apid: 45,
        fields: [%{name: "counter", offset_bits: 0, size_bits: 16, data_type: :uint}]
      })

    binding_set =
      BindingSet.new(%{
        mission_id: mission.mission_id,
        binding_set_id: mission.mission_id <> "-raw-evidence-binding-set",
        version: 1,
        rules: [
          BindingRule.new(%{
            handler_key: :definition_bound_telemetry,
            packet_kind: :space_packet,
            apid: 45,
            handler_configuration: packet_definition
          })
        ]
      })

    {:ok, persisted} = Cadence.persist_binding_set(org.organization_id, binding_set)
    persisted
  end

  defp ingest!(mission, binding_set, spacecraft_id, value, unix_seconds) do
    evidence =
      RawEvidence.new(%{
        mission_id: mission.mission_id,
        spacecraft_id: spacecraft_id,
        receipt_time: DateTime.from_unix!(unix_seconds, :second),
        raw: build_space_packet(45, 1, <<value::16>>)
      })

    {:ok, _result} =
      Cadence.process_and_persist_telemetry_ingress(
        evidence,
        binding_set.binding_set_id,
        binding_set.version
      )
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

  defp disable_telemetry_storage_runtime_invalidation! do
    previous_config = Application.get_env(:cadence, :telemetry_storage, [])

    Application.put_env(
      :cadence,
      :telemetry_storage,
      Keyword.put(previous_config, :dashboard_runtime_invalidation?, false)
    )

    on_exit(fn ->
      Application.put_env(:cadence, :telemetry_storage, previous_config)
    end)
  end

  describe "live widget raw evidence navigation" do
    test "preserves telemetry sample context through raw evidence navigation" do
      disable_telemetry_storage_runtime_invalidation!()

      {conn, org, mission} = signed_in_org_and_mission()
      spacecraft = TestFixtures.persist_spacecraft!(mission, display_name: "SC Alpha")
      binding_set = persist_binding_set!(org, mission)

      ingest!(mission, binding_set, spacecraft.spacecraft_id, 14, 1_700_000_090)
      ingest!(mission, binding_set, spacecraft.spacecraft_id, 15, 1_700_000_100)

      dashboard =
        TestFixtures.persist_dashboard_document!(mission,
          name: "Power",
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

      latest_sample =
        org.organization_id
        |> Cadence.telemetry_history(mission.mission_id, "HK.counter",
          spacecraft_id: spacecraft.spacecraft_id,
          order: :asc
        )
        |> List.last()

      latest_sample_timestamp_ms = DateTime.to_unix(latest_sample.receipt_time, :millisecond)
      telemetry_data_source_id = DataSources.default_managed_data_source().data_source_id

      {:ok, view, _html} = live(conn, show_path(mission, dashboard))
      render_dashboard_async(view)

      assert has_element?(
               view,
               ~s(#widget-#{trend_widget.widget_id} [data-widget-data-link-target="telemetry sample"][data-widget-data-link-id="#{latest_sample.sample_id}"][phx-value-target="telemetry_sample"][phx-value-target-id="#{latest_sample.sample_id}"][phx-value-placement-id="#{trend_widget.widget_id}"][phx-value-timestamp-ms="#{latest_sample_timestamp_ms}"])
             )

      view
      |> element(
        ~s(#widget-#{trend_widget.widget_id} [data-widget-data-link-target="telemetry sample"][data-widget-data-link-id="#{latest_sample.sample_id}"])
      )
      |> render_click()

      latest_sample_path = assert_patch(view)
      assert latest_sample_path =~ "panel=data_link"
      assert latest_sample_path =~ "selected_target=telemetry_sample"
      assert latest_sample_path =~ "selected_id=#{URI.encode_www_form(latest_sample.sample_id)}"
      assert latest_sample_path =~ "selected_time=#{latest_sample_timestamp_ms}"
      assert latest_sample_path =~ "realm=flight"
      assert latest_sample_path =~ "data_source_id=#{telemetry_data_source_id}"
      assert latest_sample_path =~ "source_binding_id=default_flight_telemetry"

      assert has_element?(
               view,
               ~s(#dashboard-data-link-inspector[data-data-link-target="telemetry_sample"][data-data-link-status="resolved"])
             )

      assert has_element?(
               view,
               ~s(#dashboard-data-link-inspector [data-data-link-field="Raw"]),
               "15"
             )

      assert has_element?(
               view,
               ~s(#dashboard-data-link-inspector [data-data-link-context="Data source"]),
               telemetry_data_source_id
             )

      assert has_element?(
               view,
               ~s(#dashboard-data-link-inspector [data-data-link-context="Source binding"]),
               "default_flight_telemetry"
             )

      assert has_element?(
               view,
               ~s(#dashboard-data-link-inspector [data-data-link-related-target="raw evidence"])
             )

      view
      |> element(
        ~s(#dashboard-data-link-inspector [data-data-link-related-target="raw evidence"])
      )
      |> render_click()

      raw_evidence_path = assert_patch(view)
      assert raw_evidence_path =~ "panel=data_link"
      assert raw_evidence_path =~ "selected_target=raw_evidence"
      assert raw_evidence_path =~ "selected_id=#{URI.encode_www_form(latest_sample.evidence_id)}"
      assert raw_evidence_path =~ "nav_from_target=telemetry_sample"

      assert raw_evidence_path =~
               "nav_from_target_id=#{URI.encode_www_form(latest_sample.sample_id)}"

      refute raw_evidence_path =~ "nav_from_relationship_kind=nil"
      assert raw_evidence_path =~ "nav_trail="
      assert raw_evidence_path =~ "realm=flight"
      assert raw_evidence_path =~ "data_source_id=#{telemetry_data_source_id}"
      assert raw_evidence_path =~ "source_binding_id=default_flight_telemetry"

      assert has_element?(
               view,
               ~s(#dashboard-data-link-inspector[data-data-link-target="raw_evidence"][data-data-link-status="resolved"])
             )

      assert has_element?(
               view,
               ~s(#dashboard-data-link-inspector [data-data-link-field="Raw bytes"]),
               "8"
             )

      assert has_element?(
               view,
               ~s(#dashboard-data-link-inspector [data-data-link-context="Data source"]),
               telemetry_data_source_id
             )

      assert has_element?(
               view,
               ~s(#dashboard-data-link-inspector [data-data-link-context="Source binding"]),
               "default_flight_telemetry"
             )

      assert has_element?(
               view,
               ~s(#dashboard-data-link-inspector [data-data-link-related-target="telemetry sample"])
             )

      assert has_element?(
               view,
               ~s(#dashboard-data-link-copy-link[data-clipboard-text*="/ops/dashboards/#{dashboard.dashboard_id}"][data-clipboard-text*="panel=data_link"][data-clipboard-text*="selected_target=raw_evidence"][data-clipboard-text*="selected_id=#{URI.encode_www_form(latest_sample.evidence_id)}"][data-clipboard-text*="nav_from_target=telemetry_sample"][data-clipboard-text*="nav_from_target_id=#{URI.encode_www_form(latest_sample.sample_id)}"][data-clipboard-text*="realm=flight"][data-clipboard-text*="data_source_id=#{telemetry_data_source_id}"][data-clipboard-text*="source_binding_id=default_flight_telemetry"])
             )

      assert has_element?(
               view,
               ~s(#dashboard-data-link-inspector [data-data-link-navigation] [data-data-link-nav-entry-id="#{latest_sample.sample_id}"])
             )

      assert has_element?(
               view,
               ~s(#dashboard-data-link-inspector [data-data-link-navigation] [data-data-link-nav-entry-id="#{latest_sample.sample_id}"][phx-value-placement-id="#{trend_widget.widget_id}"][phx-value-timestamp-ms="#{latest_sample_timestamp_ms}"])
             )

      {:ok, shared_raw_evidence_view, _html} = live(conn, raw_evidence_path)
      render_dashboard_async(shared_raw_evidence_view)

      assert has_element?(
               shared_raw_evidence_view,
               ~s(#dashboard-data-link-inspector[data-data-link-target="raw_evidence"][data-data-link-status="resolved"])
             )

      assert has_element?(
               shared_raw_evidence_view,
               ~s(#dashboard-data-link-inspector [data-data-link-context="Data source"]),
               telemetry_data_source_id
             )

      assert has_element?(
               shared_raw_evidence_view,
               ~s(#dashboard-data-link-inspector [data-data-link-navigation] [data-data-link-nav-entry-id="#{latest_sample.sample_id}"])
             )

      view
      |> element(
        ~s(#dashboard-data-link-inspector [data-data-link-navigation] [data-data-link-nav-entry-id="#{latest_sample.sample_id}"])
      )
      |> render_click()

      sample_back_path = assert_patch(view)
      assert sample_back_path =~ "panel=data_link"
      assert sample_back_path =~ "selected_target=telemetry_sample"
      assert sample_back_path =~ "selected_id=#{URI.encode_www_form(latest_sample.sample_id)}"
      assert sample_back_path =~ "realm=flight"
      assert sample_back_path =~ "data_source_id=#{telemetry_data_source_id}"
      assert sample_back_path =~ "source_binding_id=default_flight_telemetry"

      assert has_element?(
               view,
               ~s(#dashboard-data-link-inspector[data-data-link-target="telemetry_sample"][data-data-link-status="resolved"])
             )
    end
  end
end
