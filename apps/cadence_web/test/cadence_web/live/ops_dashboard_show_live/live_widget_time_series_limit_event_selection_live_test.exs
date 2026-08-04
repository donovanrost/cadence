defmodule CadenceWeb.OpsDashboardShowLive.LiveWidgetTimeSeriesLimitEventSelectionLiveTest do
  alias Cadence.Reads.Telemetry, as: TelemetryReads
  alias Cadence.Runtime.Persistence, as: RuntimePersistence
  use CadenceWeb.ConnCase, async: false

  @moduletag :config

  import Phoenix.LiveViewTest

  alias Phoenix.LiveViewTest.ClientProxy

  use Phoenix.VerifiedRoutes,
    endpoint: CadenceWeb.Endpoint,
    router: CadenceWeb.Router,
    statics: CadenceWeb.static_paths()

  alias Cadence.ApplicationDispatch.{BindingRule, BindingSet, CapabilityInstance}
  alias Cadence.Dashboards.{Document, RenderItem}
  alias Cadence.Ingress.RawEvidence
  alias Cadence.Limits.Definition
  alias Cadence.Management.DataSources
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
        packet_definition_id: "hk-counter-limit-selection",
        packet_name: "HK",
        apid: 42,
        fields: [%{name: "counter", offset_bits: 0, size_bits: 16, data_type: :uint}]
      })

    binding_set =
      BindingSet.new(%{
        mission_id: mission.mission_id,
        binding_set_id: mission.mission_id <> "-limit-selection-binding-set",
        version: 1,
        capability_instances: [
          CapabilityInstance.new(%{
            capability_instance_id: mission.mission_id <> "-limit-selection-instance",
            family_key: :definition_bound_telemetry,
            target_scope: :mission,
            runtime_configuration: packet_definition
          })
        ],
        rules: [
          BindingRule.new(%{
            binding_rule_id: mission.mission_id <> "-limit-selection-rule",
            capability_instance_id: mission.mission_id <> "-limit-selection-instance",
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

  defp evaluate_limits!(mission) do
    limit_definition =
      Definition.new(%{
        mission_id: mission.mission_id,
        limit_definition_id: "counter-limits",
        point_id: "HK.counter",
        thresholds: %{"yellow_high" => 10, "red_high" => 20}
      })

    {:ok, _definition} = Cadence.Limits.persist_limit_definition(limit_definition)
    {:ok, _run} = Cadence.Limits.evaluate(mission.mission_id)
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

  defp chart_limit_markers(html, widget_id) do
    chart_attribute(html, widget_id, "data-limit-markers")
  end

  defp chart_dom_id(html, widget_id) do
    [id] =
      html
      |> LazyHTML.from_fragment()
      |> LazyHTML.query(~s([id^="tlm-chart-#{widget_id}-"]))
      |> LazyHTML.attribute("id")

    id
  end

  defp chart_selected_ref(html, widget_id) do
    chart_optional_attribute(html, widget_id, "data-selected-ref")
  end

  defp chart_attribute(html, widget_id, attribute) do
    [value] =
      html
      |> LazyHTML.from_fragment()
      |> LazyHTML.query(~s([id^="tlm-chart-#{widget_id}-"]))
      |> LazyHTML.attribute(attribute)

    Jason.decode!(value)
  end

  defp chart_optional_attribute(html, widget_id, attribute) do
    case html
         |> LazyHTML.from_fragment()
         |> LazyHTML.query(~s([id^="tlm-chart-#{widget_id}-"]))
         |> LazyHTML.attribute(attribute) do
      [value] -> Jason.decode!(value)
      [] -> nil
    end
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

  describe "live widget time-series limit-event selection" do
    test "selects a time-series limit marker and hydrates the shared link" do
      disable_telemetry_storage_runtime_invalidation!()

      {conn, org, mission} = signed_in_org_and_mission()
      spacecraft = TestFixtures.persist_spacecraft!(mission, display_name: "SC Alpha")
      binding_set = persist_binding_set!(org, mission)

      ingest!(mission, binding_set, spacecraft.spacecraft_id, 14, 1_700_000_090)
      ingest!(mission, binding_set, spacecraft.spacecraft_id, 15, 1_700_000_100)
      evaluate_limits!(mission)

      assert [_older_sample, latest_sample] =
               TelemetryReads.sample_history(
                 org.organization_id,
                 mission.mission_id,
                 "HK.counter",
                 spacecraft_id: spacecraft.spacecraft_id,
                 order: :asc
               )

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
              layout: %{x: 4, y: 0, w: 6, h: 3}
            },
            %{
              type: :time_series,
              title: "Counter Mirror",
              binding: %{
                mode: :fixed,
                spacecraft_id: spacecraft.spacecraft_id,
                point_id: "HK.counter"
              },
              layout: %{x: 4, y: 3, w: 6, h: 3}
            }
          ]
        )

      document = fetch_dashboard_document!(org, mission, dashboard)
      trend_widget = render_item_by_title(document, "Counter Trend").widget
      mirror_widget = render_item_by_title(document, "Counter Mirror").widget
      trend_widget_id = trend_widget.widget_id

      {:ok, view, _html} = live(conn, show_path(mission, dashboard))
      html = render_dashboard_async(view)

      markers = chart_limit_markers(html, trend_widget.widget_id)

      marker =
        Enum.find(markers, &(&1["sample_id"] == latest_sample.sample_id)) || List.last(markers)

      marker_link_id = marker["link_id"]
      marker_limit_event_id = marker["limit_event_id"]
      marker_timestamp_ms = marker["timestamp_ms"]

      assert marker["normalized_state"] == "yellow"
      assert marker_limit_event_id
      assert is_binary(marker_link_id)

      chart_id = chart_dom_id(render(view), trend_widget_id)

      view
      |> element("##{chart_id}")
      |> render_hook("open_data_link", %{
        "link-id" => marker_link_id,
        "placement-id" => trend_widget_id,
        "target" => "limit_event",
        "target-id" => marker_limit_event_id,
        "timestamp-ms" => marker_timestamp_ms
      })

      assert_push_event(
        view,
        "tlm:select",
        %{
          "selection" => %{
            "link_id" => ^marker_link_id,
            "placement_id" => ^trend_widget_id,
            "target" => "limit_event",
            "target_id" => ^marker_limit_event_id,
            "timestamp_ms" => ^marker_timestamp_ms
          }
        },
        1_000
      )

      limit_event_path = assert_patch(view)
      limit_data_source_id = DataSources.default_limits_data_source().data_source_id
      assert limit_event_path =~ "panel=data_link"
      assert limit_event_path =~ "selected_target=limit_event"
      assert limit_event_path =~ "selected_id=#{URI.encode_www_form(marker_limit_event_id)}"
      assert limit_event_path =~ "selected_placement=#{URI.encode_www_form(trend_widget_id)}"
      assert limit_event_path =~ "selected_time=#{marker_timestamp_ms}"
      assert limit_event_path =~ "realm=flight"
      assert limit_event_path =~ "data_source_id=#{limit_data_source_id}"
      assert limit_event_path =~ "source_binding_id=default_flight_limits"

      selected_ref = chart_selected_ref(render(view), trend_widget_id)
      assert selected_ref["link_id"] == marker_link_id
      assert selected_ref["placement_id"] == trend_widget_id
      assert selected_ref["target"] == "limit_event"
      assert selected_ref["target_id"] == marker_limit_event_id
      assert selected_ref["timestamp_ms"] == marker_timestamp_ms
      assert selected_ref["realm"] == "flight"

      assert selected_ref["data_source_id"] == limit_data_source_id
      assert selected_ref["source_binding_id"] == "default_flight_limits"
      assert selected_ref["spacecraft_id"] == spacecraft.spacecraft_id
      assert chart_selected_ref(render(view), mirror_widget.widget_id) == nil

      assert has_element?(
               view,
               ~s(#dashboard-data-link-inspector[data-data-link-target="limit_event"][data-data-link-status="resolved"])
             )

      assert has_element?(
               view,
               ~s(#dashboard-data-link-inspector [data-data-link-field="Normalized state"]),
               "yellow"
             )

      assert has_element?(
               view,
               ~s(#dashboard-data-link-copy-link[data-clipboard-text*="/ops/dashboards/#{dashboard.dashboard_id}"][data-clipboard-text*="panel=data_link"][data-clipboard-text*="selected_target=limit_event"][data-clipboard-text*="selected_id=#{URI.encode_www_form(marker_limit_event_id)}"][data-clipboard-text*="selected_placement=#{trend_widget_id}"][data-clipboard-text*="selected_time=#{marker_timestamp_ms}"][data-clipboard-text*="realm=flight"][data-clipboard-text*="data_source_id=#{limit_data_source_id}"][data-clipboard-text*="source_binding_id=default_flight_limits"])
             )

      {:ok, shared_limit_view, _html} = live(conn, limit_event_path)
      render_dashboard_async(shared_limit_view)

      assert_push_event(
        shared_limit_view,
        "tlm:select",
        %{
          "selection" => %{
            "target" => "limit_event",
            "target_id" => ^marker_limit_event_id,
            "placement_id" => ^trend_widget_id,
            "timestamp_ms" => ^marker_timestamp_ms
          }
        },
        1_000
      )

      assert has_element?(
               shared_limit_view,
               ~s(#dashboard-data-link-inspector[data-data-link-target="limit_event"][data-data-link-status="resolved"])
             )

      shared_limit_selected_ref = chart_selected_ref(render(shared_limit_view), trend_widget_id)
      assert shared_limit_selected_ref["link_id"] == marker_link_id
      assert shared_limit_selected_ref["placement_id"] == trend_widget_id
      assert shared_limit_selected_ref["target"] == "limit_event"
      assert shared_limit_selected_ref["target_id"] == marker_limit_event_id
      assert shared_limit_selected_ref["timestamp_ms"] == marker_timestamp_ms
      assert shared_limit_selected_ref["realm"] == "flight"
      assert shared_limit_selected_ref["data_source_id"] == limit_data_source_id
      assert shared_limit_selected_ref["source_binding_id"] == "default_flight_limits"
      assert chart_selected_ref(render(shared_limit_view), mirror_widget.widget_id) == nil
    end
  end
end
