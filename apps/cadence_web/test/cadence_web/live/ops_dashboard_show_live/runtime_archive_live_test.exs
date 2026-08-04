defmodule CadenceWeb.OpsDashboardShowLive.RuntimeArchiveLiveTest do
  use CadenceWeb.ConnCase, async: false

  @moduletag :config

  import Phoenix.LiveViewTest

  alias Cadence.Runtime.Persistence, as: RuntimePersistence

  alias Phoenix.LiveViewTest.ClientProxy

  use Phoenix.VerifiedRoutes,
    endpoint: CadenceWeb.Endpoint,
    router: CadenceWeb.Router,
    statics: CadenceWeb.static_paths()

  alias Cadence.ApplicationDispatch.{BindingRule, BindingSet, CapabilityInstance}

  alias Cadence.Dashboards.{Document, RenderItem}

  alias Cadence.Management.DataSources

  alias Cadence.DataSources.{DataBinding, DataSource}

  alias Cadence.Ingress.RawEvidence
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

  defp chart_backfill(html, widget_id) do
    html
    |> chart_attribute(widget_id, "data-backfill")
    |> chart_backfill_points()
  end

  defp chart_backfill_points(%{"series" => [%{"points" => points} | _rest]}), do: points

  defp chart_event_markers(html, widget_id) do
    chart_attribute(html, widget_id, "data-event-markers")
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

  defp configure_telemetry_storage_source!(realm, data_source_id, binding_id) do
    previous_config = Application.get_env(:cadence, :telemetry_storage, [])

    Application.put_env(
      :cadence,
      :telemetry_storage,
      previous_config
      |> Keyword.put(:realm, realm)
      |> Keyword.put(:data_source_id, data_source_id)
      |> Keyword.put(:binding_id, binding_id)
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

  test "quick ranges slide live, absolute bounds snapshot archive, and live resumes" do
    {conn, _org, mission} = signed_in_org_and_mission()

    dashboard =
      TestFixtures.persist_dashboard_document!(mission,
        name: "Preset Time",
        widgets: [value_tile("HK.counter")]
      )

    {:ok, view, _html} = live(conn, show_path(mission, dashboard))
    render_dashboard_async(view)

    view |> element("#dashboard-time-preset-last-5m") |> render_click()

    patched_path = assert_patch(view)
    assert patched_path =~ "from=now-5m"
    assert patched_path =~ "to=now"
    refute patched_path =~ "time_mode="
    refute patched_path =~ "time_axis="

    render_dashboard_async(view)

    assert has_element?(
             view,
             ~s(#ops-dashboard-show-page[data-dashboard-time-mode="live"][data-dashboard-time-from="now-5m"][data-dashboard-time-to="now"][data-dashboard-time-validation="ok"][data-engine-snapshot="false"][data-engine-live-append-eligible="true"])
           )

    assert has_element?(view, "#dashboard-time-preset-live:not([disabled])")

    view
    |> form("#dashboard-custom-range-form", %{
      "from" => "2026-06-17T12:00:00Z",
      "to" => "2026-06-17T12:05:00Z"
    })
    |> render_submit()

    patched_path = assert_patch(view)
    assert patched_path =~ "time_mode=archive"
    assert patched_path =~ "from="
    assert patched_path =~ "to="
    refute patched_path =~ "time_axis="

    render_dashboard_async(view)

    assert has_element?(
             view,
             ~s(#ops-dashboard-show-page[data-dashboard-time-mode="archive"][data-dashboard-time-axis="receipt_time"][data-dashboard-time-validation="ok"][data-engine-time-axis="receipt_time"][data-engine-snapshot="true"][data-engine-live-append-eligible="false"])
           )

    assert has_element?(view, "#dashboard-time-preset-live:not([disabled])")

    view |> element("#dashboard-time-preset-live") |> render_click()
    assert_patch(view, show_path(mission, dashboard))
    render_dashboard_async(view)

    assert has_element?(
             view,
             ~s(#ops-dashboard-show-page[data-dashboard-time-mode="live"][data-dashboard-time-validation="ok"][data-engine-snapshot="false"][data-engine-live-append-eligible="true"])
           )
  end

  test "archive time-series charts expose source binding interval changes" do
    {conn, org, mission} = signed_in_org_and_mission()
    spacecraft = TestFixtures.persist_spacecraft!(mission, display_name: "SC Source Intervals")
    binding_set = persist_binding_set!(org, mission)
    from_time = ~U[2026-06-21 20:15:00Z]
    boundary_time = ~U[2026-06-21 21:00:00Z]
    to_time = ~U[2026-06-21 21:15:00Z]
    unique = System.unique_integer([:positive])
    source_v1 = "dashboard-source-intervals-v1-#{unique}"
    source_v2 = "dashboard-source-intervals-v2-#{unique}"
    binding_id = "dashboard-source-intervals-binding-#{unique}"

    assert {:ok, _source_v1} =
             DataSources.persist_data_source(%DataSource{
               data_source_id: source_v1,
               owner: :cadence,
               kind: :managed_tsdb,
               adapter: Cadence.Dashboards.Sources.Telemetry,
               organization_id: mission.organization_id,
               mission_id: mission.mission_id,
               isolation_level: :mission_isolated,
               capabilities: %{range_scan?: true, latest?: true}
             })

    assert {:ok, _source_v2} =
             DataSources.persist_data_source(%DataSource{
               data_source_id: source_v2,
               owner: :cadence,
               kind: :managed_tsdb,
               adapter: Cadence.Dashboards.Sources.Telemetry,
               organization_id: mission.organization_id,
               mission_id: mission.mission_id,
               isolation_level: :mission_isolated,
               capabilities: %{range_scan?: true, latest?: true}
             })

    binding = %DataBinding{
      binding_id: binding_id,
      organization_id: mission.organization_id,
      mission_id: mission.mission_id,
      realm: :rehearsal,
      logical_source: :telemetry,
      data_source_id: source_v1,
      dataset: "rehearsal-v1",
      priority: 0
    }

    assert {:ok, _binding_v1} =
             DataSources.persist_data_binding(binding, occurred_at: ~U[2026-06-21 20:00:00Z])

    configure_telemetry_storage_source!(:rehearsal, source_v1, binding_id)

    ingest!(
      mission,
      binding_set,
      spacecraft.spacecraft_id,
      11,
      DateTime.to_unix(~U[2026-06-21 20:30:00Z])
    )

    assert {:ok, _binding_v2} =
             DataSources.persist_data_binding(
               %DataBinding{binding | data_source_id: source_v2, dataset: "rehearsal-v2"},
               occurred_at: boundary_time
             )

    configure_telemetry_storage_source!(:rehearsal, source_v2, binding_id)

    ingest!(
      mission,
      binding_set,
      spacecraft.spacecraft_id,
      22,
      DateTime.to_unix(~U[2026-06-21 21:05:00Z])
    )

    dashboard =
      TestFixtures.persist_dashboard_document!(mission,
        name: "Source Intervals",
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
    from = DateTime.to_iso8601(from_time)
    to = DateTime.to_iso8601(to_time)

    {:ok, view, _html} =
      live(
        conn,
        show_path(mission, dashboard) <>
          "?time_mode=archive&from=#{from}&to=#{to}&realm=rehearsal"
      )

    html = render_dashboard_async(view)
    backfill = chart_backfill(html, trend_widget.widget_id)
    assert Enum.map(backfill, &Enum.at(&1, 1)) == [11, 22]

    source_markers =
      html
      |> chart_event_markers(trend_widget.widget_id)
      |> Enum.filter(&(&1["marker_type"] == "source_binding_interval"))

    assert Enum.map(source_markers, & &1["data_source_id"]) == [source_v1, source_v2]
    assert Enum.all?(source_markers, &(&1["target"] == "source_binding"))
    assert Enum.all?(source_markers, &(&1["target_id"] == binding_id))
    assert Enum.all?(source_markers, &is_binary(&1["marker_id"]))
    assert Enum.map(source_markers, & &1["dataset"]) == ["rehearsal-v1", "rehearsal-v2"]
    assert Enum.map(source_markers, & &1["realm"]) == ["rehearsal", "rehearsal"]
    assert Enum.all?(source_markers, &(&1["time_mode"] == "archive"))
    assert Enum.all?(source_markers, &(&1["time_axis"] == "receipt_time"))
    assert Enum.all?(source_markers, &(&1["requested_realm"] == "rehearsal"))
    assert Enum.all?(source_markers, &(&1["requested_data_view"] == "canonical"))

    first_marker = List.first(source_markers)
    chart_id = chart_dom_id(html, trend_widget.widget_id)

    view
    |> element("##{chart_id}")
    |> render_hook("open_evidence", %{
      "kind" => "source",
      "source-evidence-mode" => "health",
      "source-request-id" => first_marker["source_request_id"],
      "logical-source" => first_marker["logical_source"],
      "realm" => first_marker["realm"],
      "data-source-id" => first_marker["data_source_id"],
      "source-binding-id" => first_marker["source_binding_id"],
      "time-mode" => first_marker["time_mode"],
      "time-axis" => first_marker["time_axis"],
      "requested-realm" => first_marker["requested_realm"],
      "requested-data-view" => first_marker["requested_data_view"],
      "requested-data-source-id" => first_marker["requested_data_source_id"],
      "requested-source-binding-id" => first_marker["requested_source_binding_id"],
      "requested-dataset" => first_marker["requested_dataset"],
      "placement-id" => trend_widget.widget_id
    })

    source_evidence_path = assert_patch(view)
    assert source_evidence_path =~ "selected_time_mode=archive"
    assert source_evidence_path =~ "selected_time_axis=receipt_time"
    assert source_evidence_path =~ "selected_requested_realm=rehearsal"
    assert source_evidence_path =~ "selected_requested_data_view=canonical"

    assert has_element?(
             view,
             ~s(#dashboard-evidence-copy-link[data-clipboard-text*="selected_time_mode=archive"][data-clipboard-text*="selected_requested_realm=rehearsal"][data-clipboard-text*="selected_requested_data_view=canonical"])
           )

    assert has_element?(
             view,
             ~s(#dashboard-evidence-inspector[data-evidence-kind="source"][data-evidence-status="unknown"])
           )

    assert has_element?(
             view,
             ~s(#dashboard-evidence-inspector [data-evidence-subject-field="Source binding"]),
             binding_id
           )

    assert has_element?(
             view,
             ~s(#dashboard-evidence-inspector [data-evidence-subject-field="Data source"]),
             source_v1
           )
  end
end
