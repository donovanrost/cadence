defmodule CadenceWeb.OpsDashboardShowLive.RuntimeArchiveSourceWatermarkLiveTest do
  use CadenceWeb.ConnCase, async: false

  @moduletag :config

  import Phoenix.LiveViewTest

  alias Phoenix.LiveViewTest.ClientProxy

  use Phoenix.VerifiedRoutes,
    endpoint: CadenceWeb.Endpoint,
    router: CadenceWeb.Router,
    statics: CadenceWeb.static_paths()

  alias Cadence.ApplicationDispatch.{BindingRule, BindingSet, CapabilityInstance}
  alias Cadence.Dashboards.{DataBinding, DataSource, DataSources, Document, RenderItem}
  alias Cadence.Dashboards.SourceWatermarks
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
    tracked_views = Process.get(:ops_dashboard_archive_source_watermark_views, MapSet.new())

    unless MapSet.member?(tracked_views, pid) do
      Process.put(:ops_dashboard_archive_source_watermark_views, MapSet.put(tracked_views, pid))

      on_exit({:ops_dashboard_archive_source_watermark_view, pid}, fn ->
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

  defp enable_dashboard_source_watermark_events! do
    previous_config = Application.get_env(:cadence_web, :dashboard_engine_source_execution, [])

    Application.put_env(
      :cadence_web,
      :dashboard_engine_source_execution,
      Keyword.put(previous_config, :source_watermark_events?, true)
    )

    on_exit(fn ->
      Application.put_env(:cadence_web, :dashboard_engine_source_execution, previous_config)
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

  test "archive time-series charts expose source watermark retention gaps" do
    enable_dashboard_source_watermark_events!()

    {conn, org, mission} = signed_in_org_and_mission()
    spacecraft = TestFixtures.persist_spacecraft!(mission, display_name: "SC Retention Gap")
    binding_set = persist_binding_set!(org, mission)
    from_time = ~U[2026-06-21 19:45:00Z]
    retention_starts_at = ~U[2026-06-21 20:00:00Z]
    sample_time = ~U[2026-06-21 20:10:00Z]
    to_time = ~U[2026-06-21 20:15:00Z]
    unique = System.unique_integer([:positive])
    data_source_id = "dashboard-retention-gap-source-#{unique}"
    binding_id = "dashboard-retention-gap-binding-#{unique}"

    assert {:ok, _source} =
             DataSources.persist_data_source(%DataSource{
               data_source_id: data_source_id,
               owner: :cadence,
               kind: :managed_tsdb,
               adapter: Cadence.Dashboards.Sources.Telemetry,
               organization_id: mission.organization_id,
               mission_id: mission.mission_id,
               isolation_level: :mission_isolated,
               capabilities: %{range_scan?: true, latest?: true, watermarks?: true}
             })

    assert {:ok, _binding} =
             DataSources.persist_data_binding(
               %DataBinding{
                 binding_id: binding_id,
                 organization_id: mission.organization_id,
                 mission_id: mission.mission_id,
                 realm: :rehearsal,
                 logical_source: :telemetry,
                 data_source_id: data_source_id,
                 dataset: "rehearsal-retention",
                 priority: 0
               },
               occurred_at: ~U[2026-06-21 19:30:00Z]
             )

    assert {:ok, _event, _status} =
             SourceWatermarks.record_source_watermark(
               %{
                 organization_id: mission.organization_id,
                 mission_id: mission.mission_id,
                 logical_source: :telemetry,
                 data_source_id: data_source_id,
                 source_binding_id: binding_id,
                 realm: :rehearsal,
                 dataset: "rehearsal-retention",
                 complete_through: to_time,
                 latest_receipt_time: sample_time,
                 retention_starts_at: retention_starts_at,
                 sample_count: 1,
                 confidence: :authoritative,
                 reason: :retention_policy,
                 observed_at: ~U[2026-06-21 20:16:00Z]
               },
               invalidate_runtime_cache?: false
             )

    configure_telemetry_storage_source!(:rehearsal, data_source_id, binding_id)

    ingest!(
      mission,
      binding_set,
      spacecraft.spacecraft_id,
      33,
      DateTime.to_unix(sample_time)
    )

    dashboard =
      TestFixtures.persist_dashboard_document!(mission,
        name: "Retention Gap",
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
    assert [[_timestamp_ms, 33 | _metadata]] = chart_backfill(html, trend_widget.widget_id)

    retention_marker =
      html
      |> chart_event_markers(trend_widget.widget_id)
      |> Enum.find(&(&1["marker_type"] == "retention_gap"))

    assert retention_marker["target"] == "source_watermark"
    assert retention_marker["target_id"] == retention_marker["source_request_id"]
    assert retention_marker["data_source_id"] == data_source_id
    assert retention_marker["source_binding_id"] == binding_id
    assert retention_marker["realm"] == "rehearsal"
    assert retention_marker["freshness_state"] == "retention_gap"
    assert retention_marker["confidence"] == "authoritative"
    assert retention_marker["time_mode"] == "archive"
    assert retention_marker["time_axis"] == "receipt_time"
    assert retention_marker["requested_realm"] == "rehearsal"
    assert retention_marker["requested_data_view"] == "canonical"
    assert retention_marker["starts_at_ms"] == DateTime.to_unix(from_time, :millisecond)

    assert retention_marker["ends_at_ms"] ==
             DateTime.to_unix(retention_starts_at, :millisecond)

    chart_id = chart_dom_id(html, trend_widget.widget_id)

    view
    |> element("##{chart_id}")
    |> render_hook("open_evidence", %{
      "kind" => "source",
      "source-evidence-mode" => "health",
      "source-request-id" => retention_marker["source_request_id"],
      "logical-source" => retention_marker["logical_source"],
      "realm" => retention_marker["realm"],
      "data-source-id" => retention_marker["data_source_id"],
      "source-binding-id" => retention_marker["source_binding_id"],
      "time-mode" => retention_marker["time_mode"],
      "time-axis" => retention_marker["time_axis"],
      "requested-realm" => retention_marker["requested_realm"],
      "requested-data-view" => retention_marker["requested_data_view"],
      "requested-data-source-id" => retention_marker["requested_data_source_id"],
      "requested-source-binding-id" => retention_marker["requested_source_binding_id"],
      "requested-dataset" => retention_marker["requested_dataset"],
      "placement-id" => trend_widget.widget_id
    })

    retention_evidence_path = assert_patch(view)
    assert retention_evidence_path =~ "selected_time_mode=archive"
    assert retention_evidence_path =~ "selected_time_axis=receipt_time"
    assert retention_evidence_path =~ "selected_requested_realm=rehearsal"
    assert retention_evidence_path =~ "selected_requested_data_view=canonical"

    assert has_element?(
             view,
             ~s(#dashboard-evidence-inspector[data-evidence-kind="source"][data-evidence-status="retention_gap"])
           )

    assert has_element?(
             view,
             ~s(#dashboard-evidence-inspector [data-evidence-detail="Time mode"]),
             "archive"
           )

    assert has_element?(
             view,
             ~s(#dashboard-evidence-inspector [data-evidence-subject-field="Data source"]),
             data_source_id
           )
  end
end
