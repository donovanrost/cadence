defmodule CadenceWeb.OpsDashboardShowLive.LiveWidgetRenderingLiveTest do
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
      Cadence.Persistence.persist_processing_result(result, opts)
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

  defp placement_by_title(%Document{} = document, title) do
    Enum.find(document.placements, &(&1.widget_def.title == title))
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

  defp chart_attribute(html, widget_id, attribute) do
    [value] =
      html
      |> LazyHTML.from_fragment()
      |> LazyHTML.query(~s([id^="tlm-chart-#{widget_id}-"]))
      |> LazyHTML.attribute(attribute)

    Jason.decode!(value)
  end

  defp point_meta([_timestamp, _value, metadata]) when is_map(metadata), do: metadata
  defp point_meta(_point), do: %{}

  describe "live widget rendering" do
    test "renders live values, limit states, fleet health, and grid items" do
      disable_telemetry_storage_runtime_invalidation!()

      {conn, org, mission} = signed_in_org_and_mission()
      spacecraft = TestFixtures.persist_spacecraft!(mission, display_name: "SC Alpha")
      binding_set = persist_binding_set!(org, mission)

      ingest!(mission, binding_set, spacecraft.spacecraft_id, 14, 1_700_000_090)
      ingest!(mission, binding_set, spacecraft.spacecraft_id, 15, 1_700_000_100)
      evaluate_limits!(mission)

      assert [older_sample, latest_sample] =
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
            },
            %{type: :constellation_health, title: "Fleet", binding: %{mode: :constellation}}
          ]
        )

      document = fetch_dashboard_document!(org, mission, dashboard)
      trend_placement = placement_by_title(document, "Counter Trend")
      assert trend_placement.widget_def.binding.overlays == [:limits, :events, :quality]

      trend_widget = render_item_by_title(document, "Counter Trend").widget

      {:ok, view, _html} = live(conn, show_path(mission, dashboard))
      html = render_dashboard_async(view)

      # Status bar reflects the limit projection.
      assert html =~ "violating"

      # Grid items carry GridStack placement attributes.
      assert has_element?(view, ~s(.grid-stack-item[gs-auto-position="true"]))
      assert has_element?(view, ~s(.grid-stack-item[gs-x="4"][gs-w="6"][gs-h="3"]))
      assert has_element?(view, ~s([data-engine-backed="true"]))

      # Context widget unresolved until a spacecraft context is chosen.
      assert html =~ "Pick a spacecraft context"

      # Fixed time-series widget mounts its chart hook with backfill data.
      assert has_element?(view, ~s([phx-hook="TelemetryChart"]))

      assert has_element?(
               view,
               ~s([phx-hook="TelemetryChart"][data-engine-backed="true"])
             )

      assert has_element?(
               view,
               ~s(#ops-dashboard-show-page[data-engine-source-cache-statuses*="miss"])
             )

      refute has_element?(view, "#dashboard-source-health")

      backfill = chart_backfill(html, trend_widget.widget_id)
      older_meta = point_meta(Enum.at(backfill, 0))
      latest_meta = point_meta(Enum.at(backfill, 1))

      assert older_meta["sample_id"] == older_sample.sample_id
      assert is_binary(older_meta["link_id"])
      assert latest_meta["sample_id"] == latest_sample.sample_id

      assert has_element?(
               view,
               ~s(#widget-#{trend_widget.widget_id} [data-widget-data-link-target="telemetry sample"])
             )
    end
  end
end
