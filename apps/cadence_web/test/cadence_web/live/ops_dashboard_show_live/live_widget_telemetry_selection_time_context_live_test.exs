defmodule CadenceWeb.OpsDashboardShowLive.LiveWidgetTelemetrySelectionTimeContextLiveTest do
  use CadenceWeb.ConnCase, async: false

  import Phoenix.LiveViewTest

  alias Phoenix.LiveViewTest.ClientProxy

  use Phoenix.VerifiedRoutes,
    endpoint: CadenceWeb.Endpoint,
    router: CadenceWeb.Router,
    statics: CadenceWeb.static_paths()

  alias Cadence.ApplicationDispatch.{BindingRule, BindingSet}
  alias Cadence.Dashboards.{Document, RenderItem}
  alias Cadence.Ingress.RawEvidence
  alias Cadence.Limits.Definition
  alias Cadence.Telemetry.PacketDefinition
  alias CadenceWeb.TestFixtures

  defp signed_in_org_and_mission do
    user = TestFixtures.persist_user!()
    org = TestFixtures.persist_org!()
    _membership = TestFixtures.grant_membership!(user, org)
    mission = TestFixtures.persist_mission!(org, slug: "ops", display_name: "Ops Mission")
    {TestFixtures.member_conn(user), org, mission}
  end

  defp value_tile(point_id, mode \\ :context, spacecraft_id \\ nil) do
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
        packet_definition_id: "hk-telemetry-selection",
        packet_name: "HK",
        apid: 48,
        fields: [%{name: "counter", offset_bits: 0, size_bits: 16, data_type: :uint}]
      })

    binding_set =
      BindingSet.new(%{
        mission_id: mission.mission_id,
        binding_set_id: mission.mission_id <> "-telemetry-selection-binding-set",
        version: 1,
        rules: [
          BindingRule.new(%{
            handler_key: :definition_bound_telemetry,
            packet_kind: :space_packet,
            apid: 48,
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
        raw: build_space_packet(48, 1, <<value::16>>)
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

  defp evaluate_limits!(mission) do
    limit_definition =
      Definition.new(%{
        mission_id: mission.mission_id,
        limit_definition_id: "counter-limits",
        point_id: "HK.counter",
        thresholds: %{"yellow_high" => 10, "red_high" => 20}
      })

    {:ok, _definition} = Cadence.persist_limit_definition(limit_definition)
    {:ok, _run} = Cadence.evaluate_telemetry_limits(mission.mission_id)
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

  defp chart_backfill(html, widget_id) do
    html
    |> chart_attribute(widget_id, "data-backfill")
    |> chart_backfill_points()
  end

  defp chart_backfill_points(%{"series" => [%{"points" => points} | _rest]}), do: points
  defp chart_backfill_points(points) when is_list(points), do: points
  defp chart_backfill_points(_payload), do: []

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

  defp chart_dom_id(html, widget_id) do
    [id] =
      html
      |> LazyHTML.from_fragment()
      |> LazyHTML.query(~s([id^="tlm-chart-#{widget_id}-"]))
      |> LazyHTML.attribute("id")

    id
  end

  defp point_meta([_timestamp, _value, metadata]) when is_map(metadata), do: metadata
  defp point_meta(_point), do: %{}

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

  describe "live widget telemetry selection time context" do
    test "preserves telemetry sample selection through stale context and clear action" do
      disable_telemetry_storage_runtime_invalidation!()

      {conn, org, mission} = signed_in_org_and_mission()
      spacecraft = TestFixtures.persist_spacecraft!(mission, display_name: "SC Alpha")
      binding_set = persist_binding_set!(org, mission)

      ingest!(mission, binding_set, spacecraft.spacecraft_id, 14, 1_700_000_090)
      ingest!(mission, binding_set, spacecraft.spacecraft_id, 15, 1_700_000_100)
      evaluate_limits!(mission)

      assert [older_sample, _latest_sample] =
               Cadence.telemetry_history(org.organization_id, mission.mission_id, "HK.counter",
                 spacecraft_id: spacecraft.spacecraft_id,
                 order: :asc
               )

      dashboard =
        TestFixtures.persist_dashboard_document!(mission,
          name: "Power",
          widgets: [
            value_tile("HK.counter"),
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

      backfill = chart_backfill(html, trend_widget.widget_id)
      older_point = Enum.at(backfill, 0)
      older_meta = point_meta(older_point)
      older_link_id = older_meta["link_id"]
      older_timestamp_ms = List.first(older_point)
      older_sample_id = older_sample.sample_id

      assert older_meta["sample_id"] == older_sample_id
      assert is_binary(older_link_id)

      chart_id = chart_dom_id(render(view), trend_widget_id)

      view
      |> element("##{chart_id}")
      |> render_hook("open_data_link", %{
        "link-id" => older_link_id,
        "placement-id" => trend_widget_id,
        "target" => "telemetry_sample",
        "target-id" => older_sample_id,
        "timestamp-ms" => older_timestamp_ms
      })

      assert_push_event(
        view,
        "tlm:select",
        %{
          "selection" => %{
            "link_id" => ^older_link_id,
            "placement_id" => ^trend_widget_id,
            "target" => "telemetry_sample",
            "target_id" => ^older_sample_id,
            "timestamp_ms" => ^older_timestamp_ms
          }
        },
        1_000
      )

      selected_ref = chart_optional_attribute(render(view), trend_widget_id, "data-selected-ref")
      assert selected_ref["target"] == "telemetry_sample"
      assert selected_ref["target_id"] == older_sample_id

      assert chart_optional_attribute(render(view), mirror_widget.widget_id, "data-selected-ref") ==
               nil

      selected_path = assert_patch(view)
      assert selected_path =~ "panel=data_link"
      assert selected_path =~ "selected_link="
      assert selected_path =~ "selected_target=telemetry_sample"
      assert selected_path =~ "selected_id=#{URI.encode_www_form(older_sample_id)}"
      assert selected_path =~ "selected_placement=#{URI.encode_www_form(trend_widget_id)}"
      assert selected_path =~ "selected_time=#{older_timestamp_ms}"

      {:ok, shared_view, _html} = live(conn, selected_path)
      render_dashboard_async(shared_view)

      assert_push_event(
        shared_view,
        "tlm:select",
        %{
          "selection" => %{
            "target" => "telemetry_sample",
            "target_id" => ^older_sample_id,
            "placement_id" => ^trend_widget_id,
            "timestamp_ms" => ^older_timestamp_ms
          }
        },
        1_000
      )

      assert has_element?(
               shared_view,
               ~s(#dashboard-data-link-inspector[data-data-link-target="telemetry_sample"][data-data-link-status="resolved"])
             )

      assert has_element?(
               shared_view,
               ~s(#ops-dashboard-show-page[data-dashboard-selection-state="active"][data-dashboard-selection-target="telemetry_sample"][data-dashboard-selection-source-binding="default_flight_telemetry"])
             )

      assert chart_optional_attribute(
               render(shared_view),
               mirror_widget.widget_id,
               "data-selected-ref"
             ) ==
               nil

      other_spacecraft = TestFixtures.persist_spacecraft!(mission, display_name: "SC Beta")

      {:ok, stale_context_view, _html} =
        live(conn, selected_path <> "&spacecraft_id=#{other_spacecraft.spacecraft_id}")

      render_dashboard_async(stale_context_view)

      assert_push_event(
        stale_context_view,
        "tlm:select",
        %{"selection" => nil},
        1_000
      )

      stale_context_path = assert_patch(stale_context_view)
      assert stale_context_path =~ "spacecraft_id=#{other_spacecraft.spacecraft_id}"
      refute stale_context_path =~ "selected_target="
      refute stale_context_path =~ "selected_id="
      refute stale_context_path =~ "selected_placement="
      refute stale_context_path =~ "selected_time="
      refute has_element?(stale_context_view, "#dashboard-data-link-inspector")

      refute chart_optional_attribute(
               render(stale_context_view),
               trend_widget_id,
               "data-selected-ref"
             )

      assert has_element?(
               stale_context_view,
               ~s(#ops-dashboard-show-page[data-dashboard-selection-state="stale_context"])
             )

      assert has_element?(stale_context_view, "#dashboard-pause-at-selection[disabled]")

      shared_view
      |> element(~s(#dashboard-panel button[aria-label="Close panel"]))
      |> render_click()

      refute has_element?(shared_view, "#dashboard-data-link-inspector")
      assert has_element?(shared_view, "#dashboard-pause-at-selection:not([disabled])")

      assert chart_optional_attribute(render(shared_view), trend_widget_id, "data-selected-ref")

      direct_target_path =
        ~p"/missions/#{mission.mission_id}/ops/dashboards/#{dashboard.dashboard_id}?#{%{selected_target: "telemetry_sample", selected_id: older_sample_id, selected_placement: trend_widget_id, selected_time: older_timestamp_ms}}"

      {:ok, direct_target_view, _html} = live(conn, direct_target_path)
      render_dashboard_async(direct_target_view)

      assert has_element?(
               direct_target_view,
               ~s(#dashboard-data-link-inspector[data-data-link-target="telemetry_sample"][data-data-link-status="resolved"])
             )

      direct_target_view |> element("#dashboard-clear-selection") |> render_click()

      assert_push_event(
        direct_target_view,
        "tlm:select",
        %{"selection" => nil},
        1_000
      )

      cleared_selection_path = assert_patch(direct_target_view)
      refute cleared_selection_path =~ "selected_target="
      refute cleared_selection_path =~ "selected_id="
      refute cleared_selection_path =~ "selected_placement="
      refute cleared_selection_path =~ "selected_time="
      refute has_element?(direct_target_view, "#dashboard-data-link-inspector")

      refute chart_optional_attribute(
               render(direct_target_view),
               trend_widget_id,
               "data-selected-ref"
             )

      assert has_element?(direct_target_view, "#dashboard-pause-at-selection[disabled]")
      assert has_element?(direct_target_view, "#dashboard-clear-selection[disabled]")
    end
  end
end
