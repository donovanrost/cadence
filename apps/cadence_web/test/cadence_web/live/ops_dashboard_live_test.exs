defmodule CadenceWeb.OpsDashboardLiveTest do
  use CadenceWeb.ConnCase, async: false

  import Phoenix.LiveViewTest

  alias Phoenix.LiveViewTest.ClientProxy

  use Phoenix.VerifiedRoutes,
    endpoint: CadenceWeb.Endpoint,
    router: CadenceWeb.Router,
    statics: CadenceWeb.static_paths()

  alias Cadence.ApplicationDispatch.{BindingRule, BindingSet, CapabilityInstance}
  alias Cadence.Commanding.{CommandQueueEntry, CommandRequest}
  alias Cadence.Comms.{GroundStation, Transport}

  alias Cadence.Dashboards.{
    DataBinding,
    DataSource,
    DataSources,
    Document,
    RenderItem,
    RuntimeCache,
    RuntimeInvalidation,
    SourceWatermarks
  }

  alias Cadence.Contacts.{Path, ScheduledContact}
  alias Cadence.Ingress.RawEvidence
  alias Cadence.Limits.Definition
  alias Cadence.OperationalEvents
  alias Cadence.OperationalEvents.Event
  alias Cadence.Persistence.JsonDocument

  alias Cadence.Persistence.Schemas.{
    CommandQueueEntryRow,
    CommandRequestRow,
    OpsDashboardRow,
    PacketRecordRow,
    RawEvidenceRow,
    ReplayRunRow
  }

  alias Cadence.Projections.MissionEvents
  alias Cadence.Protocol.PacketRecord
  alias Cadence.Replay.Run
  alias Cadence.Repo
  alias Cadence.SourceEndpoints.SourceEndpoint
  alias Cadence.Telemetry.{HistoryStore, PacketDefinition, Sample, Storage}
  alias Cadence.Telemetry.HistoryStore.ETS, as: HistoryStoreETS
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

  defp persist_command_queue_entry!(
         org,
         mission,
         command_queue_entry_id,
         source_endpoint_ref,
         lifecycle_state \\ :pending
       ) do
    requested_at = DateTime.from_unix!(1_700_000_000, :second)
    command_request_id = command_queue_entry_id <> "-request"

    command_request =
      CommandRequest.new(%{
        command_request_id: command_request_id,
        mission_id: mission.mission_id,
        source_endpoint_ref: source_endpoint_ref,
        command_snapshot_id: command_queue_entry_id <> "-snapshot",
        command_id: command_queue_entry_id <> "-command",
        command_name: "NOOP",
        command_display_name: "NOOP",
        lifecycle_state: :queued,
        priority: 3,
        requested_by: %{"user_id" => "dashboard-test"},
        requested_at: requested_at,
        metadata: %{}
      })

    command_queue_entry =
      CommandQueueEntry.new(%{
        command_queue_entry_id: command_queue_entry_id,
        mission_id: mission.mission_id,
        command_request_id: command_request_id,
        source_endpoint_ref: source_endpoint_ref,
        queue_lane_key: source_endpoint_ref,
        priority: 3,
        queue_sequence: System.unique_integer([:positive, :monotonic]),
        lifecycle_state: lifecycle_state,
        enqueued_by: %{"user_id" => "dashboard-test"},
        enqueued_at: requested_at,
        metadata: %{}
      })

    assert %CommandRequestRow{} =
             Repo.insert!(
               CommandRequestRow.changeset(%CommandRequest{
                 command_request
                 | organization_id: org.organization_id
               })
             )

    assert %CommandQueueEntryRow{} =
             Repo.insert!(
               CommandQueueEntryRow.changeset(%CommandQueueEntry{
                 command_queue_entry
                 | organization_id: org.organization_id
               })
             )

    command_queue_entry
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

    {:ok, persisted} = Cadence.persist_binding_set(org.organization_id, binding_set)
    persisted
  end

  defp persist_matrix_binding_set!(org, mission) do
    packet_definition =
      PacketDefinition.new(%{
        mission_id: mission.mission_id,
        packet_definition_id: "hk-matrix",
        packet_name: "HK",
        apid: 43,
        fields: [
          %{name: "counter", offset_bits: 0, size_bits: 16, data_type: :uint},
          %{name: "voltage", offset_bits: 16, size_bits: 16, data_type: :uint}
        ]
      })

    binding_set =
      BindingSet.new(%{
        mission_id: mission.mission_id,
        binding_set_id: mission.mission_id <> "-matrix-binding-set",
        version: 1,
        rules: [
          BindingRule.new(%{
            handler_key: :definition_bound_telemetry,
            packet_kind: :space_packet,
            apid: 43,
            handler_configuration: packet_definition
          })
        ]
      })

    {:ok, persisted} = Cadence.persist_binding_set(org.organization_id, binding_set)
    persisted
  end

  defp activate_binding_set!(org, mission, binding_set) do
    {:ok, _activation} =
      Cadence.activate_binding_set(
        org.organization_id,
        mission.mission_id,
        binding_set.binding_set_id,
        binding_set.version,
        []
      )
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

  defp ingest_matrix!(mission, binding_set, spacecraft_id, counter, voltage, unix_seconds) do
    evidence =
      RawEvidence.new(%{
        mission_id: mission.mission_id,
        spacecraft_id: spacecraft_id,
        receipt_time: DateTime.from_unix!(unix_seconds, :second),
        raw: build_space_packet(43, 1, <<counter::16, voltage::16>>)
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

  defp persist_counter_limit_definition!(mission, version, thresholds) do
    limit_definition =
      Definition.new(%{
        mission_id: mission.mission_id,
        limit_definition_id: "counter-limits",
        point_id: "HK.counter",
        version: version,
        thresholds: thresholds
      })

    assert {:ok, ^limit_definition} = Cadence.persist_limit_definition(limit_definition)
    limit_definition
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

  defp persist_dashboard_realm!(
         mission,
         realm,
         capabilities \\ %{range_scan?: true, latest?: true}
       ) do
    data_source_id = "test-#{realm}-questdb-#{System.unique_integer([:positive])}"

    assert {:ok, _source} =
             DataSources.persist_data_source(%DataSource{
               data_source_id: data_source_id,
               owner: :cadence,
               kind: :managed_tsdb,
               adapter: Cadence.Dashboards.Sources.Telemetry,
               organization_id: mission.organization_id,
               mission_id: mission.mission_id,
               isolation_level: :mission_isolated,
               capabilities: capabilities
             })

    assert {:ok, _binding} =
             DataSources.persist_data_binding(%DataBinding{
               binding_id: "test-#{realm}-binding-#{System.unique_integer([:positive])}",
               organization_id: mission.organization_id,
               mission_id: mission.mission_id,
               realm: realm,
               logical_source: :telemetry,
               data_source_id: data_source_id,
               dataset: to_string(realm),
               priority: 0
             })

    %{data_source_id: data_source_id}
  end

  defp persist_dashboard_realm_source!(mission, realm, data_source_id, binding_id) do
    assert {:ok, _source} =
             DataSources.persist_data_source(%DataSource{
               data_source_id: data_source_id,
               owner: :cadence,
               kind: :managed_tsdb,
               adapter: Cadence.Dashboards.Sources.Telemetry,
               organization_id: mission.organization_id,
               mission_id: mission.mission_id,
               isolation_level: :mission_isolated,
               capabilities: %{range_scan?: true, latest?: true}
             })

    assert {:ok, _binding} =
             DataSources.persist_data_binding(%DataBinding{
               binding_id: binding_id,
               organization_id: mission.organization_id,
               mission_id: mission.mission_id,
               realm: realm,
               logical_source: :telemetry,
               data_source_id: data_source_id,
               dataset: to_string(realm),
               priority: 0
             })

    %{data_source_id: data_source_id, binding_id: binding_id}
  end

  defp persist_replay_event_and_operational_sources!(mission) do
    unique = System.unique_integer([:positive])

    assert {:ok, _source} =
             DataSources.persist_data_source(
               DataSources.default_operational_observables_data_source()
             )

    assert {:ok, _source} =
             DataSources.persist_data_source(DataSources.default_events_data_source())

    operational_binding_id = "replay-operational-observables-#{unique}"
    events_binding_id = "replay-events-#{unique}"

    assert {:ok, _binding} =
             DataSources.persist_data_binding(%DataBinding{
               DataSources.default_flight_operational_observables_binding()
               | binding_id: operational_binding_id,
                 organization_id: mission.organization_id,
                 mission_id: mission.mission_id,
                 realm: :replay,
                 dataset: "operational_observables_replay",
                 metadata: %{bootstrap_default?: false}
             })

    assert {:ok, _binding} =
             DataSources.persist_data_binding(%DataBinding{
               DataSources.default_flight_events_binding()
               | binding_id: events_binding_id,
                 organization_id: mission.organization_id,
                 mission_id: mission.mission_id,
                 realm: :replay,
                 dataset: "mission_events_replay",
                 metadata: %{bootstrap_default?: false}
             })

    %{
      operational_binding_id: operational_binding_id,
      operational_data_source_id:
        DataSources.default_operational_observables_data_source().data_source_id,
      events_binding_id: events_binding_id,
      events_data_source_id: DataSources.default_events_data_source().data_source_id
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

  defp fetch_dashboard_version!(org, mission, dashboard, version_number) do
    assert {:ok, dashboard_version} =
             Cadence.Dashboards.fetch_version(
               org.organization_id,
               mission.mission_id,
               dashboard.dashboard_id,
               version_number
             )

    dashboard_version
  end

  defp replace_dashboard_row_document!(org, mission, %Document{} = document) do
    row =
      Repo.get_by!(OpsDashboardRow,
        organization_id: org.organization_id,
        mission_id: mission.mission_id,
        dashboard_id: document.dashboard_id
      )

    row
    |> Ecto.Changeset.change(%{document: JsonDocument.encode(Document.to_map(document))})
    |> Repo.update!()

    document
  end

  defp bump_dashboard_row_latest_version!(org, mission, dashboard, version)
       when is_integer(version) and version > 0 do
    row =
      Repo.get_by!(OpsDashboardRow,
        organization_id: org.organization_id,
        mission_id: mission.mission_id,
        dashboard_id: dashboard.dashboard_id
      )

    row
    |> Ecto.Changeset.change(%{latest_version: version, draft_version: version})
    |> Repo.update!()
  end

  defp with_invalid_grid(%Document{} = document) do
    grid = Map.put(document.grid, :columns, 0)
    %Document{document | grid: grid}
  end

  defp with_invalid_runtime_defaults(%Document{} = document) do
    defaults =
      document.defaults
      |> Map.put("time", %{"mode" => "unsupported"})
      |> Map.put("data", %{"realm" => "lab"})

    %Document{document | defaults: defaults}
  end

  defp with_unknown_widget(%Document{placements: [placement | rest]} = document) do
    widget_def = %{placement.widget_def | widget_type_id: "partner.spectrum_waterfall"}
    Document.replace_placements(document, [%{placement | widget_def: widget_def} | rest])
  end

  defp without_widget_overlay(%Document{} = document, title, overlay) do
    placements =
      Enum.map(document.placements, fn placement ->
        without_placement_widget_overlay(placement, title, overlay)
      end)

    Document.replace_placements(document, placements)
  end

  defp without_placement_widget_overlay(
         %{widget_def: %{title: placement_title}} = placement,
         title,
         overlay
       )
       when placement_title == title do
    binding =
      Map.update(placement.widget_def.binding, :overlays, [], fn overlays ->
        without_overlay(overlays, overlay)
      end)

    widget_def = %{placement.widget_def | binding: binding}
    %{placement | widget_def: widget_def}
  end

  defp without_placement_widget_overlay(placement, _title, _overlay), do: placement

  defp without_overlay(overlays, overlay) do
    overlay_string = Atom.to_string(overlay)

    overlays
    |> List.wrap()
    |> Enum.reject(&(&1 == overlay or &1 == overlay_string))
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

  defp chart_limit_markers(html, widget_id) do
    chart_attribute(html, widget_id, "data-limit-markers")
  end

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

  defp chart_selected_ref(html, widget_id) do
    chart_optional_attribute(html, widget_id, "data-selected-ref")
  end

  defp element_attribute(html, selector, attribute) do
    [value] =
      html
      |> LazyHTML.from_fragment()
      |> LazyHTML.query(selector)
      |> LazyHTML.attribute(attribute)

    value
  end

  defp persist_revision_sample_identity!(org, mission, sample_id, opts \\ []) do
    point_id = Keyword.get(opts, :point_id, "HK.counter")
    sample = revision_sample(mission, sample_id, ~U[2026-06-22 11:00:00Z], opts)

    persist_sample_scope!(sample)

    assert :ok =
             Storage.persist_samples([sample],
               organization_id: org.organization_id,
               recorded_at: ~U[2026-06-22 12:00:00Z],
               dashboard_runtime_invalidation?: false
             )

    [state] =
      Storage.list_observation_identity_states(mission.mission_id,
        organization_id: org.organization_id,
        realm: :flight,
        data_source_id: "managed_questdb_primary",
        binding_id: "default_flight_telemetry",
        point_id: point_id
      )

    {sample, state}
  end

  defp revision_sample(mission, sample_id, generation_time, opts) do
    point_id = Keyword.get(opts, :point_id, "HK.counter")

    telemetry_sample(
      mission,
      sample_id,
      point_id,
      generation_time,
      DateTime.add(generation_time, 3, :second),
      raw_value: 42,
      engineering_value: 42,
      spacecraft_id: "sc-dashboard-revision",
      packet_definition_id: "packet-def-dashboard-revision",
      packet_id: "packet-dashboard-revision-#{sample_id}",
      evidence_id: "evidence-dashboard-revision-#{sample_id}"
    )
  end

  defp persist_sample_scope!(%Sample{} = sample) do
    raw_evidence =
      RawEvidence.new(%{
        evidence_id: sample.evidence_id,
        mission_id: sample.mission_id,
        spacecraft_id: sample.spacecraft_id,
        protocol_family: :space_packet,
        direction: :downlink,
        raw: <<0, 1, 2, 3>>,
        source_time: sample.generation_time,
        receipt_time: sample.receipt_time,
        source_ref: "dashboard-live-test",
        metadata: %{}
      })

    packet_record = %PacketRecord{
      packet_id: sample.packet_id,
      evidence_id: sample.evidence_id,
      mission_id: sample.mission_id,
      spacecraft_id: sample.spacecraft_id,
      protocol_family: :space_packet,
      packet_kind: :space_packet,
      apid: 1,
      sequence_flags: 3,
      sequence_count: 1,
      secondary_header?: false,
      packet_data: <<0, 1, 2, 3>>,
      source_time: sample.generation_time,
      receipt_time: sample.receipt_time,
      provenance: %{}
    }

    {:ok, _raw_evidence_row} = Repo.insert(RawEvidenceRow.changeset(raw_evidence))
    {:ok, _packet_record_row} = Repo.insert(PacketRecordRow.changeset(packet_record))

    :ok
  end

  defp telemetry_sample(mission, sample_id, point_id, generation_time, receipt_time, opts) do
    %Sample{
      sample_id: sample_id,
      mission_id: mission.mission_id,
      spacecraft_id: Keyword.get(opts, :spacecraft_id, "sc-dashboard-telemetry"),
      point_id: point_id,
      point_name: point_id,
      packet_definition_id:
        Keyword.get(opts, :packet_definition_id, "packet-def-dashboard-telemetry"),
      packet_definition_version: 1,
      packet_id: Keyword.get(opts, :packet_id, "packet-dashboard-telemetry"),
      evidence_id: Keyword.get(opts, :evidence_id, "evidence-dashboard-telemetry"),
      raw_value: Keyword.fetch!(opts, :raw_value),
      engineering_value: Keyword.fetch!(opts, :engineering_value),
      quality_state: :good,
      generation_time: generation_time,
      receipt_time: receipt_time,
      provenance: Keyword.get(opts, :provenance, %{})
    }
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

  defp delay_dashboard_engine_resolves!(delay_ms) do
    previous_delay = Application.get_env(:cadence_web, :dashboard_engine_resolve_test_delay_ms)
    previous_inline? = Application.get_env(:cadence_web, :dashboard_engine_resolve_inline?)

    Application.put_env(:cadence_web, :dashboard_engine_resolve_test_delay_ms, delay_ms)
    Application.put_env(:cadence_web, :dashboard_engine_resolve_inline?, false)

    on_exit(fn ->
      case previous_delay do
        nil ->
          Application.delete_env(:cadence_web, :dashboard_engine_resolve_test_delay_ms)

        value ->
          Application.put_env(:cadence_web, :dashboard_engine_resolve_test_delay_ms, value)
      end

      case previous_inline? do
        nil ->
          Application.delete_env(:cadence_web, :dashboard_engine_resolve_inline?)

        value ->
          Application.put_env(:cadence_web, :dashboard_engine_resolve_inline?, value)
      end
    end)
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

  defp enable_dashboard_runtime_cache! do
    previous_config = Application.get_env(:cadence, :dashboard_runtime_cache)
    Application.put_env(:cadence, :dashboard_runtime_cache, enabled?: true)

    if is_nil(Process.whereis(RuntimeCache)) do
      start_supervised!(RuntimeCache)
    end

    RuntimeCache.reset()

    on_exit(fn ->
      RuntimeCache.reset()

      case previous_config do
        nil -> Application.delete_env(:cadence, :dashboard_runtime_cache)
        value -> Application.put_env(:cadence, :dashboard_runtime_cache, value)
      end
    end)
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

  defp reset_runtime_health! do
    Cadence.reset_runtime_health()

    on_exit(fn ->
      Cadence.reset_runtime_health()
    end)
  end

  defp emit_runtime_invalidation!(measurements, metadata) do
    :telemetry.execute(RuntimeInvalidation.telemetry_event(), measurements, metadata)

    # The runtime-health telemetry handler casts into the supervised process.
    # A snapshot call from the same process is ordered after that cast.
    Cadence.runtime_health_snapshot()
  end

  defp emit_runtime_invalidation_decision!(metadata, decision) do
    metadata =
      metadata
      |> Map.put(:decision, decision)
      |> Map.merge(Map.take(decision, runtime_invalidation_decision_keys()))

    :telemetry.execute(RuntimeInvalidation.decision_telemetry_event(), %{total: 1}, metadata)

    Cadence.runtime_health_snapshot()
  end

  defp runtime_invalidation_decision_keys do
    [
      :dashboard_id,
      :organization_id,
      :mission_id,
      :matches?,
      :dashboard_matches?,
      :context_matches?,
      :context_reason,
      :refresh_allowed?,
      :refresh_reason,
      :affected_placement_count,
      :affected_placement_ids,
      :affected_widget_type_ids,
      :affected_impact_reasons,
      :decision_status
    ]
  end

  defp runtime_invalidation_test_event_id(boundary, mission_id, observable, total, occurred_at) do
    [
      boundary,
      mission_id,
      observable,
      total,
      DateTime.to_iso8601(occurred_at)
    ]
    |> Enum.map_join("-", &runtime_invalidation_test_value/1)
    |> String.replace(~r/[^a-zA-Z0-9_-]+/, "-")
  end

  defp runtime_invalidation_test_value(nil), do: "-"
  defp runtime_invalidation_test_value(value) when is_atom(value), do: Atom.to_string(value)
  defp runtime_invalidation_test_value(value) when is_integer(value), do: Integer.to_string(value)
  defp runtime_invalidation_test_value(value) when is_binary(value), do: value

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

  defp centered_archive_range(timestamp_ms) do
    {:ok, center} = DateTime.from_unix(timestamp_ms, :millisecond)

    {
      center |> DateTime.add(-150, :second) |> DateTime.to_iso8601(),
      center |> DateTime.add(150, :second) |> DateTime.to_iso8601()
    }
  end

  defp point_meta([_timestamp, _value, metadata]) when is_map(metadata), do: metadata
  defp point_meta(_point), do: %{}

  describe "ops landing" do
    test "shows the empty state, creates a dashboard, and lands on the console" do
      {conn, _org, mission} = signed_in_org_and_mission()

      {:ok, view, _html} = live(conn, ~p"/missions/#{mission.mission_id}/ops/dashboards")
      assert has_element?(view, "#ops-dashboards-page")
      assert render(view) =~ "No dashboards"

      {:ok, view, _html} = live(conn, ~p"/missions/#{mission.mission_id}/ops/dashboards/new")

      view
      |> form("#dashboard-form", dashboard: %{name: "Power Overview", description: "EPS"})
      |> render_submit()

      assert [%Cadence.Dashboards.DashboardSummary{} = summary] =
               Cadence.Dashboards.list_dashboard_summaries(
                 mission.organization_id,
                 mission.mission_id
               )

      assert summary.name == "Power Overview"
      assert summary.widget_count == 0

      assert {:ok, document} =
               Cadence.Dashboards.fetch_document(
                 mission.organization_id,
                 mission.mission_id,
                 summary.dashboard_id
               )

      assert document.name == "Power Overview"
      assert document.placements == []
      assert_redirect(view, show_path(mission, summary))
    end

    test "lists dashboards as navigation cards and in the rail" do
      {conn, _org, mission} = signed_in_org_and_mission()
      dashboard = TestFixtures.persist_dashboard_document!(mission, name: "Thermal")

      {:ok, view, html} = live(conn, ~p"/missions/#{mission.mission_id}/ops/dashboards")

      assert has_element?(
               view,
               ~s(#ops-dashboards-page a[href="#{show_path(mission, dashboard)}"])
             )

      assert has_element?(view, ~s(#ops-nav-rail a[href="#{show_path(mission, dashboard)}"]))
      assert html =~ "Thermal"
      assert html =~ "0 widgets"
      assert has_element?(view, "#ops-utc-clock")
    end

    test "requires a signed-in member" do
      {_conn, _org, mission} = signed_in_org_and_mission()

      assert {:error, {:redirect, %{to: to}}} =
               live(
                 Phoenix.ConnTest.build_conn(),
                 ~p"/missions/#{mission.mission_id}/ops/dashboards"
               )

      assert to =~ "/sign-in"
    end
  end

  describe "dashboard console" do
    test "records direct historical workflow requests from the dashboard toolbar" do
      {conn, org, mission} = signed_in_org_and_mission()
      %Document{} = dashboard = TestFixtures.persist_dashboard_document!(mission, name: "Power")

      {:ok, view, _html} = live(conn, show_path(mission, dashboard))
      render_dashboard_async(view)

      view
      |> element("#dashboard-historical-workflow-request-button")
      |> render_click()

      assert has_element?(view, "#dashboard-historical-workflow-request-form")

      assert has_element?(
               view,
               ~s(input[name="historical_workflow_request[dashboard_id]"][value="#{dashboard.dashboard_id}"])
             )

      assert has_element?(
               view,
               ~s(input[name="historical_workflow_request[dashboard_version]"][value="1"])
             )

      assert has_element?(
               view,
               ~s(input[name="historical_workflow_request[dashboard_limit_mode]"][value="observed"])
             )

      assert has_element?(
               view,
               ~s(#dashboard-historical-workflow-request-preview [data-preview-field="dashboard"]),
               "#{dashboard.dashboard_id} v1"
             )

      view
      |> element("#dashboard-historical-workflow-request-form")
      |> render_submit(%{
        "historical_workflow_request" => %{
          "workflow" => "backfill",
          "run_id" => "dashboard-workflow-run-direct",
          "realm" => "backfill",
          "data_source_id" => "managed_questdb_backfill",
          "source_binding_id" => "backfill_telemetry",
          "observable_id" => "HK.counter",
          "point_id" => "HK.counter",
          "source_from" => "2026-06-22T10:00:00Z",
          "source_to" => "2026-06-22T11:00:00Z",
          "dashboard_id" => dashboard.dashboard_id,
          "dashboard_version" => "1",
          "dashboard_time_mode" => "live",
          "dashboard_replay_run_id" => "",
          "dashboard_data_view" => "canonical",
          "dashboard_limit_mode" => "observed",
          "reason" => "operator_requested_backfill_from_dashboard",
          "confirmed" => "confirmed"
        }
      })

      assert_patch(view)

      assert [requested] =
               Storage.list_backfill_lifecycle_events(
                 mission.mission_id,
                 organization_id: org.organization_id,
                 backfill_run_id: "dashboard-workflow-run-direct"
               )

      assert requested.event_type == :backfill_requested
      assert requested.reason == "operator_requested_backfill_from_dashboard"
      assert requested.realm == :backfill
      assert requested.data_source_id == "managed_questdb_backfill"
      assert requested.binding_id == "backfill_telemetry"
      assert requested.observable_id == "HK.counter"
      assert requested.point_id == "HK.counter"
      assert requested.source_from == ~U[2026-06-22 10:00:00.000000Z]
      assert requested.source_to == ~U[2026-06-22 11:00:00.000000Z]
      assert requested.payload["request_source"] == "dashboard_direct_request"

      assert requested.payload["dashboard_context"] == %{
               "dashboard_id" => dashboard.dashboard_id,
               "dashboard_version" => "1",
               "dashboard_time_mode" => "live",
               "dashboard_data_view" => "canonical",
               "dashboard_limit_mode" => "observed"
             }

      assert has_element?(
               view,
               ~s(#dashboard-data-link-inspector [data-data-link-field="Backfill run"]),
               "dashboard-workflow-run-direct"
             )

      assert has_element?(
               view,
               ~s(#dashboard-data-link-inspector [data-data-link-field="Workflow stage"]),
               "requested"
             )

      assert has_element?(
               view,
               ~s(#dashboard-historical-workflow-latest-action[data-workflow-latest-action="request"][data-workflow-latest-action-status="ok"][data-workflow-latest-action-reason="request_recorded"][data-workflow-latest-action-count="1"][data-workflow-latest-action-result-event-ids="#{requested.backfill_lifecycle_event_id}"][data-workflow-latest-action-target-event-id="#{requested.backfill_lifecycle_event_id}"][data-workflow-latest-action-target-run-id="dashboard-workflow-run-direct"][data-workflow-latest-action-dashboard-id="#{dashboard.dashboard_id}"][data-workflow-latest-action-dashboard-version="1"][data-workflow-latest-action-dashboard-time-mode="live"][data-workflow-latest-action-dashboard-data-view="canonical"][data-workflow-latest-action-dashboard-limit-mode="observed"]),
               "Historical data workflow request recorded."
             )

      assert has_element?(
               view,
               ~s(#dashboard-historical-workflow-latest-action-handoffs[data-workflow-latest-action-handoff-count="1"][data-workflow-latest-action-handoff-primary-event="#{requested.backfill_lifecycle_event_id}"])
             )

      assert has_element?(
               view,
               ~s([data-workflow-latest-action-handoff="#{requested.backfill_lifecycle_event_id}"][data-workflow-latest-action-handoff-role="target_result"][data-workflow-latest-action-handoff-href*="panel=data_link"][data-workflow-latest-action-handoff-href*="selected_target=telemetry_backfill_lifecycle_event"][data-workflow-latest-action-handoff-href*="selected_id=#{requested.backfill_lifecycle_event_id}"]),
               "Selected result"
             )
    end

    test "records direct import workflow requests from the dashboard toolbar" do
      {conn, org, mission} = signed_in_org_and_mission()
      %Document{} = dashboard = TestFixtures.persist_dashboard_document!(mission, name: "Power")

      {:ok, view, _html} = live(conn, show_path(mission, dashboard))
      render_dashboard_async(view)

      view
      |> element("#dashboard-historical-workflow-request-button")
      |> render_click()

      view
      |> element("#dashboard-historical-workflow-request-form")
      |> render_submit(%{
        "historical_workflow_request" => %{
          "workflow" => "import",
          "run_id" => "dashboard-import-run-direct",
          "realm" => "backfill",
          "data_source_id" => "customer_archive_import",
          "source_binding_id" => "import_telemetry",
          "observable_id" => "HK.counter",
          "point_id" => "HK.counter",
          "source_from" => "2026-06-22T12:00:00Z",
          "source_to" => "2026-06-22T13:00:00Z",
          "dashboard_id" => dashboard.dashboard_id,
          "dashboard_version" => "1",
          "dashboard_time_mode" => "archive",
          "dashboard_replay_run_id" => "",
          "dashboard_data_view" => "as_recorded",
          "dashboard_limit_mode" => "observed",
          "reason" => "operator_requested_import_from_dashboard",
          "confirmed" => "confirmed"
        }
      })

      assert_patch(view)

      assert [requested] =
               Storage.list_backfill_lifecycle_events(
                 mission.mission_id,
                 organization_id: org.organization_id,
                 backfill_run_id: "dashboard-import-run-direct"
               )

      assert requested.event_type == :import_requested
      assert requested.reason == "operator_requested_import_from_dashboard"
      assert requested.realm == :backfill
      assert requested.data_source_id == "customer_archive_import"
      assert requested.binding_id == "import_telemetry"
      assert requested.observable_id == "HK.counter"
      assert requested.point_id == "HK.counter"
      assert requested.source_from == ~U[2026-06-22 12:00:00.000000Z]
      assert requested.source_to == ~U[2026-06-22 13:00:00.000000Z]
      assert requested.payload["request_source"] == "dashboard_direct_request"
      assert requested.payload["workflow"] == "import"
      assert requested.payload["run_id"] == "dashboard-import-run-direct"

      assert requested.payload["dashboard_context"] == %{
               "dashboard_id" => dashboard.dashboard_id,
               "dashboard_version" => "1",
               "dashboard_time_mode" => "archive",
               "dashboard_data_view" => "as_recorded",
               "dashboard_limit_mode" => "observed"
             }

      assert has_element?(
               view,
               ~s(#dashboard-data-link-inspector [data-data-link-field="Workflow"]),
               "import"
             )

      assert has_element?(
               view,
               ~s(#dashboard-data-link-inspector [data-data-link-field="Event type"]),
               "import_requested"
             )

      assert has_element?(
               view,
               ~s(#dashboard-data-link-inspector [data-data-link-field="Workflow run"]),
               "dashboard-import-run-direct"
             )

      assert has_element?(
               view,
               ~s(#dashboard-historical-workflow-latest-action[data-workflow-latest-action="request"][data-workflow-latest-action-status="ok"][data-workflow-latest-action-reason="request_recorded"][data-workflow-latest-action-count="1"][data-workflow-latest-action-result-event-ids="#{requested.backfill_lifecycle_event_id}"][data-workflow-latest-action-target-event-id="#{requested.backfill_lifecycle_event_id}"][data-workflow-latest-action-target-run-id="dashboard-import-run-direct"]),
               "Historical data workflow request recorded."
             )

      assert has_element?(
               view,
               ~s([data-workflow-latest-action-handoff="#{requested.backfill_lifecycle_event_id}"][data-workflow-latest-action-handoff-role="target_result"][data-workflow-latest-action-handoff-href*="panel=data_link"][data-workflow-latest-action-handoff-href*="selected_target=telemetry_backfill_lifecycle_event"][data-workflow-latest-action-handoff-href*="selected_id=#{requested.backfill_lifecycle_event_id}"]),
               "Selected result"
             )
    end

    test "records grouped import workflow requests and group approval from the dashboard toolbar" do
      {conn, org, mission} = signed_in_org_and_mission()
      %Document{} = dashboard = TestFixtures.persist_dashboard_document!(mission, name: "Power")

      {:ok, view, _html} = live(conn, show_path(mission, dashboard))
      render_dashboard_async(view)

      view
      |> element("#dashboard-historical-workflow-request-button")
      |> render_click()

      view
      |> element("#dashboard-historical-workflow-request-form")
      |> render_submit(%{
        "historical_workflow_request" => %{
          "workflow" => "import",
          "run_id" => "dashboard-import-run-bulk",
          "realm" => "backfill",
          "data_source_id" => "customer_archive_import",
          "source_binding_id" => "import_telemetry",
          "point_ids" => "HK.counter, HK.voltage",
          "source_from" => "2026-06-22T14:00:00Z",
          "source_to" => "2026-06-22T15:00:00Z",
          "dashboard_id" => dashboard.dashboard_id,
          "dashboard_version" => "1",
          "dashboard_time_mode" => "archive",
          "dashboard_replay_run_id" => "",
          "dashboard_data_view" => "as_recorded",
          "dashboard_limit_mode" => "observed",
          "reason" => "operator_requested_bulk_import_from_dashboard",
          "confirmed" => "confirmed"
        }
      })

      assert_patch(view)

      requested_events =
        mission.mission_id
        |> Storage.list_backfill_lifecycle_events(
          organization_id: org.organization_id,
          event_type: :import_requested
        )
        |> Enum.filter(&(&1.payload["request_group_id"] == "dashboard-import-run-bulk"))
        |> Enum.sort_by(& &1.payload["request_item_index"])

      assert Enum.map(requested_events, & &1.point_id) == ["HK.counter", "HK.voltage"]

      assert Enum.map(requested_events, & &1.backfill_run_id) == [
               "dashboard-import-run-bulk-001",
               "dashboard-import-run-bulk-002"
             ]

      assert Enum.all?(requested_events, &(&1.payload["workflow"] == "import"))
      assert Enum.all?(requested_events, &(&1.payload["request_mode"] == "bulk_points"))
      assert Enum.all?(requested_events, &(&1.payload["request_item_count"] == 2))
      assert Enum.all?(requested_events, &(&1.realm == :backfill))
      assert Enum.all?(requested_events, &(&1.data_source_id == "customer_archive_import"))
      assert Enum.all?(requested_events, &(&1.binding_id == "import_telemetry"))

      assert has_element?(
               view,
               ~s(#dashboard-historical-workflow-latest-action[data-workflow-latest-action="request"][data-workflow-latest-action-status="ok"][data-workflow-latest-action-reason="request_group_recorded"][data-workflow-latest-action-request-group-id="dashboard-import-run-bulk"][data-workflow-latest-action-count="2"][data-workflow-latest-action-result-event-ids*="#{Enum.at(requested_events, 0).backfill_lifecycle_event_id}"][data-workflow-latest-action-result-event-ids*="#{Enum.at(requested_events, 1).backfill_lifecycle_event_id}"][data-workflow-latest-action-target-run-id="dashboard-import-run-bulk-001"][data-workflow-latest-action-dashboard-id="#{dashboard.dashboard_id}"][data-workflow-latest-action-dashboard-version="1"][data-workflow-latest-action-dashboard-time-mode="archive"][data-workflow-latest-action-dashboard-data-view="as_recorded"][data-workflow-latest-action-dashboard-limit-mode="observed"]),
               "Historical data workflow request group recorded for 2 points."
             )

      assert has_element?(
               view,
               ~s(#dashboard-historical-workflow-group-summary[data-historical-workflow-group-state="requested"][data-historical-workflow-group-size="2"][data-historical-workflow-group-requested="2"][data-historical-workflow-group-approved="0"][data-historical-workflow-group-approve-eligible="2"])
             )

      assert has_element?(
               view,
               ~s(#dashboard-historical-workflow-group-eligible-items[data-historical-workflow-group-eligible-request-group="dashboard-import-run-bulk"][data-historical-workflow-group-eligible-size="2"])
             )

      view
      |> element("#dashboard-historical-workflow-group-form")
      |> render_submit(%{
        "historical_workflow_group" => %{
          "workflow" => "import",
          "request_group_id" => "dashboard-import-run-bulk",
          "realm" => "backfill",
          "data_source_id" => "customer_archive_import",
          "source_binding_id" => "import_telemetry",
          "stage" => "approved",
          "reason" => "operator_approved_bulk_import_from_dashboard",
          "dashboard_id" => dashboard.dashboard_id,
          "dashboard_version" => "1",
          "dashboard_time_mode" => "archive",
          "dashboard_replay_run_id" => "",
          "dashboard_data_view" => "as_recorded",
          "dashboard_limit_mode" => "observed",
          "confirmed" => "confirmed"
        }
      })

      assert_patch(view)

      approved_events =
        mission.mission_id
        |> Storage.list_backfill_lifecycle_events(
          organization_id: org.organization_id,
          event_type: :import_approved
        )
        |> Enum.filter(&(&1.payload["request_group_id"] == "dashboard-import-run-bulk"))
        |> Enum.sort_by(& &1.payload["request_item_index"])

      assert Enum.map(approved_events, & &1.point_id) == ["HK.counter", "HK.voltage"]

      assert Enum.map(approved_events, & &1.backfill_run_id) == [
               "dashboard-import-run-bulk-001",
               "dashboard-import-run-bulk-002"
             ]

      assert Enum.all?(
               approved_events,
               &(&1.reason == "operator_approved_bulk_import_from_dashboard")
             )

      assert Enum.all?(
               approved_events,
               &(&1.payload["group_transition_source"] == "dashboard_group_action")
             )

      assert has_element?(
               view,
               ~s(#dashboard-data-link-inspector [data-data-link-field="Workflow"]),
               "import"
             )

      assert has_element?(
               view,
               ~s(#dashboard-data-link-inspector [data-data-link-field="Event type"]),
               "import_approved"
             )

      assert has_element?(
               view,
               ~s(#dashboard-historical-workflow-latest-action[data-workflow-latest-action="group_stage_transition"][data-workflow-latest-action-status="ok"][data-workflow-latest-action-reason="group_approved_recorded"][data-workflow-latest-action-stage="approved"][data-workflow-latest-action-request-group-id="dashboard-import-run-bulk"][data-workflow-latest-action-count="2"][data-workflow-latest-action-result-event-ids*="#{Enum.at(approved_events, 0).backfill_lifecycle_event_id}"][data-workflow-latest-action-result-event-ids*="#{Enum.at(approved_events, 1).backfill_lifecycle_event_id}"][data-workflow-latest-action-target-run-id="dashboard-import-run-bulk-001"][data-workflow-latest-action-dashboard-id="#{dashboard.dashboard_id}"][data-workflow-latest-action-dashboard-version="1"][data-workflow-latest-action-dashboard-time-mode="archive"][data-workflow-latest-action-dashboard-data-view="as_recorded"][data-workflow-latest-action-dashboard-limit-mode="observed"]),
               "Historical data workflow group approved recorded for 2 items."
             )

      view
      |> element("#dashboard-historical-workflow-group-form")
      |> render_submit(%{
        "historical_workflow_group" => %{
          "workflow" => "import",
          "request_group_id" => "dashboard-import-run-bulk",
          "realm" => "backfill",
          "data_source_id" => "customer_archive_import",
          "source_binding_id" => "import_telemetry",
          "stage" => "started",
          "reason" => "operator_started_bulk_import_from_dashboard",
          "dashboard_id" => dashboard.dashboard_id,
          "dashboard_version" => "1",
          "dashboard_time_mode" => "archive",
          "dashboard_replay_run_id" => "",
          "dashboard_data_view" => "as_recorded",
          "dashboard_limit_mode" => "observed",
          "confirmed" => "confirmed"
        }
      })

      assert_patch(view)

      started_events =
        mission.mission_id
        |> Storage.list_backfill_lifecycle_events(
          organization_id: org.organization_id,
          event_type: :import_started
        )
        |> Enum.filter(&(&1.payload["request_group_id"] == "dashboard-import-run-bulk"))
        |> Enum.sort_by(& &1.payload["request_item_index"])

      assert Enum.map(started_events, & &1.backfill_run_id) == [
               "dashboard-import-run-bulk-001",
               "dashboard-import-run-bulk-002"
             ]

      assert Enum.all?(
               started_events,
               &(&1.reason == "operator_started_bulk_import_from_dashboard")
             )

      assert {:ok, counter_job} =
               Cadence.fetch_telemetry_historical_data_workflow_job(
                 "dashboard-import-run-bulk-001"
               )

      assert {:ok, voltage_job} =
               Cadence.fetch_telemetry_historical_data_workflow_job(
                 "dashboard-import-run-bulk-002"
               )

      assert Enum.map([counter_job, voltage_job], & &1.status) == [:queued, :queued]

      assert Enum.map([counter_job, voltage_job], & &1.payload["workflow"]) == [
               "import",
               "import"
             ]

      assert has_element?(
               view,
               ~s(#dashboard-historical-workflow-latest-action[data-workflow-latest-action="group_stage_transition"][data-workflow-latest-action-status="ok"][data-workflow-latest-action-reason="group_started"][data-workflow-latest-action-stage="started"][data-workflow-latest-action-request-group-id="dashboard-import-run-bulk"][data-workflow-latest-action-count="2"][data-workflow-latest-action-queued-jobs="2"][data-workflow-latest-action-failed-jobs="0"][data-workflow-latest-action-dashboard-id="#{dashboard.dashboard_id}"][data-workflow-latest-action-dashboard-version="1"][data-workflow-latest-action-dashboard-time-mode="archive"][data-workflow-latest-action-dashboard-data-view="as_recorded"][data-workflow-latest-action-dashboard-limit-mode="observed"]),
               "Historical data workflow group started for 2 items; 2 jobs queued."
             )

      claimed_jobs = Cadence.Jobs.claim_jobs(2)

      assert MapSet.new(Enum.map(claimed_jobs, & &1.job_id)) ==
               MapSet.new([counter_job.job_id, voltage_job.job_id])

      assert {:ok, completed_job} = Cadence.Jobs.run_job(counter_job.job_id)
      assert completed_job.status == :completed

      import_events =
        Storage.list_backfill_lifecycle_events(
          mission.mission_id,
          organization_id: org.organization_id,
          backfill_run_id: "dashboard-import-run-bulk-001"
        )

      assert Enum.map(import_events, & &1.event_type) == [
               :import_requested,
               :import_approved,
               :import_started,
               :import_completed
             ]

      completed_event = List.last(import_events)
      assert completed_event.reason == "historical_data_job_completed"
      assert completed_event.payload["workflow_job_status"] == "completed"
      assert completed_event.payload["job_id"] == counter_job.job_id
      assert completed_event.payload["request_group_id"] == "dashboard-import-run-bulk"
    end

    test "retries failed import workflow jobs from the lifecycle inspector" do
      {conn, org, mission} = signed_in_org_and_mission()
      %Document{} = dashboard = TestFixtures.persist_dashboard_document!(mission, name: "Power")

      assert {:ok, event} =
               Cadence.record_telemetry_historical_data_workflow_event(
                 "import",
                 "failed",
                 %{
                   import_run_id: "dashboard-import-run-retry",
                   organization_id: org.organization_id,
                   mission_id: mission.mission_id,
                   realm: :backfill,
                   data_source_id: "customer_archive_import",
                   binding_id: "import_telemetry",
                   observable_id: "HK.counter",
                   point_id: "HK.counter",
                   source_from: ~U[2026-06-22 12:00:00Z],
                   source_to: ~U[2026-06-22 13:00:00Z],
                   authority: :advisory,
                   reason: "historical_data_job_failed",
                   actor_id: "system",
                   actor_kind: "system",
                   payload: %{
                     "dashboard_context" => %{
                       "dashboard_id" => dashboard.dashboard_id,
                       "dashboard_version" => "1",
                       "dashboard_time_mode" => "archive",
                       "dashboard_data_view" => "as_recorded",
                       "dashboard_limit_mode" => "observed"
                     },
                     "failure" => "archive source window unavailable"
                   }
                 },
                 dashboard_runtime_invalidation?: false
               )

      assert event.event_type == :import_failed
      assert event.backfill_run_id == "dashboard-import-run-retry"
      assert event.payload["workflow"] == "import"

      assert {:ok, job} =
               Cadence.Jobs.enqueue(
                 :telemetry_historical_data_workflow,
                 mission.mission_id,
                 "dashboard-import-run-retry",
                 %{
                   "workflow" => "import",
                   "attrs" => %{"import_run_id" => "dashboard-import-run-retry"}
                 }
               )

      assert [claimed_job] = Cadence.Jobs.claim_jobs(1)
      assert claimed_job.job_id == job.job_id
      assert {:ok, failed_job} = Cadence.Jobs.fail_worker_start(job.job_id, :source_window_failed)
      assert failed_job.status == :failed

      path =
        show_path(mission, dashboard) <>
          "?panel=data_link&selected_target=telemetry_backfill_lifecycle_event&selected_id=#{event.backfill_lifecycle_event_id}"

      {:ok, view, _html} = live(conn, path)
      render_dashboard_async(view)

      assert has_element?(
               view,
               ~s(#dashboard-data-link-inspector [data-data-link-field="Workflow"]),
               "import"
             )

      assert has_element?(
               view,
               ~s(#dashboard-data-link-inspector [data-data-link-field="Event type"]),
               "import_failed"
             )

      assert has_element?(
               view,
               ~s(#dashboard-historical-workflow-job-status[data-historical-workflow-job-id="#{job.job_id}"][data-historical-workflow-job-status="failed"])
             )

      assert has_element?(
               view,
               ~s(#dashboard-historical-workflow-job-guidance[data-historical-workflow-job-guidance-next-action="retry_job"][data-historical-workflow-job-guidance-retry-eligible="true"][data-historical-workflow-job-guidance-retry-reason="failed_job_retryable"]),
               "Retry failed job #{job.job_id}"
             )

      view
      |> element("#dashboard-historical-workflow-retry-job")
      |> render_click()

      assert_patch(view)

      assert {:ok, retried_job} = Cadence.fetch_background_job(job.job_id)
      assert retried_job.status == :queued
      assert retried_job.attempt_count == 1
      assert retried_job.failure_reason == nil

      events =
        Storage.list_backfill_lifecycle_events(
          mission.mission_id,
          organization_id: org.organization_id,
          backfill_run_id: "dashboard-import-run-retry"
        )

      assert Enum.map(events, & &1.event_type) == [:import_failed, :import_retried]
      retried_event = List.last(events)
      assert retried_event.reason == "dashboard_historical_workflow_retried"
      assert retried_event.payload["workflow"] == "import"
      assert retried_event.payload["retry_action"] == "retry_job"
      assert retried_event.payload["retry_source_event_id"] == event.backfill_lifecycle_event_id
      assert retried_event.payload["retry_source_event_type"] == "import_failed"
      assert retried_event.payload["retry_job_id"] == job.job_id
      assert retried_event.payload["retry_job_status"] == "queued"

      assert retried_event.payload["dashboard_context"] == %{
               "dashboard_id" => dashboard.dashboard_id,
               "dashboard_version" => "1",
               "dashboard_time_mode" => "archive",
               "dashboard_data_view" => "as_recorded",
               "dashboard_limit_mode" => "observed"
             }

      assert has_element?(
               view,
               ~s(#dashboard-data-link-inspector [data-data-link-field="Workflow stage"]),
               "retried"
             )

      assert has_element?(
               view,
               ~s(#dashboard-historical-workflow-latest-action[data-workflow-latest-action="retry_job"][data-workflow-latest-action-status="ok"][data-workflow-latest-action-reason="retry_job_recorded"][data-workflow-latest-action-job-id="#{job.job_id}"][data-workflow-latest-action-result-event-ids="#{retried_event.backfill_lifecycle_event_id}"][data-workflow-latest-action-target-event-id="#{retried_event.backfill_lifecycle_event_id}"][data-workflow-latest-action-target-run-id="dashboard-import-run-retry"][data-workflow-latest-action-dashboard-id="#{dashboard.dashboard_id}"][data-workflow-latest-action-dashboard-version="1"][data-workflow-latest-action-dashboard-time-mode="archive"][data-workflow-latest-action-dashboard-data-view="as_recorded"][data-workflow-latest-action-dashboard-limit-mode="observed"]),
               retried_event.backfill_lifecycle_event_id
             )

      assert has_element?(
               view,
               ~s([data-workflow-latest-action-handoff="#{retried_event.backfill_lifecycle_event_id}"][data-workflow-latest-action-handoff-role="target_result"][data-workflow-latest-action-handoff-href*="panel=data_link"][data-workflow-latest-action-handoff-href*="selected_target=telemetry_backfill_lifecycle_event"][data-workflow-latest-action-handoff-href*="selected_id=#{retried_event.backfill_lifecycle_event_id}"]),
               "Selected result"
             )

      assert has_element?(
               view,
               ~s(#dashboard-data-link-inspector [data-data-link-field="Workflow retry source event"]),
               event.backfill_lifecycle_event_id
             )

      assert has_element?(
               view,
               ~s(#dashboard-historical-workflow-job-status[data-historical-workflow-job-id="#{job.job_id}"][data-historical-workflow-job-status="queued"])
             )

      refute has_element?(view, "#dashboard-historical-workflow-retry-job")
    end

    test "retries grouped failed import workflow jobs from the lifecycle inspector" do
      {conn, org, mission} = signed_in_org_and_mission()
      %Document{} = dashboard = TestFixtures.persist_dashboard_document!(mission, name: "Power")

      import_items = [
        {"HK.counter", "dashboard-import-run-group-retry-001", 1},
        {"HK.voltage", "dashboard-import-run-group-retry-002", 2}
      ]

      failed_items =
        for {point_id, run_id, item_index} <- import_items do
          assert {:ok, job} =
                   Cadence.Jobs.enqueue(
                     :telemetry_historical_data_workflow,
                     mission.mission_id,
                     run_id,
                     %{"workflow" => "import", "attrs" => %{"import_run_id" => run_id}}
                   )

          assert [claimed_job] = Cadence.Jobs.claim_jobs(1)
          assert claimed_job.job_id == job.job_id
          assert {:ok, failed_job} = Cadence.Jobs.fail_worker_start(job.job_id, :source_failed)
          assert failed_job.status == :failed

          assert {:ok, failed_event} =
                   Cadence.record_telemetry_historical_data_workflow_event(
                     "import",
                     "failed",
                     %{
                       import_run_id: run_id,
                       organization_id: org.organization_id,
                       mission_id: mission.mission_id,
                       realm: :backfill,
                       data_source_id: "customer_archive_import",
                       binding_id: "import_telemetry",
                       observable_id: point_id,
                       point_id: point_id,
                       source_from: ~U[2026-06-22 14:00:00Z],
                       source_to: ~U[2026-06-22 15:00:00Z],
                       authority: :advisory,
                       reason: "historical_data_job_failed",
                       actor_id: "system",
                       actor_kind: "system",
                       payload: %{
                         "request_source" => "dashboard_direct_request",
                         "request_mode" => "bulk_points",
                         "request_group_id" => "dashboard-import-run-group-retry",
                         "request_item_index" => item_index,
                         "request_item_count" => 2,
                         "request_item_run_id" => run_id,
                         "job_id" => job.job_id,
                         "dashboard_context" => %{
                           "dashboard_id" => dashboard.dashboard_id,
                           "dashboard_version" => "1",
                           "dashboard_time_mode" => "archive",
                           "dashboard_data_view" => "as_recorded",
                           "dashboard_limit_mode" => "observed"
                         },
                         "source" => %{
                           "failure" => %{
                             "code" => "archive_source_window_unavailable",
                             "retryable" => true,
                             "recovery_action" => "retry_job"
                           }
                         }
                       }
                     },
                     dashboard_runtime_invalidation?: false
                   )

          {failed_event, job}
        end

      [{first_failed_event, first_job}, {second_failed_event, second_job}] = failed_items

      path =
        show_path(mission, dashboard) <>
          "?panel=data_link&selected_target=telemetry_backfill_lifecycle_event&selected_id=#{first_failed_event.backfill_lifecycle_event_id}"

      {:ok, view, _html} = live(conn, path)
      render_dashboard_async(view)

      assert has_element?(
               view,
               ~s(#dashboard-data-link-inspector [data-data-link-field="Workflow"]),
               "import"
             )

      assert has_element?(
               view,
               ~s(#dashboard-historical-workflow-group-summary[data-historical-workflow-group-state="failed"][data-historical-workflow-group-failed="2"][data-historical-workflow-group-retryable-failed="2"][data-historical-workflow-group-nonretryable-failed="0"]),
               "HK.counter"
             )

      assert has_element?(
               view,
               ~s(#dashboard-historical-workflow-group-recovery-guidance[data-historical-workflow-group-recovery-guidance-next-action="retry_failed_items"][data-historical-workflow-group-recovery-guidance-retry-eligible="true"][data-historical-workflow-group-recovery-guidance-retry-reason="retryable_group_failures"]),
               "Retry 2 failed jobs in request group dashboard-import-run-group-retry"
             )

      assert has_element?(
               view,
               ~s(#dashboard-historical-workflow-group-retry-failed[data-workflow-action-eligible-count="2"])
             )

      view
      |> element("#dashboard-historical-workflow-group-retry-failed")
      |> render_click()

      assert_patch(view)

      assert has_element?(
               view,
               ~s(#dashboard-historical-workflow-latest-action[data-workflow-latest-action="retry_group_failed_jobs"][data-workflow-latest-action-status="ok"][data-workflow-latest-action-request-group-id="dashboard-import-run-group-retry"][data-workflow-latest-action-retried="2"][data-workflow-latest-action-retry-nonretryable="0"][data-workflow-latest-action-retry-skipped="0"][data-workflow-latest-action-retry-errors="0"][data-workflow-latest-action-dashboard-id="#{dashboard.dashboard_id}"][data-workflow-latest-action-dashboard-version="1"][data-workflow-latest-action-dashboard-time-mode="archive"][data-workflow-latest-action-dashboard-data-view="as_recorded"][data-workflow-latest-action-dashboard-limit-mode="observed"])
             )

      assert {:ok, retried_first_job} = Cadence.fetch_background_job(first_job.job_id)
      assert retried_first_job.status == :queued

      assert {:ok, retried_second_job} = Cadence.fetch_background_job(second_job.job_id)
      assert retried_second_job.status == :queued

      retried_events =
        mission.mission_id
        |> Storage.list_backfill_lifecycle_events(
          organization_id: org.organization_id,
          event_type: :import_retried
        )
        |> Enum.filter(&(&1.payload["request_group_id"] == "dashboard-import-run-group-retry"))
        |> Enum.sort_by(& &1.payload["request_item_index"])

      assert Enum.map(retried_events, & &1.backfill_run_id) == [
               "dashboard-import-run-group-retry-001",
               "dashboard-import-run-group-retry-002"
             ]

      assert Enum.map(retried_events, & &1.payload["workflow"]) == ["import", "import"]

      assert Enum.map(retried_events, & &1.payload["retry_source_event_id"]) == [
               first_failed_event.backfill_lifecycle_event_id,
               second_failed_event.backfill_lifecycle_event_id
             ]

      assert Enum.map(retried_events, & &1.payload["retry_source_event_type"]) == [
               "import_failed",
               "import_failed"
             ]

      assert Enum.map(retried_events, & &1.payload["retry_job_id"]) == [
               first_job.job_id,
               second_job.job_id
             ]

      assert has_element?(
               view,
               ~s(#dashboard-data-link-inspector [data-data-link-field="Event type"]),
               "import_retried"
             )
    end

    test "records corrected import workflow requests from the lifecycle inspector" do
      {conn, org, mission} = signed_in_org_and_mission()
      %Document{} = dashboard = TestFixtures.persist_dashboard_document!(mission, name: "Power")

      assert {:ok, event} =
               Cadence.record_telemetry_historical_data_workflow_event(
                 "import",
                 "failed",
                 %{
                   import_run_id: "dashboard-import-run-nonretryable",
                   organization_id: org.organization_id,
                   mission_id: mission.mission_id,
                   realm: :backfill,
                   data_source_id: "customer_archive_import",
                   binding_id: "import_telemetry",
                   authority: :advisory,
                   reason: "historical_data_job_failed",
                   actor_id: "system",
                   actor_kind: "system",
                   payload: %{
                     "dashboard_context" => %{
                       "dashboard_id" => dashboard.dashboard_id,
                       "dashboard_version" => "1",
                       "dashboard_time_mode" => "archive",
                       "dashboard_data_view" => "as_recorded",
                       "dashboard_limit_mode" => "observed"
                     },
                     "source" => %{
                       "failure" => %{
                         "code" => "missing_field:point_id",
                         "retryable" => false,
                         "retry_blockers" => ["missing point_id"],
                         "recovery_action" => "correct_workflow_request"
                       }
                     }
                   }
                 },
                 dashboard_runtime_invalidation?: false
               )

      assert event.event_type == :import_failed
      assert event.backfill_run_id == "dashboard-import-run-nonretryable"

      assert {:ok, job} =
               Cadence.Jobs.enqueue(
                 :telemetry_historical_data_workflow,
                 mission.mission_id,
                 "dashboard-import-run-nonretryable",
                 %{
                   "workflow" => "import",
                   "attrs" => %{"import_run_id" => "dashboard-import-run-nonretryable"}
                 }
               )

      assert [claimed_job] = Cadence.Jobs.claim_jobs(1)
      assert claimed_job.job_id == job.job_id
      assert {:ok, failed_job} = Cadence.Jobs.fail_worker_start(job.job_id, :missing_point_id)
      assert failed_job.status == :failed

      path =
        show_path(mission, dashboard) <>
          "?panel=data_link&selected_target=telemetry_backfill_lifecycle_event&selected_id=#{event.backfill_lifecycle_event_id}"

      {:ok, view, _html} = live(conn, path)
      render_dashboard_async(view)

      assert has_element?(
               view,
               ~s(#dashboard-data-link-inspector [data-data-link-field="Workflow"]),
               "import"
             )

      assert has_element?(
               view,
               ~s(#dashboard-historical-workflow-job-guidance[data-historical-workflow-job-guidance-next-action="create_corrected_request"][data-historical-workflow-job-guidance-retry-eligible="false"][data-historical-workflow-job-guidance-retry-reason="correction_required"][data-historical-workflow-job-guidance-correction-eligible="true"][data-historical-workflow-job-guidance-correction-reason="correction_request_required"]),
               "Create a corrected request for failed event"
             )

      refute has_element?(view, "#dashboard-historical-workflow-retry-job")
      assert has_element?(view, "#dashboard-historical-workflow-correction-form")

      view
      |> element("#dashboard-historical-workflow-correction-form")
      |> render_submit(%{
        "historical_workflow_correction" => %{
          "workflow" => "import",
          "run_id" => "dashboard-import-run-corrected",
          "original_run_id" => "dashboard-import-run-nonretryable",
          "original_event_id" => event.backfill_lifecycle_event_id,
          "original_job_id" => job.job_id,
          "realm" => "backfill",
          "data_source_id" => "customer_archive_import",
          "source_binding_id" => "import_telemetry",
          "observable_id" => "HK.counter",
          "point_id" => "HK.counter",
          "source_from" => "2026-06-22T14:00:00Z",
          "source_to" => "2026-06-22T15:00:00Z",
          "reason" => "operator_corrected_import_missing_point",
          "dashboard_id" => dashboard.dashboard_id,
          "dashboard_version" => "1",
          "dashboard_time_mode" => "archive",
          "dashboard_replay_run_id" => "",
          "dashboard_data_view" => "as_recorded",
          "dashboard_limit_mode" => "observed",
          "confirmed" => "confirmed"
        }
      })

      assert_patch(view)

      assert [corrected] =
               Storage.list_backfill_lifecycle_events(
                 mission.mission_id,
                 organization_id: org.organization_id,
                 backfill_run_id: "dashboard-import-run-corrected"
               )

      assert corrected.event_type == :import_requested
      assert corrected.reason == "operator_corrected_import_missing_point"
      assert corrected.point_id == "HK.counter"
      assert corrected.payload["workflow"] == "import"
      assert corrected.payload["recovery_action"] == "correct_workflow_request"
      assert corrected.payload["correction_source"] == "dashboard_correction_request"
      assert corrected.payload["correction_source_event_type"] == "import_failed"
      assert corrected.payload["corrects_run_id"] == "dashboard-import-run-nonretryable"
      assert corrected.payload["corrects_event_id"] == event.backfill_lifecycle_event_id
      assert corrected.payload["corrects_job_id"] == job.job_id

      assert corrected.payload["dashboard_context"] == %{
               "dashboard_id" => dashboard.dashboard_id,
               "dashboard_version" => "1",
               "dashboard_time_mode" => "archive",
               "dashboard_data_view" => "as_recorded",
               "dashboard_limit_mode" => "observed"
             }

      assert has_element?(
               view,
               ~s(#dashboard-data-link-inspector [data-data-link-field="Workflow"]),
               "import"
             )

      assert has_element?(
               view,
               ~s(#dashboard-data-link-inspector [data-data-link-field="Event type"]),
               "import_requested"
             )

      assert has_element?(
               view,
               ~s(#dashboard-historical-workflow-latest-action[data-workflow-latest-action="correction_request"][data-workflow-latest-action-status="ok"][data-workflow-latest-action-reason="correction_request_recorded"][data-workflow-latest-action-result-event-ids="#{corrected.backfill_lifecycle_event_id}"][data-workflow-latest-action-target-event-id="#{corrected.backfill_lifecycle_event_id}"][data-workflow-latest-action-target-run-id="dashboard-import-run-corrected"]),
               "Corrected historical data workflow request recorded."
             )

      assert has_element?(
               view,
               ~s(#dashboard-data-link-inspector [data-data-link-field="Workflow correction source event type"]),
               "import_failed"
             )

      assert has_element?(
               view,
               ~s(#dashboard-data-link-inspector [data-data-link-field="Workflow correction source event"]),
               event.backfill_lifecycle_event_id
             )
    end

    test "shows completed corrected import workflow evidence in the lifecycle inspector" do
      previous_history_store = Application.get_env(:cadence, :telemetry_history_store, [])

      Application.put_env(:cadence, :telemetry_history_store,
        module: HistoryStoreETS,
        max_samples_per_point: :infinity
      )

      start_supervised!(HistoryStoreETS)
      HistoryStoreETS.reset()

      on_exit(fn ->
        Application.put_env(:cadence, :telemetry_history_store, previous_history_store)
      end)

      {conn, org, mission} = signed_in_org_and_mission()
      %Document{} = dashboard = TestFixtures.persist_dashboard_document!(mission, name: "Power")

      assert {:ok, failed_source_job} =
               Cadence.Jobs.enqueue(
                 :telemetry_historical_data_workflow,
                 mission.mission_id,
                 "dashboard-import-run-correction-completed-source",
                 %{
                   "workflow" => "import",
                   "attrs" => %{
                     "import_run_id" => "dashboard-import-run-correction-completed-source"
                   }
                 }
               )

      assert [claimed_failed_source_job] = Cadence.Jobs.claim_jobs(1)
      assert claimed_failed_source_job.job_id == failed_source_job.job_id

      assert {:ok, failed_source_job} =
               Cadence.Jobs.fail_worker_start(failed_source_job.job_id, :missing_point_id)

      assert {:ok, source_event} =
               Cadence.record_telemetry_historical_data_workflow_event(
                 "import",
                 "failed",
                 %{
                   import_run_id: "dashboard-import-run-correction-completed-source",
                   organization_id: org.organization_id,
                   mission_id: mission.mission_id,
                   realm: :backfill,
                   data_source_id: "customer_archive_import",
                   binding_id: "import_telemetry",
                   observable_id: "HK.counter",
                   point_id: "HK.counter",
                   source_from: ~U[2026-06-22 14:00:00Z],
                   source_to: ~U[2026-06-22 15:00:00Z],
                   authority: :advisory,
                   reason: "historical_data_job_failed",
                   actor_id: "system",
                   actor_kind: "system",
                   payload: %{
                     "request_source" => "dashboard_direct_request",
                     "request_mode" => "bulk_points",
                     "request_group_id" => "dashboard-import-run-correction-completed",
                     "request_item_index" => 1,
                     "request_item_count" => 1,
                     "request_item_run_id" => "dashboard-import-run-correction-completed-source",
                     "job_id" => failed_source_job.job_id,
                     "dashboard_context" => %{
                       "dashboard_id" => dashboard.dashboard_id,
                       "dashboard_version" => "1",
                       "dashboard_time_mode" => "archive",
                       "dashboard_data_view" => "as_recorded",
                       "dashboard_limit_mode" => "observed"
                     },
                     "source" => %{
                       "failure" => %{
                         "code" => "missing_field:point_id",
                         "retryable" => false,
                         "recovery_action" => "correct_workflow_request"
                       }
                     }
                   }
                 },
                 dashboard_runtime_invalidation?: false
               )

      assert {:ok, correction_request} =
               Cadence.record_telemetry_historical_data_workflow_correction_request(
                 "import",
                 %{
                   import_run_id: "dashboard-import-run-correction-completed-fixed",
                   organization_id: org.organization_id,
                   mission_id: mission.mission_id,
                   realm: :backfill,
                   data_source_id: "customer_archive_import",
                   binding_id: "import_telemetry",
                   observable_id: "HK.counter",
                   point_id: "HK.counter",
                   source_from: ~U[2026-06-22 14:00:00Z],
                   source_to: ~U[2026-06-22 15:00:00Z],
                   authority: :unknown,
                   reason: "operator_corrected_completed_import"
                 },
                 %{"original_event_id" => source_event.backfill_lifecycle_event_id},
                 dashboard_runtime_invalidation?: false
               )

      assert {:ok, [_approved], [{:ok, nil}]} =
               Cadence.record_telemetry_historical_data_workflow_group_transition(
                 "import",
                 "approved",
                 "dashboard-import-run-correction-completed",
                 %{
                   organization_id: org.organization_id,
                   mission_id: mission.mission_id,
                   realm: :backfill,
                   data_source_id: "customer_archive_import",
                   binding_id: "import_telemetry",
                   authority: :authoritative,
                   reason: "operator_approved_completed_import"
                 },
                 dashboard_runtime_invalidation?: false
               )

      assert {:ok, [_started], [{:ok, started_job}]} =
               Cadence.record_telemetry_historical_data_workflow_group_transition(
                 "import",
                 "started",
                 "dashboard-import-run-correction-completed",
                 %{
                   organization_id: org.organization_id,
                   mission_id: mission.mission_id,
                   realm: :backfill,
                   data_source_id: "customer_archive_import",
                   binding_id: "import_telemetry",
                   authority: :authoritative,
                   reason: "operator_started_completed_import"
                 },
                 dashboard_runtime_invalidation?: false
               )

      source_sample =
        telemetry_sample(
          mission,
          "dashboard-import-completed-correction-source-sample",
          "HK.counter",
          ~U[2026-06-22 14:10:00Z],
          ~U[2026-06-22 14:10:03Z],
          raw_value: 91,
          engineering_value: 91,
          provenance: %{
            "storage" => %{
              "realm" => "backfill",
              "data_source_id" => "customer_archive_import",
              "binding_id" => "import_telemetry"
            }
          }
        )

      assert :ok = persist_sample_scope!(source_sample)
      assert :ok = HistoryStore.persist_samples([source_sample])
      assert [claimed_started_job] = Cadence.Jobs.claim_jobs(1)
      assert claimed_started_job.job_id == started_job.job_id
      assert {:ok, completed_job} = Cadence.Jobs.run_job(started_job.job_id)
      assert completed_job.status == :completed

      events =
        Storage.list_backfill_lifecycle_events(
          mission.mission_id,
          organization_id: org.organization_id,
          backfill_run_id: "dashboard-import-run-correction-completed-fixed"
        )

      assert Enum.map(events, & &1.event_type) == [
               :import_requested,
               :import_approved,
               :import_started,
               :import_completed
             ]

      completed_event = List.last(events)
      assert completed_event.backfill_run_id == correction_request.backfill_run_id
      assert completed_event.sample_count == 1
      assert completed_event.payload["workflow_job_status"] == "completed"

      assert completed_event.payload["corrects_event_id"] ==
               source_event.backfill_lifecycle_event_id

      assert completed_event.payload["corrects_job_id"] == failed_source_job.job_id

      completed_path =
        show_path(mission, dashboard) <>
          "?panel=data_link&selected_target=telemetry_backfill_lifecycle_event&selected_id=#{completed_event.backfill_lifecycle_event_id}"

      {:ok, view, _html} = live(conn, completed_path)
      render_dashboard_async(view)

      assert has_element?(
               view,
               ~s(#dashboard-data-link-inspector [data-data-link-field="Workflow"]),
               "import"
             )

      assert has_element?(
               view,
               ~s(#dashboard-data-link-inspector [data-data-link-field="Event type"]),
               "import_completed"
             )

      assert has_element?(
               view,
               ~s(#dashboard-data-link-inspector [data-data-link-field="Workflow job"]),
               started_job.job_id
             )

      assert has_element?(
               view,
               ~s(#dashboard-data-link-inspector [data-data-link-field="Workflow job status"]),
               "completed"
             )

      assert has_element?(
               view,
               ~s(#dashboard-data-link-inspector [data-data-link-field="Workflow correction source event type"]),
               "import_failed"
             )

      assert has_element?(
               view,
               ~s(#dashboard-data-link-inspector [data-data-link-field="Workflow correction source event"]),
               source_event.backfill_lifecycle_event_id
             )

      assert has_element?(
               view,
               ~s(#dashboard-data-link-inspector [data-data-link-field="Workflow correction source job"]),
               failed_source_job.job_id
             )

      assert has_element?(
               view,
               ~s(#dashboard-historical-workflow-job-status[data-historical-workflow-job-id="#{started_job.job_id}"][data-historical-workflow-job-status="completed"])
             )

      assert has_element?(
               view,
               ~s([data-data-link-related-id="#{source_event.backfill_lifecycle_event_id}"]),
               "Correction source event"
             )
    end

    test "records grouped historical workflow requests for multiple points" do
      {conn, org, mission} = signed_in_org_and_mission()
      %Document{} = dashboard = TestFixtures.persist_dashboard_document!(mission, name: "Power")

      {:ok, view, _html} = live(conn, show_path(mission, dashboard))
      render_dashboard_async(view)

      view
      |> element("#dashboard-historical-workflow-request-button")
      |> render_click()

      view
      |> element("#dashboard-historical-workflow-request-form")
      |> render_submit(%{
        "historical_workflow_request" => %{
          "workflow" => "backfill",
          "run_id" => "dashboard-workflow-run-bulk",
          "realm" => "backfill",
          "data_source_id" => "managed_questdb_backfill",
          "source_binding_id" => "backfill_telemetry",
          "point_ids" => "HK.counter, HK.voltage\nHK.current",
          "source_from" => "2026-06-22T10:00:00Z",
          "source_to" => "2026-06-22T11:00:00Z",
          "reason" => "operator_requested_bulk_backfill_from_dashboard",
          "confirmed" => "confirmed"
        }
      })

      assert_patch(view)

      events =
        mission.mission_id
        |> Storage.list_backfill_lifecycle_events(organization_id: org.organization_id)
        |> Enum.filter(&(&1.payload["request_group_id"] == "dashboard-workflow-run-bulk"))
        |> Enum.sort_by(& &1.point_id)

      assert Enum.map(events, & &1.point_id) == ["HK.counter", "HK.current", "HK.voltage"]

      assert Enum.map(events, & &1.backfill_run_id) == [
               "dashboard-workflow-run-bulk-001",
               "dashboard-workflow-run-bulk-003",
               "dashboard-workflow-run-bulk-002"
             ]

      assert Enum.all?(events, &(&1.event_type == :backfill_requested))
      assert Enum.all?(events, &(&1.payload["request_mode"] == "bulk_points"))
      assert Enum.all?(events, &(&1.payload["request_item_count"] == 3))
      assert Enum.all?(events, &(&1.reason == "operator_requested_bulk_backfill_from_dashboard"))

      assert has_element?(
               view,
               ~s(#dashboard-data-link-inspector [data-data-link-field="Request mode"]),
               "bulk_points"
             )

      assert has_element?(
               view,
               ~s(#dashboard-data-link-inspector [data-data-link-field="Request group"]),
               "dashboard-workflow-run-bulk"
             )

      assert has_element?(
               view,
               ~s(#dashboard-data-link-inspector [data-data-link-field="Request item"]),
               "1/3"
             )

      assert has_element?(
               view,
               ~s(#dashboard-historical-workflow-group-summary[data-historical-workflow-group-state="requested"][data-historical-workflow-group-terminal="false"][data-historical-workflow-group-size="3"][data-historical-workflow-group-requested="3"][data-historical-workflow-group-approved="0"][data-historical-workflow-group-started="0"][data-historical-workflow-group-completed="0"][data-historical-workflow-group-failed="0"][data-historical-workflow-group-request-eligible="0"][data-historical-workflow-group-approve-eligible="3"][data-historical-workflow-group-start-eligible="0"][data-historical-workflow-group-complete-eligible="0"])
             )

      assert has_element?(view, "#dashboard-historical-workflow-group-form")

      assert has_element?(
               view,
               ~s(#dashboard-historical-workflow-group-eligible-items[data-historical-workflow-group-eligible-request-group="dashboard-workflow-run-bulk"][data-historical-workflow-group-eligible-size="3"])
             )

      assert has_element?(
               view,
               ~s([data-historical-workflow-group-eligible-action="approved"][data-historical-workflow-group-eligible-count="3"][data-historical-workflow-group-eligible-state="true"]),
               "Record approve transition for 3 eligible items in request group dashboard-workflow-run-bulk"
             )

      assert has_element?(
               view,
               ~s([data-historical-workflow-group-eligible-action="started"][data-historical-workflow-group-eligible-count="0"][data-historical-workflow-group-eligible-state="false"][data-historical-workflow-group-eligible-reason="no_eligible_group_items"]),
               "No request-group items are eligible for start"
             )

      assert has_element?(
               view,
               ~s|#dashboard-historical-workflow-group-approved[data-historical-workflow-group-action-eligible="3"][data-workflow-action-id="group_stage_approved"][data-workflow-action-eligible="true"][data-workflow-action-reason="eligible_group_items"]:not([disabled])|
             )

      view
      |> element("#dashboard-historical-workflow-group-form")
      |> render_submit(%{
        "historical_workflow_group" => %{
          "workflow" => "backfill",
          "request_group_id" => "dashboard-workflow-run-bulk",
          "realm" => "backfill",
          "data_source_id" => "managed_questdb_backfill",
          "source_binding_id" => "backfill_telemetry",
          "stage" => "approved",
          "reason" => "operator_approved_bulk_backfill_from_dashboard",
          "confirmed" => "confirmed"
        }
      })

      assert_patch(view)

      approved_events =
        mission.mission_id
        |> Storage.list_backfill_lifecycle_events(
          organization_id: org.organization_id,
          event_type: :backfill_approved
        )
        |> Enum.filter(&(&1.payload["request_group_id"] == "dashboard-workflow-run-bulk"))
        |> Enum.sort_by(& &1.payload["request_item_index"])

      assert Enum.map(approved_events, & &1.point_id) == [
               "HK.counter",
               "HK.voltage",
               "HK.current"
             ]

      assert Enum.all?(
               approved_events,
               &(&1.reason == "operator_approved_bulk_backfill_from_dashboard")
             )

      assert Enum.all?(
               approved_events,
               &(&1.payload["group_transition_source"] == "dashboard_group_action")
             )

      duplicate_submit_html =
        view
        |> element("#dashboard-historical-workflow-group-form")
        |> render_submit(%{
          "historical_workflow_group" => %{
            "workflow" => "backfill",
            "request_group_id" => "dashboard-workflow-run-bulk",
            "realm" => "backfill",
            "data_source_id" => "managed_questdb_backfill",
            "source_binding_id" => "backfill_telemetry",
            "stage" => "approved",
            "reason" => "operator_duplicate_approved_bulk_backfill_from_dashboard",
            "confirmed" => "confirmed"
          }
        })

      assert duplicate_submit_html =~
               "No approve items are eligible in request group dashboard-workflow-run-bulk"

      refute duplicate_submit_html =~ "no_eligible_request_group_items"

      assert has_element?(
               view,
               ~s(#dashboard-historical-workflow-latest-action[data-workflow-latest-action="group_stage_transition"][data-workflow-latest-action-status="no_op"][data-workflow-latest-action-reason="no_eligible_group_items"][data-workflow-latest-action-stage="approved"][data-workflow-latest-action-request-group-id="dashboard-workflow-run-bulk"]),
               "No approve items are eligible in request group dashboard-workflow-run-bulk"
             )

      duplicate_approved_events =
        mission.mission_id
        |> Storage.list_backfill_lifecycle_events(
          organization_id: org.organization_id,
          event_type: :backfill_approved
        )
        |> Enum.filter(
          &(&1.payload["request_group_id"] == "dashboard-workflow-run-bulk" and
              &1.reason == "operator_duplicate_approved_bulk_backfill_from_dashboard")
        )

      assert duplicate_approved_events == []

      assert has_element?(
               view,
               ~s(#dashboard-data-link-inspector [data-data-link-field="Workflow stage"]),
               "approved"
             )

      assert has_element?(
               view,
               ~s(#dashboard-historical-workflow-group-summary[data-historical-workflow-group-state="approved"][data-historical-workflow-group-terminal="false"][data-historical-workflow-group-requested="3"][data-historical-workflow-group-approved="3"][data-historical-workflow-group-started="0"][data-historical-workflow-group-failed="0"][data-historical-workflow-group-approve-eligible="0"][data-historical-workflow-group-start-eligible="3"][data-historical-workflow-group-complete-eligible="0"])
             )

      assert has_element?(
               view,
               ~s(#dashboard-historical-workflow-group-approved[data-historical-workflow-group-action-eligible="0"][data-workflow-action-eligible="false"][data-workflow-action-reason="no_eligible_group_items"][disabled])
             )

      assert has_element?(
               view,
               ~s|#dashboard-historical-workflow-group-started[data-historical-workflow-group-action-eligible="3"]:not([disabled])|
             )

      view
      |> element("#dashboard-historical-workflow-group-form")
      |> render_submit(%{
        "historical_workflow_group" => %{
          "workflow" => "backfill",
          "request_group_id" => "dashboard-workflow-run-bulk",
          "realm" => "backfill",
          "data_source_id" => "managed_questdb_backfill",
          "source_binding_id" => "backfill_telemetry",
          "stage" => "started",
          "reason" => "operator_started_bulk_backfill_from_dashboard",
          "confirmed" => "confirmed"
        }
      })

      assert_patch(view)

      started_events =
        mission.mission_id
        |> Storage.list_backfill_lifecycle_events(
          organization_id: org.organization_id,
          event_type: :backfill_started
        )
        |> Enum.filter(&(&1.payload["request_group_id"] == "dashboard-workflow-run-bulk"))
        |> Enum.sort_by(& &1.payload["request_item_index"])

      assert Enum.map(started_events, & &1.backfill_run_id) == [
               "dashboard-workflow-run-bulk-001",
               "dashboard-workflow-run-bulk-002",
               "dashboard-workflow-run-bulk-003"
             ]

      assert Enum.all?(
               started_events,
               &(&1.reason == "operator_started_bulk_backfill_from_dashboard")
             )

      regressive_submit_html =
        view
        |> element("#dashboard-historical-workflow-group-form")
        |> render_submit(%{
          "historical_workflow_group" => %{
            "workflow" => "backfill",
            "request_group_id" => "dashboard-workflow-run-bulk",
            "realm" => "backfill",
            "data_source_id" => "managed_questdb_backfill",
            "source_binding_id" => "backfill_telemetry",
            "stage" => "approved",
            "reason" => "operator_regressed_started_bulk_backfill_from_dashboard",
            "confirmed" => "confirmed"
          }
        })

      assert regressive_submit_html =~
               "No approve items are eligible in request group dashboard-workflow-run-bulk"

      assert has_element?(
               view,
               ~s(#dashboard-data-link-action-outcome[data-data-link-action-outcome-action="group_stage_transition"][data-data-link-action-outcome-status="no_op"][data-data-link-action-outcome-kind="info"][data-data-link-action-outcome-reason="no_eligible_group_items"]),
               "No approve items are eligible in request group dashboard-workflow-run-bulk"
             )

      assert has_element?(
               view,
               ~s(#dashboard-historical-workflow-latest-action[data-workflow-latest-action="group_stage_transition"][data-workflow-latest-action-status="no_op"][data-workflow-latest-action-reason="no_eligible_group_items"][data-workflow-latest-action-stage="approved"][data-workflow-latest-action-request-group-id="dashboard-workflow-run-bulk"]),
               "No approve items are eligible in request group dashboard-workflow-run-bulk"
             )

      regressive_approved_events =
        mission.mission_id
        |> Storage.list_backfill_lifecycle_events(
          organization_id: org.organization_id,
          event_type: :backfill_approved
        )
        |> Enum.filter(
          &(&1.payload["request_group_id"] == "dashboard-workflow-run-bulk" and
              &1.reason == "operator_regressed_started_bulk_backfill_from_dashboard")
        )

      assert regressive_approved_events == []

      assert {:ok, counter_job} =
               Cadence.fetch_telemetry_historical_data_workflow_job(
                 "dashboard-workflow-run-bulk-001"
               )

      assert {:ok, voltage_job} =
               Cadence.fetch_telemetry_historical_data_workflow_job(
                 "dashboard-workflow-run-bulk-002"
               )

      assert {:ok, current_job} =
               Cadence.fetch_telemetry_historical_data_workflow_job(
                 "dashboard-workflow-run-bulk-003"
               )

      assert Enum.map([counter_job, voltage_job, current_job], & &1.status) == [
               :queued,
               :queued,
               :queued
             ]

      assert has_element?(
               view,
               ~s(#dashboard-historical-workflow-group-job-progress[data-historical-workflow-group-job-progress="queued 3"][data-historical-workflow-group-job-progress-queued="3"][data-historical-workflow-group-job-progress-running="0"][data-historical-workflow-group-job-progress-completed="0"][data-historical-workflow-group-job-progress-failed="0"][data-historical-workflow-group-job-progress-missing="0"]),
               "dashboard-workflow-run-bulk-001"
             )

      assert has_element?(
               view,
               "#dashboard-historical-workflow-group-job-progress",
               "dashboard-workflow-run-bulk-002"
             )

      assert has_element?(
               view,
               "#dashboard-historical-workflow-group-job-progress",
               "dashboard-workflow-run-bulk-003"
             )

      assert has_element?(
               view,
               ~s(#dashboard-historical-workflow-group-summary[data-historical-workflow-group-state="running"][data-historical-workflow-group-terminal="false"][data-historical-workflow-group-requested="3"][data-historical-workflow-group-approved="3"][data-historical-workflow-group-started="3"][data-historical-workflow-group-failed="0"][data-historical-workflow-group-approve-eligible="0"][data-historical-workflow-group-start-eligible="0"][data-historical-workflow-group-complete-eligible="3"])
             )

      assert has_element?(
               view,
               ~s(#dashboard-historical-workflow-group-started[data-historical-workflow-group-action-eligible="0"][disabled])
             )

      assert has_element?(
               view,
               ~s([data-historical-workflow-group-eligible-action="completed"][data-historical-workflow-group-eligible-count="3"][data-historical-workflow-group-eligible-state="true"]),
               "Record complete transition for 3 eligible items in request group dashboard-workflow-run-bulk"
             )

      assert has_element?(
               view,
               ~s|#dashboard-historical-workflow-group-completed[data-historical-workflow-group-action-eligible="3"]:not([disabled])|
             )

      assert {:ok, counter_completed} =
               Cadence.record_telemetry_historical_data_workflow_event(
                 "backfill",
                 "completed",
                 %{
                   backfill_run_id: "dashboard-workflow-run-bulk-001",
                   organization_id: org.organization_id,
                   mission_id: mission.mission_id,
                   realm: :backfill,
                   data_source_id: "managed_questdb_backfill",
                   binding_id: "backfill_telemetry",
                   observable_id: "HK.counter",
                   point_id: "HK.counter",
                   source_from: ~U[2026-06-22 10:00:00Z],
                   source_to: ~U[2026-06-22 11:00:00Z],
                   authority: :authoritative,
                   reason: "historical_data_job_completed",
                   actor_id: "system",
                   actor_kind: "system",
                   payload: %{
                     "request_source" => "dashboard_direct_request",
                     "request_mode" => "bulk_points",
                     "request_group_id" => "dashboard-workflow-run-bulk",
                     "request_item_index" => 1,
                     "request_item_count" => 3,
                     "request_item_run_id" => "dashboard-workflow-run-bulk-001"
                   }
                 },
                 dashboard_runtime_invalidation?: false
               )

      assert {:ok, failed_voltage_job} =
               Cadence.Jobs.fail_worker_start(voltage_job.job_id, :source_window_unavailable)

      assert failed_voltage_job.status == :failed

      assert {:ok, failed_current_job} =
               Cadence.Jobs.fail_worker_start(current_job.job_id, :missing_point_id)

      assert failed_current_job.status == :failed

      assert {:ok, failed_event} =
               Cadence.record_telemetry_historical_data_workflow_event(
                 "backfill",
                 "failed",
                 %{
                   backfill_run_id: "dashboard-workflow-run-bulk-002",
                   organization_id: org.organization_id,
                   mission_id: mission.mission_id,
                   realm: :backfill,
                   data_source_id: "managed_questdb_backfill",
                   binding_id: "backfill_telemetry",
                   observable_id: "HK.voltage",
                   point_id: "HK.voltage",
                   source_from: ~U[2026-06-22 10:00:00Z],
                   source_to: ~U[2026-06-22 11:00:00Z],
                   authority: :advisory,
                   reason: "historical_data_job_failed",
                   actor_id: "system",
                   actor_kind: "system",
                   payload: %{
                     "request_source" => "dashboard_direct_request",
                     "request_mode" => "bulk_points",
                     "request_group_id" => "dashboard-workflow-run-bulk",
                     "request_item_index" => 2,
                     "request_item_count" => 3,
                     "request_item_run_id" => "dashboard-workflow-run-bulk-002",
                     "source" => %{
                       "failure" => %{
                         "code" => "source_window_unavailable",
                         "retryable" => true,
                         "recovery_action" => "retry_job"
                       }
                     }
                   }
                 },
                 dashboard_runtime_invalidation?: false
               )

      assert {:ok, nonretryable_failed_event} =
               Cadence.record_telemetry_historical_data_workflow_event(
                 "backfill",
                 "failed",
                 %{
                   backfill_run_id: "dashboard-workflow-run-bulk-003",
                   organization_id: org.organization_id,
                   mission_id: mission.mission_id,
                   realm: :backfill,
                   data_source_id: "managed_questdb_backfill",
                   binding_id: "backfill_telemetry",
                   observable_id: "HK.current",
                   point_id: "HK.current",
                   source_from: ~U[2026-06-22 10:00:00Z],
                   source_to: ~U[2026-06-22 11:00:00Z],
                   authority: :advisory,
                   reason: "historical_data_job_failed",
                   actor_id: "system",
                   actor_kind: "system",
                   payload: %{
                     "request_source" => "dashboard_direct_request",
                     "request_mode" => "bulk_points",
                     "request_group_id" => "dashboard-workflow-run-bulk",
                     "request_item_index" => 3,
                     "request_item_count" => 3,
                     "request_item_run_id" => "dashboard-workflow-run-bulk-003",
                     "source" => %{
                       "failure" => %{
                         "code" => "missing_field:point_id",
                         "retryable" => false,
                         "retry_blockers" => ["missing point_id"],
                         "recovery_action" => "correct_workflow_request"
                       }
                     }
                   }
                 },
                 dashboard_runtime_invalidation?: false
               )

      failed_path =
        show_path(mission, dashboard) <>
          "?panel=data_link&selected_target=telemetry_backfill_lifecycle_event&selected_id=#{failed_event.backfill_lifecycle_event_id}"

      {:ok, failed_view, _html} = live(conn, failed_path)
      render_dashboard_async(failed_view)

      assert has_element?(
               failed_view,
               ~s(#dashboard-historical-workflow-group-summary[data-historical-workflow-group-state="completed_with_failures"][data-historical-workflow-group-terminal="true"][data-historical-workflow-group-completed="1"][data-historical-workflow-group-failed="2"][data-historical-workflow-group-retryable-failed="1"][data-historical-workflow-group-nonretryable-failed="1"]),
               "HK.voltage"
             )

      assert has_element?(
               failed_view,
               ~s(#dashboard-historical-workflow-group-job-progress[data-historical-workflow-group-job-progress="queued 1, failed 2"][data-historical-workflow-group-job-progress-queued="1"][data-historical-workflow-group-job-progress-running="0"][data-historical-workflow-group-job-progress-completed="0"][data-historical-workflow-group-job-progress-failed="2"][data-historical-workflow-group-job-progress-missing="0"]),
               "dashboard-workflow-run-bulk-002"
             )

      assert has_element?(
               failed_view,
               ~s(#dashboard-historical-workflow-group-execution-audit[data-historical-workflow-group-execution-audit-request-group="dashboard-workflow-run-bulk"][data-historical-workflow-group-execution-audit-summary*="failed 2"][data-historical-workflow-group-execution-audit-summary*="job_progress queued 1, failed 2"])
             )

      assert has_element?(
               failed_view,
               ~s([data-historical-workflow-group-execution-step="failed"][data-historical-workflow-group-execution-count="2"]),
               "HK.current"
             )

      assert has_element?(
               failed_view,
               "#dashboard-historical-workflow-group-summary",
               "HK.current"
             )

      assert has_element?(
               failed_view,
               ~s(#dashboard-historical-workflow-group-recovery[data-historical-workflow-group-recovery-id="dashboard-workflow-run-bulk"][data-historical-workflow-group-recovery-failed="2"][data-historical-workflow-group-recovery-retryable="1"][data-historical-workflow-group-recovery-correction="1"][data-historical-workflow-group-recovery-resolved="0"][data-historical-workflow-group-recovery-retried="0"][data-historical-workflow-group-recovery-correction-requested="0"]),
               "HK.voltage"
             )

      assert has_element?(
               failed_view,
               ~s(#dashboard-historical-workflow-group-recovery[data-historical-workflow-group-recovery-next-action="retry_failed_items"][data-historical-workflow-group-recovery-unresolved="2"][data-historical-workflow-group-recovery-correction-task-count="0"])
             )

      assert has_element?(
               failed_view,
               ~s(#dashboard-historical-workflow-group-recovery-guidance[data-historical-workflow-group-recovery-guidance-next-action="retry_failed_items"][data-historical-workflow-group-recovery-guidance-retry-eligible="true"][data-historical-workflow-group-recovery-guidance-retry-reason="retryable_group_failures"]),
               "Retry 1 failed jobs in request group dashboard-workflow-run-bulk"
             )

      assert has_element?(
               failed_view,
               ~s(#dashboard-historical-workflow-group-recovery-execution-plan[data-historical-workflow-group-recovery-execution-plan-request-group="dashboard-workflow-run-bulk"][data-historical-workflow-group-recovery-execution-plan-next-action="retry_failed_items"][data-historical-workflow-group-recovery-execution-plan-retry-eligible="true"][data-historical-workflow-group-recovery-execution-plan-retry-count="1"][data-historical-workflow-group-recovery-execution-plan-correction-count="1"][data-historical-workflow-group-recovery-execution-plan-unresolved="2"]),
               "Retry will requeue 1 failed item and select the retried lifecycle event."
             )

      assert has_element?(
               failed_view,
               ~s(#dashboard-historical-workflow-group-retry-failed[data-workflow-action-eligible-count="1"][data-workflow-action-expected-effect="Retry will requeue 1 failed item and select the retried lifecycle event."])
             )

      assert has_element?(
               failed_view,
               "#dashboard-historical-workflow-group-recovery",
               "HK.current"
             )

      assert has_element?(
               failed_view,
               ~s(#dashboard-historical-workflow-group-recovery[data-historical-workflow-group-recovery-failed-item-handoffs="2"])
             )

      assert has_element?(
               failed_view,
               ~s([data-historical-workflow-group-recovery-failed-item="#{failed_event.backfill_lifecycle_event_id}"][data-historical-workflow-group-recovery-failed-item-label="HK.voltage"][data-historical-workflow-group-recovery-failed-item-recovery="retry_job"][data-historical-workflow-group-recovery-failed-item-retryable="true"][data-historical-workflow-group-recovery-failed-item-href*="selected_target=telemetry_backfill_lifecycle_event"][data-historical-workflow-group-recovery-failed-item-href*="selected_id=#{failed_event.backfill_lifecycle_event_id}"]),
               "HK.voltage"
             )

      assert has_element?(
               failed_view,
               ~s([data-historical-workflow-group-recovery-failed-item="#{nonretryable_failed_event.backfill_lifecycle_event_id}"][data-historical-workflow-group-recovery-failed-item-label="HK.current"][data-historical-workflow-group-recovery-failed-item-recovery="correct_workflow_request"][data-historical-workflow-group-recovery-failed-item-retryable="false"][data-historical-workflow-group-recovery-failed-item-href*="selected_target=telemetry_backfill_lifecycle_event"][data-historical-workflow-group-recovery-failed-item-href*="selected_id=#{nonretryable_failed_event.backfill_lifecycle_event_id}"]),
               "HK.current"
             )

      assert has_element?(failed_view, "#dashboard-historical-workflow-group-retry-failed")

      failed_view
      |> element("#dashboard-historical-workflow-group-retry-failed")
      |> render_click()

      assert_patch(failed_view)

      assert has_element?(
               failed_view,
               ~s(#dashboard-historical-workflow-latest-action[data-workflow-latest-action="retry_group_failed_jobs"][data-workflow-latest-action-status="ok"][data-workflow-latest-action-request-group-id="dashboard-workflow-run-bulk"][data-workflow-latest-action-retried="1"][data-workflow-latest-action-retry-nonretryable="1"][data-workflow-latest-action-retry-skipped="0"][data-workflow-latest-action-retry-errors="0"])
             )

      assert has_element?(
               failed_view,
               ~s(#dashboard-historical-workflow-latest-action[data-workflow-latest-action-retry-nonretryable-run-ids="dashboard-workflow-run-bulk-003"][data-workflow-latest-action-retry-nonretryable-event-ids="#{nonretryable_failed_event.backfill_lifecycle_event_id}"])
             )

      assert has_element?(
               failed_view,
               "#dashboard-historical-workflow-latest-action",
               "dashboard-workflow-run-bulk-003"
             )

      assert has_element?(
               failed_view,
               "#dashboard-historical-workflow-latest-action",
               nonretryable_failed_event.backfill_lifecycle_event_id
             )

      assert {:ok, retried_voltage_job} = Cadence.fetch_background_job(voltage_job.job_id)
      assert retried_voltage_job.status == :queued

      assert {:ok, still_failed_current_job} = Cadence.fetch_background_job(current_job.job_id)
      assert still_failed_current_job.status == :failed

      retried_group_events =
        mission.mission_id
        |> Storage.list_backfill_lifecycle_events(
          organization_id: org.organization_id,
          event_type: :backfill_retried
        )
        |> Enum.filter(&(&1.payload["request_group_id"] == "dashboard-workflow-run-bulk"))

      assert [retried_group_event] = retried_group_events
      assert retried_group_event.point_id == "HK.voltage"
      assert retried_group_event.payload["retry_action"] == "retry_job"

      assert retried_group_event.payload["retry_source_event_id"] ==
               failed_event.backfill_lifecycle_event_id

      assert retried_group_event.payload["retry_job_id"] == voltage_job.job_id
      assert retried_group_event.payload["retry_job_status"] == "queued"

      assert has_element?(
               failed_view,
               ~s(#dashboard-data-link-inspector [data-data-link-field="Backfill lifecycle event"]),
               retried_group_event.backfill_lifecycle_event_id
             )

      assert has_element?(
               failed_view,
               ~s(#dashboard-data-link-inspector [data-data-link-field="Workflow stage"]),
               "retried"
             )

      assert has_element?(
               failed_view,
               ~s(#dashboard-data-link-inspector [data-data-link-field="Workflow retry source event"]),
               failed_event.backfill_lifecycle_event_id
             )

      assert has_element?(
               failed_view,
               ~s(#dashboard-historical-workflow-group-summary[data-historical-workflow-group-state="failing"][data-historical-workflow-group-terminal="false"][data-historical-workflow-group-failed="1"][data-historical-workflow-group-resolved-failed="1"][data-historical-workflow-group-retry-resolved="1"][data-historical-workflow-group-correction-requested="0"][data-historical-workflow-group-retryable-failed="0"][data-historical-workflow-group-nonretryable-failed="1"]),
               "HK.current"
             )

      assert has_element?(
               failed_view,
               ~s(#dashboard-historical-workflow-group-job-progress[data-historical-workflow-group-job-progress="queued 2, failed 1"][data-historical-workflow-group-job-progress-queued="2"][data-historical-workflow-group-job-progress-running="0"][data-historical-workflow-group-job-progress-completed="0"][data-historical-workflow-group-job-progress-failed="1"][data-historical-workflow-group-job-progress-missing="0"]),
               "dashboard-workflow-run-bulk-002"
             )

      assert has_element?(
               failed_view,
               ~s([data-historical-workflow-group-execution-step="retried"][data-historical-workflow-group-execution-count="1"]),
               "HK.voltage dashboard-workflow-run-bulk-002 retried queued #{voltage_job.job_id}"
             )

      assert has_element?(
               failed_view,
               ~s(#dashboard-historical-workflow-group-recovery[data-historical-workflow-group-recovery-failed="1"][data-historical-workflow-group-recovery-retryable="0"][data-historical-workflow-group-recovery-correction="1"][data-historical-workflow-group-recovery-resolved="1"][data-historical-workflow-group-recovery-retried="1"][data-historical-workflow-group-recovery-correction-requested="0"]),
               "HK.current"
             )

      assert has_element?(
               failed_view,
               ~s(#dashboard-historical-workflow-group-recovery-guidance[data-historical-workflow-group-recovery-guidance-next-action="create_corrected_requests"][data-historical-workflow-group-recovery-guidance-retry-eligible="false"][data-historical-workflow-group-recovery-guidance-retry-reason="no_retryable_group_failures"]),
               "Create corrected workflow requests for non-retryable failed items."
             )

      assert has_element?(
               failed_view,
               ~s(#dashboard-historical-workflow-group-recovery-execution-plan[data-historical-workflow-group-recovery-execution-plan-next-action="create_corrected_requests"][data-historical-workflow-group-recovery-execution-plan-retry-eligible="false"][data-historical-workflow-group-recovery-execution-plan-retry-count="0"][data-historical-workflow-group-recovery-execution-plan-correction-count="1"][data-historical-workflow-group-recovery-execution-plan-unresolved="0"][data-historical-workflow-group-recovery-execution-plan-blockers="Non-retryable failures require corrected workflow requests from their failed-item inspectors."]),
               "Create corrected requests for 1 non-retryable failure."
             )

      assert has_element?(
               failed_view,
               ~s(#dashboard-historical-workflow-group-recovery[data-historical-workflow-group-recovery-retried-items="HK.voltage dashboard-workflow-run-bulk-002 retried queued #{voltage_job.job_id}"])
             )

      assert has_element?(
               failed_view,
               ~s(#dashboard-historical-workflow-group-recovery[data-historical-workflow-group-recovery-failed-item-handoffs="1"])
             )

      refute has_element?(
               failed_view,
               ~s([data-historical-workflow-group-recovery-failed-item="#{failed_event.backfill_lifecycle_event_id}"])
             )

      assert has_element?(
               failed_view,
               ~s([data-historical-workflow-group-recovery-failed-item="#{nonretryable_failed_event.backfill_lifecycle_event_id}"][data-historical-workflow-group-recovery-failed-item-recovery="correct_workflow_request"][data-historical-workflow-group-recovery-failed-item-retryable="false"]),
               "HK.current"
             )

      assert has_element?(
               failed_view,
               ~s([data-historical-workflow-group-retried-item="HK.voltage dashboard-workflow-run-bulk-002 retried queued #{voltage_job.job_id}"])
             )

      refute has_element?(failed_view, "#dashboard-historical-workflow-group-retry-failed")

      failed_view
      |> element(
        ~s([data-historical-workflow-group-recovery-failed-item="#{nonretryable_failed_event.backfill_lifecycle_event_id}"])
      )
      |> render_click()

      assert_patch(failed_view)
      render_dashboard_async(failed_view)

      assert has_element?(
               failed_view,
               ~s(#dashboard-data-link-inspector [data-data-link-field="Backfill lifecycle event"]),
               nonretryable_failed_event.backfill_lifecycle_event_id
             )

      assert has_element?(
               failed_view,
               ~s(#dashboard-historical-workflow-correction-form[data-workflow-action-eligible="true"][data-workflow-action-reason="correction_request_required"])
             )

      failed_view
      |> element("#dashboard-historical-workflow-correction-form")
      |> render_submit(%{
        "historical_workflow_correction" => %{
          "workflow" => "backfill",
          "run_id" => "dashboard-workflow-run-bulk-003-corrected",
          "original_run_id" => "dashboard-workflow-run-bulk-003",
          "original_event_id" => nonretryable_failed_event.backfill_lifecycle_event_id,
          "original_job_id" => current_job.job_id,
          "realm" => "backfill",
          "data_source_id" => "managed_questdb_backfill",
          "source_binding_id" => "backfill_telemetry",
          "observable_id" => "HK.current",
          "point_id" => "HK.current",
          "source_from" => "2026-06-22T10:00:00Z",
          "source_to" => "2026-06-22T11:00:00Z",
          "reason" => "operator_corrected_bulk_item",
          "request_mode" => "bulk_points",
          "request_group_id" => "dashboard-workflow-run-bulk",
          "request_item_index" => "3",
          "request_item_count" => "3",
          "request_item_run_id" => "dashboard-workflow-run-bulk-003-corrected",
          "dashboard_id" => dashboard.dashboard_id,
          "dashboard_version" => "1",
          "dashboard_time_mode" => "archive",
          "dashboard_replay_run_id" => "",
          "dashboard_data_view" => "as_recorded",
          "dashboard_limit_mode" => "observed",
          "confirmed" => "confirmed"
        }
      })

      assert_patch(failed_view)

      assert [corrected_group_event] =
               Storage.list_backfill_lifecycle_events(
                 mission.mission_id,
                 organization_id: org.organization_id,
                 backfill_run_id: "dashboard-workflow-run-bulk-003-corrected"
               )

      assert corrected_group_event.payload["request_group_id"] == "dashboard-workflow-run-bulk"
      assert corrected_group_event.payload["request_item_index"] == 3
      assert corrected_group_event.payload["request_item_count"] == 3

      assert corrected_group_event.payload["request_item_run_id"] ==
               "dashboard-workflow-run-bulk-003-corrected"

      assert corrected_group_event.payload["dashboard_context"] == %{
               "dashboard_id" => dashboard.dashboard_id,
               "dashboard_version" => "1",
               "dashboard_time_mode" => "archive",
               "dashboard_data_view" => "as_recorded",
               "dashboard_limit_mode" => "observed"
             }

      assert has_element?(
               failed_view,
               ~s(#dashboard-historical-workflow-latest-action[data-workflow-latest-action="correction_request"][data-workflow-latest-action-status="ok"][data-workflow-latest-action-reason="correction_request_recorded"][data-workflow-latest-action-request-group-id="dashboard-workflow-run-bulk"][data-workflow-latest-action-result-event-ids="#{corrected_group_event.backfill_lifecycle_event_id}"][data-workflow-latest-action-target-event-id="#{corrected_group_event.backfill_lifecycle_event_id}"][data-workflow-latest-action-target-run-id="dashboard-workflow-run-bulk-003-corrected"]),
               "Corrected historical data workflow request recorded."
             )

      corrected_group_path =
        show_path(mission, dashboard) <>
          "?panel=data_link&selected_target=telemetry_backfill_lifecycle_event&selected_id=#{corrected_group_event.backfill_lifecycle_event_id}"

      {:ok, corrected_group_view, _html} = live(conn, corrected_group_path)
      render_dashboard_async(corrected_group_view)

      assert has_element?(
               corrected_group_view,
               ~s(#dashboard-historical-workflow-group-summary[data-historical-workflow-group-state="running"][data-historical-workflow-group-terminal="false"][data-historical-workflow-group-requested="3"][data-historical-workflow-group-started="2"][data-historical-workflow-group-completed="1"][data-historical-workflow-group-failed="0"][data-historical-workflow-group-resolved-failed="2"][data-historical-workflow-group-retry-resolved="1"][data-historical-workflow-group-correction-requested="1"][data-historical-workflow-group-correction-started="0"][data-historical-workflow-group-correction-completed="0"][data-historical-workflow-group-correction-superseded="0"][data-historical-workflow-group-retryable-failed="0"][data-historical-workflow-group-nonretryable-failed="0"])
             )

      assert has_element?(
               corrected_group_view,
               ~s(#dashboard-historical-workflow-group-recovery[data-historical-workflow-group-recovery-failed="0"][data-historical-workflow-group-recovery-retryable="0"][data-historical-workflow-group-recovery-correction="0"][data-historical-workflow-group-recovery-resolved="2"][data-historical-workflow-group-recovery-retried="1"][data-historical-workflow-group-recovery-correction-requested="1"])
             )

      assert has_element?(
               corrected_group_view,
               ~s(#dashboard-historical-workflow-group-recovery[data-historical-workflow-group-recovery-corrected-items="HK.current dashboard-workflow-run-bulk-003 corrected dashboard-workflow-run-bulk-003-corrected requested #{current_job.job_id}"])
             )

      assert has_element?(
               corrected_group_view,
               ~s([data-historical-workflow-group-execution-step="corrected"][data-historical-workflow-group-execution-count="1"]),
               "HK.current dashboard-workflow-run-bulk-003 corrected dashboard-workflow-run-bulk-003-corrected requested #{current_job.job_id}"
             )

      assert has_element?(
               corrected_group_view,
               ~s([data-historical-workflow-group-execution-step="recovery_tasks"][data-historical-workflow-group-execution-count="1"]),
               "HK.current dashboard-workflow-run-bulk-003 replacement dashboard-workflow-run-bulk-003-corrected stage requested next approve"
             )

      assert has_element?(
               corrected_group_view,
               ~s([data-historical-workflow-group-corrected-item="HK.current dashboard-workflow-run-bulk-003 corrected dashboard-workflow-run-bulk-003-corrected requested #{current_job.job_id}"])
             )

      assert has_element?(
               corrected_group_view,
               ~s([data-historical-workflow-group-correction-task="HK.current dashboard-workflow-run-bulk-003 replacement dashboard-workflow-run-bulk-003-corrected stage requested next approve"])
             )

      assert has_element?(
               corrected_group_view,
               ~s(#dashboard-historical-workflow-group-recovery-remaining-work[data-historical-workflow-group-recovery-remaining-work-count="1"][data-historical-workflow-group-recovery-remaining-work-pending-count="1"][data-historical-workflow-group-recovery-remaining-work-completed-count="0"][data-historical-workflow-group-recovery-remaining-work-next-actions="approve"][data-historical-workflow-group-recovery-remaining-work-pending-runs="dashboard-workflow-run-bulk-003-corrected"])
             )

      assert has_element?(
               corrected_group_view,
               ~s(#dashboard-historical-workflow-group-recovery-closure-readiness[data-historical-workflow-group-recovery-closure-status="inspect_job_state"][data-historical-workflow-group-recovery-closure-action="inspect_missing_replacement_jobs"][data-historical-workflow-group-recovery-closure-unresolved="0"][data-historical-workflow-group-recovery-closure-pending-replacements="1"][data-historical-workflow-group-recovery-closure-blocked-jobs="1"][data-historical-workflow-group-recovery-closure-failed-jobs="0"][data-historical-workflow-group-recovery-closure-missing-jobs="1"][data-historical-workflow-group-recovery-closure-missing-runs="dashboard-workflow-run-bulk-003-corrected"][data-historical-workflow-group-recovery-closure-stale-jobs="0"])
             )

      {:ok, missing_inspection_view, _html} = live(conn, corrected_group_path)
      render_dashboard_async(missing_inspection_view)

      missing_inspection_view
      |> element(
        "#dashboard-historical-workflow-missing-replacement-inspect-dashboard-workflow-run-bulk-003-corrected"
      )
      |> render_click()

      assert_patch(missing_inspection_view)

      assert has_element?(
               missing_inspection_view,
               ~s(#dashboard-historical-workflow-latest-action[data-workflow-latest-action="missing_replacement_job_inspection"][data-workflow-latest-action-status="ok"][data-workflow-latest-action-reason="missing_replacement_job_inspection_recorded"][data-workflow-latest-action-request-group-id="dashboard-workflow-run-bulk"][data-workflow-latest-action-target-run-id="dashboard-workflow-run-bulk-003-corrected"][data-workflow-latest-action-dashboard-id="#{dashboard.dashboard_id}"][data-workflow-latest-action-dashboard-version="1"][data-workflow-latest-action-dashboard-time-mode="archive"][data-workflow-latest-action-dashboard-data-view="as_recorded"][data-workflow-latest-action-dashboard-limit-mode="observed"])
             )

      assert has_element?(
               corrected_group_view,
               ~s([data-historical-workflow-group-recovery-remaining-work-replacement-run="dashboard-workflow-run-bulk-003-corrected"][data-historical-workflow-group-recovery-remaining-work-stage="requested"][data-historical-workflow-group-recovery-remaining-work-next-action="approve"][data-historical-workflow-group-recovery-remaining-work-status="pending"])
             )

      assert has_element?(
               corrected_group_view,
               ~s(#dashboard-historical-workflow-group-recovery-advance-corrected-form[data-historical-workflow-group-recovery-advance-request-group="dashboard-workflow-run-bulk"][data-historical-workflow-group-recovery-advance-stage="approved"][data-historical-workflow-group-recovery-advance-eligible="true"][data-historical-workflow-group-recovery-advance-count="1"]),
               "Advance 1 corrected replacement request to approved."
             )

      assert has_element?(
               corrected_group_view,
               ~s(#dashboard-historical-workflow-group-recovery-advance-corrected[data-workflow-action-stage="approved"][data-workflow-action-eligible="true"][data-workflow-action-eligible-count="1"][data-workflow-action-correction-tasks="HK.current dashboard-workflow-run-bulk-003 replacement dashboard-workflow-run-bulk-003-corrected stage requested next approve"])
             )

      corrected_group_view
      |> element("#dashboard-historical-workflow-group-recovery-advance-corrected-form")
      |> render_submit(%{
        "historical_workflow_group" => %{
          "workflow" => "backfill",
          "request_group_id" => "dashboard-workflow-run-bulk",
          "realm" => "backfill",
          "data_source_id" => "managed_questdb_backfill",
          "source_binding_id" => "backfill_telemetry",
          "stage" => "approved",
          "reason" => "dashboard_recovery_replacement_approved",
          "group_transition_scope" => "replacement_corrections",
          "group_correction_tasks" =>
            "HK.current dashboard-workflow-run-bulk-003 replacement dashboard-workflow-run-bulk-003-corrected stage requested next approve",
          "confirmed" => "confirmed"
        }
      })

      assert_patch(corrected_group_view)

      approved_replacement_events =
        mission.mission_id
        |> Storage.list_backfill_lifecycle_events(
          organization_id: org.organization_id,
          event_type: :backfill_approved
        )
        |> Enum.filter(
          &(&1.payload["request_group_id"] == "dashboard-workflow-run-bulk" and
              &1.reason == "dashboard_recovery_replacement_approved")
        )

      assert [approved_replacement_event] = approved_replacement_events

      assert approved_replacement_event.backfill_run_id ==
               "dashboard-workflow-run-bulk-003-corrected"

      assert {:ok, _corrected_group_started} =
               Cadence.record_telemetry_historical_data_workflow_event(
                 "backfill",
                 "started",
                 %{
                   backfill_run_id: "dashboard-workflow-run-bulk-003-corrected",
                   organization_id: org.organization_id,
                   mission_id: mission.mission_id,
                   realm: :backfill,
                   data_source_id: "managed_questdb_backfill",
                   binding_id: "backfill_telemetry",
                   observable_id: "HK.current",
                   point_id: "HK.current",
                   source_from: ~U[2026-06-22 10:00:00Z],
                   source_to: ~U[2026-06-22 11:00:00Z],
                   authority: :authoritative,
                   reason: "operator_started_corrected_bulk_item",
                   actor_id: "operator",
                   actor_kind: "operator",
                   payload: %{
                     "recovery_action" => "correct_workflow_request",
                     "corrects_run_id" => "dashboard-workflow-run-bulk-003",
                     "corrects_event_id" => nonretryable_failed_event.backfill_lifecycle_event_id,
                     "corrects_job_id" => current_job.job_id,
                     "request_source" => "dashboard_direct_request",
                     "request_mode" => "bulk_points",
                     "request_group_id" => "dashboard-workflow-run-bulk",
                     "request_item_index" => 3,
                     "request_item_count" => 3,
                     "request_item_run_id" => "dashboard-workflow-run-bulk-003-corrected"
                   }
                 },
                 dashboard_runtime_invalidation?: false
               )

      assert {:ok, corrected_group_completed} =
               Cadence.record_telemetry_historical_data_workflow_event(
                 "backfill",
                 "completed",
                 %{
                   backfill_run_id: "dashboard-workflow-run-bulk-003-corrected",
                   organization_id: org.organization_id,
                   mission_id: mission.mission_id,
                   realm: :backfill,
                   data_source_id: "managed_questdb_backfill",
                   binding_id: "backfill_telemetry",
                   observable_id: "HK.current",
                   point_id: "HK.current",
                   source_from: ~U[2026-06-22 10:00:00Z],
                   source_to: ~U[2026-06-22 11:00:00Z],
                   authority: :authoritative,
                   reason: "historical_data_job_completed",
                   actor_id: "system",
                   actor_kind: "system",
                   payload: %{
                     "recovery_action" => "correct_workflow_request",
                     "corrects_run_id" => "dashboard-workflow-run-bulk-003",
                     "corrects_event_id" => nonretryable_failed_event.backfill_lifecycle_event_id,
                     "corrects_job_id" => current_job.job_id,
                     "request_source" => "dashboard_direct_request",
                     "request_mode" => "bulk_points",
                     "request_group_id" => "dashboard-workflow-run-bulk",
                     "request_item_index" => 3,
                     "request_item_count" => 3,
                     "request_item_run_id" => "dashboard-workflow-run-bulk-003-corrected"
                   }
                 },
                 dashboard_runtime_invalidation?: false
               )

      corrected_group_completed_path =
        show_path(mission, dashboard) <>
          "?panel=data_link&selected_target=telemetry_backfill_lifecycle_event&selected_id=#{corrected_group_completed.backfill_lifecycle_event_id}"

      {:ok, corrected_group_completed_view, _html} = live(conn, corrected_group_completed_path)
      render_dashboard_async(corrected_group_completed_view)

      assert has_element?(
               corrected_group_completed_view,
               ~s(#dashboard-historical-workflow-group-summary[data-historical-workflow-group-state="running"][data-historical-workflow-group-terminal="false"][data-historical-workflow-group-requested="3"][data-historical-workflow-group-started="3"][data-historical-workflow-group-completed="2"][data-historical-workflow-group-failed="0"][data-historical-workflow-group-resolved-failed="2"][data-historical-workflow-group-retry-resolved="1"][data-historical-workflow-group-correction-requested="1"][data-historical-workflow-group-correction-started="1"][data-historical-workflow-group-correction-completed="1"][data-historical-workflow-group-correction-superseded="1"][data-historical-workflow-group-retryable-failed="0"][data-historical-workflow-group-nonretryable-failed="0"])
             )

      assert has_element?(
               corrected_group_completed_view,
               ~s([data-historical-workflow-group-correction-task="HK.current dashboard-workflow-run-bulk-003 replacement dashboard-workflow-run-bulk-003-corrected stage completed next done"])
             )

      assert has_element?(
               corrected_group_completed_view,
               ~s(#dashboard-historical-workflow-group-recovery-remaining-work[data-historical-workflow-group-recovery-remaining-work-count="1"][data-historical-workflow-group-recovery-remaining-work-pending-count="0"][data-historical-workflow-group-recovery-remaining-work-completed-count="1"][data-historical-workflow-group-recovery-remaining-work-next-actions=""][data-historical-workflow-group-recovery-remaining-work-pending-runs=""])
             )

      assert has_element?(
               corrected_group_completed_view,
               ~s([data-historical-workflow-group-recovery-remaining-work-replacement-run="dashboard-workflow-run-bulk-003-corrected"][data-historical-workflow-group-recovery-remaining-work-stage="completed"][data-historical-workflow-group-recovery-remaining-work-next-action="done"][data-historical-workflow-group-recovery-remaining-work-status="complete"])
             )

      completed_item_path =
        show_path(mission, dashboard) <>
          "?panel=data_link&selected_target=telemetry_backfill_lifecycle_event&selected_id=#{counter_completed.backfill_lifecycle_event_id}"

      {:ok, completed_item_view, _html} = live(conn, completed_item_path)
      render_dashboard_async(completed_item_view)

      assert has_element?(
               completed_item_view,
               ~s([data-data-link-related-id="#{failed_event.backfill_lifecycle_event_id}"]),
               "Failed item HK.voltage"
             )

      assert has_element?(
               completed_item_view,
               ~s([data-data-link-related-id="#{nonretryable_failed_event.backfill_lifecycle_event_id}"]),
               "Failed item HK.current"
             )

      completed_item_view
      |> element(~s([data-data-link-related-id="#{failed_event.backfill_lifecycle_event_id}"]))
      |> render_click()

      assert_patch(completed_item_view)

      assert has_element?(
               completed_item_view,
               ~s(#dashboard-data-link-inspector [data-data-link-field="Backfill lifecycle event"]),
               failed_event.backfill_lifecycle_event_id
             )

      assert has_element?(
               completed_item_view,
               ~s(#dashboard-data-link-inspector [data-data-link-field="Workflow stage"]),
               "failed"
             )
    end

    test "group retry latest action exposes skipped item details from the product path" do
      {conn, org, mission} = signed_in_org_and_mission()
      %Document{} = dashboard = TestFixtures.persist_dashboard_document!(mission, name: "Power")

      assert {:ok, retryable_event} =
               Cadence.record_telemetry_historical_data_workflow_event(
                 "backfill",
                 "failed",
                 %{
                   backfill_run_id: "dashboard-workflow-run-skip-001",
                   organization_id: org.organization_id,
                   mission_id: mission.mission_id,
                   realm: :backfill,
                   data_source_id: "managed_questdb_backfill",
                   binding_id: "backfill_telemetry",
                   observable_id: "HK.voltage",
                   point_id: "HK.voltage",
                   source_from: ~U[2026-06-22 10:00:00Z],
                   source_to: ~U[2026-06-22 11:00:00Z],
                   authority: :advisory,
                   reason: "historical_data_job_failed",
                   actor_id: "system",
                   actor_kind: "system",
                   payload: %{
                     "request_source" => "dashboard_direct_request",
                     "request_mode" => "bulk_points",
                     "request_group_id" => "dashboard-workflow-run-skip",
                     "request_item_index" => 1,
                     "request_item_count" => 2,
                     "request_item_run_id" => "dashboard-workflow-run-skip-001",
                     "source" => %{
                       "failure" => %{
                         "code" => "source_window_unavailable",
                         "retryable" => true,
                         "recovery_action" => "retry_job"
                       }
                     }
                   }
                 },
                 dashboard_runtime_invalidation?: false
               )

      assert {:ok, skipped_event} =
               Cadence.record_telemetry_historical_data_workflow_event(
                 "backfill",
                 "failed",
                 %{
                   backfill_run_id: "dashboard-workflow-run-skip-002",
                   organization_id: org.organization_id,
                   mission_id: mission.mission_id,
                   realm: :backfill,
                   data_source_id: "managed_questdb_backfill",
                   binding_id: "backfill_telemetry",
                   observable_id: "HK.current",
                   point_id: "HK.current",
                   source_from: ~U[2026-06-22 10:00:00Z],
                   source_to: ~U[2026-06-22 11:00:00Z],
                   authority: :advisory,
                   reason: "historical_data_job_failed",
                   actor_id: "system",
                   actor_kind: "system",
                   payload: %{
                     "request_source" => "dashboard_direct_request",
                     "request_mode" => "bulk_points",
                     "request_group_id" => "dashboard-workflow-run-skip",
                     "request_item_index" => 2,
                     "request_item_count" => 2,
                     "request_item_run_id" => "dashboard-workflow-run-skip-002",
                     "source" => %{
                       "failure" => %{
                         "code" => "source_window_unavailable",
                         "retryable" => true,
                         "recovery_action" => "retry_job"
                       }
                     }
                   }
                 },
                 dashboard_runtime_invalidation?: false
               )

      assert {:ok, retryable_job} =
               Cadence.Jobs.enqueue(
                 :telemetry_historical_data_workflow,
                 mission.mission_id,
                 "dashboard-workflow-run-skip-001",
                 %{
                   "workflow" => "backfill",
                   "attrs" => %{"backfill_run_id" => "dashboard-workflow-run-skip-001"}
                 }
               )

      assert [claimed_job] = Cadence.Jobs.claim_jobs(1)
      assert claimed_job.job_id == retryable_job.job_id

      assert {:ok, failed_job} =
               Cadence.Jobs.fail_worker_start(retryable_job.job_id, :source_window_failed)

      assert failed_job.status == :failed

      path =
        show_path(mission, dashboard) <>
          "?panel=data_link&selected_target=telemetry_backfill_lifecycle_event&selected_id=#{retryable_event.backfill_lifecycle_event_id}"

      {:ok, view, _html} = live(conn, path)
      render_dashboard_async(view)

      assert has_element?(
               view,
               ~s(#dashboard-historical-workflow-group-retry-failed[data-workflow-action-eligible-count="1"])
             )

      view
      |> element("#dashboard-historical-workflow-group-retry-failed")
      |> render_click()

      assert_patch(view)

      assert has_element?(
               view,
               ~s(#dashboard-historical-workflow-latest-action[data-workflow-latest-action="retry_group_failed_jobs"][data-workflow-latest-action-status="ok"][data-workflow-latest-action-retried="1"][data-workflow-latest-action-retry-nonretryable="0"][data-workflow-latest-action-retry-skipped="1"][data-workflow-latest-action-retry-errors="0"])
             )

      assert has_element?(
               view,
               ~s(#dashboard-historical-workflow-latest-action[data-workflow-latest-action-retry-skipped-run-ids="dashboard-workflow-run-skip-002"][data-workflow-latest-action-retry-skipped-event-ids="#{skipped_event.backfill_lifecycle_event_id}"][data-workflow-latest-action-retry-skipped-items="run=dashboard-workflow-run-skip-002 event=#{skipped_event.backfill_lifecycle_event_id} reason=job_status_missing"])
             )

      assert has_element?(
               view,
               "#dashboard-historical-workflow-latest-action",
               "run=dashboard-workflow-run-skip-002 event=#{skipped_event.backfill_lifecycle_event_id} reason=job_status_missing"
             )

      assert {:ok, retried_job} = Cadence.fetch_background_job(retryable_job.job_id)
      assert retried_job.status == :queued
    end

    test "group workflow actions advance corrected replacement request items" do
      {conn, org, mission} = signed_in_org_and_mission()
      %Document{} = dashboard = TestFixtures.persist_dashboard_document!(mission, name: "Power")

      requested_events =
        for {point_id, index} <- [{"HK.counter", 1}, {"HK.voltage", 2}, {"HK.current", 3}] do
          run_id = "dashboard-workflow-run-effective-00#{index}"

          assert {:ok, event} =
                   Cadence.record_telemetry_historical_data_workflow_event(
                     "backfill",
                     "requested",
                     %{
                       backfill_run_id: run_id,
                       organization_id: org.organization_id,
                       mission_id: mission.mission_id,
                       realm: :backfill,
                       data_source_id: "managed_questdb_backfill",
                       binding_id: "backfill_telemetry",
                       observable_id: point_id,
                       point_id: point_id,
                       source_from: ~U[2026-06-22 10:00:00Z],
                       source_to: ~U[2026-06-22 11:00:00Z],
                       authority: :advisory,
                       reason: "operator_requested_effective_group",
                       actor_id: "operator",
                       actor_kind: "operator",
                       payload: %{
                         "request_source" => "dashboard_direct_request",
                         "request_mode" => "bulk_points",
                         "request_group_id" => "dashboard-workflow-run-effective",
                         "request_item_index" => index,
                         "request_item_count" => 3,
                         "request_item_run_id" => run_id
                       }
                     },
                     dashboard_runtime_invalidation?: false
                   )

          event
        end

      original_voltage_request = Enum.at(requested_events, 1)
      original_current_request = Enum.at(requested_events, 2)

      assert {:ok, failed_voltage_event} =
               Cadence.record_telemetry_historical_data_workflow_event(
                 "backfill",
                 "failed",
                 %{
                   backfill_run_id: original_voltage_request.backfill_run_id,
                   organization_id: org.organization_id,
                   mission_id: mission.mission_id,
                   realm: :backfill,
                   data_source_id: "managed_questdb_backfill",
                   binding_id: "backfill_telemetry",
                   observable_id: "HK.voltage",
                   point_id: "HK.voltage",
                   source_from: ~U[2026-06-22 10:00:00Z],
                   source_to: ~U[2026-06-22 11:00:00Z],
                   authority: :advisory,
                   reason: "historical_data_job_failed",
                   actor_id: "system",
                   actor_kind: "system",
                   payload: %{
                     "request_source" => "dashboard_direct_request",
                     "request_mode" => "bulk_points",
                     "request_group_id" => "dashboard-workflow-run-effective",
                     "request_item_index" => 2,
                     "request_item_count" => 3,
                     "request_item_run_id" => original_voltage_request.backfill_run_id,
                     "source" => %{
                       "failure" => %{
                         "code" => "missing_field:voltage",
                         "retryable" => false,
                         "recovery_action" => "correct_workflow_request"
                       }
                     }
                   }
                 },
                 dashboard_runtime_invalidation?: false
               )

      assert {:ok, failed_current_event} =
               Cadence.record_telemetry_historical_data_workflow_event(
                 "backfill",
                 "failed",
                 %{
                   backfill_run_id: original_current_request.backfill_run_id,
                   organization_id: org.organization_id,
                   mission_id: mission.mission_id,
                   realm: :backfill,
                   data_source_id: "managed_questdb_backfill",
                   binding_id: "backfill_telemetry",
                   observable_id: "HK.current",
                   point_id: "HK.current",
                   source_from: ~U[2026-06-22 10:00:00Z],
                   source_to: ~U[2026-06-22 11:00:00Z],
                   authority: :advisory,
                   reason: "historical_data_job_failed",
                   actor_id: "system",
                   actor_kind: "system",
                   payload: %{
                     "request_source" => "dashboard_direct_request",
                     "request_mode" => "bulk_points",
                     "request_group_id" => "dashboard-workflow-run-effective",
                     "request_item_index" => 3,
                     "request_item_count" => 3,
                     "request_item_run_id" => original_current_request.backfill_run_id,
                     "source" => %{
                       "failure" => %{
                         "code" => "missing_field:point_id",
                         "retryable" => false,
                         "recovery_action" => "correct_workflow_request"
                       }
                     }
                   }
                 },
                 dashboard_runtime_invalidation?: false
               )

      assert {:ok, corrected_current_request} =
               Cadence.record_telemetry_historical_data_workflow_event(
                 "backfill",
                 "requested",
                 %{
                   backfill_run_id: "dashboard-workflow-run-effective-003-corrected",
                   organization_id: org.organization_id,
                   mission_id: mission.mission_id,
                   realm: :backfill,
                   data_source_id: "managed_questdb_backfill",
                   binding_id: "backfill_telemetry",
                   observable_id: "HK.current",
                   point_id: "HK.current",
                   source_from: ~U[2026-06-22 10:00:00Z],
                   source_to: ~U[2026-06-22 11:00:00Z],
                   authority: :advisory,
                   reason: "operator_corrected_effective_group_item",
                   actor_id: "operator",
                   actor_kind: "operator",
                   payload: %{
                     "recovery_action" => "correct_workflow_request",
                     "corrects_run_id" => original_current_request.backfill_run_id,
                     "corrects_event_id" => failed_current_event.backfill_lifecycle_event_id,
                     "corrects_job_id" => "dashboard-workflow-effective-job-current",
                     "request_source" => "dashboard_direct_request",
                     "request_mode" => "bulk_points",
                     "request_group_id" => "dashboard-workflow-run-effective",
                     "request_item_index" => 3,
                     "request_item_count" => 3,
                     "request_item_run_id" => "dashboard-workflow-run-effective-003-corrected"
                   }
                 },
                 dashboard_runtime_invalidation?: false
               )

      assert {:ok, corrected_voltage_request} =
               Cadence.record_telemetry_historical_data_workflow_event(
                 "backfill",
                 "requested",
                 %{
                   backfill_run_id: "dashboard-workflow-run-effective-002-corrected",
                   organization_id: org.organization_id,
                   mission_id: mission.mission_id,
                   realm: :backfill,
                   data_source_id: "managed_questdb_backfill",
                   binding_id: "backfill_telemetry",
                   observable_id: "HK.voltage",
                   point_id: "HK.voltage",
                   source_from: ~U[2026-06-22 10:00:00Z],
                   source_to: ~U[2026-06-22 11:00:00Z],
                   authority: :advisory,
                   reason: "operator_corrected_effective_group_item",
                   actor_id: "operator",
                   actor_kind: "operator",
                   payload: %{
                     "recovery_action" => "correct_workflow_request",
                     "corrects_run_id" => original_voltage_request.backfill_run_id,
                     "corrects_event_id" => failed_voltage_event.backfill_lifecycle_event_id,
                     "corrects_job_id" => "dashboard-workflow-effective-job-voltage",
                     "request_source" => "dashboard_direct_request",
                     "request_mode" => "bulk_points",
                     "request_group_id" => "dashboard-workflow-run-effective",
                     "request_item_index" => 2,
                     "request_item_count" => 3,
                     "request_item_run_id" => "dashboard-workflow-run-effective-002-corrected"
                   }
                 },
                 dashboard_runtime_invalidation?: false
               )

      assert {:ok, _corrected_voltage_approved} =
               Cadence.record_telemetry_historical_data_workflow_event(
                 "backfill",
                 "approved",
                 %{
                   backfill_run_id: "dashboard-workflow-run-effective-002-corrected",
                   organization_id: org.organization_id,
                   mission_id: mission.mission_id,
                   realm: :backfill,
                   data_source_id: "managed_questdb_backfill",
                   binding_id: "backfill_telemetry",
                   observable_id: "HK.voltage",
                   point_id: "HK.voltage",
                   source_from: ~U[2026-06-22 10:00:00Z],
                   source_to: ~U[2026-06-22 11:00:00Z],
                   authority: :advisory,
                   reason: "operator_preapproved_corrected_effective_group_item",
                   actor_id: "operator",
                   actor_kind: "operator",
                   payload: %{
                     "recovery_action" => "correct_workflow_request",
                     "corrects_run_id" => original_voltage_request.backfill_run_id,
                     "corrects_event_id" => failed_voltage_event.backfill_lifecycle_event_id,
                     "requested_event_id" =>
                       corrected_voltage_request.backfill_lifecycle_event_id,
                     "request_source" => "dashboard_direct_request",
                     "request_mode" => "bulk_points",
                     "request_group_id" => "dashboard-workflow-run-effective",
                     "request_item_index" => 2,
                     "request_item_count" => 3,
                     "request_item_run_id" => "dashboard-workflow-run-effective-002-corrected"
                   }
                 },
                 dashboard_runtime_invalidation?: false
               )

      path =
        show_path(mission, dashboard) <>
          "?panel=data_link&selected_target=telemetry_backfill_lifecycle_event&selected_id=#{corrected_current_request.backfill_lifecycle_event_id}"

      {:ok, view, _html} = live(conn, path)
      render_dashboard_async(view)

      approved_correction_task =
        "HK.current dashboard-workflow-run-effective-003 replacement dashboard-workflow-run-effective-003-corrected stage requested next approve"

      started_correction_task =
        "HK.current dashboard-workflow-run-effective-003 replacement dashboard-workflow-run-effective-003-corrected stage approved next start"

      completed_correction_task =
        "HK.current dashboard-workflow-run-effective-003 replacement dashboard-workflow-run-effective-003-corrected stage started next complete"

      voltage_started_correction_task =
        "HK.voltage dashboard-workflow-run-effective-002 replacement dashboard-workflow-run-effective-002-corrected stage approved next start"

      voltage_completed_correction_task =
        "HK.voltage dashboard-workflow-run-effective-002 replacement dashboard-workflow-run-effective-002-corrected stage started next complete"

      started_correction_tasks =
        "#{voltage_started_correction_task}; #{started_correction_task}"

      completed_correction_tasks =
        "#{voltage_completed_correction_task}; #{completed_correction_task}"

      assert has_element?(
               view,
               ~s(#dashboard-historical-workflow-group-recovery-remaining-work[data-historical-workflow-group-recovery-remaining-work-count="2"][data-historical-workflow-group-recovery-remaining-work-pending-count="2"][data-historical-workflow-group-recovery-remaining-work-completed-count="0"][data-historical-workflow-group-recovery-remaining-work-next-actions*="approve"][data-historical-workflow-group-recovery-remaining-work-next-actions*="start"][data-historical-workflow-group-recovery-remaining-work-pending-runs*="dashboard-workflow-run-effective-002-corrected"][data-historical-workflow-group-recovery-remaining-work-pending-runs*="dashboard-workflow-run-effective-003-corrected"])
             )

      assert has_element?(
               view,
               ~s(#dashboard-historical-workflow-group-recovery-closure-readiness[data-historical-workflow-group-recovery-closure-status="inspect_job_state"][data-historical-workflow-group-recovery-closure-action="inspect_missing_replacement_jobs"][data-historical-workflow-group-recovery-closure-unresolved="0"][data-historical-workflow-group-recovery-closure-pending-replacements="2"][data-historical-workflow-group-recovery-closure-blocked-jobs="3"][data-historical-workflow-group-recovery-closure-failed-jobs="0"][data-historical-workflow-group-recovery-closure-missing-jobs="2"][data-historical-workflow-group-recovery-closure-stale-jobs="0"])
             )

      assert has_element?(
               view,
               ~s([data-historical-workflow-group-recovery-remaining-work-replacement-run="dashboard-workflow-run-effective-002-corrected"][data-historical-workflow-group-recovery-remaining-work-stage="approved"][data-historical-workflow-group-recovery-remaining-work-next-action="start"][data-historical-workflow-group-recovery-remaining-work-status="pending"])
             )

      assert has_element?(
               view,
               ~s(#dashboard-historical-workflow-group-recovery-advance-corrected-form[data-historical-workflow-group-recovery-advance-stage="approved"][data-historical-workflow-group-recovery-advance-eligible="true"][data-historical-workflow-group-recovery-advance-count="1"])
             )

      assert has_element?(
               view,
               ~s(#dashboard-historical-workflow-group-recovery-advance-corrected[data-workflow-action-stage="approved"][data-workflow-action-correction-tasks="#{approved_correction_task}"])
             )

      view
      |> element("#dashboard-historical-workflow-group-recovery-advance-corrected-form")
      |> render_submit(%{
        "historical_workflow_group" => %{
          "workflow" => "backfill",
          "request_group_id" => "dashboard-workflow-run-effective",
          "realm" => "backfill",
          "data_source_id" => "managed_questdb_backfill",
          "source_binding_id" => "backfill_telemetry",
          "stage" => "approved",
          "reason" => "dashboard_recovery_replacement_approved",
          "group_transition_scope" => "replacement_corrections",
          "group_correction_tasks" => approved_correction_task,
          "confirmed" => "confirmed"
        }
      })

      assert_patch(view)
      render_dashboard_async(view)

      assert has_element?(
               view,
               ~s(#dashboard-historical-workflow-group-recovery-advance-corrected-form[data-historical-workflow-group-recovery-advance-stage="started"][data-historical-workflow-group-recovery-advance-eligible="true"][data-historical-workflow-group-recovery-advance-count="2"])
             )

      assert has_element?(
               view,
               ~s(#dashboard-historical-workflow-group-recovery-advance-corrected[data-workflow-action-stage="started"][data-workflow-action-correction-tasks="#{started_correction_tasks}"])
             )

      view
      |> element("#dashboard-historical-workflow-group-recovery-advance-corrected-form")
      |> render_submit(%{
        "historical_workflow_group" => %{
          "workflow" => "backfill",
          "request_group_id" => "dashboard-workflow-run-effective",
          "realm" => "backfill",
          "data_source_id" => "managed_questdb_backfill",
          "source_binding_id" => "backfill_telemetry",
          "stage" => "started",
          "reason" => "dashboard_recovery_replacement_started",
          "group_transition_scope" => "replacement_corrections",
          "group_correction_tasks" => started_correction_tasks,
          "confirmed" => "confirmed"
        }
      })

      assert_patch(view)
      render_dashboard_async(view)

      assert has_element?(
               view,
               ~s(#dashboard-historical-workflow-group-recovery-advance-corrected-form[data-historical-workflow-group-recovery-advance-stage="completed"][data-historical-workflow-group-recovery-advance-eligible="true"][data-historical-workflow-group-recovery-advance-count="2"])
             )

      assert has_element?(
               view,
               ~s(#dashboard-historical-workflow-group-recovery-advance-corrected[data-workflow-action-stage="completed"][data-workflow-action-correction-tasks="#{completed_correction_tasks}"])
             )

      view
      |> element("#dashboard-historical-workflow-group-recovery-advance-corrected-form")
      |> render_submit(%{
        "historical_workflow_group" => %{
          "workflow" => "backfill",
          "request_group_id" => "dashboard-workflow-run-effective",
          "realm" => "backfill",
          "data_source_id" => "managed_questdb_backfill",
          "source_binding_id" => "backfill_telemetry",
          "stage" => "completed",
          "reason" => "dashboard_recovery_replacement_completed",
          "group_transition_scope" => "replacement_corrections",
          "group_correction_tasks" => completed_correction_tasks,
          "confirmed" => "confirmed"
        }
      })

      assert_patch(view)

      approved_events =
        mission.mission_id
        |> Storage.list_backfill_lifecycle_events(
          organization_id: org.organization_id,
          event_type: :backfill_approved
        )
        |> Enum.filter(
          &(&1.payload["request_group_id"] == "dashboard-workflow-run-effective" and
              &1.reason == "dashboard_recovery_replacement_approved")
        )

      assert Enum.map(approved_events, & &1.backfill_run_id) == [
               "dashboard-workflow-run-effective-003-corrected"
             ]

      completed_events =
        mission.mission_id
        |> Storage.list_backfill_lifecycle_events(
          organization_id: org.organization_id,
          event_type: :backfill_completed
        )
        |> Enum.filter(
          &(&1.payload["request_group_id"] == "dashboard-workflow-run-effective" and
              &1.reason == "dashboard_recovery_replacement_completed")
        )
        |> Enum.sort_by(& &1.payload["request_item_index"])

      assert Enum.map(completed_events, & &1.backfill_run_id) == [
               "dashboard-workflow-run-effective-002-corrected",
               "dashboard-workflow-run-effective-003-corrected"
             ]

      refute Enum.any?(
               completed_events,
               &(&1.backfill_run_id == original_current_request.backfill_run_id)
             )

      corrected_completion = List.last(completed_events)

      started_events =
        mission.mission_id
        |> Storage.list_backfill_lifecycle_events(
          organization_id: org.organization_id,
          event_type: :backfill_started
        )
        |> Enum.filter(
          &(&1.payload["request_group_id"] == "dashboard-workflow-run-effective" and
              &1.reason == "dashboard_recovery_replacement_started")
        )
        |> Enum.sort_by(& &1.payload["request_item_index"])

      assert Enum.map(started_events, & &1.backfill_run_id) == [
               "dashboard-workflow-run-effective-002-corrected",
               "dashboard-workflow-run-effective-003-corrected"
             ]

      corrected_start = List.last(started_events)

      assert corrected_completion.payload["corrects_run_id"] ==
               original_current_request.backfill_run_id

      assert corrected_completion.payload["corrects_event_id"] ==
               failed_current_event.backfill_lifecycle_event_id

      assert corrected_completion.payload["requested_event_id"] ==
               corrected_current_request.backfill_lifecycle_event_id

      assert corrected_completion.payload["group_transition_source"] == "dashboard_group_action"

      assert corrected_completion.payload["group_transition_scope"] ==
               "replacement_corrections"

      assert corrected_completion.payload["correction_transition_source"] ==
               "dashboard_correction_transition"

      assert corrected_completion.payload["correction_transition_source_event_id"] ==
               corrected_start.backfill_lifecycle_event_id
    end

    test "records historical workflow stages from the backfill lifecycle inspector" do
      {conn, org, mission} = signed_in_org_and_mission()
      %Document{} = dashboard = TestFixtures.persist_dashboard_document!(mission, name: "Power")

      assert {:ok, event} =
               Cadence.record_telemetry_historical_data_workflow_event(
                 "backfill",
                 "requested",
                 %{
                   backfill_run_id: "dashboard-workflow-run-1",
                   organization_id: org.organization_id,
                   mission_id: mission.mission_id,
                   realm: :backfill,
                   data_source_id: "managed_questdb_backfill",
                   binding_id: "backfill_telemetry",
                   observable_id: "HK.counter",
                   point_id: "HK.counter",
                   source_from: ~U[2026-06-22 10:00:00Z],
                   source_to: ~U[2026-06-22 11:00:00Z],
                   authority: :advisory,
                   reason: "operator_requested_backfill",
                   actor_id: "operator-2",
                   actor_kind: "operator",
                   payload: %{
                     "dashboard_context" => %{
                       "dashboard_id" => dashboard.dashboard_id,
                       "dashboard_version" => "1",
                       "dashboard_time_mode" => "replay_run",
                       "dashboard_replay_run_id" => "replay-stage-1",
                       "dashboard_data_view" => "all_revisions",
                       "dashboard_limit_mode" => "observed"
                     }
                   }
                 },
                 dashboard_runtime_invalidation?: false
               )

      path =
        show_path(mission, dashboard) <>
          "?panel=data_link&selected_target=telemetry_backfill_lifecycle_event&selected_id=#{event.backfill_lifecycle_event_id}"

      {:ok, view, _html} = live(conn, path)
      render_dashboard_async(view)

      assert has_element?(
               view,
               ~s(#dashboard-data-link-inspector[data-data-link-target="telemetry_backfill_lifecycle_event"][data-data-link-status="resolved"])
             )

      assert has_element?(
               view,
               ~s(#dashboard-historical-workflow-controls[data-historical-workflow="backfill"][data-historical-workflow-stage="requested"][data-historical-workflow-run-id="dashboard-workflow-run-1"])
             )

      assert has_element?(view, "#dashboard-historical-workflow-requested[disabled]")
      assert has_element?(view, "#dashboard-historical-workflow-approved:not([disabled])")
      assert has_element?(view, "#dashboard-historical-workflow-confirm[required]")

      assert has_element?(
               view,
               ~s(#dashboard-historical-workflow-dashboard-replay-run-id[value="replay-stage-1"])
             )

      assert has_element?(
               view,
               ~s(#dashboard-historical-workflow-dashboard-limit-mode[value="observed"])
             )

      assert has_element?(
               view,
               ~s(#dashboard-historical-workflow-action-explanations [data-workflow-action-explanation-id="stage_requested"][data-workflow-action-explanation-reason="already_in_stage"]),
               "Request is already the current workflow stage."
             )

      assert has_element?(
               view,
               ~s(#dashboard-historical-workflow-action-explanations [data-workflow-action-explanation-id="stage_requested"][data-workflow-action-explanation-state="current stage requested"]),
               "current stage requested"
             )

      unconfirmed_html =
        view
        |> element("#dashboard-historical-workflow-form")
        |> render_submit(%{
          "historical_workflow" => %{
            "stage" => "approved",
            "reason" => "operator_approved_backfill_window",
            "source_from" => "2026-06-22T10:15:00Z",
            "source_to" => "2026-06-22T10:45:00Z"
          }
        })

      assert unconfirmed_html =~
               "Confirm the historical data workflow approved transition before recording it."

      assert has_element?(
               view,
               ~s(#dashboard-historical-workflow-action-outcome[data-workflow-action="stage_transition"][data-workflow-action-status="blocked"][data-workflow-action-reason="confirmation_required"][data-workflow-action-stage="approved"])
             )

      assert has_element?(
               view,
               ~s(#dashboard-historical-workflow-latest-action[data-workflow-latest-action="stage_transition"][data-workflow-latest-action-status="blocked"][data-workflow-latest-action-reason="confirmation_required"][data-workflow-latest-action-stage="approved"]),
               "Confirm the historical data workflow approved transition before recording it."
             )

      assert [_requested] =
               Storage.list_backfill_lifecycle_events(
                 mission.mission_id,
                 organization_id: org.organization_id,
                 backfill_run_id: "dashboard-workflow-run-1"
               )

      view
      |> element("#dashboard-historical-workflow-form")
      |> render_submit(%{
        "historical_workflow" => %{
          "stage" => "approved",
          "confirmed" => "confirmed",
          "reason" => "operator_approved_backfill_window",
          "dashboard_id" => dashboard.dashboard_id,
          "dashboard_version" => "1",
          "dashboard_time_mode" => "replay_run",
          "dashboard_replay_run_id" => "replay-stage-1",
          "dashboard_data_view" => "all_revisions",
          "dashboard_limit_mode" => "observed",
          "source_from" => "2026-06-22T10:15:00Z",
          "source_to" => "2026-06-22T10:45:00Z"
        }
      })

      assert_patch(view)

      assert [_requested, approved] =
               Storage.list_backfill_lifecycle_events(
                 mission.mission_id,
                 organization_id: org.organization_id,
                 backfill_run_id: "dashboard-workflow-run-1"
               )

      assert approved.event_type == :backfill_approved
      assert approved.reason == "operator_approved_backfill_window"
      assert approved.source_from == ~U[2026-06-22 10:15:00.000000Z]
      assert approved.source_to == ~U[2026-06-22 10:45:00.000000Z]

      assert approved.payload["dashboard_context"] == %{
               "dashboard_id" => dashboard.dashboard_id,
               "dashboard_version" => "1",
               "dashboard_time_mode" => "replay_run",
               "dashboard_replay_run_id" => "replay-stage-1",
               "dashboard_data_view" => "all_revisions",
               "dashboard_limit_mode" => "observed"
             }

      assert has_element?(
               view,
               ~s(#dashboard-historical-workflow-action-outcome[data-workflow-action="stage_transition"][data-workflow-action-status="ok"][data-workflow-action-reason="stage_recorded"][data-workflow-action-stage="approved"][data-workflow-action-target-event-id="#{approved.backfill_lifecycle_event_id}"][data-workflow-action-target-run-id="dashboard-workflow-run-1"][data-workflow-action-dashboard-id="#{dashboard.dashboard_id}"][data-workflow-action-dashboard-version="1"][data-workflow-action-dashboard-time-mode="replay_run"][data-workflow-action-dashboard-replay-run-id="replay-stage-1"][data-workflow-action-dashboard-data-view="all_revisions"][data-workflow-action-dashboard-limit-mode="observed"])
             )

      assert has_element?(
               view,
               ~s(#dashboard-historical-workflow-latest-action[data-workflow-latest-action="stage_transition"][data-workflow-latest-action-status="ok"][data-workflow-latest-action-reason="stage_recorded"][data-workflow-latest-action-stage="approved"][data-workflow-latest-action-target-event-id="#{approved.backfill_lifecycle_event_id}"][data-workflow-latest-action-target-run-id="dashboard-workflow-run-1"][data-workflow-latest-action-dashboard-id="#{dashboard.dashboard_id}"][data-workflow-latest-action-dashboard-version="1"][data-workflow-latest-action-dashboard-time-mode="replay_run"][data-workflow-latest-action-dashboard-replay-run-id="replay-stage-1"][data-workflow-latest-action-dashboard-data-view="all_revisions"][data-workflow-latest-action-dashboard-limit-mode="observed"]),
               "Historical data workflow approved recorded."
             )

      assert has_element?(
               view,
               ~s([data-workflow-latest-action-handoff="#{approved.backfill_lifecycle_event_id}"][data-workflow-latest-action-handoff-role="target"][data-workflow-latest-action-handoff-href*="panel=data_link"][data-workflow-latest-action-handoff-href*="selected_id=#{approved.backfill_lifecycle_event_id}"]),
               "Selected event"
             )

      assert has_element?(
               view,
               ~s(#dashboard-data-link-inspector [data-data-link-field="Event type"]),
               "backfill_approved"
             )

      assert has_element?(
               view,
               ~s(#dashboard-data-link-inspector [data-data-link-field="Workflow stage"]),
               "approved"
             )

      view
      |> element("#dashboard-historical-workflow-form")
      |> render_submit(%{
        "historical_workflow" => %{
          "stage" => "started",
          "confirmed" => "confirmed",
          "reason" => "operator_started_backfill_window",
          "dashboard_id" => dashboard.dashboard_id,
          "dashboard_version" => "1",
          "dashboard_time_mode" => "replay_run",
          "dashboard_replay_run_id" => "replay-stage-1",
          "dashboard_data_view" => "all_revisions",
          "dashboard_limit_mode" => "observed",
          "source_from" => "2026-06-22T10:15:00Z",
          "source_to" => "2026-06-22T10:45:00Z"
        }
      })

      assert_patch(view)

      assert {:ok, job} =
               Cadence.fetch_telemetry_historical_data_workflow_job("dashboard-workflow-run-1")

      assert job.job_type == :telemetry_historical_data_workflow
      assert job.status == :queued
      assert job.payload["workflow"] == "backfill"

      started_events =
        Storage.list_backfill_lifecycle_events(
          mission.mission_id,
          organization_id: org.organization_id,
          backfill_run_id: "dashboard-workflow-run-1"
        )

      started = Enum.find(started_events, &(&1.event_type == :backfill_started))

      assert started.payload["dashboard_context"] == %{
               "dashboard_id" => dashboard.dashboard_id,
               "dashboard_version" => "1",
               "dashboard_time_mode" => "replay_run",
               "dashboard_replay_run_id" => "replay-stage-1",
               "dashboard_data_view" => "all_revisions",
               "dashboard_limit_mode" => "observed"
             }

      assert has_element?(
               view,
               ~s(#dashboard-historical-workflow-latest-action[data-workflow-latest-action="stage_transition"][data-workflow-latest-action-status="ok"][data-workflow-latest-action-reason="stage_recorded_job_queued"][data-workflow-latest-action-stage="started"][data-workflow-latest-action-job-id="#{job.job_id}"][data-workflow-latest-action-target-event-id="#{started.backfill_lifecycle_event_id}"][data-workflow-latest-action-target-run-id="dashboard-workflow-run-1"][data-workflow-latest-action-dashboard-id="#{dashboard.dashboard_id}"][data-workflow-latest-action-dashboard-version="1"][data-workflow-latest-action-dashboard-time-mode="replay_run"][data-workflow-latest-action-dashboard-replay-run-id="replay-stage-1"][data-workflow-latest-action-dashboard-data-view="all_revisions"][data-workflow-latest-action-dashboard-limit-mode="observed"]),
               "Historical data workflow started recorded and job #{job.job_id} queued."
             )

      assert has_element?(
               view,
               ~s([data-workflow-latest-action-handoff="#{started.backfill_lifecycle_event_id}"][data-workflow-latest-action-handoff-role="target"][data-workflow-latest-action-handoff-href*="panel=data_link"][data-workflow-latest-action-handoff-href*="selected_id=#{started.backfill_lifecycle_event_id}"]),
               "Selected event"
             )

      assert has_element?(
               view,
               ~s(#dashboard-historical-workflow-job-status[data-historical-workflow-job-id="#{job.job_id}"][data-historical-workflow-job-status="queued"])
             )

      assert [claimed_job] = Cadence.Jobs.claim_jobs(1)
      assert claimed_job.job_id == job.job_id

      assert {:ok, completed_job} = Cadence.Jobs.run_job(claimed_job.job_id)
      assert completed_job.status == :completed

      events =
        Storage.list_backfill_lifecycle_events(
          mission.mission_id,
          organization_id: org.organization_id,
          backfill_run_id: "dashboard-workflow-run-1"
        )

      assert Enum.map(events, & &1.event_type) == [
               :backfill_requested,
               :backfill_approved,
               :backfill_started,
               :backfill_completed
             ]

      completed = List.last(events)
      assert completed.reason == "historical_data_job_completed"
      assert completed.payload["job_id"] == job.job_id
    end

    test "retries failed historical workflow jobs from the lifecycle inspector" do
      {conn, org, mission} = signed_in_org_and_mission()
      %Document{} = dashboard = TestFixtures.persist_dashboard_document!(mission, name: "Power")

      assert {:ok, event} =
               Cadence.record_telemetry_historical_data_workflow_event(
                 "backfill",
                 "failed",
                 %{
                   backfill_run_id: "dashboard-workflow-run-retry",
                   organization_id: org.organization_id,
                   mission_id: mission.mission_id,
                   realm: :backfill,
                   data_source_id: "managed_questdb_backfill",
                   binding_id: "backfill_telemetry",
                   observable_id: "HK.counter",
                   point_id: "HK.counter",
                   source_from: ~U[2026-06-22 10:00:00Z],
                   source_to: ~U[2026-06-22 11:00:00Z],
                   authority: :advisory,
                   reason: "historical_data_job_failed",
                   actor_id: "system",
                   actor_kind: "system",
                   payload: %{"failure" => "source window unavailable"}
                 },
                 dashboard_runtime_invalidation?: false
               )

      assert {:ok, job} =
               Cadence.Jobs.enqueue(
                 :telemetry_historical_data_workflow,
                 mission.mission_id,
                 "dashboard-workflow-run-retry",
                 %{
                   "workflow" => "backfill",
                   "attrs" => %{"backfill_run_id" => "dashboard-workflow-run-retry"}
                 }
               )

      assert [claimed_job] = Cadence.Jobs.claim_jobs(1)
      assert claimed_job.job_id == job.job_id
      assert {:ok, failed_job} = Cadence.Jobs.fail_worker_start(job.job_id, :source_window_failed)
      assert failed_job.status == :failed

      path =
        show_path(mission, dashboard) <>
          "?panel=data_link&selected_target=telemetry_backfill_lifecycle_event&selected_id=#{event.backfill_lifecycle_event_id}"

      {:ok, view, _html} = live(conn, path)
      render_dashboard_async(view)

      assert has_element?(
               view,
               ~s(#dashboard-historical-workflow-job-status[data-historical-workflow-job-id="#{job.job_id}"][data-historical-workflow-job-status="failed"])
             )

      assert has_element?(
               view,
               ~s(#dashboard-historical-workflow-job-guidance[data-historical-workflow-job-guidance-next-action="retry_job"][data-historical-workflow-job-guidance-retry-eligible="true"][data-historical-workflow-job-guidance-retry-reason="failed_job_retryable"]),
               "Retry failed job #{job.job_id}"
             )

      view
      |> element("#dashboard-historical-workflow-retry-job")
      |> render_click()

      assert_patch(view)

      assert {:ok, retried_job} = Cadence.fetch_background_job(job.job_id)
      assert retried_job.status == :queued
      assert retried_job.attempt_count == 1
      assert retried_job.failure_reason == nil
      assert retried_job.started_at == nil
      assert retried_job.completed_at == nil

      events =
        Storage.list_backfill_lifecycle_events(
          mission.mission_id,
          organization_id: org.organization_id,
          backfill_run_id: "dashboard-workflow-run-retry"
        )

      assert Enum.map(events, & &1.event_type) == [:backfill_failed, :backfill_retried]
      retried_event = List.last(events)
      assert retried_event.reason == "dashboard_historical_workflow_retried"
      assert retried_event.payload["retry_action"] == "retry_job"
      assert retried_event.payload["retry_source_event_id"] == event.backfill_lifecycle_event_id
      assert retried_event.payload["retry_job_id"] == job.job_id
      assert retried_event.payload["retry_job_status"] == "queued"

      assert has_element?(
               view,
               ~s(#dashboard-data-link-inspector [data-data-link-field="Backfill lifecycle event"]),
               retried_event.backfill_lifecycle_event_id
             )

      assert has_element?(
               view,
               ~s(#dashboard-data-link-inspector [data-data-link-field="Workflow stage"]),
               "retried"
             )

      assert has_element?(
               view,
               ~s(#dashboard-historical-workflow-latest-action[data-workflow-latest-action="retry_job"][data-workflow-latest-action-status="ok"][data-workflow-latest-action-reason="retry_job_recorded"][data-workflow-latest-action-job-id="#{job.job_id}"][data-workflow-latest-action-result-event-ids="#{retried_event.backfill_lifecycle_event_id}"][data-workflow-latest-action-target-event-id="#{retried_event.backfill_lifecycle_event_id}"][data-workflow-latest-action-target-run-id="dashboard-workflow-run-retry"]),
               retried_event.backfill_lifecycle_event_id
             )

      assert has_element?(
               view,
               ~s([data-workflow-latest-action-handoff="#{retried_event.backfill_lifecycle_event_id}"][data-workflow-latest-action-handoff-role="target_result"][data-workflow-latest-action-handoff-href*="panel=data_link"][data-workflow-latest-action-handoff-href*="selected_id=#{retried_event.backfill_lifecycle_event_id}"]),
               "Selected result"
             )

      assert has_element?(
               view,
               ~s(#dashboard-data-link-inspector [data-data-link-field="Workflow retry source event"]),
               event.backfill_lifecycle_event_id
             )

      assert has_element?(
               view,
               ~s(#dashboard-historical-workflow-job-status[data-historical-workflow-job-id="#{job.job_id}"][data-historical-workflow-job-status="queued"])
             )

      assert has_element?(
               view,
               ~s(#dashboard-historical-workflow-job-guidance[data-historical-workflow-job-guidance-next-action="monitor_job"][data-historical-workflow-job-guidance-retry-eligible="false"][data-historical-workflow-job-guidance-retry-reason="job_not_failed"]),
               "monitor the worker outcome"
             )

      refute has_element?(view, "#dashboard-historical-workflow-retry-job")
    end

    test "does not offer retry for non-retryable historical workflow failures" do
      {conn, org, mission} = signed_in_org_and_mission()
      %Document{} = dashboard = TestFixtures.persist_dashboard_document!(mission, name: "Power")

      assert {:ok, event} =
               Cadence.record_telemetry_historical_data_workflow_event(
                 "backfill",
                 "failed",
                 %{
                   backfill_run_id: "dashboard-workflow-run-nonretryable",
                   organization_id: org.organization_id,
                   mission_id: mission.mission_id,
                   realm: :backfill,
                   data_source_id: "managed_questdb_backfill",
                   binding_id: "backfill_telemetry",
                   authority: :advisory,
                   reason: "historical_data_job_failed",
                   actor_id: "system",
                   actor_kind: "system",
                   payload: %{
                     "dashboard_context" => %{
                       "dashboard_id" => dashboard.dashboard_id,
                       "dashboard_version" => "1",
                       "dashboard_time_mode" => "replay_run",
                       "dashboard_replay_run_id" => "replay-correction-1",
                       "dashboard_data_view" => "all_revisions",
                       "dashboard_limit_mode" => "observed"
                     },
                     "source" => %{
                       "failure" => %{
                         "code" => "missing_field:point_id",
                         "retryable" => false,
                         "retry_blockers" => ["missing point_id"],
                         "recovery_action" => "correct_workflow_request"
                       }
                     }
                   }
                 },
                 dashboard_runtime_invalidation?: false
               )

      assert {:ok, job} =
               Cadence.Jobs.enqueue(
                 :telemetry_historical_data_workflow,
                 mission.mission_id,
                 "dashboard-workflow-run-nonretryable",
                 %{
                   "workflow" => "backfill",
                   "attrs" => %{"backfill_run_id" => "dashboard-workflow-run-nonretryable"}
                 }
               )

      assert [claimed_job] = Cadence.Jobs.claim_jobs(1)
      assert claimed_job.job_id == job.job_id
      assert {:ok, failed_job} = Cadence.Jobs.fail_worker_start(job.job_id, :missing_point_id)
      assert failed_job.status == :failed

      path =
        show_path(mission, dashboard) <>
          "?panel=data_link&selected_target=telemetry_backfill_lifecycle_event&selected_id=#{event.backfill_lifecycle_event_id}"

      {:ok, view, _html} = live(conn, path)
      render_dashboard_async(view)

      assert has_element?(
               view,
               ~s(#dashboard-historical-workflow-job-status[data-historical-workflow-job-id="#{job.job_id}"][data-historical-workflow-job-status="failed"])
             )

      assert has_element?(
               view,
               "#dashboard-historical-workflow-job-status",
               "missing_field:point_id"
             )

      assert has_element?(view, "#dashboard-historical-workflow-job-status", "false")

      assert has_element?(
               view,
               "#dashboard-historical-workflow-job-status",
               "correct_workflow_request"
             )

      assert has_element?(
               view,
               ~s(#dashboard-historical-workflow-job-guidance[data-historical-workflow-job-guidance-next-action="create_corrected_request"][data-historical-workflow-job-guidance-retry-eligible="false"][data-historical-workflow-job-guidance-retry-reason="correction_required"][data-historical-workflow-job-guidance-correction-eligible="true"][data-historical-workflow-job-guidance-correction-reason="correction_request_required"]),
               "Create a corrected request for failed event"
             )

      refute has_element?(view, "#dashboard-historical-workflow-retry-job")
      assert has_element?(view, "#dashboard-historical-workflow-correction-form")

      assert has_element?(
               view,
               ~s(#dashboard-historical-workflow-correction-dashboard-replay-run-id[value="replay-correction-1"])
             )

      assert has_element?(
               view,
               ~s(#dashboard-historical-workflow-correction-dashboard-limit-mode[value="observed"])
             )

      assert has_element?(
               view,
               ~s(#dashboard-historical-workflow-action-explanations [data-workflow-action-explanation-id="retry_job"][data-workflow-action-explanation-reason="correction_required"]),
               "Create a corrected workflow request instead of retrying this job."
             )

      assert has_element?(
               view,
               ~s(#dashboard-historical-workflow-action-explanations [data-workflow-action-explanation-id="retry_job"][data-workflow-action-explanation-state="job #{job.job_id}; status failed; retryable false; recovery correct_workflow_request"]),
               "job #{job.job_id}; status failed; retryable false; recovery correct_workflow_request"
             )

      view
      |> element("#dashboard-historical-workflow-correction-form")
      |> render_submit(%{
        "historical_workflow_correction" => %{
          "workflow" => "backfill",
          "run_id" => "dashboard-workflow-run-corrected",
          "original_run_id" => "dashboard-workflow-run-nonretryable",
          "original_event_id" => event.backfill_lifecycle_event_id,
          "original_job_id" => job.job_id,
          "realm" => "backfill",
          "data_source_id" => "managed_questdb_backfill",
          "source_binding_id" => "backfill_telemetry",
          "observable_id" => "HK.counter",
          "point_id" => "HK.counter",
          "source_from" => "2026-06-22T10:00:00Z",
          "source_to" => "2026-06-22T11:00:00Z",
          "reason" => "operator_corrected_missing_point",
          "dashboard_id" => dashboard.dashboard_id,
          "dashboard_version" => "1",
          "dashboard_time_mode" => "replay_run",
          "dashboard_replay_run_id" => "replay-correction-1",
          "dashboard_data_view" => "all_revisions",
          "dashboard_limit_mode" => "observed",
          "confirmed" => "confirmed"
        }
      })

      assert_patch(view)

      events =
        Storage.list_backfill_lifecycle_events(
          mission.mission_id,
          organization_id: org.organization_id,
          backfill_run_id: "dashboard-workflow-run-corrected"
        )

      assert [corrected] = events
      assert corrected.event_type == :backfill_requested
      assert corrected.reason == "operator_corrected_missing_point"
      assert corrected.point_id == "HK.counter"
      assert corrected.payload["recovery_action"] == "correct_workflow_request"
      assert corrected.payload["correction_source"] == "dashboard_correction_request"
      assert corrected.payload["correction_source_event_type"] == "backfill_failed"
      assert corrected.payload["corrects_run_id"] == "dashboard-workflow-run-nonretryable"
      assert corrected.payload["corrects_event_id"] == event.backfill_lifecycle_event_id
      assert corrected.payload["corrects_job_id"] == job.job_id

      assert corrected.payload["dashboard_context"] == %{
               "dashboard_id" => dashboard.dashboard_id,
               "dashboard_version" => "1",
               "dashboard_time_mode" => "replay_run",
               "dashboard_replay_run_id" => "replay-correction-1",
               "dashboard_data_view" => "all_revisions",
               "dashboard_limit_mode" => "observed"
             }

      assert has_element?(
               view,
               ~s(#dashboard-data-link-inspector [data-data-link-field="Backfill run"]),
               "dashboard-workflow-run-corrected"
             )

      assert has_element?(
               view,
               ~s(#dashboard-data-link-inspector [data-data-link-field="Workflow stage"]),
               "requested"
             )

      assert has_element?(
               view,
               ~s(#dashboard-historical-workflow-latest-action[data-workflow-latest-action="correction_request"][data-workflow-latest-action-status="ok"][data-workflow-latest-action-reason="correction_request_recorded"][data-workflow-latest-action-result-event-ids="#{corrected.backfill_lifecycle_event_id}"][data-workflow-latest-action-target-event-id="#{corrected.backfill_lifecycle_event_id}"][data-workflow-latest-action-target-run-id="dashboard-workflow-run-corrected"][data-workflow-latest-action-dashboard-id="#{dashboard.dashboard_id}"][data-workflow-latest-action-dashboard-version="1"][data-workflow-latest-action-dashboard-time-mode="replay_run"][data-workflow-latest-action-dashboard-replay-run-id="replay-correction-1"][data-workflow-latest-action-dashboard-data-view="all_revisions"][data-workflow-latest-action-dashboard-limit-mode="observed"]),
               "Corrected historical data workflow request recorded."
             )

      assert has_element?(
               view,
               ~s(#dashboard-historical-workflow-action-outcome[data-workflow-action="correction_request"][data-workflow-action-status="ok"][data-workflow-action-reason="correction_request_recorded"][data-workflow-action-result-event-ids="#{corrected.backfill_lifecycle_event_id}"][data-workflow-action-target-event-id="#{corrected.backfill_lifecycle_event_id}"][data-workflow-action-target-run-id="dashboard-workflow-run-corrected"][data-workflow-action-dashboard-id="#{dashboard.dashboard_id}"][data-workflow-action-dashboard-version="1"][data-workflow-action-dashboard-time-mode="replay_run"][data-workflow-action-dashboard-replay-run-id="replay-correction-1"][data-workflow-action-dashboard-data-view="all_revisions"][data-workflow-action-dashboard-limit-mode="observed"])
             )

      assert has_element?(
               view,
               ~s([data-workflow-latest-action-handoff="#{corrected.backfill_lifecycle_event_id}"][data-workflow-latest-action-handoff-role="target_result"][data-workflow-latest-action-handoff-href*="panel=data_link"][data-workflow-latest-action-handoff-href*="selected_id=#{corrected.backfill_lifecycle_event_id}"]),
               "Selected result"
             )

      assert has_element?(
               view,
               ~s(#dashboard-data-link-inspector [data-data-link-field="Workflow correction action"]),
               "correct_workflow_request"
             )

      assert has_element?(
               view,
               ~s(#dashboard-data-link-inspector [data-data-link-field="Workflow correction source"]),
               "dashboard_correction_request"
             )

      assert has_element?(
               view,
               ~s(#dashboard-data-link-inspector [data-data-link-field="Workflow correction source event type"]),
               "backfill_failed"
             )

      assert has_element?(
               view,
               ~s(#dashboard-data-link-inspector [data-data-link-field="Workflow correction source event"]),
               event.backfill_lifecycle_event_id
             )

      assert has_element?(
               view,
               ~s([data-data-link-related-id="#{event.backfill_lifecycle_event_id}"]),
               "Correction source event"
             )

      source_path =
        show_path(mission, dashboard) <>
          "?panel=data_link&selected_target=telemetry_backfill_lifecycle_event&selected_id=#{event.backfill_lifecycle_event_id}&realm=backfill&data_source_id=managed_questdb_backfill&source_binding_id=backfill_telemetry"

      {:ok, source_view, _html} = live(conn, source_path)
      render_dashboard_async(source_view)

      assert has_element?(
               source_view,
               ~s(#dashboard-data-link-inspector[data-data-link-target="telemetry_backfill_lifecycle_event"][data-data-link-status="resolved"])
             )

      assert has_element?(
               source_view,
               ~s(#ops-dashboard-show-page[data-dashboard-selection-state="query_only"][data-dashboard-selection-target="telemetry_backfill_lifecycle_event"])
             )

      assert has_element?(
               source_view,
               ~s(#dashboard-data-link-inspector [data-data-link-context="Data realm"]),
               "backfill"
             )

      assert has_element?(
               source_view,
               ~s(#dashboard-data-link-inspector [data-data-link-context="Data source"]),
               "managed_questdb_backfill"
             )

      assert has_element?(
               source_view,
               ~s(#dashboard-data-link-inspector [data-data-link-context="Source binding"]),
               "backfill_telemetry"
             )

      assert has_element?(
               source_view,
               ~s(#dashboard-data-link-copy-link[data-clipboard-text*="panel=data_link"][data-clipboard-text*="selected_target=telemetry_backfill_lifecycle_event"][data-clipboard-text*="selected_id=#{URI.encode_www_form(event.backfill_lifecycle_event_id)}"][data-clipboard-text*="realm=backfill"][data-clipboard-text*="data_source_id=managed_questdb_backfill"][data-clipboard-text*="source_binding_id=backfill_telemetry"])
             )

      assert has_element?(
               source_view,
               ~s([data-data-link-related-id="#{corrected.backfill_lifecycle_event_id}"]),
               "Correction request HK.counter"
             )

      source_view
      |> element(~s([data-data-link-related-id="#{corrected.backfill_lifecycle_event_id}"]))
      |> render_click()

      corrected_path = assert_patch(source_view)
      assert corrected_path =~ "panel=data_link"

      assert corrected_path =~
               "selected_id=#{URI.encode_www_form(corrected.backfill_lifecycle_event_id)}"

      assert corrected_path =~
               "nav_from_target_id=#{URI.encode_www_form(event.backfill_lifecycle_event_id)}"

      assert corrected_path =~ "nav_from_relationship_kind=correction_request"
      assert corrected_path =~ "nav_trail="
      assert corrected_path =~ "realm=backfill"
      assert corrected_path =~ "data_source_id=managed_questdb_backfill"
      assert corrected_path =~ "source_binding_id=backfill_telemetry"

      assert has_element?(
               source_view,
               ~s(#dashboard-data-link-inspector [data-data-link-navigation] [data-data-link-nav-entry-id="#{event.backfill_lifecycle_event_id}"])
             )

      source_view
      |> element(
        ~s(#dashboard-data-link-inspector [data-data-link-navigation] [data-data-link-nav-entry-id="#{event.backfill_lifecycle_event_id}"])
      )
      |> render_click()

      breadcrumb_path = assert_patch(source_view)
      assert breadcrumb_path =~ "panel=data_link"

      assert breadcrumb_path =~
               "selected_id=#{URI.encode_www_form(event.backfill_lifecycle_event_id)}"

      assert breadcrumb_path =~ "realm=backfill"
      assert breadcrumb_path =~ "data_source_id=managed_questdb_backfill"
      assert breadcrumb_path =~ "source_binding_id=backfill_telemetry"
    end

    test "records late-data policy decisions from the lifecycle inspector" do
      previous_history_store = Application.get_env(:cadence, :telemetry_history_store, [])

      Application.put_env(:cadence, :telemetry_history_store,
        module: HistoryStoreETS,
        max_samples_per_point: :infinity
      )

      start_supervised!(HistoryStoreETS)
      HistoryStoreETS.reset()

      on_exit(fn ->
        Application.put_env(:cadence, :telemetry_history_store, previous_history_store)
      end)

      {conn, org, mission} = signed_in_org_and_mission()
      %Document{} = dashboard = TestFixtures.persist_dashboard_document!(mission, name: "Power")

      selected_sample =
        telemetry_sample(
          mission,
          "dashboard-late-source-sample",
          "HK.counter",
          ~U[2026-06-22 10:10:00Z],
          ~U[2026-06-22 12:05:00Z],
          raw_value: 72,
          engineering_value: 72,
          provenance: %{
            "storage" => %{
              "realm" => "backfill",
              "data_source_id" => "managed_questdb_backfill",
              "binding_id" => "backfill_telemetry"
            }
          }
        )

      assert :ok = persist_sample_scope!(selected_sample)
      assert :ok = HistoryStore.persist_samples([selected_sample])

      assert {:ok, source_event} =
               Cadence.record_telemetry_historical_data_workflow_event(
                 "backfill",
                 "completed",
                 %{
                   backfill_run_id: "dashboard-late-policy-run",
                   organization_id: org.organization_id,
                   mission_id: mission.mission_id,
                   realm: :backfill,
                   data_source_id: "managed_questdb_backfill",
                   binding_id: "backfill_telemetry",
                   observable_id: "HK.counter",
                   point_id: "HK.counter",
                   source_from: ~U[2026-06-22 10:00:00Z],
                   source_to: ~U[2026-06-22 11:00:00Z],
                   receipt_from: ~U[2026-06-22 12:00:00Z],
                   receipt_to: ~U[2026-06-22 12:10:00Z],
                   sample_count: 3,
                   authority: :authoritative,
                   reason: "operator_backfill_completed",
                   actor_id: "system",
                   actor_kind: "system",
                   payload: %{"workflow" => "backfill", "stage" => "completed"}
                 },
                 dashboard_runtime_invalidation?: false
               )

      path =
        show_path(mission, dashboard) <>
          "?panel=data_link&selected_target=telemetry_backfill_lifecycle_event&selected_id=#{source_event.backfill_lifecycle_event_id}"

      {:ok, view, _html} = live(conn, path)
      render_dashboard_async(view)

      assert has_element?(
               view,
               ~s(#dashboard-late-data-policy-controls[data-late-data-policy-source-event="#{source_event.backfill_lifecycle_event_id}"][data-late-data-policy-run-id="dashboard-late-policy-run"][data-late-data-policy-execution-mode="sample_execution"])
             )

      view
      |> form("#dashboard-late-data-policy-form", %{
        "late_data_policy" => %{
          "decision" => "accept",
          "reason" => "operator_accepts_late_data",
          "confirmed" => "confirmed"
        }
      })
      |> render_submit()

      assert_patch(view)

      events =
        Storage.list_backfill_lifecycle_events(
          mission.mission_id,
          organization_id: org.organization_id,
          backfill_run_id: "dashboard-late-policy-run"
        )

      policy_event = Enum.find(events, &(&1.event_type == :late_data_accepted))
      assert policy_event.reason == "operator_accepts_late_data"
      assert policy_event.sample_count == 1
      assert policy_event.payload["kind"] == "late_data_policy_decision"
      assert policy_event.payload["policy_decision"] == "accept"
      assert policy_event.payload["source_event_id"] == source_event.backfill_lifecycle_event_id
      assert policy_event.payload["source_event_type"] == "backfill_completed"
      assert policy_event.payload["selected_sample_count"] == 1
      assert policy_event.payload["write_validity_state"] == "canonical"
      assert policy_event.payload["record_current_values"]
      assert policy_event.payload["refresh_latest_value"]

      assert policy_event.payload["projection_effect"] ==
               "canonical_history_and_current_projection"

      assert policy_event.payload["dashboard_context"]["dashboard_limit_mode"] == "observed"

      assert %Sample{} = latest = Cadence.latest_telemetry_value(mission.mission_id, "HK.counter")
      assert latest.sample_id == "dashboard-late-source-sample"
      assert latest.raw_value == 72

      assert has_element?(
               view,
               ~s(#dashboard-data-link-action-outcome[data-data-link-action-outcome-action="late_data_policy"][data-data-link-action-outcome-status="ok"][data-data-link-action-outcome-reason="late_data_policy_applied"][data-data-link-action-outcome-decision="accept"][data-data-link-action-outcome-execution-mode="sample_execution"][data-data-link-action-outcome-dashboard-time-mode="live"][data-data-link-action-outcome-dashboard-limit-mode="observed"][data-data-link-action-outcome-result-event-id="#{policy_event.backfill_lifecycle_event_id}"][data-data-link-action-outcome-target-event-id="#{policy_event.backfill_lifecycle_event_id}"][data-data-link-action-outcome-target-run-id="dashboard-late-policy-run"]),
               "Late-data policy applied."
             )

      metadata =
        view
        |> render()
        |> element_attribute(
          "#dashboard-data-link-action-outcome",
          "data-data-link-action-outcome-metadata"
        )
        |> Jason.decode!()

      assert metadata == %{
               "dashboard_limit_mode" => "observed",
               "dashboard_time_mode" => "live",
               "decision" => "accept",
               "execution_mode" => "sample_execution",
               "result_event_id" => policy_event.backfill_lifecycle_event_id,
               "target_event_id" => policy_event.backfill_lifecycle_event_id,
               "target_run_id" => "dashboard-late-policy-run"
             }

      assert has_element?(
               view,
               ~s(#dashboard-data-link-inspector [data-data-link-field="Backfill lifecycle event"]),
               policy_event.backfill_lifecycle_event_id
             )

      assert has_element?(
               view,
               ~s(#dashboard-data-link-inspector [data-data-link-field="Event type"]),
               "late_data_accepted"
             )

      assert has_element?(
               view,
               ~s(#dashboard-data-link-inspector [data-data-link-field="Late data execution mode"]),
               "sample_execution"
             )

      assert has_element?(
               view,
               ~s(#dashboard-data-link-inspector [data-data-link-field="Late data source event type"]),
               "backfill_completed"
             )

      assert has_element?(
               view,
               ~s(#dashboard-data-link-inspector [data-data-link-field="Late data selected samples"]),
               "1"
             )

      source_event_selector =
        ~s(#dashboard-data-link-inspector [data-data-link-related-target="telemetry backfill lifecycle event"][data-data-link-related-id="#{source_event.backfill_lifecycle_event_id}"][data-data-link-related-kind="source_event"])

      assert has_element?(view, source_event_selector)

      view
      |> element(source_event_selector)
      |> render_click()

      source_event_path = assert_patch(view)
      assert source_event_path =~ "selected_target=telemetry_backfill_lifecycle_event"
      assert source_event_path =~ "selected_id=#{source_event.backfill_lifecycle_event_id}"

      assert has_element?(
               view,
               ~s(#dashboard-data-link-inspector [data-data-link-field="Backfill lifecycle event"]),
               source_event.backfill_lifecycle_event_id
             )
    end

    test "applies revision decisions from the revision event inspector" do
      {conn, org, mission} = signed_in_org_and_mission()
      %Document{} = dashboard = TestFixtures.persist_dashboard_document!(mission, name: "Power")

      {sample, initial_state} =
        persist_revision_sample_identity!(org, mission, "sample-dashboard-revision-live")

      assert initial_state.validity_state == :canonical

      assert %Sample{} =
               latest_before_decision =
               Cadence.latest_telemetry_value(
                 org.organization_id,
                 mission.mission_id,
                 "HK.counter",
                 spacecraft_id: sample.spacecraft_id,
                 realm: :flight,
                 data_source_id: "managed_questdb_primary",
                 binding_id: "default_flight_telemetry"
               )

      assert latest_before_decision.sample_id == sample.sample_id

      assert {:ok, _state} =
               Cadence.apply_telemetry_observation_identity_decision(
                 initial_state.observation_identity_id,
                 "mark_canonical",
                 %{
                   organization_id: org.organization_id,
                   mission_id: mission.mission_id,
                   realm: :flight,
                   data_source_id: "managed_questdb_primary",
                   binding_id: "default_flight_telemetry",
                   canonical_observation_id: initial_state.canonical_observation_id,
                   canonical_sample_id: initial_state.canonical_sample_id,
                   canonical_revision: initial_state.canonical_revision,
                   decision_reason: "prior_dashboard_canonical_review",
                   authority: "operator",
                   requested_by: "dashboard",
                   operator_id: "operator-source",
                   evidence_ref: %{
                     "kind" => "dashboard_revision_marker",
                     "id" => "source-marker-1",
                     "source_target" => "comparison_finding",
                     "source_target_id" => "placement-1",
                     "source_link_label" => "Comparison finding"
                   }
                 },
                 dashboard_runtime_invalidation?: false
               )

      assert %Sample{} =
               latest_after_source_decision =
               Cadence.latest_telemetry_value(
                 org.organization_id,
                 mission.mission_id,
                 "HK.counter",
                 spacecraft_id: sample.spacecraft_id,
                 realm: :flight,
                 data_source_id: "managed_questdb_primary",
                 binding_id: "default_flight_telemetry"
               )

      assert latest_after_source_decision.sample_id == sample.sample_id

      [source_event] =
        Storage.list_observation_identity_decision_events(
          initial_state.observation_identity_id,
          organization_id: org.organization_id,
          mission_id: mission.mission_id,
          realm: :flight,
          data_source_id: "managed_questdb_primary",
          binding_id: "default_flight_telemetry"
        )

      path =
        show_path(mission, dashboard) <>
          "?panel=data_link&selected_target=telemetry_revision_decision_event&selected_id=#{source_event.decision_event_id}&limit_mode=compare"

      {:ok, view, _html} = live(conn, path)
      render_dashboard_async(view)

      assert has_element?(
               view,
               ~s(#dashboard-revision-decision-controls[data-revision-decision-observation-identity="#{initial_state.observation_identity_id}"])
             )

      assert has_element?(
               view,
               ~s(#dashboard-revision-decision-dashboard-limit-mode[value="compare"])
             )

      view
      |> form("#dashboard-revision-decision-form", %{
        "revision_decision" => %{
          "decision" => "mark_conflict",
          "decision_reason" => "operator_marked_conflict_from_dashboard",
          "confirmed" => "confirmed"
        }
      })
      |> render_submit()

      assert_patch(view)

      decision_events =
        Storage.list_observation_identity_decision_events(
          initial_state.observation_identity_id,
          organization_id: org.organization_id,
          mission_id: mission.mission_id,
          realm: :flight,
          data_source_id: "managed_questdb_primary",
          binding_id: "default_flight_telemetry"
        )

      assert has_element?(
               view,
               ~s(#dashboard-data-link-action-outcome[data-data-link-action-outcome-action="revision_decision"][data-data-link-action-outcome-status="ok"][data-data-link-action-outcome-reason="revision_decision_applied"][data-data-link-action-outcome-decision="mark_conflict"][data-data-link-action-outcome-dashboard-limit-mode="compare"]),
               "Telemetry revision decision applied."
             )

      metadata =
        view
        |> render()
        |> element_attribute(
          "#dashboard-data-link-action-outcome",
          "data-data-link-action-outcome-metadata"
        )
        |> Jason.decode!()

      applied_event =
        Enum.find(
          decision_events,
          &(&1.decision_event_id == metadata["result_event_id"])
        )

      assert has_element?(
               view,
               ~s(#dashboard-data-link-action-outcome[data-data-link-action-outcome-result-event-id="#{applied_event.decision_event_id}"][data-data-link-action-outcome-target-event-id="#{applied_event.decision_event_id}"][data-data-link-action-outcome-target-observation-identity-id="#{initial_state.observation_identity_id}"])
             )

      assert applied_event.decision == :mark_conflict
      assert applied_event.decision_reason == "operator_marked_conflict_from_dashboard"
      assert applied_event.evidence_ref["kind"] == "dashboard_revision_decision"
      assert applied_event.evidence_ref["id"] == source_event.decision_event_id
      assert applied_event.evidence_ref["source_target"] == "telemetry_revision_decision_event"
      assert applied_event.evidence_ref["source_target_id"] == source_event.decision_event_id

      assert applied_event.evidence_ref["dashboard_context"] == %{
               "dashboard_limit_mode" => "compare"
             }

      assert applied_event.previous_state["validity_state"] == "canonical"
      assert applied_event.new_state["validity_state"] == "conflict"
      assert applied_event.previous_state["canonical_sample_id"] == sample.sample_id
      assert applied_event.new_state["canonical_sample_id"] == sample.sample_id

      assert {:ok, applied_state} =
               Storage.fetch_observation_identity_state(initial_state.observation_identity_id)

      assert applied_state.validity_state == :conflict
      assert applied_state.decision_event_id == applied_event.decision_event_id
      assert applied_state.decision_reason == "operator_marked_conflict_from_dashboard"

      assert applied_state.payload["decision"]["evidence_ref"]["dashboard_context"] == %{
               "dashboard_limit_mode" => "compare"
             }

      refute Cadence.latest_telemetry_value(org.organization_id, mission.mission_id, "HK.counter",
               spacecraft_id: sample.spacecraft_id,
               realm: :flight,
               data_source_id: "managed_questdb_primary",
               binding_id: "default_flight_telemetry"
             )

      assert metadata == %{
               "dashboard_limit_mode" => "compare",
               "decision" => "mark_conflict",
               "result_event_id" => applied_event.decision_event_id,
               "target_event_id" => applied_event.decision_event_id,
               "target_observation_identity_id" => initial_state.observation_identity_id
             }

      assert has_element?(
               view,
               ~s(#dashboard-data-link-inspector [data-data-link-field="Revision decision event"]),
               applied_event.decision_event_id
             )

      assert has_element?(
               view,
               ~s(#dashboard-data-link-inspector [data-data-link-field="Previous validity state"]),
               "canonical"
             )

      assert has_element?(
               view,
               ~s(#dashboard-data-link-inspector [data-data-link-field="New validity state"]),
               "conflict"
             )
    end

    test "requests comparison reviews from the rollup and resolves them from activity" do
      {conn, user, org, mission} = signed_in_user_org_and_mission()
      spacecraft = TestFixtures.persist_spacecraft!(mission, display_name: "SC Review")
      binding_set = persist_binding_set!(org, mission)
      ingest!(mission, binding_set, spacecraft.spacecraft_id, 5, 1_700_000_100)

      dashboard =
        TestFixtures.persist_dashboard_document!(mission,
          name: "Review Rollup",
          widgets: [value_tile("HK.counter", :fixed, spacecraft.spacecraft_id)]
        )

      {:ok, view, _html} =
        live(
          conn,
          show_path(mission, dashboard) <>
            "?data_view=all_revisions&compare_data_view=canonical"
        )

      render_dashboard_async(view)

      assert has_element?(
               view,
               ~s(#dashboard-comparison-rollup[data-dashboard-comparison-open="1"])
             )

      assert has_element?(view, "#dashboard-comparison-open-findings-review-form")

      view
      |> form("#dashboard-comparison-open-findings-review-form")
      |> render_submit()

      patched_path = assert_patch(view)
      assert patched_path =~ "panel=versions"
      assert patched_path =~ "activity_filter=comparison_reviews"

      [request_event] =
        Cadence.Dashboards.list_lifecycle_events(
          org.organization_id,
          mission.mission_id,
          dashboard.dashboard_id
        )

      assert request_event.event_type == :comparison_review_requested
      assert request_event.actor_id == user.user_id
      assert request_event.payload["source"] == "dashboard_comparison_rollup"
      assert request_event.payload["open_count"] == 1

      assert has_element?(
               view,
               ~s([data-dashboard-comparison-review-request="#{request_event.dashboard_lifecycle_event_id}"][data-dashboard-comparison-review-status="open"])
             )

      view
      |> element("#dashboard-activity-filter-open-reviews")
      |> render_click()

      patched_path = assert_patch(view)
      assert patched_path =~ "activity_filter=open_comparison_reviews"

      assert has_element?(
               view,
               ~s(#dashboard-activity-section[data-dashboard-activity-mode="open_comparison_reviews"][data-dashboard-comparison-review-open-count="1"][data-dashboard-comparison-review-work-queue-count="1"])
             )

      view
      |> form(
        "#dashboard-comparison-review-resolve-form-#{request_event.dashboard_lifecycle_event_id}",
        %{
          "review" => %{"resolution_reason" => "Resolved from rollup request"}
        }
      )
      |> render_submit()

      patched_path = assert_patch(view)
      assert patched_path =~ "activity_filter=comparison_reviews"

      [request_event, resolution_event] =
        Cadence.Dashboards.list_lifecycle_events(
          org.organization_id,
          mission.mission_id,
          dashboard.dashboard_id
        )

      assert resolution_event.event_type == :comparison_review_resolved
      assert resolution_event.actor_id == user.user_id

      assert resolution_event.payload["source_request_event_id"] ==
               request_event.dashboard_lifecycle_event_id

      assert resolution_event.payload["resolution_reason"] == "Resolved from rollup request"

      assert resolution_event.payload["workflow_intent"] ==
               request_event.payload["workflow_intent"]

      assert resolution_event.payload["open_findings"] == request_event.payload["open_findings"]
      assert resolution_event.payload["source_open_count"] == request_event.payload["open_count"]

      assert resolution_event.payload["source_open_placement_ids"] ==
               request_event.payload["open_placement_ids"]

      assert has_element?(
               view,
               ~s([data-dashboard-comparison-review-request="#{request_event.dashboard_lifecycle_event_id}"][data-dashboard-comparison-review-status="resolved"][data-dashboard-comparison-review-resolution-event="#{resolution_event.dashboard_lifecycle_event_id}"])
             )

      assert has_element?(
               view,
               ~s([data-dashboard-comparison-review-resolution="#{resolution_event.dashboard_lifecycle_event_id}"][data-dashboard-comparison-review-resolution-workflow-kind="bulk_correction_authority_review"][data-dashboard-comparison-review-resolution-workflow-action="request_comparison_review"][data-dashboard-comparison-review-resolution-workflow-selection-count="1"][data-dashboard-comparison-review-resolution-source-open-count="1"])
             )
    end

    test "opens dashboard lifecycle events directly from data-link routes" do
      {conn, user, org, mission} = signed_in_user_org_and_mission()
      %Document{} = dashboard = TestFixtures.persist_dashboard_document!(mission, name: "Power")

      assert {:ok, request_event} =
               Cadence.Dashboards.record_dashboard_comparison_review_request(
                 org.organization_id,
                 mission.mission_id,
                 dashboard.dashboard_id,
                 %{
                   "schema" => "dashboard_comparison_review_request.v1",
                   "request_kind" => "comparison_open_findings_review",
                   "open_count" => 1,
                   "open_placement_ids" => ["placement-counter"]
                 },
                 actor_id: user.user_id
               )

      path =
        show_path(mission, dashboard) <>
          "?panel=data_link&selected_target=dashboard_lifecycle_event&selected_id=#{request_event.dashboard_lifecycle_event_id}"

      {:ok, view, _html} = live(conn, path)
      render_dashboard_async(view)

      assert has_element?(
               view,
               ~s(#dashboard-data-link-inspector[data-data-link-target="dashboard_lifecycle_event"][data-data-link-target-id="#{request_event.dashboard_lifecycle_event_id}"][data-data-link-status="resolved"])
             )

      assert has_element?(
               view,
               ~s(#ops-dashboard-show-page[data-dashboard-selection-state="query_only"][data-dashboard-selection-target="dashboard_lifecycle_event"])
             )

      assert has_element?(
               view,
               ~s(#dashboard-data-link-inspector [data-data-link-field="Dashboard lifecycle event"]),
               request_event.dashboard_lifecycle_event_id
             )

      assert has_element?(
               view,
               ~s(#dashboard-data-link-inspector [data-data-link-field="Event type"]),
               "comparison_review_requested"
             )

      assert has_element?(
               view,
               ~s(#dashboard-data-link-inspector [data-data-link-field="Comparison review kind"]),
               "comparison_open_findings_review"
             )

      assert has_element?(
               view,
               ~s(#dashboard-data-link-copy-link[data-clipboard-text*="panel=data_link"][data-clipboard-text*="selected_target=dashboard_lifecycle_event"][data-clipboard-text*="selected_id=#{URI.encode_www_form(request_event.dashboard_lifecycle_event_id)}"])
             )
    end

    test "keeps missing dashboard lifecycle data-link routes inspectable" do
      {conn, _org, mission} = signed_in_org_and_mission()
      %Document{} = dashboard = TestFixtures.persist_dashboard_document!(mission, name: "Power")
      missing_event_id = "missing-dashboard-lifecycle-event"

      path =
        show_path(mission, dashboard) <>
          "?panel=data_link&selected_target=dashboard_lifecycle_event&selected_id=#{missing_event_id}"

      {:ok, view, _html} = live(conn, path)
      render_dashboard_async(view)

      assert has_element?(
               view,
               ~s(#dashboard-data-link-inspector[data-data-link-target="dashboard_lifecycle_event"][data-data-link-target-id="#{missing_event_id}"][data-data-link-status="missing"])
             )

      assert has_element?(
               view,
               ~s(#ops-dashboard-show-page[data-dashboard-selection-state="missing_target"][data-dashboard-selection-target="dashboard_lifecycle_event"])
             )

      assert has_element?(
               view,
               ~s(#dashboard-data-link-copy-link[data-clipboard-text*="panel=data_link"][data-clipboard-text*="selected_target=dashboard_lifecycle_event"][data-clipboard-text*="selected_id=#{missing_event_id}"])
             )
    end

    test "resolves mixed comparison reviews with bulk decision audit context" do
      {conn, user, org, mission} = signed_in_user_org_and_mission()
      %Document{} = dashboard = TestFixtures.persist_dashboard_document!(mission, name: "Power")

      source_context = %{
        "realm" => "flight",
        "data_source_id" => "managed_questdb_primary",
        "source_binding_id" => "default_flight_telemetry"
      }

      assert {:ok, request_event} =
               Cadence.Dashboards.record_dashboard_comparison_review_request(
                 org.organization_id,
                 mission.mission_id,
                 dashboard.dashboard_id,
                 %{
                   "schema" => "dashboard_comparison_review_request.v1",
                   "request_kind" => "comparison_open_findings_review",
                   "open_count" => 2,
                   "open_placement_ids" => ["placement-counter", "placement-untracked"],
                   "workflow_intent" => %{
                     "kind" => "bulk_correction_authority_review",
                     "action" => "request_comparison_review",
                     "selection_count" => 2
                   },
                   "open_findings" => %{
                     "schema" => "dashboard_comparison_open_findings.v1",
                     "runtime_query" => source_context,
                     "findings" => [
                       %{
                         "placement_id" => "placement-counter",
                         "title" => "Counter",
                         "state" => "increased",
                         "decision_status" => "unhandled",
                         "observation_identity_id" => "identity-counter",
                         "primary_data_link" => %{"context" => %{"data" => source_context}}
                       },
                       %{
                         "placement_id" => "placement-untracked",
                         "title" => "Untracked finding",
                         "state" => "missing",
                         "decision_status" => "unhandled",
                         "primary_data_link" => %{"context" => %{"data" => source_context}}
                       }
                     ]
                   }
                 },
                 actor_id: user.user_id
               )

      path =
        show_path(mission, dashboard) <>
          "?panel=versions&activity_filter=open_comparison_reviews&activity_event=#{request_event.dashboard_lifecycle_event_id}"

      {:ok, view, _html} = live(conn, path)
      render_dashboard_async(view)

      view
      |> form(
        "#dashboard-comparison-review-resolve-form-#{request_event.dashboard_lifecycle_event_id}",
        %{
          "review" => %{"resolution_reason" => "Mixed request reviewed"}
        }
      )
      |> render_submit()

      assert_patch(view)

      [_request_event, resolution_event] =
        Cadence.Dashboards.list_lifecycle_events(
          org.organization_id,
          mission.mission_id,
          dashboard.dashboard_id
        )

      assert resolution_event.payload["source_bulk_decision_actionable_count"] == 1

      assert resolution_event.payload["source_bulk_decision_actionable_placement_ids"] == [
               "placement-counter"
             ]

      assert resolution_event.payload["source_bulk_decision_skipped_count"] == 1

      assert resolution_event.payload["source_bulk_decision_skipped_placement_ids"] == [
               "placement-untracked"
             ]

      assert resolution_event.payload["source_bulk_decision_skipped_reasons"] == [
               "missing_observation_identity"
             ]

      assert has_element?(
               view,
               ~s([data-dashboard-comparison-review-resolution="#{resolution_event.dashboard_lifecycle_event_id}"][data-dashboard-comparison-review-resolution-source-actionable-count="1"][data-dashboard-comparison-review-resolution-source-actionable-placements="placement-counter"][data-dashboard-comparison-review-resolution-source-skipped-count="1"][data-dashboard-comparison-review-resolution-source-skipped-placements="placement-untracked"][data-dashboard-comparison-review-resolution-source-skipped-reasons="missing_observation_identity"]),
               "1 actionable / 1 skipped"
             )
    end

    test "applies bulk revision decisions from an open comparison review" do
      {conn, user, org, mission} = signed_in_user_org_and_mission()
      %Document{} = dashboard = TestFixtures.persist_dashboard_document!(mission, name: "Power")

      {_sample_a, state_a} =
        persist_revision_sample_identity!(org, mission, "sample-review-bulk-counter",
          point_id: "HK.counter"
        )

      {_sample_b, state_b} =
        persist_revision_sample_identity!(org, mission, "sample-review-bulk-voltage",
          point_id: "HK.voltage"
        )

      source_context = %{
        "realm" => "flight",
        "data_source_id" => "managed_questdb_primary",
        "source_binding_id" => "default_flight_telemetry"
      }

      assert {:ok, request_event} =
               Cadence.Dashboards.record_dashboard_comparison_review_request(
                 org.organization_id,
                 mission.mission_id,
                 dashboard.dashboard_id,
                 %{
                   "schema" => "dashboard_comparison_review_request.v1",
                   "request_kind" => "comparison_open_findings_review",
                   "open_count" => 2,
                   "open_placement_ids" => ["placement-counter", "placement-voltage"],
                   "open_findings" => %{
                     "schema" => "dashboard_comparison_open_findings.v1",
                     "runtime_query" => source_context,
                     "findings" => [
                       %{
                         "placement_id" => "placement-counter",
                         "title" => "Counter",
                         "state" => "increased",
                         "decision_status" => "unhandled",
                         "observation_identity_id" => state_a.observation_identity_id,
                         "primary_sample_id" => state_a.canonical_sample_id,
                         "primary_observation_identity_id" => state_a.observation_identity_id,
                         "primary_observation_id" => state_a.canonical_observation_id,
                         "primary_revision" => state_a.canonical_revision,
                         "primary_data_link" => %{"context" => %{"data" => source_context}}
                       },
                       %{
                         "placement_id" => "placement-voltage",
                         "title" => "Voltage",
                         "state" => "missing",
                         "decision_status" => "unhandled",
                         "observation_identity_id" => state_b.observation_identity_id,
                         "primary_sample_id" => state_b.canonical_sample_id,
                         "primary_observation_identity_id" => state_b.observation_identity_id,
                         "primary_observation_id" => state_b.canonical_observation_id,
                         "primary_revision" => state_b.canonical_revision,
                         "primary_data_link" => %{"context" => %{"data" => source_context}}
                       }
                     ]
                   }
                 },
                 actor_id: user.user_id
               )

      path =
        show_path(mission, dashboard) <>
          "?panel=versions&activity_filter=open_comparison_reviews&activity_event=#{request_event.dashboard_lifecycle_event_id}"

      {:ok, view, _html} = live(conn, path)
      render_dashboard_async(view)

      assert has_element?(
               view,
               ~s(#dashboard-comparison-review-bulk-decision-form-#{request_event.dashboard_lifecycle_event_id}[data-dashboard-comparison-review-bulk-decision-count="2"][data-dashboard-comparison-review-bulk-decision-placements="placement-counter,placement-voltage"])
             )

      view
      |> form(
        "#dashboard-comparison-review-bulk-decision-form-#{request_event.dashboard_lifecycle_event_id}"
      )
      |> render_submit()

      assert_patch(view)

      assert has_element?(
               view,
               ~s(#dashboard-comparison-review-action-outcome[data-dashboard-comparison-review-action="comparison_review_bulk_decision"][data-dashboard-comparison-review-action-status="ok"][data-dashboard-comparison-review-action-source-request-id="#{request_event.dashboard_lifecycle_event_id}"][data-dashboard-comparison-review-action-workflow-id="#{request_event.dashboard_lifecycle_event_id}"][data-dashboard-comparison-review-action-requested="2"][data-dashboard-comparison-review-action-applied="2"][data-dashboard-comparison-review-action-failed="0"])
             )

      action_html = render(view)

      assert action_html =~ "Comparison Review Action"
      assert action_html =~ "Comparison review decisions applied to 2 findings."
      assert action_html =~ "Requested"
      assert action_html =~ "Applied"
      assert action_html =~ "Failed"

      action_metadata =
        action_html
        |> element_attribute(
          "#dashboard-comparison-review-action-outcome",
          "data-dashboard-comparison-review-action-metadata"
        )
        |> Jason.decode!()

      assert action_metadata["requested"] == "2"
      assert action_metadata["applied"] == "2"
      assert action_metadata["failed"] == "0"

      assert action_metadata["source_request_event_id"] ==
               request_event.dashboard_lifecycle_event_id

      assert action_metadata["workflow_id"] == request_event.dashboard_lifecycle_event_id

      query_opts = [
        organization_id: org.organization_id,
        mission_id: mission.mission_id,
        realm: :flight,
        data_source_id: "managed_questdb_primary",
        binding_id: "default_flight_telemetry"
      ]

      [event_a] =
        Storage.list_observation_identity_decision_events(
          state_a.observation_identity_id,
          query_opts
        )

      [event_b] =
        Storage.list_observation_identity_decision_events(
          state_b.observation_identity_id,
          query_opts
        )

      for {event, state, index, placement_id} <- [
            {event_a, state_a, 1, "placement-counter"},
            {event_b, state_b, 2, "placement-voltage"}
          ] do
        assert event.decision == :mark_conflict
        assert event.decision_reason == "dashboard_comparison_review_mark_conflict"
        assert event.actor_id == user.user_id
        assert event.actor_kind == "operator"
        assert event.evidence_ref["kind"] == "dashboard_comparison_review_finding"
        assert event.evidence_ref["placement_id"] == placement_id
        assert event.evidence_ref["comparison_finding"]["placement_id"] == placement_id

        assert event.evidence_ref["bulk_workflow_item"] == %{
                 "kind" => "telemetry_correction_authority_workflow_item",
                 "workflow_id" => request_event.dashboard_lifecycle_event_id,
                 "item_index" => index,
                 "item_count" => 2,
                 "observation_identity_id" => state.observation_identity_id,
                 "selection_kind" => "open_comparison_findings"
               }

        assert event.evidence_ref["correction_workflow"]["id"] ==
                 request_event.dashboard_lifecycle_event_id

        assert event.evidence_ref["correction_workflow"]["item_index"] == index
        assert event.evidence_ref["correction_workflow"]["item_count"] == 2
      end

      decision_event_path =
        show_path(mission, dashboard) <>
          "?panel=data_link&selected_target=telemetry_revision_decision_event&selected_id=#{event_a.decision_event_id}"

      {:ok, decision_view, _html} = live(conn, decision_event_path)
      render_dashboard_async(decision_view)

      assert has_element?(
               decision_view,
               ~s(#dashboard-data-link-inspector[data-data-link-target="telemetry_revision_decision_event"][data-data-link-target-id="#{event_a.decision_event_id}"][data-data-link-status="resolved"])
             )

      assert has_element?(
               decision_view,
               ~s(#dashboard-data-link-inspector [data-data-link-field="Bulk workflow"]),
               request_event.dashboard_lifecycle_event_id
             )

      assert has_element?(
               decision_view,
               ~s(#dashboard-data-link-inspector [data-data-link-field="Bulk workflow item"]),
               "1"
             )

      assert has_element?(
               decision_view,
               ~s(#dashboard-data-link-inspector [data-data-link-field="Bulk workflow item count"]),
               "2"
             )

      assert has_element?(
               decision_view,
               ~s(#dashboard-data-link-inspector [data-data-link-field="Bulk workflow observation identity"]),
               state_a.observation_identity_id
             )

      assert has_element?(
               decision_view,
               ~s(#dashboard-data-link-inspector [data-data-link-field="Bulk workflow selection"]),
               "open_comparison_findings"
             )

      assert has_element?(
               decision_view,
               ~s(#dashboard-data-link-inspector [data-data-link-related-target="dashboard lifecycle event"][data-data-link-related-id="#{request_event.dashboard_lifecycle_event_id}"][data-data-link-related-kind="comparison_review_origin"])
             )

      assert {:ok, updated_a} =
               Storage.fetch_observation_identity_state(state_a.observation_identity_id)

      assert {:ok, updated_b} =
               Storage.fetch_observation_identity_state(state_b.observation_identity_id)

      assert updated_a.validity_state == :conflict
      assert updated_b.validity_state == :conflict
    end

    test "applies bulk comparison review decisions only to actionable findings" do
      {conn, user, org, mission} = signed_in_user_org_and_mission()
      %Document{} = dashboard = TestFixtures.persist_dashboard_document!(mission, name: "Power")

      {_sample, state} =
        persist_revision_sample_identity!(org, mission, "sample-review-bulk-mixed-actionable",
          point_id: "HK.counter"
        )

      source_context = %{
        "realm" => "flight",
        "data_source_id" => "managed_questdb_primary",
        "source_binding_id" => "default_flight_telemetry"
      }

      assert {:ok, request_event} =
               Cadence.Dashboards.record_dashboard_comparison_review_request(
                 org.organization_id,
                 mission.mission_id,
                 dashboard.dashboard_id,
                 %{
                   "schema" => "dashboard_comparison_review_request.v1",
                   "request_kind" => "comparison_open_findings_review",
                   "open_count" => 2,
                   "open_placement_ids" => ["placement-counter", "placement-untracked"],
                   "open_findings" => %{
                     "schema" => "dashboard_comparison_open_findings.v1",
                     "runtime_query" => source_context,
                     "findings" => [
                       %{
                         "placement_id" => "placement-counter",
                         "title" => "Counter",
                         "state" => "increased",
                         "decision_status" => "unhandled",
                         "observation_identity_id" => state.observation_identity_id,
                         "primary_sample_id" => state.canonical_sample_id,
                         "primary_observation_identity_id" => state.observation_identity_id,
                         "primary_observation_id" => state.canonical_observation_id,
                         "primary_revision" => state.canonical_revision,
                         "primary_data_link" => %{"context" => %{"data" => source_context}}
                       },
                       %{
                         "placement_id" => "placement-untracked",
                         "title" => "Untracked finding",
                         "state" => "missing",
                         "decision_status" => "unhandled",
                         "primary_data_view" => "all_revisions",
                         "compare_data_view" => "canonical",
                         "primary_data_link" => %{"context" => %{"data" => source_context}}
                       }
                     ]
                   }
                 },
                 actor_id: user.user_id
               )

      path =
        show_path(mission, dashboard) <>
          "?panel=versions&activity_filter=open_comparison_reviews&activity_event=#{request_event.dashboard_lifecycle_event_id}"

      {:ok, view, _html} = live(conn, path)
      render_dashboard_async(view)

      assert has_element?(
               view,
               ~s(#dashboard-activity-section[data-dashboard-comparison-review-open-count="1"][data-dashboard-comparison-review-open-placements="placement-counter,placement-untracked"])
             )

      assert has_element?(
               view,
               ~s(#dashboard-comparison-review-bulk-decision-form-#{request_event.dashboard_lifecycle_event_id}[data-dashboard-comparison-review-bulk-decision-count="1"][data-dashboard-comparison-review-bulk-decision-placements="placement-counter"])
             )

      assert has_element?(
               view,
               ~s([data-dashboard-comparison-review-request="#{request_event.dashboard_lifecycle_event_id}"][data-dashboard-comparison-review-bulk-decision-skipped-count="1"][data-dashboard-comparison-review-bulk-decision-skipped-placements="placement-untracked"][data-dashboard-comparison-review-bulk-decision-skipped-reasons="missing_observation_identity"])
             )

      assert has_element?(
               view,
               ~s([data-dashboard-comparison-review-bulk-decision-skipped="#{request_event.dashboard_lifecycle_event_id}"][data-dashboard-comparison-review-bulk-decision-skipped-count="1"]),
               "1 finding skipped for bulk action."
             )

      assert has_element?(
               view,
               ~s([data-dashboard-comparison-review-finding="placement-counter"][data-dashboard-comparison-review-finding-bulk-decision="included"][data-dashboard-comparison-review-finding-bulk-decision-label="Included in bulk action"])
             )

      assert has_element?(
               view,
               ~s([data-dashboard-comparison-review-finding="placement-untracked"][data-dashboard-comparison-review-finding-bulk-decision="skipped"][data-dashboard-comparison-review-finding-bulk-decision-reason="missing_observation_identity"][data-dashboard-comparison-review-finding-bulk-decision-label="Skipped: missing observation identity"])
             )

      view
      |> form(
        "#dashboard-comparison-review-bulk-decision-form-#{request_event.dashboard_lifecycle_event_id}"
      )
      |> render_submit()

      assert_patch(view)

      assert has_element?(
               view,
               ~s(#dashboard-comparison-review-action-outcome[data-dashboard-comparison-review-action="comparison_review_bulk_decision"][data-dashboard-comparison-review-action-status="ok"][data-dashboard-comparison-review-action-source-request-id="#{request_event.dashboard_lifecycle_event_id}"][data-dashboard-comparison-review-action-workflow-id="#{request_event.dashboard_lifecycle_event_id}"][data-dashboard-comparison-review-action-requested="1"][data-dashboard-comparison-review-action-applied="1"][data-dashboard-comparison-review-action-failed="0"])
             )

      action_html = render(view)

      assert action_html =~ "Comparison review decisions applied to 1 findings."

      action_metadata =
        action_html
        |> element_attribute(
          "#dashboard-comparison-review-action-outcome",
          "data-dashboard-comparison-review-action-metadata"
        )
        |> Jason.decode!()

      assert action_metadata["requested"] == "1"
      assert action_metadata["applied"] == "1"
      assert action_metadata["failed"] == "0"

      [event] =
        Storage.list_observation_identity_decision_events(
          state.observation_identity_id,
          organization_id: org.organization_id,
          mission_id: mission.mission_id,
          realm: :flight,
          data_source_id: "managed_questdb_primary",
          binding_id: "default_flight_telemetry"
        )

      assert event.decision == :mark_conflict
      assert event.evidence_ref["placement_id"] == "placement-counter"

      assert event.evidence_ref["bulk_workflow_item"] == %{
               "kind" => "telemetry_correction_authority_workflow_item",
               "workflow_id" => request_event.dashboard_lifecycle_event_id,
               "item_index" => 1,
               "item_count" => 1,
               "observation_identity_id" => state.observation_identity_id,
               "selection_kind" => "open_comparison_findings"
             }
    end

    test "shows partial failure outcome for bulk comparison review decisions" do
      {conn, user, org, mission} = signed_in_user_org_and_mission()
      %Document{} = dashboard = TestFixtures.persist_dashboard_document!(mission, name: "Power")

      {_sample, state} =
        persist_revision_sample_identity!(org, mission, "sample-review-bulk-partial",
          point_id: "HK.counter"
        )

      missing_observation_identity_id = "missing-observation-identity-partial"

      source_context = %{
        "realm" => "flight",
        "data_source_id" => "managed_questdb_primary",
        "source_binding_id" => "default_flight_telemetry"
      }

      assert {:ok, request_event} =
               Cadence.Dashboards.record_dashboard_comparison_review_request(
                 org.organization_id,
                 mission.mission_id,
                 dashboard.dashboard_id,
                 %{
                   "schema" => "dashboard_comparison_review_request.v1",
                   "request_kind" => "comparison_open_findings_review",
                   "open_count" => 2,
                   "open_placement_ids" => ["placement-counter", "placement-missing"],
                   "open_findings" => %{
                     "schema" => "dashboard_comparison_open_findings.v1",
                     "runtime_query" => source_context,
                     "findings" => [
                       %{
                         "placement_id" => "placement-counter",
                         "title" => "Counter",
                         "state" => "increased",
                         "decision_status" => "unhandled",
                         "observation_identity_id" => state.observation_identity_id,
                         "primary_sample_id" => state.canonical_sample_id,
                         "primary_observation_identity_id" => state.observation_identity_id,
                         "primary_observation_id" => state.canonical_observation_id,
                         "primary_revision" => state.canonical_revision,
                         "primary_data_link" => %{"context" => %{"data" => source_context}}
                       },
                       %{
                         "placement_id" => "placement-missing",
                         "title" => "Missing identity",
                         "state" => "missing",
                         "decision_status" => "unhandled",
                         "observation_identity_id" => missing_observation_identity_id,
                         "primary_observation_identity_id" => missing_observation_identity_id,
                         "primary_data_link" => %{"context" => %{"data" => source_context}}
                       }
                     ]
                   }
                 },
                 actor_id: user.user_id
               )

      path =
        show_path(mission, dashboard) <>
          "?panel=versions&activity_filter=open_comparison_reviews&activity_event=#{request_event.dashboard_lifecycle_event_id}"

      {:ok, view, _html} = live(conn, path)
      render_dashboard_async(view)

      assert has_element?(
               view,
               ~s(#dashboard-comparison-review-bulk-decision-form-#{request_event.dashboard_lifecycle_event_id}[data-dashboard-comparison-review-bulk-decision-count="2"][data-dashboard-comparison-review-bulk-decision-placements="placement-counter,placement-missing"])
             )

      view
      |> form(
        "#dashboard-comparison-review-bulk-decision-form-#{request_event.dashboard_lifecycle_event_id}"
      )
      |> render_submit()

      assert_patch(view)

      assert has_element?(
               view,
               ~s(#dashboard-comparison-review-action-outcome[data-dashboard-comparison-review-action="comparison_review_bulk_decision"][data-dashboard-comparison-review-action-status="degraded"][data-dashboard-comparison-review-action-source-request-id="#{request_event.dashboard_lifecycle_event_id}"][data-dashboard-comparison-review-action-workflow-id="#{request_event.dashboard_lifecycle_event_id}"][data-dashboard-comparison-review-action-requested="2"][data-dashboard-comparison-review-action-applied="1"][data-dashboard-comparison-review-action-failed="1"])
             )

      action_html = render(view)

      assert action_html =~ "Comparison Review Action"
      assert action_html =~ "Comparison review decisions applied to 1 findings; 1 failed."
      assert action_html =~ "Partial"

      action_metadata =
        action_html
        |> element_attribute(
          "#dashboard-comparison-review-action-outcome",
          "data-dashboard-comparison-review-action-metadata"
        )
        |> Jason.decode!()

      assert action_metadata["requested"] == "2"
      assert action_metadata["applied"] == "1"
      assert action_metadata["failed"] == "1"

      assert action_metadata["source_request_event_id"] ==
               request_event.dashboard_lifecycle_event_id

      assert action_metadata["workflow_id"] == request_event.dashboard_lifecycle_event_id

      query_opts = [
        organization_id: org.organization_id,
        mission_id: mission.mission_id,
        realm: :flight,
        data_source_id: "managed_questdb_primary",
        binding_id: "default_flight_telemetry"
      ]

      [event] =
        Storage.list_observation_identity_decision_events(
          state.observation_identity_id,
          query_opts
        )

      assert event.decision == :mark_conflict
      assert event.decision_reason == "dashboard_comparison_review_mark_conflict"
      assert event.actor_id == user.user_id
      assert event.evidence_ref["placement_id"] == "placement-counter"

      assert event.evidence_ref["bulk_workflow_item"] == %{
               "kind" => "telemetry_correction_authority_workflow_item",
               "workflow_id" => request_event.dashboard_lifecycle_event_id,
               "item_index" => 1,
               "item_count" => 2,
               "observation_identity_id" => state.observation_identity_id,
               "selection_kind" => "open_comparison_findings"
             }

      assert Storage.list_observation_identity_decision_events(
               missing_observation_identity_id,
               query_opts
             ) == []

      assert {:ok, updated_state} =
               Storage.fetch_observation_identity_state(state.observation_identity_id)

      assert updated_state.validity_state == :conflict
    end

    test "explains unavailable bulk comparison decisions when source context is missing" do
      {conn, user, org, mission} = signed_in_user_org_and_mission()
      %Document{} = dashboard = TestFixtures.persist_dashboard_document!(mission, name: "Power")

      {_sample, state} =
        persist_revision_sample_identity!(org, mission, "sample-review-missing-source",
          point_id: "HK.counter"
        )

      assert {:ok, request_event} =
               Cadence.Dashboards.record_dashboard_comparison_review_request(
                 org.organization_id,
                 mission.mission_id,
                 dashboard.dashboard_id,
                 %{
                   "schema" => "dashboard_comparison_review_request.v1",
                   "request_kind" => "comparison_open_findings_review",
                   "open_count" => 1,
                   "open_placement_ids" => ["placement-counter"],
                   "open_findings" => %{
                     "schema" => "dashboard_comparison_open_findings.v1",
                     "findings" => [
                       %{
                         "placement_id" => "placement-counter",
                         "title" => "Counter",
                         "state" => "increased",
                         "decision_status" => "unhandled",
                         "observation_identity_id" => state.observation_identity_id,
                         "primary_sample_id" => state.canonical_sample_id,
                         "primary_observation_identity_id" => state.observation_identity_id,
                         "primary_observation_id" => state.canonical_observation_id,
                         "primary_revision" => state.canonical_revision
                       }
                     ]
                   }
                 },
                 actor_id: user.user_id
               )

      path =
        show_path(mission, dashboard) <>
          "?panel=versions&activity_filter=open_comparison_reviews&activity_event=#{request_event.dashboard_lifecycle_event_id}"

      {:ok, view, _html} = live(conn, path)
      render_dashboard_async(view)

      refute has_element?(
               view,
               "#dashboard-comparison-review-bulk-decision-form-#{request_event.dashboard_lifecycle_event_id}"
             )

      assert has_element?(
               view,
               ~s([data-dashboard-comparison-review-bulk-decision-unavailable="#{request_event.dashboard_lifecycle_event_id}"][data-dashboard-comparison-review-bulk-decision-unavailable-reason="missing_source_context"][data-dashboard-comparison-review-bulk-decision-unavailable-count="1"][data-dashboard-comparison-review-bulk-decision-unavailable-placements="placement-counter"]),
               "Bulk decision unavailable: telemetry source context is missing."
             )

      assert [] =
               Storage.list_observation_identity_decision_events(
                 state.observation_identity_id,
                 organization_id: org.organization_id,
                 mission_id: mission.mission_id,
                 realm: :flight,
                 data_source_id: "managed_questdb_primary",
                 binding_id: "default_flight_telemetry"
               )
    end

    test "explains unavailable bulk comparison decisions when no findings are actionable" do
      {conn, user, org, mission} = signed_in_user_org_and_mission()
      %Document{} = dashboard = TestFixtures.persist_dashboard_document!(mission, name: "Power")

      source_context = %{
        "realm" => "flight",
        "data_source_id" => "managed_questdb_primary",
        "source_binding_id" => "default_flight_telemetry"
      }

      assert {:ok, request_event} =
               Cadence.Dashboards.record_dashboard_comparison_review_request(
                 org.organization_id,
                 mission.mission_id,
                 dashboard.dashboard_id,
                 %{
                   "schema" => "dashboard_comparison_review_request.v1",
                   "request_kind" => "comparison_open_findings_review",
                   "open_count" => 1,
                   "open_placement_ids" => ["placement-counter"],
                   "open_findings" => %{
                     "schema" => "dashboard_comparison_open_findings.v1",
                     "findings" => [
                       %{
                         "placement_id" => "placement-counter",
                         "title" => "Counter",
                         "state" => "increased",
                         "decision_status" => "unhandled",
                         "primary_data_view" => "all_revisions",
                         "compare_data_view" => "canonical",
                         "primary_data_link" => %{"context" => %{"data" => source_context}}
                       }
                     ]
                   }
                 },
                 actor_id: user.user_id
               )

      path =
        show_path(mission, dashboard) <>
          "?panel=versions&activity_filter=open_comparison_reviews&activity_event=#{request_event.dashboard_lifecycle_event_id}"

      {:ok, view, _html} = live(conn, path)
      render_dashboard_async(view)

      refute has_element?(
               view,
               "#dashboard-comparison-review-bulk-decision-form-#{request_event.dashboard_lifecycle_event_id}"
             )

      assert has_element?(
               view,
               ~s([data-dashboard-comparison-review-bulk-decision-unavailable="#{request_event.dashboard_lifecycle_event_id}"][data-dashboard-comparison-review-bulk-decision-unavailable-reason="no_actionable_findings"][data-dashboard-comparison-review-bulk-decision-unavailable-count="0"][data-dashboard-comparison-review-bulk-decision-unavailable-placements=""]),
               "Bulk decision unavailable: no actionable findings."
             )

      assert [] =
               Storage.list_observation_identity_decision_events(
                 "missing-observation-identity",
                 organization_id: org.organization_id,
                 mission_id: mission.mission_id,
                 realm: :flight,
                 data_source_id: "managed_questdb_primary",
                 binding_id: "default_flight_telemetry"
               )
    end

    test "resolves comparison reviews from the versions activity queue" do
      {conn, user, org, mission} = signed_in_user_org_and_mission()
      %Document{} = dashboard = TestFixtures.persist_dashboard_document!(mission, name: "Power")

      assert {:ok, request_event} =
               Cadence.Dashboards.record_dashboard_comparison_review_request(
                 org.organization_id,
                 mission.mission_id,
                 dashboard.dashboard_id,
                 %{
                   "schema" => "dashboard_comparison_review_request.v1",
                   "request_kind" => "comparison_open_findings_review",
                   "open_count" => 2,
                   "open_placement_ids" => ["placement-1", "placement-2"],
                   "open_findings" => %{
                     "schema" => "dashboard_comparison_open_findings.v1",
                     "findings" => [
                       %{
                         "placement_id" => "placement-1",
                         "title" => "Bus voltage",
                         "state" => "increased",
                         "decision_status" => "unhandled"
                       },
                       %{
                         "placement_id" => "placement-2",
                         "title" => "Current",
                         "state" => "missing",
                         "decision_status" => "unhandled"
                       }
                     ]
                   }
                 },
                 actor_id: user.user_id
               )

      path =
        show_path(mission, dashboard) <>
          "?panel=versions&activity_filter=comparison_reviews&activity_event=#{request_event.dashboard_lifecycle_event_id}"

      {:ok, view, _html} = live(conn, path)
      render_dashboard_async(view)

      assert has_element?(
               view,
               ~s([data-dashboard-comparison-review-request="#{request_event.dashboard_lifecycle_event_id}"][data-dashboard-comparison-review-status="open"][data-dashboard-comparison-review-target-event-id="#{request_event.dashboard_lifecycle_event_id}"])
             )

      view
      |> form(
        "#dashboard-comparison-review-resolve-form-#{request_event.dashboard_lifecycle_event_id}",
        %{
          "review" => %{"resolution_reason" => "Reviewed by dashboard operator"}
        }
      )
      |> render_submit()

      patched_path = assert_patch(view)
      assert patched_path =~ "activity_filter=comparison_reviews"

      [request_event, resolution_event] =
        Cadence.Dashboards.list_lifecycle_events(
          org.organization_id,
          mission.mission_id,
          dashboard.dashboard_id
        )

      assert resolution_event.event_type == :comparison_review_resolved

      assert resolution_event.payload["source_request_event_id"] ==
               request_event.dashboard_lifecycle_event_id

      assert resolution_event.payload["resolution_reason"] == "Reviewed by dashboard operator"

      assert has_element?(
               view,
               ~s([data-dashboard-comparison-review-request="#{request_event.dashboard_lifecycle_event_id}"][data-dashboard-comparison-review-status="resolved"][data-dashboard-comparison-review-resolution-event="#{resolution_event.dashboard_lifecycle_event_id}"][data-dashboard-comparison-review-result-event-id="#{resolution_event.dashboard_lifecycle_event_id}"][data-dashboard-comparison-review-target-event-id="#{request_event.dashboard_lifecycle_event_id}"])
             )

      assert has_element?(
               view,
               ~s([data-dashboard-comparison-review-resolution="#{resolution_event.dashboard_lifecycle_event_id}"][data-dashboard-comparison-review-resolution-result-event-id="#{resolution_event.dashboard_lifecycle_event_id}"][data-dashboard-comparison-review-resolution-target-event-id="#{resolution_event.dashboard_lifecycle_event_id}"][data-dashboard-comparison-review-resolution-source="#{request_event.dashboard_lifecycle_event_id}"][data-dashboard-comparison-review-resolution-disposition="review_completed"][data-dashboard-comparison-review-resolution-affected-placements="placement-1,placement-2"]),
               "Reviewed by dashboard operator"
             )
    end

    test "starts a grouped historical workflow request from an open comparison review" do
      {conn, user, org, mission} = signed_in_user_org_and_mission()
      %Document{} = dashboard = TestFixtures.persist_dashboard_document!(mission, name: "Power")

      assert {:ok, request_event} =
               Cadence.Dashboards.record_dashboard_comparison_review_request(
                 org.organization_id,
                 mission.mission_id,
                 dashboard.dashboard_id,
                 %{
                   "schema" => "dashboard_comparison_review_request.v1",
                   "request_kind" => "comparison_open_findings_review",
                   "open_count" => 2,
                   "open_placement_ids" => ["placement-counter", "placement-voltage"],
                   "workflow_intent" => %{
                     "schema" => "dashboard_comparison_workflow_intent.v1",
                     "kind" => "bulk_correction_authority_review",
                     "source" => "dashboard_comparison_rollup",
                     "action" => "request_comparison_review",
                     "selection_kind" => "open_comparison_findings",
                     "selection_count" => 2,
                     "placement_ids" => ["placement-counter", "placement-voltage"],
                     "primary_data_view" => "all_revisions",
                     "compare_data_view" => "canonical"
                   },
                   "open_findings" => %{
                     "schema" => "dashboard_comparison_open_findings.v1",
                     "comparison" => %{
                       "primary_data_view" => "all_revisions",
                       "compare_data_view" => "canonical"
                     },
                     "findings" => [
                       %{
                         "placement_id" => "placement-counter",
                         "title" => "Counter",
                         "state" => "increased",
                         "decision_status" => "unhandled",
                         "primary_observable_ids" => ["HK.counter"],
                         "compare_observable_ids" => ["HK.counter"]
                       },
                       %{
                         "placement_id" => "placement-voltage",
                         "title" => "Voltage",
                         "state" => "missing",
                         "decision_status" => "unhandled",
                         "primary_observable_ids" => ["HK.voltage"],
                         "compare_observable_ids" => ["HK.voltage"]
                       }
                     ]
                   }
                 },
                 actor_id: user.user_id
               )

      path =
        show_path(mission, dashboard) <>
          "?panel=versions&activity_filter=open_comparison_reviews&activity_event=#{request_event.dashboard_lifecycle_event_id}"

      {:ok, view, _html} = live(conn, path)
      render_dashboard_async(view)

      assert has_element?(
               view,
               ~s(#dashboard-comparison-review-workflow-request-#{request_event.dashboard_lifecycle_event_id}[data-dashboard-comparison-review-workflow-point-count="2"][data-dashboard-comparison-review-workflow-point-ids="HK.counter,HK.voltage"])
             )

      view
      |> element(
        "#dashboard-comparison-review-workflow-request-#{request_event.dashboard_lifecycle_event_id}"
      )
      |> render_click()

      assert has_element?(view, "#dashboard-historical-workflow-request-form")

      assert has_element?(
               view,
               ~s(input[name="historical_workflow_request[observable_id]"][value="HK.counter"])
             )

      assert has_element?(
               view,
               ~s(input[name="historical_workflow_request[point_id]"][value="HK.counter"])
             )

      assert has_element?(
               view,
               ~s(input[name="historical_workflow_request[point_ids]"][value="HK.counter, HK.voltage"])
             )

      assert has_element?(
               view,
               ~s(input[name="historical_workflow_request[reason]"][value="operator_requested_bulk_correction_authority_review"])
             )

      assert has_element?(
               view,
               ~s(input[name="historical_workflow_request[comparison_review_request_event_id]"][value="#{request_event.dashboard_lifecycle_event_id}"])
             )

      assert has_element?(
               view,
               ~s(input[name="historical_workflow_request[comparison_review_request_kind]"][value="comparison_open_findings_review"])
             )

      assert has_element?(
               view,
               ~s(input[name="historical_workflow_request[comparison_review_open_count]"][value="2"])
             )

      assert has_element?(
               view,
               ~s(input[name="historical_workflow_request[comparison_review_open_placement_ids]"][value="placement-counter,placement-voltage"])
             )

      assert has_element?(
               view,
               ~s(input[name="historical_workflow_request[comparison_review_workflow_kind]"][value="bulk_correction_authority_review"])
             )

      assert has_element?(
               view,
               ~s(input[name="historical_workflow_request[comparison_review_workflow_action]"][value="request_comparison_review"])
             )

      assert has_element?(
               view,
               ~s(input[name="historical_workflow_request[comparison_review_workflow_selection_kind]"][value="open_comparison_findings"])
             )

      assert has_element?(
               view,
               ~s(input[name="historical_workflow_request[comparison_review_workflow_selection_count]"][value="2"])
             )

      assert has_element?(
               view,
               ~s(input[name="historical_workflow_request[comparison_review_primary_data_view]"][value="all_revisions"])
             )

      assert has_element?(
               view,
               ~s(input[name="historical_workflow_request[comparison_review_compare_data_view]"][value="canonical"])
             )

      view
      |> form("#dashboard-historical-workflow-request-form", %{
        "historical_workflow_request" => %{
          "workflow" => "backfill",
          "run_id" => "dashboard-comparison-workflow-run",
          "realm" => "backfill",
          "data_source_id" => "managed_questdb_backfill",
          "source_binding_id" => "backfill_telemetry",
          "point_ids" => "HK.counter, HK.voltage",
          "source_from" => "2026-06-22T10:00:00Z",
          "source_to" => "2026-06-22T11:00:00Z",
          "reason" => "operator_requested_bulk_correction_authority_review",
          "confirmed" => "confirmed"
        }
      })
      |> render_submit()

      assert_patch(view)

      events =
        mission.mission_id
        |> Storage.list_backfill_lifecycle_events(organization_id: org.organization_id)
        |> Enum.filter(&(&1.payload["request_group_id"] == "dashboard-comparison-workflow-run"))
        |> Enum.sort_by(& &1.point_id)

      assert Enum.map(events, & &1.point_id) == ["HK.counter", "HK.voltage"]
      assert Enum.all?(events, &(&1.event_type == :backfill_requested))
      assert Enum.all?(events, &(&1.payload["request_mode"] == "bulk_points"))
      assert Enum.all?(events, &(&1.payload["request_item_count"] == 2))

      expected_origin = %{
        "request_event_id" => request_event.dashboard_lifecycle_event_id,
        "request_kind" => "comparison_open_findings_review",
        "open_count" => "2",
        "open_placement_ids" => "placement-counter,placement-voltage",
        "workflow_kind" => "bulk_correction_authority_review",
        "workflow_action" => "request_comparison_review",
        "workflow_selection_kind" => "open_comparison_findings",
        "workflow_selection_count" => "2",
        "primary_data_view" => "all_revisions",
        "compare_data_view" => "canonical"
      }

      assert Enum.all?(events, &(&1.payload["comparison_review_origin"] == expected_origin))

      source_event = List.first(events)

      nav_trail =
        Jason.encode!([
          %{
            "target" => "telemetry_backfill_lifecycle_event",
            "target_id" => source_event.backfill_lifecycle_event_id,
            "label" => "Backfill lifecycle event",
            "relationship_kind" => "comparison_review_origin",
            "relationship_label" => "Comparison review request",
            "realm" => "backfill",
            "data_source_id" => "managed_questdb_backfill",
            "source_binding_id" => "backfill_telemetry"
          }
        ])

      lifecycle_route =
        show_path(mission, dashboard) <>
          "?" <>
          URI.encode_query(%{
            "panel" => "data_link",
            "selected_target" => "dashboard_lifecycle_event",
            "selected_id" => request_event.dashboard_lifecycle_event_id,
            "nav_from_target" => "telemetry_backfill_lifecycle_event",
            "nav_from_target_id" => source_event.backfill_lifecycle_event_id,
            "nav_from_label" => "Backfill lifecycle event",
            "nav_from_relationship_kind" => "comparison_review_origin",
            "nav_from_relationship_label" => "Comparison review request",
            "nav_trail" => nav_trail,
            "realm" => "backfill",
            "data_source_id" => "managed_questdb_backfill",
            "source_binding_id" => "backfill_telemetry"
          })

      {:ok, lifecycle_view, _html} = live(conn, lifecycle_route)
      render_dashboard_async(lifecycle_view)

      assert has_element?(
               lifecycle_view,
               ~s(#dashboard-data-link-inspector[data-data-link-target="dashboard_lifecycle_event"][data-data-link-target-id="#{request_event.dashboard_lifecycle_event_id}"][data-data-link-status="resolved"])
             )

      assert has_element?(
               lifecycle_view,
               ~s(#dashboard-data-link-inspector [data-data-link-navigation] [data-data-link-nav-entry-id="#{source_event.backfill_lifecycle_event_id}"][phx-value-target="telemetry_backfill_lifecycle_event"][phx-value-nav-from-target-id="#{request_event.dashboard_lifecycle_event_id}"])
             )

      assert has_element?(
               lifecycle_view,
               ~s(#dashboard-data-link-copy-link[data-clipboard-text*="panel=data_link"][data-clipboard-text*="selected_target=dashboard_lifecycle_event"][data-clipboard-text*="selected_id=#{URI.encode_www_form(request_event.dashboard_lifecycle_event_id)}"][data-clipboard-text*="nav_from_target=telemetry_backfill_lifecycle_event"][data-clipboard-text*="nav_from_target_id=#{URI.encode_www_form(source_event.backfill_lifecycle_event_id)}"][data-clipboard-text*="nav_trail="])
             )

      assert Enum.all?(
               events,
               &(&1.reason == "operator_requested_bulk_correction_authority_review")
             )

      assert has_element?(
               view,
               ~s(#dashboard-historical-workflow-group-summary[data-historical-workflow-group-comparison-review-request="#{request_event.dashboard_lifecycle_event_id}"][data-historical-workflow-group-comparison-review-open-count="2"][data-historical-workflow-group-comparison-review-placements="placement-counter,placement-voltage"])
             )

      assert has_element?(
               view,
               ~s(#dashboard-historical-workflow-group-summary[data-historical-workflow-group-comparison-review-workflow-kind="bulk_correction_authority_review"][data-historical-workflow-group-comparison-review-workflow-action="request_comparison_review"][data-historical-workflow-group-comparison-review-workflow-selection-kind="open_comparison_findings"][data-historical-workflow-group-comparison-review-workflow-selection-count="2"][data-historical-workflow-group-comparison-review-primary-data-view="all_revisions"][data-historical-workflow-group-comparison-review-compare-data-view="canonical"])
             )

      assert has_element?(
               view,
               ~s(#dashboard-historical-workflow-review-origin[data-historical-workflow-review-origin-request="#{request_event.dashboard_lifecycle_event_id}"][data-historical-workflow-review-origin-open-count="2"][data-historical-workflow-review-origin-placements="placement-counter,placement-voltage"])
             )

      assert has_element?(
               view,
               ~s(#dashboard-historical-workflow-review-origin[data-historical-workflow-review-origin-workflow-kind="bulk_correction_authority_review"][data-historical-workflow-review-origin-workflow-action="request_comparison_review"][data-historical-workflow-review-origin-workflow-selection-kind="open_comparison_findings"][data-historical-workflow-review-origin-workflow-selection-count="2"][data-historical-workflow-review-origin-primary-data-view="all_revisions"][data-historical-workflow-review-origin-compare-data-view="canonical"])
             )

      assert has_element?(
               view,
               ~s([data-historical-workflow-review-origin-link="#{request_event.dashboard_lifecycle_event_id}"][data-historical-workflow-review-origin-href*="activity_filter=open_comparison_reviews"][data-historical-workflow-review-origin-href*="activity_event=#{request_event.dashboard_lifecycle_event_id}"]),
               "Open review"
             )

      assert has_element?(
               view,
               ~s([data-historical-workflow-review-origin-placement="placement-counter"][data-historical-workflow-review-origin-placement-href*="selected_placement=placement-counter"]),
               "placement-counter"
             )

      assert has_element?(
               view,
               ~s([data-historical-workflow-review-origin-placement="placement-voltage"][data-historical-workflow-review-origin-placement-href*="selected_placement=placement-voltage"]),
               "placement-voltage"
             )

      view
      |> element("#dashboard-historical-workflow-group-form")
      |> render_submit(%{
        "historical_workflow_group" => %{
          "workflow" => "backfill",
          "request_group_id" => "dashboard-comparison-workflow-run",
          "realm" => "backfill",
          "data_source_id" => "managed_questdb_backfill",
          "source_binding_id" => "backfill_telemetry",
          "stage" => "approved",
          "reason" => "operator_approved_bulk_correction_authority_review",
          "confirmed" => "confirmed"
        }
      })

      assert_patch(view)

      approved_events =
        mission.mission_id
        |> Storage.list_backfill_lifecycle_events(
          organization_id: org.organization_id,
          event_type: :backfill_approved
        )
        |> Enum.filter(&(&1.payload["request_group_id"] == "dashboard-comparison-workflow-run"))
        |> Enum.sort_by(& &1.point_id)

      assert Enum.map(approved_events, & &1.point_id) == ["HK.counter", "HK.voltage"]

      assert Enum.all?(
               approved_events,
               &(&1.payload["comparison_review_origin"] == expected_origin)
             )

      assert Enum.all?(
               approved_events,
               &(&1.payload["group_transition_source"] == "dashboard_group_action")
             )

      assert Enum.all?(
               approved_events,
               &(&1.reason == "operator_approved_bulk_correction_authority_review")
             )

      assert has_element?(
               view,
               ~s(#dashboard-historical-workflow-group-start-orchestration[data-historical-workflow-group-start-next-action="start_eligible_items"][data-historical-workflow-group-start-eligible="2"][data-historical-workflow-group-start-expected-jobs="2"][data-historical-workflow-group-start-review-request="#{request_event.dashboard_lifecycle_event_id}"][data-historical-workflow-group-start-review-open-count="2"][data-historical-workflow-group-start-review-placements="placement-counter,placement-voltage"]),
               "2 review findings are attached."
             )

      assert has_element?(
               view,
               ~s(#dashboard-historical-workflow-group-start-orchestration[data-historical-workflow-group-start-review-workflow-kind="bulk_correction_authority_review"][data-historical-workflow-group-start-review-workflow-action="request_comparison_review"][data-historical-workflow-group-start-review-workflow-selection-kind="open_comparison_findings"][data-historical-workflow-group-start-review-workflow-selection-count="2"][data-historical-workflow-group-start-review-primary-data-view="all_revisions"][data-historical-workflow-group-start-review-compare-data-view="canonical"])
             )

      assert has_element?(
               view,
               ~s(#dashboard-historical-workflow-group-start-orchestration[data-historical-workflow-group-start-reason="eligible_group_items"]),
               "Record start transition for 2 eligible items in request group dashboard-comparison-workflow-run"
             )

      view
      |> element("#dashboard-historical-workflow-group-form")
      |> render_submit(%{
        "historical_workflow_group" => %{
          "workflow" => "backfill",
          "request_group_id" => "dashboard-comparison-workflow-run",
          "realm" => "backfill",
          "data_source_id" => "managed_questdb_backfill",
          "source_binding_id" => "backfill_telemetry",
          "stage" => "started",
          "reason" => "operator_started_bulk_correction_authority_review",
          "confirmed" => "confirmed"
        }
      })

      assert_patch(view)

      started_events =
        mission.mission_id
        |> Storage.list_backfill_lifecycle_events(
          organization_id: org.organization_id,
          event_type: :backfill_started
        )
        |> Enum.filter(&(&1.payload["request_group_id"] == "dashboard-comparison-workflow-run"))
        |> Enum.sort_by(& &1.point_id)

      assert Enum.map(started_events, & &1.point_id) == ["HK.counter", "HK.voltage"]

      assert Enum.all?(
               started_events,
               &(&1.payload["comparison_review_origin"] == expected_origin)
             )

      started_event = List.first(started_events)

      assert has_element?(
               view,
               ~s(#dashboard-historical-workflow-latest-action[data-workflow-latest-action="group_stage_transition"][data-workflow-latest-action-status="ok"][data-workflow-latest-action-stage="started"][data-workflow-latest-action-request-group-id="dashboard-comparison-workflow-run"][data-workflow-latest-action-count="2"][data-workflow-latest-action-queued-jobs="2"][data-workflow-latest-action-failed-jobs="0"])
             )

      assert {:ok, job} =
               Cadence.fetch_telemetry_historical_data_workflow_job(started_event.backfill_run_id)

      assert has_element?(
               view,
               ~s(#dashboard-historical-workflow-job-status[data-historical-workflow-job-id="#{job.job_id}"][data-historical-workflow-job-status="queued"][data-historical-workflow-job-comparison-review-request="#{request_event.dashboard_lifecycle_event_id}"][data-historical-workflow-job-comparison-review-placements="placement-counter,placement-voltage"])
             )

      assert has_element?(
               view,
               ~s(#dashboard-historical-workflow-job-review-origin[data-historical-workflow-job-review-origin-request="#{request_event.dashboard_lifecycle_event_id}"][data-historical-workflow-job-review-origin-open-count="2"][data-historical-workflow-job-review-origin-placements="placement-counter,placement-voltage"])
             )

      assert has_element?(
               view,
               ~s(#dashboard-historical-workflow-job-review-origin[data-historical-workflow-job-review-origin-workflow-kind="bulk_correction_authority_review"][data-historical-workflow-job-review-origin-workflow-action="request_comparison_review"][data-historical-workflow-job-review-origin-workflow-selection-kind="open_comparison_findings"][data-historical-workflow-job-review-origin-workflow-selection-count="2"][data-historical-workflow-job-review-origin-primary-data-view="all_revisions"][data-historical-workflow-job-review-origin-compare-data-view="canonical"])
             )

      assert has_element?(
               view,
               ~s([data-historical-workflow-job-review-origin-link="#{request_event.dashboard_lifecycle_event_id}"][data-historical-workflow-job-review-origin-href*="activity_filter=open_comparison_reviews"][data-historical-workflow-job-review-origin-href*="activity_event=#{request_event.dashboard_lifecycle_event_id}"]),
               "Open review"
             )

      assert has_element?(
               view,
               ~s([data-historical-workflow-job-review-origin-placement="placement-counter"][data-historical-workflow-job-review-origin-placement-href*="selected_placement=placement-counter"]),
               "placement-counter"
             )
    end

    test "operator view resolves the published document while edit mode opens the draft" do
      {conn, org, mission} = signed_in_org_and_mission()

      %Document{} =
        dashboard = TestFixtures.persist_dashboard_document!(mission, name: "Published Power")

      assert {:ok, %Cadence.Dashboards.Version{}} =
               Cadence.Dashboards.publish_document(
                 org.organization_id,
                 mission.mission_id,
                 dashboard.dashboard_id,
                 1,
                 expected_version: 1
               )

      assert {:ok, %Document{} = _draft} =
               Cadence.Dashboards.update_document(
                 org.organization_id,
                 mission.mission_id,
                 dashboard.dashboard_id,
                 %Document{dashboard | name: "Draft Power"},
                 expected_version: 1
               )

      {:ok, view, _html} = live(conn, show_path(mission, dashboard))
      render_dashboard_async(view)

      assert has_element?(
               view,
               ~s(#ops-dashboard-show-page[data-dashboard-document-mode="published"])
             )

      assert has_element?(
               view,
               ~s(#ops-dashboard-show-page[data-dashboard-publication-state="draft_ahead"][data-dashboard-publishable-version="2"][data-dashboard-draft-ahead="true"][data-dashboard-publish-available="true"])
             )

      assert has_element?(
               view,
               ~s(#dashboard-menu button[data-dashboard-lifecycle-action="publish"][data-dashboard-action-available="true"])
             )

      refute has_element?(
               view,
               ~s(#dashboard-menu button[data-dashboard-lifecycle-action="publish"][disabled])
             )

      assert has_element?(view, "h1", "Published Power")
      refute has_element?(view, "h1", "Draft Power")

      view |> element("#edit-layout-toggle") |> render_click()
      render_dashboard_async(view)

      assert has_element?(
               view,
               ~s(#ops-dashboard-show-page[data-dashboard-document-mode="draft"])
             )

      assert has_element?(view, "h1", "Draft Power")

      view |> element("#edit-layout-toggle") |> render_click()
      render_dashboard_async(view)

      assert has_element?(
               view,
               ~s(#ops-dashboard-show-page[data-dashboard-document-mode="published"])
             )

      assert has_element?(view, "h1", "Published Power")

      view |> element("#edit-layout-toggle") |> render_click()
      view |> element(~s(#dashboard-menu button[phx-click="publish_dashboard"])) |> render_click()
      render_dashboard_async(view)

      assert has_element?(
               view,
               ~s(#ops-dashboard-show-page[data-dashboard-document-mode="published"])
             )

      assert has_element?(
               view,
               ~s(#ops-dashboard-show-page[data-dashboard-publication-state="published_current"][data-dashboard-published-current="true"][data-dashboard-publish-available="false"])
             )

      assert has_element?(
               view,
               ~s(#dashboard-menu button[data-dashboard-lifecycle-action="publish"][data-dashboard-action-available="false"][disabled])
             )

      assert has_element?(view, "h1", "Draft Power")

      assert [%Cadence.Dashboards.DashboardSummary{} = summary] =
               Cadence.Dashboards.list_dashboard_summaries(
                 org.organization_id,
                 mission.mission_id
               )

      assert summary.latest_version == 2
      assert summary.draft_version == nil
      assert summary.published_version == 2
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
               Cadence.persist_scheduled_contact(org.organization_id, scheduled_contact)

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

      contact_markers = chart_event_markers(html, trend_widget.widget_id)

      assert [%{"contact_id" => "dashboard-runtime-scope-contact", "target" => "contact"}] =
               Enum.filter(contact_markers, &(&1["marker_type"] == "contact_interval"))
    end

    test "contact-scoped telemetry no-data exposes scope filter diagnostics" do
      {conn, org, mission} = signed_in_org_and_mission()
      spacecraft = TestFixtures.persist_spacecraft!(mission, display_name: "SC Alpha")
      binding_set = persist_binding_set!(org, mission)

      scheduled_contact =
        ScheduledContact.new(%{
          scheduled_contact_id: "dashboard-runtime-empty-contact",
          mission_id: mission.mission_id,
          source_endpoint_refs: ["source-endpoint-alpha"],
          paths: contact_paths("source-endpoint-alpha"),
          starts_at: DateTime.from_unix!(1_700_000_080, :second),
          ends_at: DateTime.from_unix!(1_700_000_220, :second)
        })

      assert {:ok, _scheduled_contact} =
               Cadence.persist_scheduled_contact(org.organization_id, scheduled_contact)

      ingest!(mission, binding_set, spacecraft.spacecraft_id, 15, 1_700_000_100,
        source_endpoint_id: "source-endpoint-beta"
      )

      dashboard =
        TestFixtures.persist_dashboard_document!(mission,
          name: "Scoped Empty Power",
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
          ~p"/missions/#{mission.mission_id}/ops/dashboards/#{dashboard.dashboard_id}?#{%{scope_kind: "contact", scope_id: scheduled_contact.scheduled_contact_id}}"
        )

      render_dashboard_async(view)

      widget_selector = "#widget-#{trend_item.placement_id}"

      assert has_element?(
               view,
               ~s(#{widget_selector}[data-widget-source-data-state="no_data"][data-widget-source-empty-reason="contact_scope_no_data"])
             )

      assert has_element?(
               view,
               ~s(#{widget_selector}[data-widget-source-scope-kinds="spacecraft"][data-widget-source-contact-ids="dashboard-runtime-empty-contact"])
             )

      assert has_element?(
               view,
               ~s(#{widget_selector}[data-widget-source-source-endpoint-ids="source-endpoint-alpha"])
             )

      assert has_element?(
               view,
               ~s(#ops-dashboard-show-page[data-dashboard-health-state="stale"][data-dashboard-health-stale-placements="#{trend_item.placement_id}"][data-dashboard-health-affected-placements="#{trend_item.placement_id}"])
             )

      assert has_element?(
               view,
               ~s(#dashboard-health-rollup[data-dashboard-health-state="stale"][data-dashboard-health-affected="1"][data-dashboard-health-stale-placements="#{trend_item.placement_id}"])
             )

      assert has_element?(
               view,
               ~s(#dashboard-health-rollup [data-dashboard-health-item="#{trend_item.placement_id}"][href="#widget-#{trend_item.placement_id}"][data-dashboard-health-item-source="unknown"])
             )

      assert has_element?(
               view,
               ~s(#{widget_selector} button[data-widget-source-badge="unknown"][data-widget-source-badge-inventory-action="source_inventory"][data-widget-source-badge-inventory-href*="/ops/data-sources"][data-widget-source-badge-inventory-href*="contact_id=dashboard-runtime-empty-contact"][data-widget-source-badge-inventory-href*="source_endpoint_id=source-endpoint-alpha"])
             )

      assert has_element?(
               view,
               ~s(#{widget_selector} a[data-widget-source-badge-inventory-open="unknown"][href*="/ops/data-sources"][href*="contact_id=dashboard-runtime-empty-contact"][href*="source_endpoint_id=source-endpoint-alpha"])
             )

      assert has_element?(
               view,
               ~s(#{widget_selector} [data-widget-query-diagnostics][data-widget-query-source-state="unknown"][data-widget-query-data-view="canonical"][data-widget-query-time-modes="live"][data-widget-query-contact-ids="dashboard-runtime-empty-contact"][data-widget-query-source-endpoint-ids="source-endpoint-alpha"])
             )

      assert has_element?(
               view,
               ~s(#{widget_selector} [data-widget-query-value="contacts"]),
               "dashboard-runtime-empty-contact"
             )

      view
      |> element(~s(#{widget_selector} [data-widget-query-evidence-open]))
      |> render_click()

      query_evidence_path = assert_patch(view)
      assert query_evidence_path =~ "panel=evidence"
      assert query_evidence_path =~ "selected_evidence_kind=query"
      assert query_evidence_path =~ "selected_widget_title=Counter+Trend"
      assert query_evidence_path =~ "selected_requested_data_view=canonical"
      assert query_evidence_path =~ "selected_source_evidence_state=unknown"
      assert query_evidence_path =~ "selected_contact_id=dashboard-runtime-empty-contact"
      assert query_evidence_path =~ "selected_source_endpoint_id=source-endpoint-alpha"

      assert has_element?(
               view,
               ~s(#dashboard-evidence-inspector[data-evidence-kind="query"][data-evidence-status="unknown"][data-evidence-subject="Counter Trend"])
             )

      assert has_element?(
               view,
               ~s(#dashboard-evidence-inspector [data-evidence-subject-field="Widget"]),
               "Counter Trend"
             )

      assert has_element?(
               view,
               ~s(#dashboard-evidence-inspector [data-evidence-detail="Contact"]),
               "dashboard-runtime-empty-contact"
             )

      assert has_element?(
               view,
               ~s(#dashboard-evidence-copy-link[data-clipboard-text*="panel=evidence"][data-clipboard-text*="selected_evidence_kind=query"][data-clipboard-text*="selected_widget_title=Counter+Trend"][data-clipboard-text*="selected_contact_id=dashboard-runtime-empty-contact"])
             )

      assert has_element?(
               view,
               ~s(#dashboard-evidence-source-inventory[href*="contact_id=dashboard-runtime-empty-contact"][href*="source_endpoint_id=source-endpoint-alpha"][href*="source_dashboard_id=#{dashboard.dashboard_id}"])
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
               ~s(#dashboard-evidence-inspector [data-evidence-detail="Contact"]),
               "dashboard-runtime-empty-contact"
             )

      assert has_element?(
               view,
               ~s(#dashboard-evidence-inspector [data-evidence-detail="Source endpoint"]),
               "source-endpoint-alpha"
             )

      assert render(view) =~
               "Widget source status is unknown; source health or watermark evidence could not prove freshness for this value."

      assert has_element?(
               view,
               ~s(#dashboard-evidence-source-health[href*="contact_id=dashboard-runtime-empty-contact"][href*="source_endpoint_id=source-endpoint-alpha"][href*="source_dashboard_id=#{dashboard.dashboard_id}"])
             )

      assert has_element?(
               view,
               ~s(#dashboard-evidence-source-inventory[href*="contact_id=dashboard-runtime-empty-contact"][href*="source_endpoint_id=source-endpoint-alpha"][href*="source_dashboard_id=#{dashboard.dashboard_id}"])
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
               Cadence.persist_source_endpoint(org.organization_id, source_endpoint)

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

    test "generic scope URL is validated against the current mission" do
      {conn, org, mission} = signed_in_org_and_mission()
      other_mission = TestFixtures.persist_mission!(org, display_name: "Other Mission")
      spacecraft = TestFixtures.persist_spacecraft!(mission, display_name: "SC Alpha")

      other_contact =
        ScheduledContact.new(%{
          scheduled_contact_id: "other-mission-contact",
          mission_id: other_mission.mission_id,
          source_endpoint_refs: ["source-endpoint-beta"],
          paths: contact_paths("source-endpoint-beta"),
          starts_at: DateTime.from_unix!(1_700_000_080, :second),
          ends_at: DateTime.from_unix!(1_700_000_220, :second)
        })

      assert {:ok, _scheduled_contact} =
               Cadence.persist_scheduled_contact(org.organization_id, other_contact)

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

      {:ok, invalid_mission_scope_view, _html} =
        live(
          conn,
          ~p"/missions/#{mission.mission_id}/ops/dashboards/#{dashboard.dashboard_id}?#{%{scope_kind: "mission", scope_id: other_mission.mission_id, spacecraft_id: spacecraft.spacecraft_id}}"
        )

      render_dashboard_async(invalid_mission_scope_view)

      refute has_element?(
               invalid_mission_scope_view,
               ~s(#ops-dashboard-show-page[data-dashboard-scope-kind="mission"])
             )

      refute has_element?(
               invalid_mission_scope_view,
               ~s(#ops-dashboard-show-page[data-dashboard-scope-id="#{other_mission.mission_id}"])
             )

      refute has_element?(
               invalid_mission_scope_view,
               ~s(#ops-dashboard-show-page[data-dashboard-scope-kind="spacecraft"][data-dashboard-scope-id="#{spacecraft.spacecraft_id}"])
             )

      {:ok, cross_mission_contact_view, _html} =
        live(
          conn,
          ~p"/missions/#{mission.mission_id}/ops/dashboards/#{dashboard.dashboard_id}?#{%{scope_kind: "contact", scope_id: other_contact.scheduled_contact_id}}"
        )

      render_dashboard_async(cross_mission_contact_view)

      refute has_element?(
               cross_mission_contact_view,
               ~s(#ops-dashboard-show-page[data-dashboard-scope-kind="contact"])
             )

      refute has_element?(
               cross_mission_contact_view,
               ~s(#ops-dashboard-show-page[data-dashboard-scope-id="#{other_contact.scheduled_contact_id}"])
             )
    end

    test "shows version history and restores a historical version as the latest draft" do
      {conn, user, org, mission} = signed_in_user_org_and_mission()

      %Document{} =
        dashboard = TestFixtures.persist_dashboard_document!(mission, name: "Original Power")

      assert {:ok, %Document{} = updated} =
               Cadence.Dashboards.update_document(
                 org.organization_id,
                 mission.mission_id,
                 dashboard.dashboard_id,
                 %Document{dashboard | name: "Published Power"},
                 expected_version: 1
               )

      assert {:ok, %Cadence.Dashboards.Version{}} =
               Cadence.Dashboards.publish_document(
                 org.organization_id,
                 mission.mission_id,
                 dashboard.dashboard_id,
                 Document.version(updated),
                 expected_version: Document.version(updated)
               )

      {:ok, view, _html} = live(conn, show_path(mission, dashboard))
      render_dashboard_async(view)

      assert has_element?(
               view,
               ~s(#ops-dashboard-show-page[data-dashboard-document-mode="published"])
             )

      assert has_element?(
               view,
               ~s(#ops-dashboard-show-page[data-dashboard-publication-state="published_current"][data-dashboard-published-current="true"])
             )

      assert has_element?(view, "h1", "Published Power")

      view |> element("#dashboard-versions-button") |> render_click()

      assert has_element?(view, "#dashboard-versions-panel")
      assert has_element?(view, ~s(#dashboard-version-2 [data-version-pointer="published"]))
      assert has_element?(view, ~s(#dashboard-version-2 [data-version-pointer="latest"]))
      refute has_element?(view, ~s(#dashboard-version-2 [data-version-pointer="draft"]))

      assert has_element?(
               view,
               ~s(#dashboard-version-2[data-version-publish-available="false"][data-version-publish-reason="already_published"][data-version-restore-available="false"][data-version-restore-reason="already_latest"])
             )

      assert has_element?(
               view,
               ~s(#dashboard-version-1[data-version-publish-available="true"][data-version-publish-reason="available"][data-version-restore-available="true"][data-version-restore-reason="available"])
             )

      assert has_element?(view, ~s(#publish-version-2[disabled]))
      assert has_element?(view, ~s(#restore-version-2[disabled]))
      refute has_element?(view, ~s(#publish-version-1[disabled]))
      refute has_element?(view, ~s(#restore-version-1[disabled]))
      assert has_element?(view, "#dashboard-version-1", "draft save")
      assert has_element?(view, "#dashboard-activity-list")
      assert has_element?(view, ~s([data-lifecycle-event-type="published"]))

      assert has_element?(
               view,
               ~s([data-lifecycle-event-type="published"] [data-activity-field="Published"]),
               "- -> v2"
             )

      view |> element("#restore-version-1") |> render_click()

      assert has_element?(
               view,
               ~s(#ops-dashboard-show-page[data-dashboard-document-mode="draft"])
             )

      assert has_element?(
               view,
               ~s(#ops-dashboard-show-page[data-dashboard-publication-state="draft_ahead"][data-dashboard-publishable-version="3"][data-dashboard-draft-ahead="true"])
             )

      assert has_element?(view, "#edit-paused-note")
      refute has_element?(view, "#dashboard-versions-panel")
      assert has_element?(view, "h1", "Original Power")

      view |> element("#dashboard-versions-button") |> render_click()

      assert has_element?(view, ~s([data-lifecycle-event-type="reverted"]))

      assert has_element?(
               view,
               ~s([data-lifecycle-event-type="reverted"][data-lifecycle-source-version="1"][data-lifecycle-reverted-version="3"])
             )

      assert has_element?(
               view,
               ~s([data-lifecycle-event-type="reverted"] [data-activity-field="Source"]),
               "v1"
             )

      assert has_element?(
               view,
               ~s([data-lifecycle-event-type="reverted"] [data-activity-field="New draft"]),
               "v3"
             )

      assert {:ok, %Document{} = latest_document} =
               Cadence.Dashboards.fetch_document(
                 org.organization_id,
                 mission.mission_id,
                 dashboard.dashboard_id
               )

      assert latest_document.name == "Original Power"
      assert Document.version(latest_document) == 3
      version = fetch_dashboard_version!(org, mission, dashboard, 3)
      assert version.change_summary == "Restored version 1 as draft"
      assert version.created_by == user.user_id

      assert [%Cadence.Dashboards.DashboardSummary{} = summary] =
               Cadence.Dashboards.list_dashboard_summaries(
                 org.organization_id,
                 mission.mission_id
               )

      assert summary.latest_version == 3
      assert summary.draft_version == 3
      assert summary.published_version == 2
    end

    test "runs the dashboard lifecycle across create edit publish conflict revert archive restore and audit surfaces" do
      enable_dashboard_engine_inline_resolves!()

      {conn, user, org, mission} = signed_in_user_org_and_mission()
      binding_set = persist_binding_set!(org, mission)
      activate_binding_set!(org, mission, binding_set)

      {:ok, new_view, _html} = live(conn, ~p"/missions/#{mission.mission_id}/ops/dashboards/new")

      new_view
      |> form("#dashboard-form", dashboard: %{name: "Lifecycle Console", description: "Ops"})
      |> render_submit()

      assert [%Cadence.Dashboards.DashboardSummary{} = created_summary] =
               Cadence.Dashboards.list_dashboard_summaries(
                 org.organization_id,
                 mission.mission_id
               )

      {dashboard_path, _flash} = assert_redirect(new_view)
      assert dashboard_path == show_path(mission, created_summary)

      dashboard = fetch_dashboard_document!(org, mission, created_summary)
      assert dashboard.name == "Lifecycle Console"
      assert Document.version(dashboard) == 1
      assert dashboard.placements == []

      {:ok, view, _html} = live(conn, dashboard_path)
      render_dashboard_async(view)

      assert has_element?(
               view,
               ~s(#ops-dashboard-show-page[data-dashboard-publication-state="unpublished"][data-dashboard-publishable-version="1"])
             )

      view |> element("#add-widget-button") |> render_click()
      view |> element(~s(button[phx-value-point-id="HK.counter"])) |> render_click()

      view
      |> form("#widget-form", widget: %{type: "value_tile", title: "Counter", mode: "context"})
      |> render_submit()

      render_dashboard_async(view)

      edited = fetch_dashboard_document!(org, mission, created_summary)
      assert Document.version(edited) == 2
      assert [%{widget_def: %{title: "Counter"}}] = edited.placements

      assert has_element?(
               view,
               ~s(#ops-dashboard-show-page[data-dashboard-publication-state="unpublished"][data-dashboard-publishable-version="2"])
             )

      view |> element(~s(#dashboard-menu button[phx-click="publish_dashboard"])) |> render_click()
      render_dashboard_async(view)

      assert has_element?(
               view,
               ~s(#ops-dashboard-show-page[data-dashboard-publication-state="published_current"][data-dashboard-published-current="true"][data-dashboard-publish-available="false"])
             )

      assert [%Cadence.Dashboards.DashboardSummary{} = published_summary] =
               Cadence.Dashboards.list_dashboard_summaries(
                 org.organization_id,
                 mission.mission_id
               )

      assert published_summary.latest_version == 2
      assert published_summary.draft_version == nil
      assert published_summary.published_version == 2

      assert {:ok, %Document{} = externally_updated} =
               Cadence.Dashboards.update_document(
                 org.organization_id,
                 mission.mission_id,
                 created_summary.dashboard_id,
                 %Document{edited | name: "Lifecycle Console Updated"},
                 expected_version: 2,
                 created_by: "other-operator",
                 change_summary: "External edit"
               )

      assert Document.version(externally_updated) == 3

      view |> element("#add-widget-button") |> render_click()
      view |> element(~s(button[phx-value-point-id="HK.counter"])) |> render_click()

      html =
        view
        |> form("#widget-form",
          widget: %{type: "value_tile", title: "Late Counter", mode: "context"}
        )
        |> render_submit()

      assert html =~ "Dashboard changed in another session"
      assert has_element?(view, "h1", "Lifecycle Console Updated")

      conflicted = fetch_dashboard_document!(org, mission, created_summary)
      assert Document.version(conflicted) == 3
      assert conflicted.name == "Lifecycle Console Updated"
      assert [%{widget_def: %{title: "Counter"}}] = conflicted.placements

      view |> element("#dashboard-versions-button") |> render_click()

      assert has_element?(
               view,
               ~s(#dashboard-version-2[data-version-publish-available="false"][data-version-publish-reason="already_published"])
             )

      assert has_element?(
               view,
               ~s(#dashboard-version-3[data-version-restore-available="false"][data-version-restore-reason="already_latest"])
             )

      assert has_element?(
               view,
               ~s([data-lifecycle-event-type="published"] [data-activity-field="Published"]),
               "- -> v2"
             )

      view |> element("#restore-version-1") |> render_click()

      assert has_element?(
               view,
               ~s(#ops-dashboard-show-page[data-dashboard-document-mode="draft"][data-dashboard-publication-state="draft_ahead"][data-dashboard-publishable-version="4"])
             )

      restored_draft = fetch_dashboard_document!(org, mission, created_summary)
      assert Document.version(restored_draft) == 4
      assert restored_draft.name == "Lifecycle Console"
      assert restored_draft.placements == []

      view |> element("#dashboard-versions-button") |> render_click()

      assert has_element?(
               view,
               ~s([data-lifecycle-event-type="reverted"][data-lifecycle-source-version="1"][data-lifecycle-reverted-version="4"])
             )

      view
      |> element(~s(#dashboard-menu button[phx-click="archive_dashboard"]))
      |> render_click()

      assert %{"info" => "Dashboard archived."} =
               assert_redirect(view, ~p"/missions/#{mission.mission_id}/ops/dashboards")

      assert [] =
               Cadence.Dashboards.list_dashboard_summaries(
                 org.organization_id,
                 mission.mission_id
               )

      assert [%Cadence.Dashboards.DashboardSummary{} = archived_summary] =
               Cadence.Dashboards.list_archived_dashboard_summaries(
                 org.organization_id,
                 mission.mission_id
               )

      assert archived_summary.lifecycle_state == "archived"
      assert archived_summary.latest_version == 4

      {:ok, list_view, _html} = live(conn, ~p"/missions/#{mission.mission_id}/ops/dashboards")

      assert has_element?(
               list_view,
               ~s(#archived-dashboard-#{created_summary.dashboard_id}[data-dashboard-publication-state="archived"][data-dashboard-restore-available="true"])
             )

      list_view
      |> element("#restore-dashboard-#{created_summary.dashboard_id}")
      |> render_click()

      assert has_element?(
               list_view,
               ~s(#active-dashboard-#{created_summary.dashboard_id}[data-dashboard-publication-state="draft_ahead"][data-dashboard-archive-available="true"][data-dashboard-restore-available="false"])
             )

      assert [
               %Cadence.Dashboards.LifecycleEvent{event_type: :published, dashboard_version: 2},
               %Cadence.Dashboards.LifecycleEvent{
                 event_type: :reverted,
                 dashboard_version: 4
               },
               %Cadence.Dashboards.LifecycleEvent{event_type: :archived, dashboard_version: 4},
               %Cadence.Dashboards.LifecycleEvent{event_type: :restored, dashboard_version: 4}
             ] =
               Cadence.Dashboards.list_lifecycle_events(
                 org.organization_id,
                 mission.mission_id,
                 created_summary.dashboard_id
               )

      {:ok, restored_view, _html} = live(conn, dashboard_path)
      render_dashboard_async(restored_view)

      assert has_element?(
               restored_view,
               ~s(#ops-dashboard-show-page[data-dashboard-publication-state="draft_ahead"][data-dashboard-publishable-version="4"][data-dashboard-draft-ahead="true"])
             )

      restored_view |> element("#dashboard-versions-button") |> render_click()

      assert has_element?(restored_view, ~s([data-lifecycle-event-type="published"]))
      assert has_element?(restored_view, ~s([data-lifecycle-event-type="reverted"]))
      assert has_element?(restored_view, ~s([data-lifecycle-event-type="archived"]))
      assert has_element?(restored_view, ~s([data-lifecycle-event-type="restored"]))

      assert has_element?(
               restored_view,
               ~s([data-lifecycle-event-type="restored"] [data-activity-field="Actor"]),
               user.user_id
             )
    end

    test "publishes a historical version from the versions panel without discarding the newer draft" do
      {conn, user, org, mission} = signed_in_user_org_and_mission()

      %Document{} =
        dashboard = TestFixtures.persist_dashboard_document!(mission, name: "Original Power")

      assert {:ok, %Document{} = updated} =
               Cadence.Dashboards.update_document(
                 org.organization_id,
                 mission.mission_id,
                 dashboard.dashboard_id,
                 %Document{dashboard | name: "Published Power"},
                 expected_version: 1
               )

      assert {:ok, %Cadence.Dashboards.Version{}} =
               Cadence.Dashboards.publish_document(
                 org.organization_id,
                 mission.mission_id,
                 dashboard.dashboard_id,
                 Document.version(updated),
                 expected_version: Document.version(updated)
               )

      {:ok, view, _html} = live(conn, show_path(mission, dashboard))
      render_dashboard_async(view)

      view |> element("#dashboard-versions-button") |> render_click()

      view |> element("#publish-version-1") |> render_click()
      render_dashboard_async(view)

      assert has_element?(
               view,
               ~s(#ops-dashboard-show-page[data-dashboard-document-mode="published"][data-dashboard-publication-state="draft_ahead"][data-dashboard-publishable-version="2"])
             )

      assert has_element?(view, "h1", "Original Power")

      assert [%Cadence.Dashboards.DashboardSummary{} = summary] =
               Cadence.Dashboards.list_dashboard_summaries(
                 org.organization_id,
                 mission.mission_id
               )

      assert summary.latest_version == 2
      assert summary.draft_version == 2
      assert summary.published_version == 1

      assert %Cadence.Dashboards.LifecycleEvent{} =
               published =
               org.organization_id
               |> Cadence.Dashboards.list_lifecycle_events(
                 mission.mission_id,
                 dashboard.dashboard_id
               )
               |> List.last()

      assert published.event_type == :published
      assert published.dashboard_version == 1
      assert published.actor_id == user.user_id
    end

    test "blocks publish and opens validation details when the saved draft is invalid" do
      {conn, org, mission} = signed_in_org_and_mission()
      dashboard = TestFixtures.persist_dashboard_document!(mission, name: "Invalid Publish")

      replace_dashboard_row_document!(org, mission, with_invalid_grid(dashboard))

      {:ok, view, _html} = live(conn, show_path(mission, dashboard))
      render_dashboard_async(view)

      assert has_element?(
               view,
               ~s(#ops-dashboard-show-page[data-dashboard-publication-state="unpublished"][data-dashboard-publishable-version="1"][data-dashboard-publish-available="true"])
             )

      view |> element(~s(#dashboard-menu button[phx-click="publish_dashboard"])) |> render_click()

      assert has_element?(view, "#dashboard-versions-panel")

      assert has_element?(
               view,
               ~s(#dashboard-publish-validation[data-publish-validation-status="blocked"])
             )

      assert has_element?(
               view,
               ~s([data-publish-validation-severity="error"][data-publish-validation-code="invalid_grid"])
             )

      assert has_element?(view, ~s([data-publish-validation-detail="field"]), "columns")

      assert [%Cadence.Dashboards.DashboardSummary{} = summary] =
               Cadence.Dashboards.list_dashboard_summaries(
                 org.organization_id,
                 mission.mission_id
               )

      assert summary.latest_version == 1
      assert summary.draft_version == 1
      assert summary.published_version == nil

      assert [] =
               Cadence.Dashboards.list_lifecycle_events(
                 org.organization_id,
                 mission.mission_id,
                 dashboard.dashboard_id
               )
    end

    test "blocks publish when runtime defaults are not valid engine context" do
      {conn, user, org, mission} = signed_in_user_org_and_mission()
      dashboard = TestFixtures.persist_dashboard_document!(mission, name: "Invalid Defaults")

      replace_dashboard_row_document!(org, mission, with_invalid_runtime_defaults(dashboard))

      {:ok, view, _html} = live(conn, show_path(mission, dashboard))
      render_dashboard_async(view)

      assert has_element?(
               view,
               ~s(#dashboard-publish-readiness-summary[data-dashboard-publish-readiness-status="blocked"][data-dashboard-publish-readiness-issue-count="2"]),
               "Publish blocked"
             )

      view |> element(~s(#dashboard-menu button[phx-click="publish_dashboard"])) |> render_click()

      assert has_element?(view, "#dashboard-versions-panel")

      assert has_element?(
               view,
               ~s(#dashboard-publish-validation[data-publish-validation-status="blocked"])
             )

      assert has_element?(
               view,
               ~s(#dashboard-publish-validation-freshness[data-publish-validation-freshness-state="current"][data-publish-validation-draft-version="1"][data-publish-validation-summary-draft-version="1"])
             )

      assert has_element?(
               view,
               ~s([data-publish-validation-severity="error"][data-publish-validation-code="invalid_runtime_default_context"])
             )

      assert has_element?(view, ~s([data-publish-validation-detail="Context"]), "time")
      assert has_element?(view, ~s([data-publish-validation-detail="Context"]), "data")

      assert has_element?(
               view,
               ~s([data-publish-validation-detail="Errors"]),
               "unsupported_time_mode"
             )

      assert has_element?(
               view,
               ~s([data-publish-validation-detail="Errors"]),
               "unsupported_data_realm"
             )

      view |> element("#refresh-publish-readiness") |> render_click()

      assert has_element?(
               view,
               ~s(#dashboard-publish-validation[data-publish-validation-status="blocked"])
             )

      assert has_element?(
               view,
               ~s([data-publish-validation-severity="error"][data-publish-validation-code="invalid_runtime_default_context"])
             )

      assert [%Cadence.Dashboards.DashboardSummary{} = summary] =
               Cadence.Dashboards.list_dashboard_summaries(
                 org.organization_id,
                 mission.mission_id
               )

      assert summary.latest_version == 1
      assert summary.draft_version == 1
      assert summary.published_version == nil

      assert [%Cadence.Dashboards.LifecycleEvent{} = event] =
               Cadence.Dashboards.list_lifecycle_events(
                 org.organization_id,
                 mission.mission_id,
                 dashboard.dashboard_id
               )

      assert event.event_type == :publish_readiness_checked
      assert event.actor_id == user.user_id
      assert event.dashboard_version == 1
      assert event.previous_lifecycle_state == "active"
      assert event.current_lifecycle_state == "active"
      assert event.payload["schema"] == "dashboard_publish_readiness_check.v1"
      assert event.payload["source"] == "dashboard_publish_readiness"
      assert event.payload["dashboard_name"] == "Invalid Defaults"
      assert event.payload["draft_version"] == 1
      assert event.payload["result"] == "still_blocked"
      assert event.payload["valid"] == false
      assert event.payload["error_count"] == 2
      assert event.payload["warning_count"] == 0
      assert event.payload["issue_count"] == 2

      assert event.payload["issue_codes"] == [
               "invalid_runtime_default_context",
               "invalid_runtime_default_context"
             ]

      assert event.payload["source_warning_codes"] == []

      assert [
               %{
                 "id" => "error:invalid_runtime_default_context:time:unsupported_time_mode",
                 "severity" => "error",
                 "code" => "invalid_runtime_default_context",
                 "message" => "Dashboard runtime defaults include unsupported time context.",
                 "action" => %{
                   "issue_id" =>
                     "error:invalid_runtime_default_context:time:unsupported_time_mode",
                   "label" => "Update runtime defaults",
                   "target" => "dashboard_context",
                   "message" =>
                     "Open dashboard context controls and choose a supported mission, scope, data realm, and source binding before publishing.",
                   "params" => %{
                     "selected_publish_issue" =>
                       "error:invalid_runtime_default_context:time:unsupported_time_mode"
                   }
                 }
               },
               %{
                 "id" => "error:invalid_runtime_default_context:data:unsupported_data_realm",
                 "severity" => "error",
                 "code" => "invalid_runtime_default_context",
                 "message" => "Dashboard runtime defaults include unsupported data context.",
                 "action" => %{
                   "issue_id" =>
                     "error:invalid_runtime_default_context:data:unsupported_data_realm",
                   "label" => "Update runtime defaults",
                   "target" => "dashboard_context",
                   "message" =>
                     "Open dashboard context controls and choose a supported mission, scope, data realm, and source binding before publishing.",
                   "params" => %{
                     "selected_publish_issue" =>
                       "error:invalid_runtime_default_context:data:unsupported_data_realm"
                   }
                 }
               }
             ] = event.payload["issue_summaries"]

      assert [
               %{
                 "issue_id" => "error:invalid_runtime_default_context:time:unsupported_time_mode",
                 "label" => "Update runtime defaults",
                 "target" => "dashboard_context",
                 "message" =>
                   "Open dashboard context controls and choose a supported mission, scope, data realm, and source binding before publishing.",
                 "params" => %{
                   "selected_publish_issue" =>
                     "error:invalid_runtime_default_context:time:unsupported_time_mode"
                 }
               },
               %{
                 "issue_id" =>
                   "error:invalid_runtime_default_context:data:unsupported_data_realm",
                 "label" => "Update runtime defaults",
                 "target" => "dashboard_context",
                 "message" =>
                   "Open dashboard context controls and choose a supported mission, scope, data realm, and source binding before publishing.",
                 "params" => %{
                   "selected_publish_issue" =>
                     "error:invalid_runtime_default_context:data:unsupported_data_realm"
                 }
               }
             ] = event.payload["remediation_targets"]

      view
      |> element("#dashboard-activity-select-#{event.dashboard_lifecycle_event_id}")
      |> render_click()

      assert has_element?(
               view,
               ~s(#dashboard-selected-activity-event[data-dashboard-selected-activity-event="#{event.dashboard_lifecycle_event_id}"][data-dashboard-selected-activity-event-type="publish_readiness_checked"])
             )

      assert has_element?(
               view,
               ~s(#dashboard-selected-activity-refresh-readiness[data-dashboard-selected-activity-refresh-readiness="#{event.dashboard_lifecycle_event_id}"][phx-click="refresh_publish_readiness"])
             )

      view |> element("#dashboard-selected-activity-refresh-readiness") |> render_click()

      assert [^event, %Cadence.Dashboards.LifecycleEvent{} = followup_event] =
               Cadence.Dashboards.list_lifecycle_events(
                 org.organization_id,
                 mission.mission_id,
                 dashboard.dashboard_id
               )

      assert followup_event.event_type == :publish_readiness_checked
      assert followup_event.actor_id == user.user_id
      assert followup_event.payload["result"] == "still_blocked"
      assert followup_event.payload["issue_count"] == 2

      assert has_element?(
               view,
               "#dashboard-activity-select-#{followup_event.dashboard_lifecycle_event_id}"
             )
    end

    test "allows warning-only draft publish and shows warnings in the publish check" do
      {conn, user, org, mission} = signed_in_user_org_and_mission()

      dashboard =
        TestFixtures.persist_dashboard_document!(mission,
          name: "Legacy Warning",
          widgets: [value_tile("HK.counter")]
        )

      assert {:ok, %Document{} = warning_document} =
               Cadence.Dashboards.update_document(
                 org.organization_id,
                 mission.mission_id,
                 dashboard.dashboard_id,
                 with_unknown_widget(dashboard),
                 expected_version: Document.version(dashboard),
                 created_by: user.user_id,
                 change_summary: "Imported legacy widget"
               )

      {:ok, view, _html} = live(conn, show_path(mission, dashboard))
      render_dashboard_async(view)

      view |> element("#dashboard-versions-button") |> render_click()

      assert has_element?(
               view,
               ~s(#dashboard-publish-validation[data-publish-validation-status="warnings"])
             )

      assert has_element?(
               view,
               ~s([data-publish-validation-severity="warning"][data-publish-validation-code="unknown_widget_type"])
             )

      view |> element(~s(#dashboard-menu button[phx-click="publish_dashboard"])) |> render_click()
      render_dashboard_async(view)

      assert has_element?(
               view,
               ~s(#ops-dashboard-show-page[data-dashboard-document-mode="published"])
             )

      assert [%Cadence.Dashboards.DashboardSummary{} = summary] =
               Cadence.Dashboards.list_dashboard_summaries(
                 org.organization_id,
                 mission.mission_id
               )

      assert summary.latest_version == Document.version(warning_document)
      assert summary.draft_version == nil
      assert summary.published_version == Document.version(warning_document)

      assert [%Cadence.Dashboards.LifecycleEvent{} = event] =
               Cadence.Dashboards.list_lifecycle_events(
                 org.organization_id,
                 mission.mission_id,
                 dashboard.dashboard_id
               )

      assert event.event_type == :published
      assert event.dashboard_version == Document.version(warning_document)
      assert event.actor_id == user.user_id
    end

    test "reloads the latest dashboard when a stale publish conflicts" do
      {conn, org, mission} = signed_in_org_and_mission()
      %Document{} = dashboard = TestFixtures.persist_dashboard_document!(mission, name: "Power")

      {:ok, view, _html} = live(conn, show_path(mission, dashboard))
      render_dashboard_async(view)

      assert {:ok, %Document{} = _updated} =
               Cadence.Dashboards.update_document(
                 org.organization_id,
                 mission.mission_id,
                 dashboard.dashboard_id,
                 %Document{dashboard | name: "Power Updated"},
                 expected_version: Document.version(dashboard)
               )

      html =
        view
        |> element(~s(#dashboard-menu button[phx-click="publish_dashboard"]))
        |> render_click()

      assert html =~ "Dashboard changed in another session"
      assert has_element?(view, "h1", "Power Updated")

      assert [%Cadence.Dashboards.DashboardSummary{} = summary] =
               Cadence.Dashboards.list_dashboard_summaries(
                 org.organization_id,
                 mission.mission_id
               )

      assert summary.latest_version == 2
      assert summary.draft_version == 2
      assert summary.published_version == nil

      assert [] =
               Cadence.Dashboards.list_lifecycle_events(
                 org.organization_id,
                 mission.mission_id,
                 dashboard.dashboard_id
               )
    end

    test "reloads the latest dashboard when a stale archive conflicts" do
      {conn, org, mission} = signed_in_org_and_mission()
      %Document{} = dashboard = TestFixtures.persist_dashboard_document!(mission, name: "Power")

      {:ok, view, _html} = live(conn, show_path(mission, dashboard))
      render_dashboard_async(view)

      assert {:ok, %Document{} = _updated} =
               Cadence.Dashboards.update_document(
                 org.organization_id,
                 mission.mission_id,
                 dashboard.dashboard_id,
                 %Document{dashboard | name: "Power Updated"},
                 expected_version: Document.version(dashboard)
               )

      html =
        view
        |> element(~s(#dashboard-menu button[phx-click="archive_dashboard"]))
        |> render_click()

      assert html =~ "Dashboard changed in another session"
      assert has_element?(view, "h1", "Power Updated")

      assert [%Cadence.Dashboards.DashboardSummary{} = summary] =
               Cadence.Dashboards.list_dashboard_summaries(
                 org.organization_id,
                 mission.mission_id
               )

      assert summary.latest_version == 2
      assert summary.lifecycle_state == "active"

      assert [] =
               Cadence.Dashboards.list_lifecycle_events(
                 org.organization_id,
                 mission.mission_id,
                 dashboard.dashboard_id
               )
    end

    test "telemetry explore route renders point context and matching samples" do
      {conn, org, mission} = signed_in_org_and_mission()
      spacecraft = TestFixtures.persist_spacecraft!(mission, display_name: "SC Alpha")
      binding_set = persist_binding_set!(org, mission)

      source_context =
        persist_dashboard_realm_source!(
          mission,
          :rehearsal,
          "explore-rehearsal-tsdb",
          "explore-rehearsal-binding"
        )

      configure_telemetry_storage_source!(
        :rehearsal,
        source_context.data_source_id,
        source_context.binding_id
      )

      ingest!(mission, binding_set, spacecraft.spacecraft_id, 14, 1_700_000_090)
      ingest!(mission, binding_set, spacecraft.spacecraft_id, 15, 1_700_000_100)

      assert [older_sample, _latest_sample] =
               Cadence.telemetry_history(org.organization_id, mission.mission_id, "HK.counter",
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
              layout: %{x: 0, y: 0, w: 6, h: 3}
            }
          ]
        )

      {:ok, view, _html} =
        live(
          conn,
          ~p"/missions/#{mission.mission_id}/ops/telemetry/explore?#{%{point_id: "HK.counter", spacecraft_id: spacecraft.spacecraft_id, sample_id: older_sample.sample_id, selected_time: DateTime.to_iso8601(older_sample.receipt_time), realm: "rehearsal", data_source_id: source_context.data_source_id, source_binding_id: source_context.binding_id, source_dashboard_id: dashboard.dashboard_id}}"
        )

      assert has_element?(view, "#ops-telemetry-explore-page")

      assert has_element?(
               view,
               ~s(#ops-telemetry-explore-page[data-explore-source-state="matched"][data-explore-selected-sample-state="matched"][data-explore-data-source="#{source_context.data_source_id}"][data-explore-source-binding="#{source_context.binding_id}"])
             )

      assert has_element?(view, ~s([data-explore-point-field="Point"]), "HK.counter")
      assert has_element?(view, ~s([data-explore-context="Spacecraft"]), spacecraft.spacecraft_id)

      assert has_element?(
               view,
               ~s(#telemetry-explore-sample-#{older_sample.sample_id}[data-explore-selected])
             )

      assert has_element?(
               view,
               ~s(#telemetry-explore-selected-sample-card[data-explore-selected-sample-card="#{older_sample.sample_id}"])
             )

      assert has_element?(
               view,
               ~s(#telemetry-explore-selected-sample-card [data-explore-selected-provenance="Evidence"]),
               older_sample.evidence_id
             )

      assert has_element?(
               view,
               ~s(#telemetry-explore-selected-sample-card [data-explore-selected-provenance="Packet"]),
               older_sample.packet_id
             )

      assert has_element?(
               view,
               ~s(#telemetry-explore-selected-sample-card [data-explore-selected-provenance="Definition"]),
               "#{older_sample.packet_definition_id}@#{older_sample.packet_definition_version}"
             )

      assert has_element?(
               view,
               ~s(#telemetry-explore-selected-sample-card [data-explore-selected-provenance="Validity"]),
               "canonical"
             )

      assert has_element?(
               view,
               ~s(#telemetry-explore-sample-#{older_sample.sample_id} [data-explore-sample-evidence="#{older_sample.evidence_id}"])
             )

      assert has_element?(
               view,
               ~s([data-explore-open-sample="#{older_sample.sample_id}"])
             )

      assert has_element?(view, ~s([data-explore-diagnostics="Requested"]), "100")
      assert has_element?(view, ~s([data-explore-diagnostics="Returned"]), "2")
      assert has_element?(view, ~s([data-explore-diagnostics="Physical exists"]), "true")
      assert has_element?(view, ~s([data-explore-source="State"]), "matched")
      assert has_element?(view, ~s([data-explore-source="Logical source"]), "telemetry")

      assert has_element?(
               view,
               ~s(#telemetry-explore-source-card[data-explore-source-state="matched"][data-explore-matched-data-source="#{source_context.data_source_id}"][data-explore-matched-source-binding="#{source_context.binding_id}"])
             )

      assert has_element?(
               view,
               ~s(#telemetry-explore-copy-link[data-clipboard-text*="/ops/telemetry/explore"][data-clipboard-text*="point_id=HK.counter"][data-clipboard-text*="sample_id=#{older_sample.sample_id}"][data-clipboard-text*="data_source_id=#{source_context.data_source_id}"][data-clipboard-text*="source_binding_id=#{source_context.binding_id}"])
             )

      assert has_element?(
               view,
               ~s(#telemetry-explore-investigation-summary[data-investigation-path*="point_id=HK.counter"][data-investigation-fingerprint])
             )

      assert has_element?(view, "#telemetry-explore-back-to-dashboard")

      view |> element("#telemetry-explore-clear-selected-sample") |> render_click()
      cleared_path = assert_patch(view)
      assert cleared_path =~ "point_id=HK.counter"
      assert cleared_path =~ "spacecraft_id=#{URI.encode_www_form(spacecraft.spacecraft_id)}"
      refute cleared_path =~ "sample_id="
      refute cleared_path =~ "selected_time="
      refute cleared_path =~ "source_dashboard_id="
      refute has_element?(view, "#telemetry-explore-selected-sample-card")

      from = "2023-11-14T22:14:45Z"
      to = "2023-11-14T22:15:00Z"

      view
      |> element("#telemetry-explore-filter-form")
      |> render_submit(%{
        "explore" => %{
          "point_id" => "HK.counter",
          "spacecraft_id" => spacecraft.spacecraft_id,
          "time_mode" => "archive",
          "from" => from,
          "to" => to,
          "order" => "asc",
          "limit" => "1",
          "realm" => "rehearsal",
          "logical_source" => "telemetry",
          "data_source_id" => source_context.data_source_id,
          "source_binding_id" => source_context.binding_id,
          "source_dashboard_id" => dashboard.dashboard_id,
          "sample_id" => older_sample.sample_id,
          "selected_time" => DateTime.to_iso8601(older_sample.receipt_time)
        }
      })

      patched_path = assert_patch(view)
      assert patched_path =~ "point_id=HK.counter"
      assert patched_path =~ "time_mode=archive"
      assert patched_path =~ "from=#{URI.encode_www_form(from)}"
      assert patched_path =~ "to=#{URI.encode_www_form(to)}"
      assert patched_path =~ "order=asc"
      assert patched_path =~ "limit=1"
      assert patched_path =~ "realm=rehearsal"
      assert patched_path =~ "data_source_id=#{source_context.data_source_id}"
      assert patched_path =~ "source_binding_id=#{source_context.binding_id}"
      refute patched_path =~ "logical_source=telemetry"

      assert has_element?(view, ~s([data-explore-source="Requested realm"]), "rehearsal")

      assert has_element?(
               view,
               ~s([data-explore-source="Requested source"]),
               source_context.data_source_id
             )

      assert has_element?(
               view,
               ~s([data-explore-source="Requested binding"]),
               source_context.binding_id
             )

      view
      |> element("#telemetry-explore-filter-form")
      |> render_submit(%{
        "explore" => %{
          "point_id" => "HK.counter",
          "spacecraft_id" => spacecraft.spacecraft_id,
          "time_mode" => "latest",
          "order" => "desc",
          "limit" => "100",
          "selection_view" => "all_revisions",
          "validity_state" => "conflict",
          "realm" => "rehearsal",
          "data_source_id" => source_context.data_source_id,
          "source_binding_id" => source_context.binding_id,
          "source_dashboard_id" => dashboard.dashboard_id,
          "sample_id" => older_sample.sample_id,
          "selected_time" => DateTime.to_iso8601(older_sample.receipt_time)
        }
      })

      filtered_path = assert_patch(view)
      assert filtered_path =~ "selection_view=all_revisions"
      assert filtered_path =~ "validity_state=conflict"
      assert filtered_path =~ "realm=rehearsal"
      assert filtered_path =~ "data_source_id=#{source_context.data_source_id}"
      assert filtered_path =~ "source_binding_id=#{source_context.binding_id}"
      refute filtered_path =~ "time_mode=latest"
      refute filtered_path =~ "order=desc"
      refute filtered_path =~ "limit=100"

      assert render(view) =~
               "Physical samples exist, but none matched the current selection view or validity filter."

      assert has_element?(view, ~s([data-explore-diagnostics="Returned"]), "0")
      assert has_element?(view, ~s([data-explore-diagnostics="Physical exists"]), "true")

      assert has_element?(
               view,
               ~s(#ops-telemetry-explore-page[data-explore-source-state="matched"][data-explore-selected-sample-state="missing"])
             )

      assert has_element?(
               view,
               ~s(#telemetry-explore-selected-sample-status[data-explore-selected-sample-state="missing"][data-explore-selected-sample-id="#{older_sample.sample_id}"])
             )
    end

    test "telemetry explore route marks stale source evidence targets as missing" do
      {conn, org, mission} = signed_in_org_and_mission()
      spacecraft = TestFixtures.persist_spacecraft!(mission, display_name: "SC Alpha")
      binding_set = persist_binding_set!(org, mission)

      ingest!(mission, binding_set, spacecraft.spacecraft_id, 14, 1_700_000_090)

      {:ok, view, _html} =
        live(
          conn,
          ~p"/missions/#{mission.mission_id}/ops/telemetry/explore?#{%{point_id: "HK.counter", spacecraft_id: spacecraft.spacecraft_id, realm: "rehearsal", data_source_id: "retired-rehearsal-tsdb", source_binding_id: "retired-rehearsal-binding"}}"
        )

      assert has_element?(
               view,
               ~s(#ops-telemetry-explore-page[data-explore-source-state="missing"][data-explore-data-source="retired-rehearsal-tsdb"][data-explore-source-binding="retired-rehearsal-binding"][data-explore-selected-sample-state="none"])
             )

      assert has_element?(
               view,
               ~s(#telemetry-explore-source-card[data-explore-source-state="missing"][data-explore-data-source="retired-rehearsal-tsdb"][data-explore-source-binding="retired-rehearsal-binding"])
             )

      assert has_element?(view, ~s([data-explore-source="State"]), "missing")
      assert has_element?(view, ~s([data-explore-diagnostics="Returned"]), "0")
    end

    test "renders live values, limit states, fleet health, and grid items" do
      disable_telemetry_storage_runtime_invalidation!()

      {conn, org, mission} = signed_in_org_and_mission()
      spacecraft = TestFixtures.persist_spacecraft!(mission, display_name: "SC Alpha")
      binding_set = persist_binding_set!(org, mission)

      scheduled_contact =
        ScheduledContact.new(%{
          scheduled_contact_id: "dashboard-contact-alpha",
          mission_id: mission.mission_id,
          source_endpoint_refs: ["source-endpoint-alpha"],
          paths: contact_paths("source-endpoint-alpha"),
          starts_at: DateTime.from_unix!(1_700_000_080, :second),
          ends_at: DateTime.from_unix!(1_700_000_220, :second)
        })

      assert {:ok, _scheduled_contact} =
               Cadence.persist_scheduled_contact(org.organization_id, scheduled_contact)

      ingest!(mission, binding_set, spacecraft.spacecraft_id, 14, 1_700_000_090)
      ingest!(mission, binding_set, spacecraft.spacecraft_id, 15, 1_700_000_100)
      evaluate_limits!(mission)

      canonical_event_time = DateTime.from_unix!(1_700_000_120, :second)

      canonical_event =
        Event.new(%{
          event_id: "operational_event:binding_set_activation:dashboard-live",
          organization_id: org.organization_id,
          mission_id: mission.mission_id,
          occurred_at: canonical_event_time,
          recorded_at: canonical_event_time,
          effective_at: canonical_event_time,
          category: :runtime,
          kind: :binding_set_activated,
          severity: :info,
          actor: %{kind: :system, id: "dashboard-live-test"},
          subject: %{kind: :binding_set, id: binding_set.binding_set_id},
          scope: %{
            spacecraft_id: spacecraft.spacecraft_id,
            source_endpoint_ref: "source-endpoint-alpha"
          },
          causality: %{
            correlation_id: binding_set.binding_set_id,
            source_record_kind: :binding_set_activation,
            source_record_id: "dashboard-live-activation"
          },
          payload: %{
            binding_set_id: binding_set.binding_set_id,
            binding_set_version: binding_set.version,
            activation_id: "dashboard-live-activation"
          },
          current: %{state: :active},
          metadata: %{"source" => "dashboard-live-test"}
        })

      assert {:ok, persisted_canonical_event} = OperationalEvents.persist_event(canonical_event)

      assert {:ok, 1} =
               MissionEvents.persist_entries(
                 Repo,
                 MissionEvents.project_many([persisted_canonical_event])
               )

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

      value_widget = render_item_by_title(document, "Counter").widget
      trend_widget = render_item_by_title(document, "Counter Trend").widget
      mirror_widget = render_item_by_title(document, "Counter Mirror").widget
      trend_widget_id = trend_widget.widget_id

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
               ~s(#dashboard-source-health[data-source-cache*="Telemetry:source=miss"])
             )

      assert has_element?(
               view,
               ~s(#dashboard-source-health[data-source-execution*="Telemetry:cache_miss"])
             )

      assert has_element?(
               view,
               ~s(#dashboard-source-health[data-source-execution-severity*="Telemetry:info"][data-source-execution-action*="Telemetry:none"])
             )

      assert has_element?(
               view,
               ~s([data-source-cache-detail="Telemetry:miss"] [data-source-health-field="Source cache"]),
               "miss"
             )

      assert has_element?(
               view,
               ~s([data-source-execution-detail="Telemetry:cache_miss"] [data-source-health-field="Execution status"]),
               "cache_miss"
             )

      assert has_element?(
               view,
               ~s([data-source-execution-action-detail="Telemetry:none"] [data-source-health-field="Execution action"]),
               "none"
             )

      backfill = chart_backfill(html, trend_widget.widget_id)
      older_point = Enum.at(backfill, 0)
      older_meta = point_meta(Enum.at(backfill, 0))
      latest_meta = point_meta(Enum.at(backfill, 1))
      older_link_id = older_meta["link_id"]
      older_timestamp_ms = List.first(older_point)

      assert older_meta["sample_id"] == older_sample.sample_id
      assert is_binary(older_link_id)
      assert latest_meta["sample_id"] == latest_sample.sample_id

      markers = chart_limit_markers(html, trend_widget.widget_id)

      marker =
        Enum.find(markers, &(&1["sample_id"] == latest_sample.sample_id)) || List.last(markers)

      marker_link_id = marker["link_id"]
      marker_limit_event_id = marker["limit_event_id"]
      marker_timestamp_ms = marker["timestamp_ms"]
      older_sample_id = older_sample.sample_id

      assert marker["normalized_state"] == "yellow"
      assert marker_limit_event_id
      assert is_binary(marker_link_id)

      event_markers = chart_event_markers(html, trend_widget.widget_id)

      contact_marker =
        Enum.find(
          event_markers,
          &(&1["marker_type"] == "contact_interval" and
              &1["contact_id"] == scheduled_contact.scheduled_contact_id)
        )

      mission_event_marker =
        Enum.find(
          event_markers,
          &(&1["marker_type"] == "mission_event" and
              &1["source_record_id"] == persisted_canonical_event.event_id)
        )

      assert contact_marker["target"] == "contact"
      assert contact_marker["target_id"] == scheduled_contact.scheduled_contact_id
      assert contact_marker["starts_at_ms"] == 1_700_000_080_000
      assert contact_marker["ends_at_ms"] == 1_700_000_220_000
      assert is_binary(contact_marker["link_id"])
      contact_link_id = contact_marker["link_id"]
      contact_target_id = contact_marker["target_id"]
      contact_timestamp_ms = contact_marker["starts_at_ms"]

      assert mission_event_marker["target"] == "mission_event"
      assert mission_event_marker["mission_event_id"]
      assert mission_event_marker["timestamp_ms"]
      assert is_binary(mission_event_marker["link_id"])
      assert mission_event_marker["source_record_id"] == persisted_canonical_event.event_id
      mission_event_link_id = mission_event_marker["link_id"]
      mission_event_id = mission_event_marker["mission_event_id"]
      mission_event_timestamp_ms = mission_event_marker["timestamp_ms"]

      assert has_element?(
               view,
               ~s(#widget-#{trend_widget.widget_id} [data-widget-data-link-target="telemetry sample"])
             )

      view
      |> element(~s(#widget-#{trend_widget.widget_id} [data-widget-frame-evidence]))
      |> render_click()

      evidence_path = assert_patch(view)
      assert evidence_path =~ "panel=evidence"
      assert evidence_path =~ "selected_evidence_kind=frame"
      assert evidence_path =~ "selected_placement=#{URI.encode_www_form(trend_widget.widget_id)}"
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
               ~s(#dashboard-evidence-copy-link[phx-hook="ClipboardButton"][data-clipboard-text*="/ops/dashboards/#{dashboard.dashboard_id}"][data-clipboard-text*="panel=evidence"][data-clipboard-text*="selected_evidence_kind=frame"][data-clipboard-text*="selected_placement=#{URI.encode_www_form(trend_widget.widget_id)}"][data-clipboard-text*="selected_observable=HK.counter"])
             )

      refute has_element?(
               view,
               ~s(#dashboard-evidence-copy-link[data-clipboard-text*="selected_target="])
             )

      assert has_element?(
               view,
               ~s(#dashboard-evidence-explore[data-dashboard-action-target="telemetry_explore"][data-dashboard-action-source="evidence_panel"][href*="/ops/telemetry/explore"][href*="point_id=HK.counter"][href*="sample_id="][href*="data_source_id="][href*="source_binding_id="][href*="source_dashboard_id=#{dashboard.dashboard_id}"])
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

      chart_id = chart_dom_id(render(view), trend_widget_id)

      view
      |> element("##{chart_id}")
      |> render_hook("open_data_link", %{
        "link-id" => contact_link_id,
        "placement-id" => trend_widget_id,
        "target" => "contact",
        "target-id" => scheduled_contact.scheduled_contact_id,
        "timestamp-ms" => contact_timestamp_ms
      })

      assert_push_event(
        view,
        "tlm:select",
        %{
          "selection" => %{
            "link_id" => ^contact_link_id,
            "placement_id" => ^trend_widget_id,
            "target" => "contact",
            "target_id" => ^contact_target_id,
            "timestamp_ms" => ^contact_timestamp_ms
          }
        },
        1_000
      )

      contact_path = assert_patch(view)
      assert contact_path =~ "panel=data_link"
      assert contact_path =~ "selected_target=contact"

      assert contact_path =~
               "selected_id=#{URI.encode_www_form(scheduled_contact.scheduled_contact_id)}"

      assert contact_path =~ "selected_placement=#{URI.encode_www_form(trend_widget_id)}"

      assert has_element?(
               view,
               ~s(#dashboard-data-link-inspector[data-data-link-target="contact"][data-data-link-status="resolved"])
             )

      assert has_element?(
               view,
               ~s(#ops-dashboard-show-page[data-dashboard-evidence-state="none"])
             )

      assert has_element?(
               view,
               ~s(#dashboard-data-link-inspector [data-data-link-field="Contact"]),
               scheduled_contact.scheduled_contact_id
             )

      view |> element(~s(#dashboard-panel button[aria-label="Close panel"])) |> render_click()

      chart_id = chart_dom_id(render(view), trend_widget_id)

      view
      |> element("##{chart_id}")
      |> render_hook("open_data_link", %{
        "link-id" => mission_event_link_id,
        "placement-id" => trend_widget_id,
        "target" => "mission_event",
        "target-id" => mission_event_id,
        "timestamp-ms" => mission_event_timestamp_ms
      })

      assert_push_event(
        view,
        "tlm:select",
        %{
          "selection" => %{
            "link_id" => ^mission_event_link_id,
            "placement_id" => ^trend_widget_id,
            "target" => "mission_event",
            "target_id" => ^mission_event_id,
            "timestamp_ms" => ^mission_event_timestamp_ms
          }
        },
        1_000
      )

      mission_event_path = assert_patch(view)
      assert mission_event_path =~ "panel=data_link"
      assert mission_event_path =~ "selected_target=mission_event"
      assert mission_event_path =~ "selected_id=#{URI.encode_www_form(mission_event_id)}"

      assert has_element?(
               view,
               ~s(#dashboard-data-link-inspector[data-data-link-target="mission_event"][data-data-link-status="resolved"])
             )

      assert has_element?(
               view,
               ~s(#dashboard-data-link-inspector [data-data-link-field="Mission event"]),
               mission_event_id
             )

      assert has_element?(
               view,
               ~s(#dashboard-data-link-inspector [data-data-link-field="Source record kind"]),
               "operational_event"
             )

      assert has_element?(
               view,
               ~s(#dashboard-data-link-inspector [data-data-link-related-target="operational event"][data-data-link-related-id="#{persisted_canonical_event.event_id}"][data-data-link-related-kind="source_event"])
             )

      view
      |> element(
        ~s(#dashboard-data-link-inspector [data-data-link-related-target="operational event"][data-data-link-related-id="#{persisted_canonical_event.event_id}"])
      )
      |> render_click()

      operational_event_path = assert_patch(view)
      assert operational_event_path =~ "panel=data_link"
      assert operational_event_path =~ "selected_target=operational_event"

      assert operational_event_path =~
               "selected_id=#{URI.encode_www_form(persisted_canonical_event.event_id)}"

      assert operational_event_path =~ "nav_from_target=mission_event"

      assert operational_event_path =~
               "nav_from_target_id=#{URI.encode_www_form(mission_event_id)}"

      assert has_element?(
               view,
               ~s(#dashboard-data-link-inspector[data-data-link-target="operational_event"][data-data-link-status="resolved"])
             )

      assert has_element?(
               view,
               ~s(#dashboard-data-link-inspector [data-data-link-field="Operational event"]),
               persisted_canonical_event.event_id
             )

      assert has_element?(
               view,
               ~s(#dashboard-data-link-inspector [data-data-link-field="Kind"]),
               "binding_set_activated"
             )

      assert has_element?(
               view,
               ~s(#dashboard-data-link-copy-link[data-clipboard-text*="panel=data_link"][data-clipboard-text*="selected_target=operational_event"][data-clipboard-text*="selected_id=#{URI.encode_www_form(persisted_canonical_event.event_id)}"][data-clipboard-text*="nav_from_target=mission_event"][data-clipboard-text*="nav_from_target_id=#{URI.encode_www_form(mission_event_id)}"])
             )

      view |> element(~s(#dashboard-panel button[aria-label="Close panel"])) |> render_click()

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
               ~s(#dashboard-data-link-copy-link[data-clipboard-text*="/ops/dashboards/#{dashboard.dashboard_id}"][data-clipboard-text*="panel=data_link"][data-clipboard-text*="selected_target=limit_event"][data-clipboard-text*="selected_id=#{URI.encode_www_form(marker_limit_event_id)}"][data-clipboard-text*="selected_placement=#{URI.encode_www_form(trend_widget_id)}"][data-clipboard-text*="selected_time=#{marker_timestamp_ms}"][data-clipboard-text*="realm=flight"][data-clipboard-text*="data_source_id=#{limit_data_source_id}"][data-clipboard-text*="source_binding_id=default_flight_limits"])
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

      view |> element(~s(#dashboard-panel button[aria-label="Close panel"])) |> render_click()

      html = render(view)
      chart_id = chart_dom_id(html, trend_widget_id)

      current_older_link_id =
        html
        |> chart_backfill(trend_widget.widget_id)
        |> Enum.find_value(fn point ->
          meta = point_meta(point)
          if meta["sample_id"] == older_sample_id, do: meta["link_id"]
        end)

      current_older_link_id = current_older_link_id || older_link_id

      view
      |> element("##{chart_id}")
      |> render_hook("open_data_link", %{
        "link-id" => current_older_link_id,
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
            "link_id" => ^current_older_link_id,
            "placement_id" => ^trend_widget_id,
            "target" => "telemetry_sample",
            "target_id" => ^older_sample_id,
            "timestamp_ms" => ^older_timestamp_ms
          }
        },
        1_000
      )

      selected_ref = chart_selected_ref(render(view), trend_widget_id)
      assert selected_ref["placement_id"] == trend_widget_id
      assert selected_ref["target"] == "telemetry_sample"
      assert selected_ref["target_id"] == older_sample_id
      assert selected_ref["timestamp_ms"] == older_timestamp_ms
      assert selected_ref["realm"] == "flight"

      assert selected_ref["data_source_id"] ==
               DataSources.default_managed_data_source().data_source_id

      assert selected_ref["source_binding_id"] == "default_flight_telemetry"
      assert selected_ref["spacecraft_id"] == spacecraft.spacecraft_id
      assert chart_selected_ref(render(view), mirror_widget.widget_id) == nil

      selected_path = assert_patch(view)
      assert selected_path =~ "panel=data_link"
      assert selected_path =~ "selected_link="
      assert selected_path =~ "selected_target=telemetry_sample"
      assert selected_path =~ "selected_id=#{URI.encode_www_form(older_sample_id)}"
      assert selected_path =~ "selected_placement=#{URI.encode_www_form(trend_widget_id)}"
      assert selected_path =~ "selected_time=#{older_timestamp_ms}"
      assert selected_path =~ "realm=flight"

      assert selected_path =~
               "data_source_id=#{DataSources.default_managed_data_source().data_source_id}"

      assert selected_path =~ "source_binding_id=default_flight_telemetry"

      assert has_element?(
               view,
               ~s(#dashboard-data-link-explore[data-dashboard-action-target="telemetry_explore"][data-dashboard-action-source="data_link_panel"][href*="/ops/telemetry/explore"][href*="point_id=HK.counter"][href*="sample_id=#{URI.encode_www_form(older_sample_id)}"][href*="data_source_id=#{DataSources.default_managed_data_source().data_source_id}"][href*="source_binding_id=default_flight_telemetry"])
             )

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
               ~s(#dashboard-data-link-inspector [data-data-link-field="Sample"]),
               older_sample_id
             )

      assert has_element?(
               shared_view,
               ~s(#ops-dashboard-show-page[data-dashboard-selection-state="active"][data-dashboard-selection-target="telemetry_sample"][data-dashboard-selection-source-binding="default_flight_telemetry"])
             )

      assert has_element?(
               shared_view,
               ~s(#dashboard-data-link-copy-link[data-clipboard-text*="/ops/dashboards/#{dashboard.dashboard_id}"][data-clipboard-text*="panel=data_link"][data-clipboard-text*="selected_target=telemetry_sample"][data-clipboard-text*="selected_id=#{URI.encode_www_form(older_sample_id)}"][data-clipboard-text*="selected_placement=#{URI.encode_www_form(trend_widget_id)}"][data-clipboard-text*="selected_time=#{older_timestamp_ms}"][data-clipboard-text*="data_source_id=#{DataSources.default_managed_data_source().data_source_id}"][data-clipboard-text*="source_binding_id=default_flight_telemetry"])
             )

      shared_selected_ref = chart_selected_ref(render(shared_view), trend_widget_id)
      assert shared_selected_ref["placement_id"] == trend_widget_id
      assert shared_selected_ref["target"] == "telemetry_sample"
      assert shared_selected_ref["target_id"] == older_sample_id
      assert shared_selected_ref["timestamp_ms"] == older_timestamp_ms
      assert shared_selected_ref["realm"] == "flight"

      assert shared_selected_ref["data_source_id"] ==
               DataSources.default_managed_data_source().data_source_id

      assert shared_selected_ref["source_binding_id"] == "default_flight_telemetry"
      assert chart_selected_ref(render(shared_view), mirror_widget.widget_id) == nil

      explicit_panel_path =
        ~p"/missions/#{mission.mission_id}/ops/dashboards/#{dashboard.dashboard_id}?#{%{panel: "data_link", selected_target: "telemetry_sample", selected_id: older_sample_id, selected_placement: trend_widget_id, selected_time: older_timestamp_ms, selected_evidence_kind: "frame", selected_observable: "HK.counter", realm: "flight", data_source_id: DataSources.default_managed_data_source().data_source_id, source_binding_id: "default_flight_telemetry"}}"

      {:ok, explicit_panel_view, _html} = live(conn, explicit_panel_path)
      render_dashboard_async(explicit_panel_view)

      assert has_element?(
               explicit_panel_view,
               ~s(#dashboard-data-link-inspector[data-data-link-target="telemetry_sample"][data-data-link-status="resolved"])
             )

      assert has_element?(
               explicit_panel_view,
               ~s(#dashboard-data-link-inspector [data-data-link-context="Data source"]),
               DataSources.default_managed_data_source().data_source_id
             )

      assert has_element?(
               explicit_panel_view,
               ~s(#dashboard-data-link-inspector [data-data-link-context="Source binding"]),
               "default_flight_telemetry"
             )

      refute has_element?(explicit_panel_view, "#dashboard-evidence-inspector")

      assert has_element?(
               explicit_panel_view,
               ~s(#ops-dashboard-show-page[data-dashboard-selection-state="active"][data-dashboard-evidence-state="none"])
             )

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
      refute chart_selected_ref(render(stale_context_view), trend_widget_id)

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

      shared_selected_ref = chart_selected_ref(render(shared_view), trend_widget_id)
      assert shared_selected_ref["target"] == "telemetry_sample"
      assert shared_selected_ref["target_id"] == older_sample_id
      assert shared_selected_ref["timestamp_ms"] == older_timestamp_ms

      direct_target_path =
        ~p"/missions/#{mission.mission_id}/ops/dashboards/#{dashboard.dashboard_id}?#{%{selected_target: "telemetry_sample", selected_id: older_sample_id, selected_placement: trend_widget_id, selected_time: older_timestamp_ms}}"

      {:ok, direct_target_view, _html} = live(conn, direct_target_path)
      render_dashboard_async(direct_target_view)

      assert has_element?(
               direct_target_view,
               ~s(#dashboard-data-link-inspector[data-data-link-target="telemetry_sample"][data-data-link-status="resolved"])
             )

      assert has_element?(
               direct_target_view,
               ~s(#dashboard-data-link-inspector [data-data-link-field="Sample"]),
               older_sample_id
             )

      direct_target_selected_ref = chart_selected_ref(render(direct_target_view), trend_widget_id)
      assert direct_target_selected_ref["placement_id"] == trend_widget_id
      assert direct_target_selected_ref["target"] == "telemetry_sample"
      assert direct_target_selected_ref["target_id"] == older_sample_id
      assert direct_target_selected_ref["timestamp_ms"] == older_timestamp_ms

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
      refute chart_selected_ref(render(direct_target_view), trend_widget_id)
      assert has_element?(direct_target_view, "#dashboard-pause-at-selection[disabled]")
      assert has_element?(direct_target_view, "#dashboard-clear-selection[disabled]")

      stale_target_path =
        ~p"/missions/#{mission.mission_id}/ops/dashboards/#{dashboard.dashboard_id}?#{%{selected_target: "telemetry_sample", selected_id: "missing-sample"}}"

      {:ok, stale_target_view, _html} = live(conn, stale_target_path)
      render_dashboard_async(stale_target_view)

      assert has_element?(
               stale_target_view,
               ~s(#dashboard-data-link-inspector[data-data-link-target="telemetry_sample"][data-data-link-target-id="missing-sample"][data-data-link-status="missing"])
             )

      assert has_element?(
               stale_target_view,
               ~s(#ops-dashboard-show-page[data-dashboard-selection-state="missing_target"][data-dashboard-selection-target="telemetry_sample"])
             )

      assert has_element?(
               stale_target_view,
               ~s(#ops-dashboard-show-page[data-dashboard-evidence-state="none"])
             )

      assert has_element?(
               stale_target_view,
               ~s(#dashboard-data-link-copy-link[data-clipboard-text*="selected_target=telemetry_sample"][data-clipboard-text*="selected_id=missing-sample"])
             )

      stale_link_path =
        ~p"/missions/#{mission.mission_id}/ops/dashboards/#{dashboard.dashboard_id}?#{%{panel: "data_link", selected_link: "stale-link-1"}}"

      {:ok, stale_link_view, _html} = live(conn, stale_link_path)
      render_dashboard_async(stale_link_view)

      assert has_element?(
               stale_link_view,
               ~s(#dashboard-data-link-inspector[data-data-link-target="data_link"][data-data-link-target-id="stale-link-1"][data-data-link-status="missing"])
             )

      assert has_element?(
               stale_link_view,
               ~s(#ops-dashboard-show-page[data-dashboard-selection-state="missing_target"])
             )

      refute chart_selected_ref(render(stale_link_view), trend_widget_id)

      unsupported_target_path =
        ~p"/missions/#{mission.mission_id}/ops/dashboards/#{dashboard.dashboard_id}?#{%{selected_target: "command", selected_id: "cmd-1"}}"

      {:ok, unsupported_target_view, _html} = live(conn, unsupported_target_path)
      render_dashboard_async(unsupported_target_view)

      assert has_element?(
               unsupported_target_view,
               ~s(#ops-dashboard-show-page[data-dashboard-selection-state="none"])
             )

      refute has_element?(unsupported_target_view, "#dashboard-data-link-inspector")
      refute chart_selected_ref(render(unsupported_target_view), trend_widget_id)
      assert has_element?(unsupported_target_view, "#dashboard-pause-at-selection[disabled]")
      assert has_element?(unsupported_target_view, "#dashboard-clear-selection[disabled]")

      assert has_element?(view, "#dashboard-pause-at-selection:not([disabled])")

      ingest!(mission, binding_set, spacecraft.spacecraft_id, 25, 1_700_000_500)
      evaluate_limits!(mission)
      render_dashboard_async(view)

      future_sample =
        org.organization_id
        |> Cadence.telemetry_history(mission.mission_id, "HK.counter",
          spacecraft_id: spacecraft.spacecraft_id,
          order: :asc
        )
        |> List.last()

      assert future_sample.raw_value == 25
      future_sample_id = future_sample.sample_id

      {expected_from, expected_to} = centered_archive_range(older_timestamp_ms)

      view |> element("#dashboard-pause-at-selection") |> render_click()

      paused_path = assert_patch(view)
      assert paused_path =~ "time_mode=archive"
      assert paused_path =~ URI.encode_www_form(expected_from)
      assert paused_path =~ URI.encode_www_form(expected_to)
      render_dashboard_async(view)

      assert has_element?(
               view,
               ~s(#ops-dashboard-show-page[data-dashboard-time-mode="archive"][data-dashboard-time-from="#{expected_from}"][data-dashboard-time-to="#{expected_to}"])
             )

      assert has_element?(
               view,
               ~s(#ops-dashboard-show-page[data-engine-time-mode="archive"][data-engine-snapshot="true"][data-engine-live-append-eligible="false"])
             )

      refute has_element?(
               view,
               ~s(#dashboard-engine-warnings[data-warning-codes*="time_range_ignored"])
             )

      selected_ref = chart_selected_ref(render(view), trend_widget_id)
      assert selected_ref["placement_id"] == trend_widget_id
      assert selected_ref["target"] == "telemetry_sample"
      assert selected_ref["target_id"] == older_sample_id
      assert selected_ref["timestamp_ms"] == older_timestamp_ms
      assert chart_selected_ref(render(view), mirror_widget.widget_id) == nil

      assert has_element?(
               view,
               ~s(#dashboard-data-link-copy-link[data-clipboard-text*="time_mode=archive"][data-clipboard-text*="from=#{URI.encode_www_form(expected_from)}"][data-clipboard-text*="to=#{URI.encode_www_form(expected_to)}"][data-clipboard-text*="selected_target=telemetry_sample"][data-clipboard-text*="selected_id=#{URI.encode_www_form(older_sample_id)}"])
             )

      paused_markers = chart_limit_markers(render(view), trend_widget.widget_id)
      refute Enum.any?(paused_markers, &(&1["sample_id"] == future_sample_id))

      view |> element("#context-search-form") |> render_change(%{"q" => "alpha"})

      view
      |> element(~s(button[phx-value-spacecraft-id="#{spacecraft.spacecraft_id}"]))
      |> render_click()

      assert_patch(view)
      render_dashboard_async(view)
      paused_html = render(view)
      assert paused_html =~ "15"
      assert paused_html =~ "Yellow"
      refute paused_html =~ "Pick a spacecraft context"

      assert has_element?(view, "#dashboard-resume-live:not([disabled])")

      view |> element("#dashboard-resume-live") |> render_click()

      assert_patch(view)
      render_dashboard_async(view)

      assert has_element?(
               view,
               ~s(#ops-dashboard-show-page[data-dashboard-time-mode="live"])
             )

      assert has_element?(
               view,
               ~s(#ops-dashboard-show-page[data-engine-time-mode="live"][data-engine-snapshot="false"][data-engine-live-append-eligible="true"])
             )

      assert chart_selected_ref(render(view), mirror_widget.widget_id) == nil

      assert has_element?(
               view,
               ~s(#dashboard-data-link-inspector[data-data-link-target="telemetry_sample"][data-data-link-status="resolved"])
             )

      assert has_element?(
               view,
               ~s(#dashboard-data-link-inspector [data-data-link-field="Sample"]),
               older_sample_id
             )

      assert has_element?(
               view,
               ~s(#dashboard-data-link-inspector [data-data-link-field="Raw"]),
               "14"
             )

      view |> element(~s(#dashboard-panel button[aria-label="Close panel"])) |> render_click()

      telemetry_data_source_id = DataSources.default_managed_data_source().data_source_id
      latest_sample_timestamp_ms = DateTime.to_unix(latest_sample.receipt_time, :millisecond)

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

      view |> element(~s(#dashboard-panel button[aria-label="Close panel"])) |> render_click()

      html = render(view)
      assert html =~ "25"
      assert html =~ "Red"
      refute html =~ "Pick a spacecraft context"

      assert has_element?(
               view,
               ~s(#widget-#{value_widget.widget_id} [data-widget-data-link-target="limit event"])
             )

      view
      |> element(
        ~s(#widget-#{value_widget.widget_id} [data-widget-data-link-target="limit event"])
      )
      |> render_click()

      assert has_element?(
               view,
               ~s(#dashboard-data-link-inspector[data-data-link-target="limit_event"][data-data-link-status="resolved"])
             )

      assert has_element?(
               view,
               ~s(#dashboard-data-link-inspector [data-data-link-field="Normalized state"]),
               "red"
             )

      assert has_element?(
               view,
               ~s(#dashboard-data-link-inspector [data-data-link-related-target="limit definition"])
             )

      view
      |> element(
        ~s(#dashboard-data-link-inspector [data-data-link-related-target="limit definition"])
      )
      |> render_click()

      assert has_element?(
               view,
               ~s(#dashboard-data-link-inspector[data-data-link-target="limit_definition"][data-data-link-status="resolved"])
             )

      assert has_element?(
               view,
               ~s(#dashboard-data-link-inspector [data-data-link-field="Definition"]),
               "counter-limits"
             )
    end

    test "renders status matrix rows from latest telemetry and limit overlays" do
      disable_telemetry_storage_runtime_invalidation!()

      {conn, org, mission} = signed_in_org_and_mission()
      spacecraft = TestFixtures.persist_spacecraft!(mission, display_name: "SC Matrix")
      binding_set = persist_matrix_binding_set!(org, mission)

      ingest_matrix!(mission, binding_set, spacecraft.spacecraft_id, 15, 28, 1_700_000_100)
      evaluate_limits!(mission)

      dashboard =
        TestFixtures.persist_dashboard_document!(mission,
          name: "Matrix",
          widgets: [
            %{
              type: :status_matrix,
              title: "Counter Matrix",
              binding: %{
                mode: :fixed,
                spacecraft_id: spacecraft.spacecraft_id,
                point_ids: ["HK.counter", "HK.voltage"]
              }
            }
          ]
        )

      document = fetch_dashboard_document!(org, mission, dashboard)
      matrix_widget = render_item_by_title(document, "Counter Matrix").widget

      {:ok, view, _html} = live(conn, show_path(mission, dashboard))
      render_dashboard_async(view)

      assert has_element?(
               view,
               ~s(#widget-#{matrix_widget.widget_id} [data-status-matrix][data-engine-backed="true"])
             )

      assert has_element?(
               view,
               ~s(#widget-#{matrix_widget.widget_id} [data-status-matrix-row="HK.counter"] [data-status-matrix-field="value"]),
               "15"
             )

      assert has_element?(
               view,
               ~s(#widget-#{matrix_widget.widget_id} [data-status-matrix-row="HK.counter"] [data-status-matrix-field="quality"]),
               "Good"
             )

      assert has_element?(
               view,
               ~s(#widget-#{matrix_widget.widget_id} [data-status-matrix-row="HK.counter"] [data-status-matrix-field="limit"]),
               "Yellow"
             )

      assert has_element?(
               view,
               ~s(#widget-#{matrix_widget.widget_id} [data-status-matrix-row="HK.voltage"] [data-status-matrix-field="value"]),
               "28"
             )

      assert has_element?(
               view,
               ~s(#widget-#{matrix_widget.widget_id} [data-status-matrix-row="HK.voltage"] [data-status-matrix-field="limit"]),
               "None"
             )

      view
      |> element(
        ~s(#widget-#{matrix_widget.widget_id} [data-status-matrix-row-evidence="HK.counter"])
      )
      |> render_click()

      assert has_element?(
               view,
               ~s(#dashboard-evidence-inspector[data-evidence-kind="frame"][data-evidence-status="resolved"])
             )

      assert has_element?(
               view,
               ~s(#dashboard-evidence-inspector [data-evidence-subject-field="Observable"]),
               "HK.counter"
             )

      assert has_element?(
               view,
               ~s(#dashboard-evidence-inspector [data-evidence-detail="Value"]),
               "15"
             )

      assert has_element?(
               view,
               ~s(#dashboard-evidence-inspector [data-evidence-link-target="limit event"])
             )

      view |> element(~s(#dashboard-panel button[aria-label="Close panel"])) |> render_click()

      view
      |> element(
        ~s(#widget-#{matrix_widget.widget_id} [data-status-matrix-row-link="HK.counter"][data-status-matrix-row-link-target="limit event"])
      )
      |> render_click()

      assert has_element?(
               view,
               ~s(#dashboard-data-link-inspector[data-data-link-target="limit_event"][data-data-link-status="resolved"])
             )

      assert has_element?(
               view,
               ~s(#dashboard-data-link-inspector [data-data-link-field="Point"]),
               "HK.counter"
             )

      assert has_element?(
               view,
               ~s(#dashboard-data-link-inspector [data-data-link-field="Normalized state"]),
               "yellow"
             )

      view |> element(~s(#dashboard-panel button[aria-label="Close panel"])) |> render_click()

      view
      |> element(
        ~s(#widget-#{matrix_widget.widget_id} [data-status-matrix-row-link="HK.voltage"][data-status-matrix-row-link-target="telemetry sample"])
      )
      |> render_click()

      assert has_element?(
               view,
               ~s(#dashboard-data-link-inspector[data-data-link-target="telemetry_sample"][data-data-link-status="resolved"])
             )

      assert has_element?(
               view,
               ~s(#dashboard-data-link-inspector [data-data-link-field="Point"]),
               "HK.voltage"
             )

      assert has_element?(
               view,
               ~s(#dashboard-data-link-inspector [data-data-link-field="Raw"]),
               "28"
             )
    end

    test "renders data table rows from latest telemetry and limit overlays" do
      disable_telemetry_storage_runtime_invalidation!()

      {conn, org, mission} = signed_in_org_and_mission()
      spacecraft = TestFixtures.persist_spacecraft!(mission, display_name: "SC Table")
      binding_set = persist_matrix_binding_set!(org, mission)

      ingest_matrix!(mission, binding_set, spacecraft.spacecraft_id, 15, 28, 1_700_000_100)
      evaluate_limits!(mission)

      dashboard =
        TestFixtures.persist_dashboard_document!(mission,
          name: "Table",
          widgets: [
            %{
              type: :data_table,
              title: "HK Table",
              binding: %{
                mode: :fixed,
                spacecraft_id: spacecraft.spacecraft_id,
                point_ids: ["HK.counter", "HK.voltage"]
              }
            }
          ]
        )

      document = fetch_dashboard_document!(org, mission, dashboard)
      table_widget = render_item_by_title(document, "HK Table").widget

      {:ok, view, _html} = live(conn, show_path(mission, dashboard))
      render_dashboard_async(view)

      assert has_element?(
               view,
               ~s(#widget-#{table_widget.widget_id} [data-data-table][data-engine-backed="true"])
             )

      assert has_element?(
               view,
               ~s(#widget-#{table_widget.widget_id} [data-data-table-row="HK.counter"] [data-data-table-field="value"]),
               "15"
             )

      assert has_element?(
               view,
               ~s(#widget-#{table_widget.widget_id} [data-data-table-row="HK.counter"] [data-data-table-field="quality"]),
               "Good"
             )

      assert has_element?(
               view,
               ~s(#widget-#{table_widget.widget_id} [data-data-table-row="HK.counter"] [data-data-table-field="state"]),
               "Yellow"
             )

      assert has_element?(
               view,
               ~s(#widget-#{table_widget.widget_id} [data-data-table-row="HK.voltage"] [data-data-table-field="value"]),
               "28"
             )

      view
      |> element(
        ~s(#widget-#{table_widget.widget_id} [data-data-table-row-link="HK.voltage"][data-data-table-row-link-target="telemetry sample"])
      )
      |> render_click()

      assert has_element?(
               view,
               ~s(#dashboard-data-link-inspector[data-data-link-target="telemetry_sample"][data-data-link-status="resolved"])
             )

      assert has_element?(
               view,
               ~s(#dashboard-data-link-inspector [data-data-link-field="Point"]),
               "HK.voltage"
             )
    end

    test "renders contact phase operational observable rows with phase presentation" do
      enable_dashboard_engine_inline_resolves!()

      {conn, org, mission} = signed_in_org_and_mission()

      scheduled_contact =
        ScheduledContact.new(%{
          scheduled_contact_id: "dashboard-contact-phase-alpha",
          mission_id: mission.mission_id,
          source_endpoint_refs: ["source-endpoint-alpha"],
          paths: contact_paths("source-endpoint-alpha"),
          starts_at: DateTime.from_unix!(1_700_000_080, :second),
          ends_at: DateTime.from_unix!(1_700_000_220, :second)
        })

      assert {:ok, _scheduled_contact} =
               Cadence.persist_scheduled_contact(org.organization_id, scheduled_contact)

      dashboard =
        TestFixtures.persist_dashboard_document!(mission,
          name: "Contact Phase",
          widgets: [
            %{
              type: :status_matrix,
              title: "Contact Phase",
              binding: %{
                source: :operational_observables,
                observables: ["contacts.phase"]
              }
            }
          ]
        )

      document = fetch_dashboard_document!(org, mission, dashboard)
      matrix_widget = render_item_by_title(document, "Contact Phase").widget

      {:ok, view, _html} = live(conn, show_path(mission, dashboard))
      render_dashboard_async(view)

      row_selector =
        ~s(#widget-#{matrix_widget.widget_id} [data-status-matrix-row="contacts.phase:dashboard-contact-phase-alpha"])

      assert has_element?(
               view,
               row_selector <>
                 ~s([data-status-matrix-source="operational_observables"][data-status-matrix-status-policy="contact_phase"][data-status-matrix-contact-kind="scheduled"][data-status-matrix-phase="scheduled"])
             )

      assert has_element?(
               view,
               row_selector <> ~s( [data-status-matrix-field="value"]),
               "Scheduled"
             )

      assert has_element?(
               view,
               row_selector <> ~s( [data-status-matrix-field="quality"]),
               "Scheduled"
             )

      assert has_element?(
               view,
               row_selector <> ~s( [data-status-matrix-field="limit"]),
               "Scheduled"
             )

      assert has_element?(
               view,
               row_selector <> ~s( [data-status-matrix-field="time"]),
               scheduled_contact.scheduled_contact_id
             )

      assert has_element?(
               view,
               row_selector <>
                 ~s( [data-status-matrix-row-link-target="contact"][data-status-matrix-row-link-id="#{scheduled_contact.scheduled_contact_id}"])
             )

      stop_dashboard_view(view)
    end

    test "renders connection state operational observable rows with connection presentation" do
      enable_dashboard_engine_inline_resolves!()

      {conn, org, mission} = signed_in_org_and_mission()

      source_endpoint =
        SourceEndpoint.new(%{
          source_endpoint_id: "dashboard-source-endpoint-alpha",
          mission_id: mission.mission_id,
          display_name: "Goldstone DSS-14",
          metadata: %{"ground_station_id" => "dss-14"}
        })

      assert {:ok, _source_endpoint} =
               Cadence.persist_source_endpoint(org.organization_id, source_endpoint)

      transport =
        Transport.new(%{
          transport_id: "dashboard-transport-alpha",
          mission_id: mission.mission_id,
          display_name: "Lab TCP",
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

      assert {:ok, _transport} = Cadence.persist_transport(org.organization_id, transport)

      dashboard =
        TestFixtures.persist_dashboard_document!(mission,
          name: "Connection State",
          widgets: [
            %{
              type: :status_matrix,
              title: "Connection State",
              binding: %{
                source: :operational_observables,
                observables: ["comms.transport.connection_state"]
              }
            }
          ]
        )

      document = fetch_dashboard_document!(org, mission, dashboard)
      matrix_widget = render_item_by_title(document, "Connection State").widget

      {:ok, view, _html} = live(conn, show_path(mission, dashboard))
      render_dashboard_async(view)

      row_selector =
        ~s(#widget-#{matrix_widget.widget_id} [data-status-matrix-row="comms.transport.connection_state:dashboard-transport-alpha"])

      assert has_element?(
               view,
               row_selector <>
                 ~s([data-status-matrix-source="operational_observables"][data-status-matrix-status-policy="connection_state"][data-status-matrix-resource-id="dashboard-transport-alpha"][data-status-matrix-transport-id="dashboard-transport-alpha"][data-status-matrix-source-endpoint-id="dashboard-source-endpoint-alpha"][data-status-matrix-ground-station-id="dss-14"][data-status-matrix-connection-state="unknown"])
             )

      assert has_element?(
               view,
               row_selector <>
                 ~s([data-status-matrix-frame-observable-id="comms.transport.connection_state"][data-status-matrix-product-family="connection_state"][data-status-matrix-supported-capability="connection_state"][data-status-matrix-data-source-id="managed_operational_observables"])
             )

      assert has_element?(
               view,
               row_selector <>
                 ~s( [data-status-matrix-row-evidence="comms.transport.connection_state:dashboard-transport-alpha"][data-status-matrix-row-evidence-observable="comms.transport.connection_state"])
             )

      assert has_element?(
               view,
               row_selector <>
                 ~s( [data-status-matrix-row-link="comms.transport.connection_state:dashboard-transport-alpha"][data-status-matrix-row-link-target="transport"][data-status-matrix-row-link-id="dashboard-transport-alpha"][phx-value-target="transport"][phx-value-target-id="dashboard-transport-alpha"][phx-value-data-source-id="managed_operational_observables"][phx-value-source-binding-id="default_flight_operational_observables"])
             )

      assert has_element?(
               view,
               row_selector <> ~s( [data-status-matrix-field="value"]),
               "Unknown"
             )

      assert has_element?(
               view,
               row_selector <> ~s( [data-status-matrix-field="quality"]),
               "Tcp socket"
             )

      assert has_element?(
               view,
               row_selector <> ~s( [data-status-matrix-field="limit"]),
               "Unknown"
             )

      assert has_element?(
               view,
               row_selector <> ~s( [data-status-matrix-field="time"]),
               "dashboard-transport-alpha"
             )

      transport_link_path =
        show_path(mission, dashboard) <>
          "?panel=data_link&selected_target=transport&selected_id=dashboard-transport-alpha&selected_transport_id=dashboard-transport-alpha&realm=flight&data_source_id=managed_operational_observables&source_binding_id=default_flight_operational_observables"

      {:ok, transport_link_view, _html} = live(conn, transport_link_path)
      render_dashboard_async(transport_link_view)

      assert has_element?(
               transport_link_view,
               ~s(#dashboard-data-link-inspector[data-data-link-target="transport"][data-data-link-status="resolved"])
             )

      assert has_element?(
               transport_link_view,
               ~s(#dashboard-data-link-inspector [data-data-link-context="Data source"]),
               "managed_operational_observables"
             )

      assert has_element?(
               transport_link_view,
               ~s(#dashboard-data-link-inspector [data-data-link-context="Source binding"]),
               "default_flight_operational_observables"
             )

      assert has_element?(
               transport_link_view,
               ~s(#dashboard-data-link-copy-link[data-clipboard-text*="panel=data_link"][data-clipboard-text*="selected_target=transport"][data-clipboard-text*="selected_id=dashboard-transport-alpha"][data-clipboard-text*="data_source_id=managed_operational_observables"][data-clipboard-text*="source_binding_id=default_flight_operational_observables"])
             )

      stop_dashboard_view(view)
      stop_dashboard_view(transport_link_view)
    end

    test "mission scope renders aggregate operational observable rows" do
      enable_dashboard_engine_inline_resolves!()

      {conn, org, mission} = signed_in_org_and_mission()

      persist_command_queue_entry!(
        org,
        mission,
        "dashboard-queue-alpha",
        "dashboard-source-endpoint-alpha"
      )

      persist_command_queue_entry!(
        org,
        mission,
        "dashboard-queue-beta",
        "dashboard-source-endpoint-beta"
      )

      persist_command_queue_entry!(
        org,
        mission,
        "dashboard-queue-released",
        "dashboard-source-endpoint-alpha",
        :released
      )

      dashboard =
        TestFixtures.persist_dashboard_document!(mission,
          name: "Mission Command Queue",
          widgets: [
            %{
              type: :status_matrix,
              title: "Command Queue",
              binding: %{
                source: :operational_observables,
                observables: ["commanding.queue_depth"]
              }
            }
          ]
        )

      document = fetch_dashboard_document!(org, mission, dashboard)
      matrix_widget = render_item_by_title(document, "Command Queue").widget

      {:ok, view, _html} =
        live(
          conn,
          show_path(mission, dashboard) <>
            "?scope_kind=mission&scope_id=#{mission.mission_id}"
        )

      render_dashboard_async(view)

      assert has_element?(
               view,
               ~s(#ops-dashboard-show-page[data-dashboard-scope-kind="mission"][data-dashboard-scope-id="#{mission.mission_id}"])
             )

      mission_row_selector =
        ~s(#widget-#{matrix_widget.widget_id} [data-status-matrix-row="commanding.queue_depth:#{mission.mission_id}"])

      assert has_element?(
               view,
               mission_row_selector <>
                 ~s([data-status-matrix-source="operational_observables"][data-status-matrix-status-policy="metric_value"][data-status-matrix-resource-id="#{mission.mission_id}"][data-status-matrix-scope-kind="mission"])
             )

      assert has_element?(
               view,
               mission_row_selector <>
                 ~s([data-status-matrix-frame-observable-id="commanding.queue_depth"][data-status-matrix-product-family="commanding"][data-status-matrix-supported-capability="command_queue_depth"][data-status-matrix-data-source-id="managed_operational_observables"][data-status-matrix-source-binding-id="default_flight_operational_observables"])
             )

      assert has_element?(
               view,
               mission_row_selector <> ~s( [data-status-matrix-field="observable"]),
               "Pending commands"
             )

      assert has_element?(
               view,
               mission_row_selector <> ~s( [data-status-matrix-field="value"]),
               "2"
             )

      assert has_element?(
               view,
               mission_row_selector <>
                 ~s( [data-status-matrix-row-evidence="commanding.queue_depth:#{mission.mission_id}"][data-status-matrix-row-evidence-observable="commanding.queue_depth"][phx-value-logical-source="operational_observables"][phx-value-data-source-id="managed_operational_observables"][phx-value-source-binding-id="default_flight_operational_observables"])
             )

      refute has_element?(
               view,
               ~s(#widget-#{matrix_widget.widget_id} [data-status-matrix-row-link="commanding.queue_depth:#{mission.mission_id}"])
             )

      stop_dashboard_view(view)
    end

    test "document multi-entity scope filters operational observable rows" do
      enable_dashboard_engine_inline_resolves!()

      {conn, org, mission} = signed_in_org_and_mission()

      alpha_endpoint =
        SourceEndpoint.new(%{
          source_endpoint_id: "dashboard-source-endpoint-alpha",
          mission_id: mission.mission_id,
          display_name: "Goldstone DSS-14",
          metadata: %{"ground_station_id" => "dss-14"}
        })

      beta_endpoint =
        SourceEndpoint.new(%{
          source_endpoint_id: "dashboard-source-endpoint-beta",
          mission_id: mission.mission_id,
          display_name: "Madrid DSS-63",
          metadata: %{"ground_station_id" => "dss-63"}
        })

      gamma_endpoint =
        SourceEndpoint.new(%{
          source_endpoint_id: "dashboard-source-endpoint-gamma",
          mission_id: mission.mission_id,
          display_name: "Canberra DSS-43",
          metadata: %{"ground_station_id" => "dss-43"}
        })

      assert {:ok, _source_endpoint} =
               Cadence.persist_source_endpoint(org.organization_id, alpha_endpoint)

      assert {:ok, _source_endpoint} =
               Cadence.persist_source_endpoint(org.organization_id, beta_endpoint)

      assert {:ok, _source_endpoint} =
               Cadence.persist_source_endpoint(org.organization_id, gamma_endpoint)

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
            "ground_station_id" => "dss-14"
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
            "ground_station_id" => "dss-63"
          }
        })

      gamma_transport =
        Transport.new(%{
          transport_id: "dashboard-transport-gamma",
          mission_id: mission.mission_id,
          display_name: "Gamma TCP",
          transport_kind: :tcp_socket,
          direction_capability: :bidirectional,
          adapter_key: :tcp_socket,
          configuration: %{
            "mode" => "connect",
            "direction_capability" => "bidirectional",
            "host" => "gamma.ground.example",
            "port" => "5002",
            "framing_mode" => "raw",
            "tls_enabled" => "false"
          },
          metadata: %{
            "source_endpoint_id" => gamma_endpoint.source_endpoint_id,
            "ground_station_id" => "dss-43"
          }
        })

      assert {:ok, _transport} = Cadence.persist_transport(org.organization_id, alpha_transport)
      assert {:ok, _transport} = Cadence.persist_transport(org.organization_id, beta_transport)
      assert {:ok, _transport} = Cadence.persist_transport(org.organization_id, gamma_transport)

      dashboard =
        TestFixtures.persist_dashboard_document!(mission,
          name: "Multi Source Endpoint Connection State",
          widgets: [
            %{
              type: :status_matrix,
              title: "Connection State",
              binding: %{
                source: :operational_observables,
                observables: ["comms.transport.connection_state"]
              }
            }
          ]
        )

      document =
        org
        |> fetch_dashboard_document!(mission, dashboard)
        |> then(fn document ->
          %Document{} = document

          %Document{
            document
            | defaults: %{
                "scope" => %{
                  "primary" => %{
                    "kind" => "source_endpoint",
                    "mode" => "many",
                    "ids" => [
                      alpha_endpoint.source_endpoint_id,
                      beta_endpoint.source_endpoint_id
                    ]
                  }
                }
              }
          }
        end)
        |> then(&replace_dashboard_row_document!(org, mission, &1))

      matrix_widget = render_item_by_title(document, "Connection State").widget

      {:ok, view, _html} = live(conn, show_path(mission, dashboard))
      render_dashboard_async(view)

      assert has_element?(
               view,
               ~s(#ops-dashboard-show-page[data-dashboard-scope-kind="source_endpoint"][data-dashboard-scope-id="#{alpha_endpoint.source_endpoint_id}"])
             )

      alpha_row_selector =
        ~s(#widget-#{matrix_widget.widget_id} [data-status-matrix-row="comms.transport.connection_state:dashboard-transport-alpha"])

      beta_row_selector =
        ~s(#widget-#{matrix_widget.widget_id} [data-status-matrix-row="comms.transport.connection_state:dashboard-transport-beta"])

      gamma_row_selector =
        ~s(#widget-#{matrix_widget.widget_id} [data-status-matrix-row="comms.transport.connection_state:dashboard-transport-gamma"])

      assert has_element?(
               view,
               alpha_row_selector <>
                 ~s([data-status-matrix-source="operational_observables"][data-status-matrix-status-policy="connection_state"][data-status-matrix-resource-id="dashboard-transport-alpha"][data-status-matrix-scope-kind="transport"][data-status-matrix-source-endpoint-id="#{alpha_endpoint.source_endpoint_id}"][data-status-matrix-ground-station-id="dss-14"])
             )

      assert has_element?(
               view,
               beta_row_selector <>
                 ~s([data-status-matrix-source="operational_observables"][data-status-matrix-status-policy="connection_state"][data-status-matrix-resource-id="dashboard-transport-beta"][data-status-matrix-scope-kind="transport"][data-status-matrix-source-endpoint-id="#{beta_endpoint.source_endpoint_id}"][data-status-matrix-ground-station-id="dss-63"])
             )

      assert has_element?(
               view,
               alpha_row_selector <>
                 ~s([data-status-matrix-data-source-id="managed_operational_observables"][data-status-matrix-source-binding-id="default_flight_operational_observables"][data-status-matrix-supported-capability="connection_state"])
             )

      refute has_element?(view, gamma_row_selector)

      stop_dashboard_view(view)
    end

    test "context selector can apply and clear a multi-transport runtime scope" do
      {conn, org, mission} = signed_in_org_and_mission()
      spacecraft = TestFixtures.persist_spacecraft!(mission, display_name: "SC Alpha")

      alpha_transport =
        Transport.new(%{
          transport_id: "dashboard-context-alpha-transport",
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
          metadata: %{"ground_station_id" => "dss-14"}
        })

      beta_transport =
        Transport.new(%{
          transport_id: "dashboard-context-beta-transport",
          mission_id: mission.mission_id,
          display_name: "Alpha Backup TCP",
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
          metadata: %{"ground_station_id" => "dss-63"}
        })

      gamma_transport =
        Transport.new(%{
          transport_id: "dashboard-context-gamma-transport",
          mission_id: mission.mission_id,
          display_name: "Gamma TCP",
          transport_kind: :tcp_socket,
          direction_capability: :bidirectional,
          adapter_key: :tcp_socket,
          configuration: %{
            "mode" => "connect",
            "direction_capability" => "bidirectional",
            "host" => "gamma.ground.example",
            "port" => "5002",
            "framing_mode" => "raw",
            "tls_enabled" => "false"
          },
          metadata: %{"ground_station_id" => "dss-43"}
        })

      assert {:ok, _transport} = Cadence.persist_transport(org.organization_id, alpha_transport)
      assert {:ok, _transport} = Cadence.persist_transport(org.organization_id, beta_transport)
      assert {:ok, _transport} = Cadence.persist_transport(org.organization_id, gamma_transport)

      dashboard =
        TestFixtures.persist_dashboard_document!(mission,
          name: "Multi Transport Context Control",
          widgets: [value_tile("HK.counter", :context, spacecraft.spacecraft_id)]
        )

      {:ok, view, _html} = live(conn, show_path(mission, dashboard))
      render_dashboard_async(view)

      view |> element("#context-search-form") |> render_change(%{"q" => "Alpha"})

      expected_scope_ids =
        "#{beta_transport.transport_id},#{alpha_transport.transport_id}"

      assert has_element?(
               view,
               ~s(button[data-dashboard-context-batch-result="transport"][data-dashboard-context-batch-count="2"][data-dashboard-context-batch-ids="#{expected_scope_ids}"])
             )

      refute has_element?(
               view,
               ~s(button[data-dashboard-context-batch-result="transport"][data-dashboard-context-batch-ids*="#{gamma_transport.transport_id}"])
             )

      view
      |> element(~s(button[data-dashboard-context-batch-result="transport"]))
      |> render_click()

      patched_path = assert_patch(view)
      assert patched_path =~ "scope_kind=transport"
      assert patched_path =~ "scope_ids=#{URI.encode_www_form(expected_scope_ids)}"
      refute patched_path =~ "scope_id="

      render_dashboard_async(view)

      assert has_element?(
               view,
               ~s(#ops-dashboard-show-page[data-dashboard-scope-kind="transport"][data-dashboard-scope-id="#{beta_transport.transport_id}"][data-dashboard-scope-ids="#{expected_scope_ids}"])
             )

      assert has_element?(
               view,
               ~s(#dashboard-selected-context[data-dashboard-selected-context-kind="transport"][data-dashboard-selected-context-id="#{beta_transport.transport_id}"][data-dashboard-selected-context-ids="#{expected_scope_ids}"]),
               "2 transports"
             )

      view |> element(~s(button[aria-label="Clear context"])) |> render_click()

      cleared_path = assert_patch(view)
      refute cleared_path =~ "scope_kind="
      refute cleared_path =~ "scope_id="
      refute cleared_path =~ "scope_ids="

      render_dashboard_async(view)

      refute has_element?(view, "#dashboard-selected-context")
      stop_dashboard_view(view)
    end

    test "source endpoint scope filters operational observable transport rows" do
      enable_dashboard_engine_inline_resolves!()

      {conn, org, mission} = signed_in_org_and_mission()

      alpha_endpoint =
        SourceEndpoint.new(%{
          source_endpoint_id: "dashboard-source-endpoint-alpha",
          mission_id: mission.mission_id,
          display_name: "Goldstone DSS-14",
          metadata: %{"ground_station_id" => "dss-14"}
        })

      beta_endpoint =
        SourceEndpoint.new(%{
          source_endpoint_id: "dashboard-source-endpoint-beta",
          mission_id: mission.mission_id,
          display_name: "Madrid DSS-63",
          metadata: %{"ground_station_id" => "dss-63"}
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
            "ground_station_id" => "dss-14"
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
            "ground_station_id" => "dss-63"
          }
        })

      assert {:ok, _transport} = Cadence.persist_transport(org.organization_id, alpha_transport)
      assert {:ok, _transport} = Cadence.persist_transport(org.organization_id, beta_transport)

      dashboard =
        TestFixtures.persist_dashboard_document!(mission,
          name: "Source Endpoint Connection State",
          widgets: [
            %{
              type: :status_matrix,
              title: "Connection State",
              binding: %{
                source: :operational_observables,
                observables: ["comms.transport.connection_state"]
              }
            }
          ]
        )

      document = fetch_dashboard_document!(org, mission, dashboard)
      matrix_widget = render_item_by_title(document, "Connection State").widget

      {:ok, view, _html} =
        live(
          conn,
          show_path(mission, dashboard) <>
            "?scope_kind=source_endpoint&scope_id=#{alpha_endpoint.source_endpoint_id}"
        )

      render_dashboard_async(view)

      assert has_element?(
               view,
               ~s(#ops-dashboard-show-page[data-dashboard-scope-kind="source_endpoint"][data-dashboard-scope-id="#{alpha_endpoint.source_endpoint_id}"])
             )

      alpha_row_selector =
        ~s(#widget-#{matrix_widget.widget_id} [data-status-matrix-row="comms.transport.connection_state:dashboard-transport-alpha"])

      beta_row_selector =
        ~s(#widget-#{matrix_widget.widget_id} [data-status-matrix-row="comms.transport.connection_state:dashboard-transport-beta"])

      assert has_element?(
               view,
               alpha_row_selector <>
                 ~s([data-status-matrix-source="operational_observables"][data-status-matrix-status-policy="connection_state"][data-status-matrix-resource-id="dashboard-transport-alpha"][data-status-matrix-scope-kind="transport"][data-status-matrix-source-endpoint-id="#{alpha_endpoint.source_endpoint_id}"][data-status-matrix-ground-station-id="dss-14"])
             )

      assert has_element?(
               view,
               alpha_row_selector <>
                 ~s([data-status-matrix-data-source-id="managed_operational_observables"][data-status-matrix-source-binding-id="default_flight_operational_observables"][data-status-matrix-supported-capability="connection_state"])
             )

      assert has_element?(
               view,
               alpha_row_selector <>
                 ~s( [data-status-matrix-row-link="comms.transport.connection_state:dashboard-transport-alpha"][data-status-matrix-row-link-target="transport"][data-status-matrix-row-link-id="dashboard-transport-alpha"][phx-value-data-source-id="managed_operational_observables"][phx-value-source-binding-id="default_flight_operational_observables"])
             )

      refute has_element?(view, beta_row_selector)

      view
      |> element(
        alpha_row_selector <>
          ~s( [data-status-matrix-row-link="comms.transport.connection_state:dashboard-transport-alpha"][data-status-matrix-row-link-target="transport"])
      )
      |> render_click()

      transport_link_path = assert_patch(view)
      assert transport_link_path =~ "panel=data_link"
      assert transport_link_path =~ "selected_target=transport"
      assert transport_link_path =~ "selected_id=dashboard-transport-alpha"
      assert transport_link_path =~ "scope_kind=source_endpoint"
      assert transport_link_path =~ "scope_id=#{alpha_endpoint.source_endpoint_id}"
      assert transport_link_path =~ "realm=flight"
      assert transport_link_path =~ "data_source_id=managed_operational_observables"
      assert transport_link_path =~ "source_binding_id=default_flight_operational_observables"

      assert has_element?(
               view,
               ~s(#dashboard-data-link-inspector[data-data-link-target="transport"][data-data-link-status="resolved"])
             )

      assert has_element?(
               view,
               ~s(#dashboard-data-link-inspector [data-data-link-context="Data source"]),
               "managed_operational_observables"
             )

      assert has_element?(
               view,
               ~s(#dashboard-data-link-copy-link[data-clipboard-text*="scope_kind=source_endpoint"][data-clipboard-text*="scope_id=dashboard-source-endpoint-alpha"][data-clipboard-text*="selected_target=transport"][data-clipboard-text*="selected_id=dashboard-transport-alpha"][data-clipboard-text*="data_source_id=managed_operational_observables"][data-clipboard-text*="source_binding_id=default_flight_operational_observables"])
             )

      stop_dashboard_view(view)
    end

    test "transport scope filters operational observable rows and resolves setup DataLink" do
      enable_dashboard_engine_inline_resolves!()

      {conn, org, mission} = signed_in_org_and_mission()

      alpha_endpoint =
        SourceEndpoint.new(%{
          source_endpoint_id: "dashboard-source-endpoint-alpha",
          mission_id: mission.mission_id,
          display_name: "Goldstone DSS-14",
          metadata: %{"ground_station_id" => "dss-14"}
        })

      beta_endpoint =
        SourceEndpoint.new(%{
          source_endpoint_id: "dashboard-source-endpoint-beta",
          mission_id: mission.mission_id,
          display_name: "Madrid DSS-63",
          metadata: %{"ground_station_id" => "dss-63"}
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
            "ground_station_id" => "dss-14"
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
            "ground_station_id" => "dss-63"
          }
        })

      assert {:ok, _transport} = Cadence.persist_transport(org.organization_id, alpha_transport)
      assert {:ok, _transport} = Cadence.persist_transport(org.organization_id, beta_transport)

      dashboard =
        TestFixtures.persist_dashboard_document!(mission,
          name: "Transport Connection State",
          widgets: [
            %{
              type: :status_matrix,
              title: "Connection State",
              binding: %{
                source: :operational_observables,
                observables: ["comms.transport.connection_state"]
              }
            }
          ]
        )

      document = fetch_dashboard_document!(org, mission, dashboard)
      matrix_widget = render_item_by_title(document, "Connection State").widget

      {:ok, view, _html} =
        live(
          conn,
          show_path(mission, dashboard) <>
            "?scope_kind=transport&scope_id=#{alpha_transport.transport_id}"
        )

      render_dashboard_async(view)

      assert has_element?(
               view,
               ~s(#ops-dashboard-show-page[data-dashboard-scope-kind="transport"][data-dashboard-scope-id="#{alpha_transport.transport_id}"])
             )

      alpha_row_selector =
        ~s(#widget-#{matrix_widget.widget_id} [data-status-matrix-row="comms.transport.connection_state:dashboard-transport-alpha"])

      beta_row_selector =
        ~s(#widget-#{matrix_widget.widget_id} [data-status-matrix-row="comms.transport.connection_state:dashboard-transport-beta"])

      assert has_element?(
               view,
               alpha_row_selector <>
                 ~s([data-status-matrix-source="operational_observables"][data-status-matrix-status-policy="connection_state"][data-status-matrix-resource-id="dashboard-transport-alpha"][data-status-matrix-scope-kind="transport"][data-status-matrix-source-endpoint-id="#{alpha_endpoint.source_endpoint_id}"][data-status-matrix-ground-station-id="dss-14"])
             )

      assert has_element?(
               view,
               alpha_row_selector <>
                 ~s([data-status-matrix-data-source-id="managed_operational_observables"][data-status-matrix-source-binding-id="default_flight_operational_observables"][data-status-matrix-supported-capability="connection_state"])
             )

      assert has_element?(
               view,
               alpha_row_selector <>
                 ~s( [data-status-matrix-row-link="comms.transport.connection_state:dashboard-transport-alpha"][data-status-matrix-row-link-target="transport"][data-status-matrix-row-link-id="dashboard-transport-alpha"][phx-value-target="transport"][phx-value-target-id="dashboard-transport-alpha"][phx-value-data-source-id="managed_operational_observables"][phx-value-source-binding-id="default_flight_operational_observables"])
             )

      refute has_element?(view, beta_row_selector)

      view
      |> element(
        alpha_row_selector <>
          ~s( [data-status-matrix-row-link="comms.transport.connection_state:dashboard-transport-alpha"][data-status-matrix-row-link-target="transport"])
      )
      |> render_click()

      transport_link_path = assert_patch(view)
      assert transport_link_path =~ "panel=data_link"
      assert transport_link_path =~ "selected_target=transport"
      assert transport_link_path =~ "selected_id=dashboard-transport-alpha"
      assert transport_link_path =~ "scope_kind=transport"
      assert transport_link_path =~ "scope_id=dashboard-transport-alpha"
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
               ~s(#dashboard-data-link-copy-link[data-clipboard-text*="scope_kind=transport"][data-clipboard-text*="scope_id=dashboard-transport-alpha"][data-clipboard-text*="selected_target=transport"][data-clipboard-text*="selected_id=dashboard-transport-alpha"][data-clipboard-text*="data_source_id=managed_operational_observables"][data-clipboard-text*="source_binding_id=default_flight_operational_observables"])
             )

      stop_dashboard_view(view)
    end

    test "link scope filters operational observable rows and preserves setup DataLink context" do
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
            }
          ]
        )

      document = fetch_dashboard_document!(org, mission, dashboard)
      matrix_widget = render_item_by_title(document, "RF Lock").widget

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
        ~s(#widget-#{matrix_widget.widget_id} [data-status-matrix-row="link.rf_lock_state:link-alpha"])

      beta_row_selector =
        ~s(#widget-#{matrix_widget.widget_id} [data-status-matrix-row="link.rf_lock_state:link-beta"])

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

    test "ground station scope filters operational observable rows and resolves setup DataLink" do
      enable_dashboard_engine_inline_resolves!()

      {conn, org, mission} = signed_in_org_and_mission()

      dss_14 =
        GroundStation.new(%{
          ground_station_id: "dss-14",
          mission_id: mission.mission_id,
          display_name: "Goldstone DSS-14",
          provider: "DSN",
          region: "California",
          metadata: %{
            "source_endpoint_id" => "dashboard-source-endpoint-alpha",
            "transport_id" => "dashboard-transport-alpha"
          }
        })

      dss_63 =
        GroundStation.new(%{
          ground_station_id: "dss-63",
          mission_id: mission.mission_id,
          display_name: "Madrid DSS-63",
          provider: "DSN",
          region: "Madrid",
          metadata: %{
            "source_endpoint_id" => "dashboard-source-endpoint-beta",
            "transport_id" => "dashboard-transport-beta"
          }
        })

      assert {:ok, _ground_station} = Cadence.persist_ground_station(org.organization_id, dss_14)
      assert {:ok, _ground_station} = Cadence.persist_ground_station(org.organization_id, dss_63)

      alpha_endpoint =
        SourceEndpoint.new(%{
          source_endpoint_id: "dashboard-source-endpoint-alpha",
          mission_id: mission.mission_id,
          display_name: "Goldstone DSS-14",
          metadata: %{"ground_station_id" => dss_14.ground_station_id}
        })

      beta_endpoint =
        SourceEndpoint.new(%{
          source_endpoint_id: "dashboard-source-endpoint-beta",
          mission_id: mission.mission_id,
          display_name: "Madrid DSS-63",
          metadata: %{"ground_station_id" => dss_63.ground_station_id}
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
            "ground_station_id" => dss_14.ground_station_id
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
            "ground_station_id" => dss_63.ground_station_id
          }
        })

      assert {:ok, _transport} = Cadence.persist_transport(org.organization_id, alpha_transport)
      assert {:ok, _transport} = Cadence.persist_transport(org.organization_id, beta_transport)

      dashboard =
        TestFixtures.persist_dashboard_document!(mission,
          name: "Ground Station Connection State",
          widgets: [
            %{
              type: :status_matrix,
              title: "Connection State",
              binding: %{
                source: :operational_observables,
                observables: [
                  "comms.transport.connection_state",
                  "ground.station.connection_state"
                ]
              }
            }
          ]
        )

      document = fetch_dashboard_document!(org, mission, dashboard)
      matrix_widget = render_item_by_title(document, "Connection State").widget

      {:ok, view, _html} =
        live(
          conn,
          show_path(mission, dashboard) <>
            "?scope_kind=ground_station&scope_id=#{dss_14.ground_station_id}"
        )

      render_dashboard_async(view)

      assert has_element?(
               view,
               ~s(#ops-dashboard-show-page[data-dashboard-scope-kind="ground_station"][data-dashboard-scope-id="#{dss_14.ground_station_id}"])
             )

      ground_station_row_selector =
        ~s(#widget-#{matrix_widget.widget_id} [data-status-matrix-row="ground.station.connection_state:dss-14"])

      alpha_transport_row_selector =
        ~s(#widget-#{matrix_widget.widget_id} [data-status-matrix-row="comms.transport.connection_state:dashboard-transport-alpha"])

      beta_transport_row_selector =
        ~s(#widget-#{matrix_widget.widget_id} [data-status-matrix-row="comms.transport.connection_state:dashboard-transport-beta"])

      beta_ground_station_row_selector =
        ~s(#widget-#{matrix_widget.widget_id} [data-status-matrix-row="ground.station.connection_state:dss-63"])

      assert has_element?(
               view,
               ground_station_row_selector <>
                 ~s([data-status-matrix-source="operational_observables"][data-status-matrix-status-policy="connection_state"][data-status-matrix-resource-id="dss-14"][data-status-matrix-scope-kind="ground_station"][data-status-matrix-source-endpoint-id="#{alpha_endpoint.source_endpoint_id}"][data-status-matrix-ground-station-id="dss-14"])
             )

      assert has_element?(
               view,
               alpha_transport_row_selector <>
                 ~s([data-status-matrix-resource-id="dashboard-transport-alpha"][data-status-matrix-scope-kind="transport"][data-status-matrix-source-endpoint-id="#{alpha_endpoint.source_endpoint_id}"][data-status-matrix-ground-station-id="dss-14"])
             )

      refute has_element?(view, beta_transport_row_selector)
      refute has_element?(view, beta_ground_station_row_selector)

      assert has_element?(
               view,
               ground_station_row_selector <>
                 ~s( [data-status-matrix-row-link="ground.station.connection_state:dss-14"][data-status-matrix-row-link-target="ground station"][data-status-matrix-row-link-id="dss-14"][phx-value-target="ground_station"][phx-value-target-id="dss-14"][phx-value-data-source-id="managed_operational_observables"][phx-value-source-binding-id="default_flight_operational_observables"])
             )

      view
      |> element(
        ground_station_row_selector <>
          ~s( [data-status-matrix-row-link="ground.station.connection_state:dss-14"][data-status-matrix-row-link-target="ground station"])
      )
      |> render_click()

      ground_station_link_path = assert_patch(view)
      assert ground_station_link_path =~ "panel=data_link"
      assert ground_station_link_path =~ "selected_target=ground_station"
      assert ground_station_link_path =~ "selected_id=dss-14"
      assert ground_station_link_path =~ "scope_kind=ground_station"
      assert ground_station_link_path =~ "scope_id=dss-14"
      assert ground_station_link_path =~ "realm=flight"
      assert ground_station_link_path =~ "data_source_id=managed_operational_observables"

      assert ground_station_link_path =~
               "source_binding_id=default_flight_operational_observables"

      assert has_element?(
               view,
               ~s(#dashboard-data-link-inspector[data-data-link-target="ground_station"][data-data-link-status="resolved"])
             )

      assert has_element?(
               view,
               ~s(#dashboard-data-link-inspector [data-data-link-field="Display name"]),
               "Goldstone DSS-14"
             )

      assert has_element?(
               view,
               ~s(#dashboard-data-link-copy-link[data-clipboard-text*="scope_kind=ground_station"][data-clipboard-text*="scope_id=dss-14"][data-clipboard-text*="selected_target=ground_station"][data-clipboard-text*="selected_id=dss-14"][data-clipboard-text*="data_source_id=managed_operational_observables"][data-clipboard-text*="source_binding_id=default_flight_operational_observables"])
             )

      stop_dashboard_view(view)
    end

    test "ticks push chart appends for new samples only" do
      disable_telemetry_storage_runtime_invalidation!()

      {conn, org, mission} = signed_in_org_and_mission()
      spacecraft = TestFixtures.persist_spacecraft!(mission, display_name: "SC Beta")
      binding_set = persist_binding_set!(org, mission)

      ingest!(mission, binding_set, spacecraft.spacecraft_id, 5, 1_700_000_100,
        dashboard_runtime_invalidation?: false
      )

      dashboard =
        TestFixtures.persist_dashboard_document!(mission,
          name: "Trend",
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

      {:ok, view, _html} = live(conn, show_path(mission, dashboard))
      render_dashboard_async(view)

      assert {:ok, document} =
               Cadence.Dashboards.fetch_document(
                 org.organization_id,
                 mission.mission_id,
                 dashboard.dashboard_id
               )

      assert [%{placement_id: placement_id}] = document.placements

      # The mount-time sample is already in the chart backfill — the first
      # tick must NOT re-append it as a duplicate point.
      send(view.pid, :tick)
      render_dashboard_async(view)
      refute_push_event(view, "tlm:append", %{"series" => %{^placement_id => _data}})

      ingest!(mission, binding_set, spacecraft.spacecraft_id, 7, 1_700_000_110,
        dashboard_runtime_invalidation?: false
      )

      send(view.pid, :tick)
      render_dashboard_async(view)

      assert_push_event(
        view,
        "tlm:append",
        %{
          "series" => %{
            ^placement_id => %{
              version: 1,
              series: [
                %{
                  id: "HK.counter",
                  observable_id: "HK.counter",
                  points: [[_ts, 7, %{sample_id: sample_id, link_id: link_id}]]
                }
              ]
            }
          }
        },
        1_000
      )

      assert is_binary(sample_id)
      assert is_binary(link_id)

      send(view.pid, :tick)
      render_dashboard_async(view)
      refute_push_event(view, "tlm:append", %{"series" => %{^placement_id => _data}})
    end

    test "ticks run conservative dashboard engine live refresh" do
      disable_telemetry_storage_runtime_invalidation!()
      enable_dashboard_runtime_cache!()

      {conn, org, mission} = signed_in_org_and_mission()
      spacecraft = TestFixtures.persist_spacecraft!(mission, display_name: "SC Engine")
      binding_set = persist_binding_set!(org, mission)

      ingest!(mission, binding_set, spacecraft.spacecraft_id, 5, 1_700_000_100,
        dashboard_runtime_invalidation?: false
      )

      dashboard =
        TestFixtures.persist_dashboard_document!(mission,
          name: "Engine Tick",
          widgets: [
            value_tile("HK.counter", :fixed, spacecraft.spacecraft_id),
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

      {:ok, view, _html} = live(conn, show_path(mission, dashboard))
      render_dashboard_async(view)

      assert has_element?(
               view,
               ~s(#ops-dashboard-show-page[data-engine-resolve-mode="initial"])
             )

      assert has_element?(
               view,
               ~s(#ops-dashboard-show-page[data-runtime-status="idle"][data-runtime-decision-actions="start_resolve accept_result"][data-runtime-resolved="true"])
             )

      assert has_element?(view, ~s([data-engine-backed="true"]))

      assert has_element?(
               view,
               ~s([phx-hook="TelemetryChart"][data-engine-backed="true"])
             )

      assert render(view) =~ "5"

      ingest!(mission, binding_set, spacecraft.spacecraft_id, 9, 1_700_000_110,
        dashboard_runtime_invalidation?: false
      )

      send(view.pid, :tick)
      render_dashboard_async(view)

      assert has_element?(
               view,
               ~s(#ops-dashboard-show-page[data-engine-resolve-mode="live_tick"][data-engine-source-requests="3"][data-engine-executed-source-requests="2"][data-engine-skipped-source-requests="1"])
             )

      assert has_element?(
               view,
               ~s(#ops-dashboard-show-page[data-runtime-refresh-status="settled"][data-runtime-refresh-reason="accepted"][data-runtime-visible-refresh-action="accept_result"][data-runtime-refresh-starts="live_tick:tick:1"][data-runtime-canceled-resolves="0"][data-runtime-failed-resolves="0"])
             )

      assert has_element?(
               view,
               ~s(#ops-dashboard-show-page[data-runtime-last-refresh-duration-ms])
             )

      assert has_element?(
               view,
               ~s(#ops-dashboard-show-page[data-engine-source-cache-statuses*="stale"][data-engine-frame-cache-statuses*="refresh"])
             )

      assert has_element?(
               view,
               ~s(#dashboard-source-health[data-source-execution*="Limits:cache_stale"])
             )

      assert has_element?(
               view,
               ~s(#dashboard-source-health[data-source-execution-severity*="Limits:warning"][data-source-execution-action*="Limits:wait_for_refresh"])
             )

      view
      |> element("#dashboard-diagnostics-button")
      |> render_click()

      assert has_element?(
               view,
               ~s(#dashboard-cache-summary[data-cache-classification="stale"][data-cache-source*="stale"][data-cache-frame*="refresh"])
             )

      assert has_element?(
               view,
               ~s(#dashboard-cache-summary [data-cache-field="Source"]),
               "stale"
             )

      assert has_element?(
               view,
               ~s(#dashboard-cache-evidence[data-cache-evidence-count][data-cache-evidence-resolved][data-cache-evidence-context-only][data-cache-evidence-missing])
             )

      assert has_element?(
               view,
               ~s(#dashboard-cache-evidence [data-cache-evidence-state-field="Resolved"])
             )

      assert has_element?(
               view,
               ~s(#dashboard-cache-evidence [data-cache-evidence-layer="source"][data-cache-evidence-status="stale"][data-cache-evidence-state="resolved"][data-cache-evidence-request-id][data-cache-evidence-source-binding-id][data-cache-evidence-data-source-id])
             )

      assert has_element?(
               view,
               ~s(#dashboard-cache-evidence [data-cache-evidence-layer="source"][data-cache-evidence-status="stale"][data-cache-evidence-incident-status="cache_stale"][data-cache-evidence-incident-severity="warning"][data-cache-evidence-incident-action="wait_for_refresh"])
             )

      assert has_element?(
               view,
               ~s(#dashboard-cache-evidence [data-cache-evidence-field="Action"]),
               "wait_for_refresh"
             )

      assert has_element?(
               view,
               ~s(#dashboard-cache-evidence [data-cache-evidence-layer="frame"][data-cache-evidence-status="refresh"][data-cache-evidence-request-id][data-cache-evidence-placement-id])
             )

      view
      |> element(
        ~s(#dashboard-cache-evidence [data-cache-evidence-layer="source"][data-cache-evidence-status="stale"][data-cache-evidence-source="limits"] [data-cache-evidence-open])
      )
      |> render_click()

      source_evidence_path = assert_patch(view)
      assert source_evidence_path =~ "panel=evidence"
      assert source_evidence_path =~ "selected_evidence_kind=source"
      assert source_evidence_path =~ "selected_source_evidence_mode=execution"
      assert source_evidence_path =~ "selected_source_request="
      assert source_evidence_path =~ "selected_logical_source=limits"
      assert source_evidence_path =~ "selected_requested_data_source="
      refute source_evidence_path =~ "selected_target="

      assert has_element?(
               view,
               ~s(#dashboard-evidence-inspector[data-evidence-kind="source"][data-evidence-status="cache_stale"])
             )

      assert has_element?(
               view,
               ~s(#dashboard-evidence-inspector [data-evidence-detail="Execution status"]),
               "cache_stale"
             )

      assert has_element?(
               view,
               ~s(#dashboard-evidence-copy-link[data-clipboard-text*="panel=evidence"][data-clipboard-text*="selected_evidence_kind=source"][data-clipboard-text*="selected_source_request="])
             )

      {:ok, context_only_view, _html} =
        live(
          conn,
          show_path(mission, dashboard) <>
            "?panel=evidence&selected_evidence_kind=source&selected_source_evidence_mode=health&selected_source_evidence_state=context_only&selected_cache_evidence_layer=source&selected_cache_evidence_status=hit&selected_cache_evidence_reasons=operator_requested&selected_source_request=missing-cache-source&selected_logical_source=telemetry&selected_realm=flight&selected_data_source=managed_questdb_primary&selected_source_binding=default_flight_telemetry"
        )

      render_dashboard_async(context_only_view)

      assert has_element?(
               context_only_view,
               ~s(#dashboard-evidence-inspector[data-evidence-kind="source"][data-evidence-status="context_only"])
             )

      assert has_element?(
               context_only_view,
               ~s(#dashboard-evidence-inspector [data-evidence-subject-field="Source request"]),
               "missing-cache-source"
             )

      assert has_element?(
               context_only_view,
               ~s(#dashboard-evidence-inspector [data-evidence-detail="Cache evidence status"]),
               "hit"
             )

      assert has_element?(
               context_only_view,
               ~s(#dashboard-evidence-copy-link[data-clipboard-text*="selected_source_evidence_state=context_only"][data-clipboard-text*="selected_cache_evidence_status=hit"])
             )

      assert has_element?(
               view,
               ~s(#ops-dashboard-show-page[data-runtime-source-execution-actions="refresh_source_result:2"][data-runtime-source-execution-retryable="2"][data-runtime-source-execution-actionable="0"][data-runtime-source-execution-degraded="0"])
             )

      assert has_element?(
               view,
               ~s(#ops-dashboard-show-page[data-runtime-status="idle"][data-runtime-decision-actions="start_resolve accept_result"][data-runtime-resolved="true"])
             )

      assert has_element?(view, ~s([data-engine-backed="true"]))
      assert render(view) =~ "9"
    end

    test "URL runtime params drive dashboard engine contexts" do
      {conn, org, mission} = signed_in_org_and_mission()
      spacecraft = TestFixtures.persist_spacecraft!(mission, display_name: "SC Runtime")
      binding_set = persist_binding_set!(org, mission)
      ingest!(mission, binding_set, spacecraft.spacecraft_id, 5, 1_700_000_100)
      widget = value_tile("HK.counter", :fixed, spacecraft.spacecraft_id)

      dashboard =
        TestFixtures.persist_dashboard_document!(mission,
          name: "Runtime",
          widgets: [widget]
        )

      document = fetch_dashboard_document!(org, mission, dashboard)
      runtime_item = render_item_by_title(document, "Counter")

      {:ok, view, _html} =
        live(
          conn,
          show_path(mission, dashboard) <>
            "?time_mode=archive&time_axis=generation_time&from=2026-06-17T12:00:00Z&to=2026-06-17T12:05:00Z&limit_mode=current&data_view=all_revisions&compare_data_view=canonical"
        )

      render_dashboard_async(view)

      assert has_element?(
               view,
               ~s(#ops-dashboard-show-page[data-dashboard-time-mode="archive"][data-dashboard-time-axis="generation_time"][data-engine-time-mode="archive"][data-engine-time-axis="generation_time"][data-dashboard-data-view="all_revisions"][data-dashboard-compare-data-view="canonical"][data-engine-data-view="all_revisions"][data-compare-engine-data-view="canonical"][data-dashboard-limit-mode="current"][data-engine-limit-mode="current"])
             )

      assert has_element?(view, ~s|#dashboard-time-axis option[value="generation_time"]|)
      assert has_element?(view, ~s|#dashboard-time-axis option[value="receipt_time"]|)
      assert has_element?(view, ~s|#dashboard-data-view option[value="all_revisions"]|)
      assert has_element?(view, ~s|#dashboard-compare-data-view option[value="canonical"]|)

      assert has_element?(
               view,
               ~s(#widget-#{runtime_item.widget.widget_id} [data-engine-warning="all_revisions_view"]),
               "All revisions"
             )

      assert has_element?(
               view,
               ~s(#widget-#{runtime_item.widget.widget_id} [data-data-management-badges*="all_revisions"])
             )

      assert has_element?(
               view,
               ~s|#dashboard-limit-mode option[value="observed"]:not([disabled])|
             )

      assert has_element?(view, ~s|#dashboard-limit-mode option[value="current"]:not([disabled])|)

      assert has_element?(
               view,
               ~s|#dashboard-limit-mode option[value="recomputed"]:not([disabled])|
             )

      assert has_element?(view, ~s|#dashboard-limit-mode option[value="compare"]:not([disabled])|)

      refute has_element?(
               view,
               ~s(#dashboard-limit-mode-fallback[data-requested-limit-mode="current"])
             )

      send(view.pid, :tick)
      render(view)

      assert has_element?(
               view,
               ~s(#ops-dashboard-show-page[data-runtime-status="idle"][data-runtime-decision-actions="noop"][data-runtime-resolved="true"])
             )

      assert has_element?(
               view,
               ~s(#ops-dashboard-show-page[data-runtime-refresh-status="suppressed"][data-runtime-refresh-reason="not_live_time_mode"][data-runtime-visible-refresh-action="noop"][data-runtime-refresh-noops="live_tick:not_live_time_mode:1"][data-runtime-canceled-resolves="0"][data-runtime-failed-resolves="0"])
             )

      view
      |> element("#runtime-context-form")
      |> render_change(%{
        "time_mode" => "live",
        "from" => "2026-06-17T12:00:00Z",
        "to" => "2026-06-17T12:05:00Z",
        "realm" => "flight",
        "data_view" => "canonical",
        "compare_data_view" => "",
        "limit_mode" => "observed"
      })

      assert_patch(view, show_path(mission, dashboard))

      render_dashboard_async(view)

      assert has_element?(
               view,
               ~s(#ops-dashboard-show-page[data-dashboard-time-mode="live"][data-engine-time-mode="live"][data-dashboard-data-view="canonical"][data-engine-data-view="canonical"][data-engine-limit-mode="observed"])
             )

      {:ok, invalid_view, _html} =
        live(conn, show_path(mission, dashboard) <> "?data_view=unsupported")

      render_dashboard_async(invalid_view)

      assert has_element?(
               invalid_view,
               ~s(#ops-dashboard-show-page[data-dashboard-data-view="canonical"][data-engine-data-view="canonical"])
             )
    end

    test "runtime context precedence composes document defaults URL params and live controls" do
      {conn, org, mission} = signed_in_org_and_mission()
      spacecraft = TestFixtures.persist_spacecraft!(mission, display_name: "SC Precedence")
      binding_set = persist_binding_set!(org, mission)
      unique = System.unique_integer([:positive])

      rehearsal_source =
        persist_dashboard_realm_source!(
          mission,
          :rehearsal,
          "precedence-rehearsal-source-#{unique}",
          "precedence-rehearsal-binding-#{unique}"
        )

      replay_source =
        persist_dashboard_realm_source!(
          mission,
          :replay,
          "precedence-replay-source-#{unique}",
          "precedence-replay-binding-#{unique}"
        )

      configure_telemetry_storage_source!(
        :rehearsal,
        rehearsal_source.data_source_id,
        rehearsal_source.binding_id
      )

      ingest!(mission, binding_set, spacecraft.spacecraft_id, 17, 1_700_000_100)

      dashboard =
        TestFixtures.persist_dashboard_document!(mission,
          name: "Runtime Precedence",
          widgets: [value_tile("HK.counter", :fixed, spacecraft.spacecraft_id)]
        )

      document =
        org
        |> fetch_dashboard_document!(mission, dashboard)
        |> then(fn document ->
          %Document{} = document

          %Document{
            document
            | defaults: %{
                "data" => %{
                  "realm" => "rehearsal",
                  "view" => "all_revisions",
                  "source_mode" => "specific",
                  "source_contexts" => %{
                    "telemetry" => %{
                      "source_binding_id" => rehearsal_source.binding_id
                    }
                  }
                }
              }
          }
        end)
        |> then(&replace_dashboard_row_document!(org, mission, &1))

      {:ok, defaults_view, _html} = live(conn, show_path(mission, document))
      render_dashboard_async(defaults_view)

      assert has_element?(
               defaults_view,
               ~s(#ops-dashboard-show-page[data-dashboard-data-realm="rehearsal"][data-dashboard-data-view="all_revisions"][data-dashboard-source-binding-id="#{rehearsal_source.binding_id}"][data-engine-data-realm="rehearsal"][data-engine-data-view="all_revisions"][data-engine-source-binding-id="#{rehearsal_source.binding_id}"])
             )

      replay_query =
        URI.encode_query(%{
          scope_kind: "mission",
          scope_id: mission.mission_id,
          time_mode: "replay_run",
          time_axis: "receipt_time",
          replay_run_id: "replay-precedence-1",
          source_binding_id: replay_source.binding_id,
          data_view: "as_recorded",
          compare_data_view: "canonical",
          limit_mode: "current"
        })

      {:ok, view, _html} = live(conn, show_path(mission, dashboard) <> "?#{replay_query}")
      render_dashboard_async(view)

      assert has_element?(
               view,
               ~s(#ops-dashboard-show-page[data-dashboard-scope-kind="mission"][data-dashboard-scope-id="#{mission.mission_id}"][data-dashboard-time-mode="replay_run"][data-dashboard-time-axis="receipt_time"][data-dashboard-replay-run-id="replay-precedence-1"][data-dashboard-data-realm="replay"][data-dashboard-data-view="as_recorded"][data-dashboard-compare-data-view="canonical"][data-dashboard-source-binding-id="#{replay_source.binding_id}"][data-dashboard-limit-mode="current"][data-engine-time-mode="replay_run"][data-engine-time-axis="receipt_time"][data-engine-replay-run-id="replay-precedence-1"][data-engine-data-realm="replay"][data-engine-data-view="as_recorded"][data-engine-source-binding-id="#{replay_source.binding_id}"][data-engine-limit-mode="current"])
             )

      view
      |> element("#runtime-context-form")
      |> render_change(%{
        "time_mode" => "live",
        "time_axis" => "generation_time",
        "from" => "",
        "to" => "",
        "realm" => "rehearsal",
        "source_binding_id" => rehearsal_source.binding_id,
        "data_view" => "canonical",
        "compare_data_view" => "",
        "limit_mode" => "observed"
      })

      patched_path = assert_patch(view)
      assert patched_path =~ "scope_kind=mission"
      assert patched_path =~ "scope_id=#{mission.mission_id}"
      assert patched_path =~ "data_view=canonical"
      assert patched_path =~ "data_source_id=#{rehearsal_source.data_source_id}"
      assert patched_path =~ "source_binding_id=#{rehearsal_source.binding_id}"
      refute patched_path =~ "realm="
      refute patched_path =~ "time_mode="
      refute patched_path =~ "time_axis="
      refute patched_path =~ "replay_run_id="
      refute patched_path =~ "limit_mode="

      render_dashboard_async(view)

      assert has_element?(
               view,
               ~s(#ops-dashboard-show-page[data-dashboard-scope-kind="mission"][data-dashboard-scope-id="#{mission.mission_id}"][data-dashboard-time-mode="live"][data-dashboard-data-realm="rehearsal"][data-dashboard-data-view="canonical"][data-dashboard-source-binding-id="#{rehearsal_source.binding_id}"][data-dashboard-limit-mode="observed"][data-engine-time-mode="live"][data-engine-data-realm="rehearsal"][data-engine-data-view="canonical"][data-engine-source-binding-id="#{rehearsal_source.binding_id}"][data-engine-limit-mode="observed"])
             )
    end

    test "comparison investigation presets can be saved loaded and deleted" do
      {conn, user, org, mission} = signed_in_user_org_and_mission()
      spacecraft = TestFixtures.persist_spacecraft!(mission, display_name: "SC Preset")
      binding_set = persist_binding_set!(org, mission)
      ingest!(mission, binding_set, spacecraft.spacecraft_id, 5, 1_700_000_100)

      dashboard =
        TestFixtures.persist_dashboard_document!(mission,
          name: "Runtime Presets",
          widgets: [value_tile("HK.counter", :fixed, spacecraft.spacecraft_id)]
        )

      {:ok, view, _html} =
        live(
          conn,
          show_path(mission, dashboard) <>
            "?data_view=all_revisions&compare_data_view=canonical"
        )

      render_dashboard_async(view)

      assert has_element?(view, "#dashboard-comparison-preset-form")

      view
      |> form("#dashboard-comparison-preset-form", %{
        "preset" => %{"name" => "All revisions vs canonical"}
      })
      |> render_submit()

      [preset] =
        Cadence.Dashboards.list_dashboard_investigation_presets(
          org.organization_id,
          mission.mission_id,
          dashboard.dashboard_id
        )

      assert preset.created_by == user.user_id
      assert preset.name == "All revisions vs canonical"
      assert preset.runtime_query["data_view"] == "all_revisions"
      assert preset.runtime_query["compare_data_view"] == "canonical"

      assert has_element?(
               view,
               ~s([data-dashboard-comparison-saved-preset="#{preset.dashboard_investigation_preset_id}"])
             )

      view
      |> element("#runtime-context-form")
      |> render_change(%{
        "time_mode" => "live",
        "from" => "",
        "to" => "",
        "realm" => "flight",
        "data_view" => "canonical",
        "compare_data_view" => "",
        "limit_mode" => "observed"
      })

      assert_patch(view, show_path(mission, dashboard))
      render_dashboard_async(view)

      assert has_element?(
               view,
               ~s([data-dashboard-comparison-saved-preset-apply="#{preset.dashboard_investigation_preset_id}"])
             )

      view
      |> element(
        ~s([data-dashboard-comparison-saved-preset-apply="#{preset.dashboard_investigation_preset_id}"])
      )
      |> render_click()

      patched_path = assert_patch(view)
      assert patched_path =~ "data_view=all_revisions"
      assert patched_path =~ "compare_data_view=canonical"

      render_dashboard_async(view)

      view
      |> element(
        ~s([data-dashboard-comparison-saved-preset-delete="#{preset.dashboard_investigation_preset_id}"])
      )
      |> render_click()

      assert [] =
               Cadence.Dashboards.list_dashboard_investigation_presets(
                 org.organization_id,
                 mission.mission_id,
                 dashboard.dashboard_id
               )
    end

    test "replay URL runtime params drive replay contexts without live refresh" do
      {conn, org, mission} = signed_in_org_and_mission()
      spacecraft = TestFixtures.persist_spacecraft!(mission, display_name: "SC Replay")
      _source = persist_dashboard_realm!(mission, :replay)

      replay_run =
        Run.new(%{
          replay_run_id: "replay_run_001",
          mission_id: mission.mission_id,
          binding_set_id: "replay-runtime-binding-set",
          binding_set_version: 1,
          status: :completed,
          replayed_evidence_count: 3,
          replayed_packet_count: 3,
          replayed_sample_count: 2,
          started_at: ~U[2026-06-17 11:59:00Z],
          completed_at: ~U[2026-06-17 12:06:00Z]
        })

      Repo.insert!(ReplayRunRow.changeset(replay_run))

      dashboard =
        TestFixtures.persist_dashboard_document!(mission,
          name: "Replay Runtime",
          widgets: [value_tile("HK.counter", :fixed, spacecraft.spacecraft_id)]
        )

      document = fetch_dashboard_document!(org, mission, dashboard)
      replay_widget = render_item_by_title(document, "Counter").widget

      {:ok, view, _html} =
        live(
          conn,
          show_path(mission, dashboard) <>
            "?time_mode=replay_run&replay_run_id=replay_run_001"
        )

      render_dashboard_async(view)

      assert has_element?(
               view,
               ~s(#ops-dashboard-show-page[data-dashboard-time-mode="replay_run"][data-dashboard-replay-run-id="replay_run_001"][data-dashboard-data-realm="replay"][data-engine-time-mode="replay_run"][data-engine-replay-run-id="replay_run_001"][data-engine-snapshot="true"][data-engine-live-append-eligible="false"])
             )

      assert has_element?(view, ~s(#dashboard-time-mode option[value="replay_run"]))

      assert has_element?(
               view,
               ~s(#dashboard-replay-run-selector option[value="replay_run_001"][selected])
             )

      assert has_element?(
               view,
               ~s(#dashboard-replay-progress-clock[data-dashboard-replay-run-id="replay_run_001"][data-dashboard-replay-run-known="true"][data-dashboard-replay-run-status="completed"][data-dashboard-replay-run-sample-count="2"])
             )

      refute has_element?(view, "#dashboard-replay-metadata-warning")

      view
      |> element("#dashboard-historical-workflow-request-button")
      |> render_click()

      assert has_element?(
               view,
               ~s(input[name="historical_workflow_request[dashboard_time_mode]"][value="replay_run"])
             )

      assert has_element?(
               view,
               ~s(input[name="historical_workflow_request[dashboard_replay_run_id]"][value="replay_run_001"])
             )

      assert has_element?(
               view,
               ~s(input[name="historical_workflow_request[dashboard_limit_mode]"][value="observed"])
             )

      view
      |> element(
        ~s(#widget-#{replay_widget.widget_id} [data-engine-warning-detail="capability_fallback"] [data-warning-link-target="telemetry point"])
      )
      |> render_click()

      assert has_element?(
               view,
               ~s(#dashboard-data-link-inspector[data-data-link-target="telemetry_point"][data-data-link-status="context_only"])
             )

      assert has_element?(
               view,
               ~s(#dashboard-data-link-inspector [data-data-link-context="Time mode"]),
               "replay_run"
             )

      assert has_element?(
               view,
               ~s(#dashboard-data-link-inspector [data-data-link-context="Replay run"]),
               "replay_run_001"
             )

      assert has_element?(
               view,
               ~s(#dashboard-data-link-inspector [data-data-link-context="Data realm"]),
               "replay"
             )

      assert has_element?(
               view,
               ~s(#dashboard-data-link-copy-link[data-clipboard-text*="time_mode=replay_run"][data-clipboard-text*="replay_run_id=replay_run_001"][data-clipboard-text*="selected_target=telemetry_point"])
             )

      assert has_element?(
               view,
               ~s(#dashboard-data-link-explore[href*="time_mode=replay_run"][href*="replay_run_id=replay_run_001"][href*="realm=replay"])
             )

      send(view.pid, :tick)
      render(view)

      assert has_element?(
               view,
               ~s(#ops-dashboard-show-page[data-runtime-refresh-noops*="live_tick:not_live_time_mode"][data-runtime-canceled-resolves="0"][data-runtime-failed-resolves="0"])
             )

      view |> element("#dashboard-time-preset-live") |> render_click()
      assert_patch(view, show_path(mission, dashboard))
      render_dashboard_async(view)

      assert has_element?(
               view,
               ~s(#ops-dashboard-show-page[data-dashboard-time-mode="live"][data-engine-time-mode="live"][data-engine-snapshot="false"][data-engine-live-append-eligible="true"])
             )
    end

    test "replay URL runtime params drive event and operational observable source families" do
      enable_dashboard_engine_inline_resolves!()

      {conn, org, mission} = signed_in_org_and_mission()
      _telemetry_replay_source = persist_dashboard_realm!(mission, :replay)
      replay_sources = persist_replay_event_and_operational_sources!(mission)

      replay_run =
        Run.new(%{
          replay_run_id: "replay_run_events_ops",
          mission_id: mission.mission_id,
          binding_set_id: "replay-events-ops-binding-set",
          binding_set_version: 1,
          status: :completed,
          replayed_evidence_count: 1,
          replayed_packet_count: 0,
          replayed_sample_count: 0,
          started_at: ~U[2026-06-17 11:59:00Z],
          completed_at: ~U[2026-06-17 12:06:00Z]
        })

      Repo.insert!(ReplayRunRow.changeset(replay_run))

      scheduled_contact =
        ScheduledContact.new(%{
          scheduled_contact_id: "dashboard-replay-contact-alpha",
          mission_id: mission.mission_id,
          source_endpoint_refs: ["source-endpoint-alpha"],
          paths: contact_paths("source-endpoint-alpha"),
          starts_at: DateTime.from_unix!(1_700_000_080, :second),
          ends_at: DateTime.from_unix!(1_700_000_220, :second)
        })

      assert {:ok, _scheduled_contact} =
               Cadence.persist_scheduled_contact(org.organization_id, scheduled_contact)

      replay_contact_starts_at = ~U[2026-06-17 12:01:00Z]
      replay_contact_ends_at = ~U[2026-06-17 12:04:00Z]

      assert {:ok, _contact_operational_event} =
               Event.new(%{
                 event_id:
                   "operational_event:scheduled_contact_interval:#{scheduled_contact.scheduled_contact_id}:replay_run_events_ops",
                 organization_id: org.organization_id,
                 mission_id: mission.mission_id,
                 occurred_at: replay_contact_starts_at,
                 recorded_at: replay_contact_starts_at,
                 effective_at: replay_contact_starts_at,
                 category: :contact,
                 kind: :scheduled_contact_interval,
                 severity: :info,
                 actor: %{kind: :replay, id: "replay_run_events_ops"},
                 subject: %{kind: :contact, id: scheduled_contact.scheduled_contact_id},
                 scope: %{
                   replay_run_id: "replay_run_events_ops",
                   source_endpoint_ref: "source-endpoint-alpha"
                 },
                 causality: %{
                   correlation_id: scheduled_contact.scheduled_contact_id,
                   replay_run_id: "replay_run_events_ops"
                 },
                 payload: %{
                   scheduled_contact_id: scheduled_contact.scheduled_contact_id,
                   starts_at: replay_contact_starts_at,
                   ends_at: replay_contact_ends_at,
                   status: :scheduled,
                   source_endpoint_refs: scheduled_contact.source_endpoint_refs
                 }
               })
               |> OperationalEvents.persist_event()

      dashboard =
        TestFixtures.persist_dashboard_document!(mission,
          name: "Replay Event Operations",
          widgets: [
            %{
              type: :event_timeline,
              title: "Replay Mission Events",
              binding: %{source: :events, observables: []}
            },
            %{
              type: :status_matrix,
              title: "Replay Contact Phase",
              binding: %{
                source: :operational_observables,
                observables: ["contacts.phase"]
              }
            }
          ]
        )

      document =
        org
        |> fetch_dashboard_document!(mission, dashboard)
        |> then(fn %Document{} = document ->
          %Document{
            document
            | defaults: %{
                "data" => %{
                  "realm" => "replay",
                  "source_mode" => "specific",
                  "source_contexts" => %{
                    "events" => %{
                      "source_binding_id" => replay_sources.events_binding_id
                    },
                    "operational_observables" => %{
                      "source_binding_id" => replay_sources.operational_binding_id
                    }
                  }
                }
              }
          }
        end)
        |> then(&replace_dashboard_row_document!(org, mission, &1))

      events_widget = render_item_by_title(document, "Replay Mission Events").widget
      matrix_widget = render_item_by_title(document, "Replay Contact Phase").widget

      {:ok, view, _html} =
        live(
          conn,
          show_path(mission, dashboard) <>
            "?time_mode=replay_run&replay_run_id=replay_run_events_ops"
        )

      render_dashboard_async(view)

      assert has_element?(
               view,
               ~s(#ops-dashboard-show-page[data-dashboard-time-mode="replay_run"][data-dashboard-replay-run-id="replay_run_events_ops"][data-dashboard-data-realm="replay"])
             )

      event_row_selector =
        ~s(#widget-#{events_widget.widget_id} [data-event-timeline-record-id="#{scheduled_contact.scheduled_contact_id}"])

      assert has_element?(
               view,
               event_row_selector <>
                 ~s([data-event-timeline-logical-source="events"][data-event-timeline-realm="replay"][data-event-timeline-data-source-id="#{replay_sources.events_data_source_id}"][data-event-timeline-source-binding-id="#{replay_sources.events_binding_id}"][data-event-timeline-replay-run-id="replay_run_events_ops"][data-event-timeline-dataset="mission_events_replay"])
             )

      assert has_element?(
               view,
               event_row_selector <>
                 ~s( [data-event-timeline-row-link-target="contact"][data-event-timeline-row-link-id="#{scheduled_contact.scheduled_contact_id}"][phx-value-replay-run-id="replay_run_events_ops"][phx-value-realm="replay"][phx-value-source-binding-id="#{replay_sources.events_binding_id}"])
             )

      matrix_row_selector =
        ~s(#widget-#{matrix_widget.widget_id} [data-status-matrix-row="contacts.phase:#{scheduled_contact.scheduled_contact_id}"])

      assert has_element?(
               view,
               matrix_row_selector <>
                 ~s([data-status-matrix-source="operational_observables"][data-status-matrix-status-policy="contact_phase"][data-status-matrix-realm="replay"][data-status-matrix-data-source-id="#{replay_sources.operational_data_source_id}"][data-status-matrix-source-binding-id="#{replay_sources.operational_binding_id}"][data-status-matrix-replay-run-id="replay_run_events_ops"][data-status-matrix-dataset="operational_observables_replay"])
             )

      assert has_element?(
               view,
               matrix_row_selector <>
                 ~s( [data-status-matrix-row-link-target="contact"][data-status-matrix-row-link-id="#{scheduled_contact.scheduled_contact_id}"][phx-value-replay-run-id="replay_run_events_ops"][phx-value-realm="replay"][phx-value-source-binding-id="#{replay_sources.operational_binding_id}"])
             )

      assert has_element?(
               view,
               matrix_row_selector <>
                 ~s( [data-status-matrix-row-evidence="contacts.phase:#{scheduled_contact.scheduled_contact_id}"][phx-value-replay-run-id="replay_run_events_ops"][phx-value-source-binding-id="#{replay_sources.operational_binding_id}"])
             )

      stop_dashboard_view(view)
    end

    test "event timeline source-capability posture rows open canonical operational-event inspectors" do
      enable_dashboard_engine_inline_resolves!()

      {conn, org, mission} = signed_in_org_and_mission()

      assert {:ok, _events_source} =
               DataSources.persist_data_source(DataSources.default_events_data_source())

      assert {:ok, _events_binding} =
               DataSources.persist_data_binding(DataSources.default_flight_events_binding(),
                 occurred_at: ~U[2026-06-17 11:59:00Z]
               )

      dashboard =
        TestFixtures.persist_dashboard_document!(mission,
          name: "Source Capability Events",
          widgets: [
            %{
              type: :event_timeline,
              title: "Mission Events",
              binding: %{source: :events, observables: []}
            }
          ]
        )

      document = fetch_dashboard_document!(org, mission, dashboard)
      events_widget = render_item_by_title(document, "Mission Events").widget
      source_request_id = "source_req_#{events_widget.widget_id}_primary_events"

      source_capability_posture_id =
        "dashboard-live-source-capability:resolve-1:#{source_request_id}"

      assert {:ok, persisted_event} =
               Event.from_source_capability_posture(%{
                 organization_id: org.organization_id,
                 mission_id: mission.mission_id,
                 source_capability_posture_id: source_capability_posture_id,
                 dashboard_id: dashboard.dashboard_id,
                 dashboard_version: 1,
                 resolve_id: "dashboard-live-source-capability-resolve",
                 source_request_id: source_request_id,
                 logical_source: :events,
                 data_source_id: DataSources.default_events_data_source().data_source_id,
                 source_binding_id: DataSources.default_flight_events_binding().binding_id,
                 realm: :flight,
                 dataset: "mission_events",
                 status: :fallback,
                 requested_sampling: :event_history,
                 supported_sampling: [:event_history],
                 requested_time_axis: :generation_time,
                 executed_time_axis: :occurred_at,
                 supported_time_axes: [:occurred_at],
                 fallbacks: [:occurred_at_axis],
                 unsupported: [:generation_time_axis],
                 source_execution_status: :resolved,
                 source_execution_cache_status: :miss,
                 source_execution_operator_action: :inspect_source_capability,
                 source_execution_runtime_action: :use_occurred_at_axis,
                 source_execution_warning_codes: [:unsupported_source_capability],
                 observed_at: ~U[2026-06-17 12:01:00Z]
               })
               |> OperationalEvents.persist_event()

      assert [^persisted_event] =
               OperationalEvents.list_events(org.organization_id, mission.mission_id,
                 category: :data_source,
                 source_record_kind: :source_capability_posture,
                 from_occurred_at: ~U[2026-06-17 12:00:00Z],
                 to_occurred_at: ~U[2026-06-17 12:05:00Z],
                 order: :asc
               )

      if Process.whereis(RuntimeCache), do: RuntimeCache.reset()

      {:ok, view, _html} =
        live(
          conn,
          show_path(mission, dashboard) <>
            "?time_mode=archive&time_axis=occurred_at&from=2026-06-17T12:00:00Z&to=2026-06-17T12:05:00Z"
        )

      render_dashboard_async(view)

      row_selector =
        ~s(#widget-#{events_widget.widget_id} [data-event-timeline-record-id="#{source_capability_posture_id}"])

      assert has_element?(
               view,
               row_selector <>
                 ~s([data-event-timeline-category="Source capability"][data-event-timeline-kind="Source capability fallback"][data-event-timeline-target="Operational event"][data-event-timeline-target-id="#{persisted_event.event_id}"][data-event-timeline-logical-source="events"][data-event-timeline-realm="flight"][data-event-timeline-data-source-id="#{DataSources.default_events_data_source().data_source_id}"][data-event-timeline-source-binding-id="#{DataSources.default_flight_events_binding().binding_id}"][data-event-timeline-dataset="mission_events"])
             )

      assert has_element?(
               view,
               row_selector <>
                 ~s( [data-event-timeline-row-link-target="operational event"][data-event-timeline-row-link-id="#{persisted_event.event_id}"][phx-value-target="operational_event"][phx-value-target-id="#{persisted_event.event_id}"][phx-value-realm="flight"][phx-value-source-binding-id="#{DataSources.default_flight_events_binding().binding_id}"][phx-value-data-source-id="#{DataSources.default_events_data_source().data_source_id}"])
             )

      view
      |> element(
        row_selector <>
          ~s( [data-event-timeline-row-link-target="operational event"][data-event-timeline-row-link-id="#{persisted_event.event_id}"])
      )
      |> render_click()

      operational_event_path = assert_patch(view)
      assert operational_event_path =~ "panel=data_link"
      assert operational_event_path =~ "selected_target=operational_event"

      assert operational_event_path =~
               "selected_id=#{URI.encode_www_form(persisted_event.event_id)}"

      assert operational_event_path =~
               "selected_placement=#{URI.encode_www_form(events_widget.widget_id)}"

      assert operational_event_path =~ "realm=flight"

      assert has_element?(
               view,
               ~s(#dashboard-data-link-inspector[data-data-link-target="operational_event"][data-data-link-status="resolved"])
             )

      assert has_element?(
               view,
               ~s(#dashboard-data-link-inspector [data-data-link-field="Operational event"]),
               persisted_event.event_id
             )

      assert has_element?(
               view,
               ~s(#dashboard-data-link-inspector [data-data-link-field="Source capability posture"]),
               source_capability_posture_id
             )

      assert has_element?(
               view,
               ~s(#dashboard-data-link-inspector [data-data-link-field="Capability status"]),
               "fallback"
             )

      assert has_element?(
               view,
               ~s(#dashboard-data-link-inspector [data-data-link-field="Executed time axis"]),
               "occurred_at"
             )

      assert has_element?(
               view,
               ~s(#dashboard-data-link-copy-link[data-clipboard-text*="panel=data_link"][data-clipboard-text*="selected_target=operational_event"][data-clipboard-text*="selected_id=#{URI.encode_www_form(persisted_event.event_id)}"][data-clipboard-text*="selected_placement=#{URI.encode_www_form(events_widget.widget_id)}"])
             )

      stop_dashboard_view(view)
    end

    test "time presets patch archive snapshot context and can resume live" do
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

    test "invalid archive time params fall back to live with validation state" do
      {conn, _org, mission} = signed_in_org_and_mission()

      dashboard =
        TestFixtures.persist_dashboard_document!(mission,
          name: "Invalid Time",
          widgets: [value_tile("HK.counter")]
        )

      {:ok, view, _html} =
        live(
          conn,
          show_path(mission, dashboard) <>
            "?time_mode=archive&from=not-a-time&to=2026-06-17T12:05:00Z"
        )

      render_dashboard_async(view)

      assert has_element?(
               view,
               ~s(#ops-dashboard-show-page[data-dashboard-time-mode="live"][data-dashboard-time-validation="invalid_time_bound"][data-engine-time-mode="live"])
             )

      assert has_element?(
               view,
               ~s(#dashboard-time-validation[data-time-validation="invalid_time_bound"])
             )

      {:ok, reversed_view, _html} =
        live(
          conn,
          show_path(mission, dashboard) <>
            "?time_mode=archive&from=2026-06-17T12:05:00Z&to=2026-06-17T12:00:00Z"
        )

      render_dashboard_async(reversed_view)

      assert has_element?(
               reversed_view,
               ~s(#ops-dashboard-show-page[data-dashboard-time-mode="live"][data-dashboard-time-validation="time_range_reversed"][data-engine-time-mode="live"])
             )
    end

    test "archive time-series charts expose clickable limit definition intervals" do
      {conn, org, mission} = signed_in_org_and_mission()
      spacecraft = TestFixtures.persist_spacecraft!(mission, display_name: "SC Limit Intervals")
      binding_set = persist_binding_set!(org, mission)
      sample_time = DateTime.utc_now() |> DateTime.truncate(:second)

      ingest!(mission, binding_set, spacecraft.spacecraft_id, 15, DateTime.to_unix(sample_time))

      persist_counter_limit_definition!(mission, 1, %{"yellow_high" => 10, "red_high" => 20})

      dashboard =
        TestFixtures.persist_dashboard_document!(mission,
          name: "Limit Intervals",
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
      from = sample_time |> DateTime.add(-10, :second) |> DateTime.to_iso8601()
      to = DateTime.utc_now() |> DateTime.add(600, :second) |> DateTime.to_iso8601()

      {:ok, view, _html} =
        live(conn, show_path(mission, dashboard) <> "?time_mode=archive&from=#{from}&to=#{to}")

      html = render_dashboard_async(view)
      markers = chart_limit_markers(html, trend_widget.widget_id)

      interval_marker =
        Enum.find(markers, &(&1["marker_type"] == "limit_definition_interval"))

      assert interval_marker["target"] == "limit_definition"
      assert interval_marker["target_id"] == "counter-limits"
      assert interval_marker["limit_definition_id"] == "counter-limits"
      assert interval_marker["limit_definition_version"] == 1
      assert interval_marker["limit_set_name"] == "DEFAULT"
      assert interval_marker["yellow_high"] == 10
      assert interval_marker["red_high"] == 20
      assert is_integer(interval_marker["starts_at_ms"])
      assert is_binary(interval_marker["link_id"])

      chart_id = chart_dom_id(html, trend_widget.widget_id)
      link_id = interval_marker["link_id"]
      target_id = interval_marker["target_id"]
      timestamp_ms = interval_marker["starts_at_ms"]

      view
      |> element("##{chart_id}")
      |> render_hook("open_data_link", %{
        "link-id" => link_id,
        "target" => "limit_definition",
        "target-id" => target_id,
        "timestamp-ms" => timestamp_ms
      })

      assert_push_event(
        view,
        "tlm:select",
        %{
          "selection" => %{
            "link_id" => ^link_id,
            "target" => "limit_definition",
            "target_id" => ^target_id,
            "timestamp_ms" => ^timestamp_ms
          }
        },
        1_000
      )

      assert has_element?(
               view,
               ~s(#dashboard-data-link-inspector[data-data-link-target="limit_definition"][data-data-link-status="resolved"])
             )

      assert has_element?(
               view,
               ~s(#dashboard-data-link-inspector [data-data-link-field="Definition"]),
               "counter-limits"
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

    test "archive dashboard resolves when scoped runtime invalidation broadcasts" do
      enable_dashboard_runtime_cache!()

      {conn, org, mission} = signed_in_org_and_mission()
      spacecraft = TestFixtures.persist_spacecraft!(mission, display_name: "SC Invalidation")
      binding_set = persist_binding_set!(org, mission)
      ingest!(mission, binding_set, spacecraft.spacecraft_id, 5, 1_700_000_100)

      dashboard =
        TestFixtures.persist_dashboard_document!(mission,
          name: "Runtime Invalidation",
          widgets: [value_tile("HK.counter", :fixed, spacecraft.spacecraft_id)]
        )

      from = DateTime.from_unix!(1_700_000_095, :second) |> DateTime.to_iso8601()
      to = DateTime.from_unix!(1_700_000_105, :second) |> DateTime.to_iso8601()

      {:ok, view, _html} =
        live(
          conn,
          show_path(mission, dashboard) <>
            "?time_mode=archive&from=#{from}&to=#{to}&limit_mode=current"
        )

      render_dashboard_async(view)

      assert has_element?(
               view,
               ~s(#ops-dashboard-show-page[data-dashboard-time-mode="archive"][data-engine-time-mode="archive"])
             )

      assert %{plans: 0, source_results: _source_results, frames: _frames} =
               RuntimeInvalidation.historical_data_changed(
                 %{
                   organization_id: mission.organization_id,
                   mission_id: mission.mission_id,
                   logical_source: :telemetry,
                   time_range: %{from: from, to: to}
                 },
                 runtime_cache: RuntimeCache
               )

      render_dashboard_async(view)

      assert has_element?(
               view,
               ~s(#ops-dashboard-show-page[data-engine-resolve-mode="context_change"][data-runtime-last-invalidation-boundary="historical_data_changed"][data-runtime-last-invalidation-refresh-reason="runtime_invalidation"])
             )
    end

    test "live dashboard refreshes when dashboard version invalidation broadcasts lifecycle action" do
      enable_dashboard_runtime_cache!()

      {conn, org, mission} = signed_in_org_and_mission()
      spacecraft = TestFixtures.persist_spacecraft!(mission, display_name: "SC Version")
      binding_set = persist_binding_set!(org, mission)
      ingest!(mission, binding_set, spacecraft.spacecraft_id, 5, 1_700_000_100)

      dashboard =
        TestFixtures.persist_dashboard_document!(mission,
          name: "Version Invalidation",
          widgets: [value_tile("HK.counter", :fixed, spacecraft.spacecraft_id)]
        )

      {:ok, view, _html} = live(conn, show_path(mission, dashboard))
      render_dashboard_async(view)

      assert has_element?(
               view,
               ~s(#ops-dashboard-show-page[data-dashboard-time-mode="live"][data-engine-time-mode="live"])
             )

      assert %{plans: _plans, source_results: 0, frames: 0} =
               RuntimeInvalidation.dashboard_version_changed(
                 %{
                   organization_id: mission.organization_id,
                   mission_id: mission.mission_id,
                   dashboard_id: dashboard.dashboard_id,
                   document_version: 2,
                   lifecycle_action: :published
                 },
                 runtime_cache: RuntimeCache
               )

      render_dashboard_async(view)

      assert has_element?(
               view,
               ~s(#ops-dashboard-show-page[data-engine-resolve-mode="context_change"][data-runtime-last-invalidation-boundary="dashboard_version_changed"][data-runtime-last-invalidation-refresh-reason="runtime_invalidation"])
             )

      view |> element("#dashboard-diagnostics-button") |> render_click()

      assert has_element?(
               view,
               ~s(#dashboard-recent-invalidations [data-runtime-invalidation-boundary="dashboard_version_changed"][data-runtime-invalidation-lifecycle-action="published"][data-runtime-invalidation-document-version="2"])
             )
    end

    test "event runtime invalidation refreshes live dashboard event overlays" do
      {conn, org, mission} = signed_in_org_and_mission()
      spacecraft = TestFixtures.persist_spacecraft!(mission, display_name: "SC Events")
      binding_set = persist_binding_set!(org, mission)
      ingest!(mission, binding_set, spacecraft.spacecraft_id, 5, 1_700_000_100)

      dashboard =
        TestFixtures.persist_dashboard_document!(mission,
          name: "Events Refresh",
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

      refute Enum.any?(
               chart_event_markers(initial_html, trend_widget.widget_id),
               &(&1["marker_type"] == "contact_interval")
             )

      scheduled_contact =
        ScheduledContact.new(%{
          scheduled_contact_id: "dashboard-refresh-contact",
          mission_id: mission.mission_id,
          source_endpoint_refs: ["source-endpoint-alpha"],
          paths: contact_paths("source-endpoint-alpha"),
          starts_at: DateTime.from_unix!(1_700_000_080, :second),
          ends_at: DateTime.from_unix!(1_700_000_220, :second)
        })

      assert {:ok, _scheduled_contact} =
               Cadence.persist_scheduled_contact(org.organization_id, scheduled_contact)

      refreshed_html = render_dashboard_async(view)
      refreshed_chart_id = chart_dom_id(refreshed_html, trend_widget.widget_id)

      assert has_element?(
               view,
               ~s(#ops-dashboard-show-page[data-engine-resolve-mode="context_change"][data-runtime-last-invalidation-boundary="events_changed"][data-runtime-last-invalidation-refresh-reason="runtime_invalidation"])
             )

      assert initial_chart_id == "tlm-chart-#{trend_widget.widget_id}-none-0"
      assert refreshed_chart_id == "tlm-chart-#{trend_widget.widget_id}-none-1"

      event_markers = chart_event_markers(refreshed_html, trend_widget.widget_id)

      assert Enum.any?(
               event_markers,
               &(&1["marker_type"] == "contact_interval" and
                   &1["contact_id"] == scheduled_contact.scheduled_contact_id)
             )
    end

    test "event runtime invalidation skips dashboards without event overlays" do
      {conn, org, mission} = signed_in_org_and_mission()
      spacecraft = TestFixtures.persist_spacecraft!(mission, display_name: "SC Tile Events")
      binding_set = persist_binding_set!(org, mission)
      ingest!(mission, binding_set, spacecraft.spacecraft_id, 5, 1_700_000_100)

      dashboard =
        TestFixtures.persist_dashboard_document!(mission,
          name: "No Event Consumers",
          widgets: [value_tile("HK.counter", :fixed, spacecraft.spacecraft_id)]
        )

      {:ok, view, _html} = live(conn, show_path(mission, dashboard))
      render_dashboard_async(view)

      assert has_element?(
               view,
               ~s(#ops-dashboard-show-page[data-engine-resolve-mode="initial"])
             )

      scheduled_contact =
        ScheduledContact.new(%{
          scheduled_contact_id: "dashboard-skip-tile-contact",
          mission_id: mission.mission_id,
          source_endpoint_refs: ["source-endpoint-alpha"],
          paths: contact_paths("source-endpoint-alpha"),
          starts_at: DateTime.from_unix!(1_700_000_080, :second),
          ends_at: DateTime.from_unix!(1_700_000_220, :second)
        })

      assert {:ok, _scheduled_contact} =
               Cadence.persist_scheduled_contact(org.organization_id, scheduled_contact)

      render_dashboard_async(view)

      assert has_element?(
               view,
               ~s(#ops-dashboard-show-page[data-engine-resolve-mode="initial"])
             )

      refute has_element?(
               view,
               ~s(#ops-dashboard-show-page[data-runtime-last-invalidation-boundary="events_changed"])
             )
    end

    test "event runtime invalidation skips time series widgets without event overlay" do
      {conn, org, mission} = signed_in_org_and_mission()
      spacecraft = TestFixtures.persist_spacecraft!(mission, display_name: "SC No Events")
      binding_set = persist_binding_set!(org, mission)
      ingest!(mission, binding_set, spacecraft.spacecraft_id, 5, 1_700_000_100)

      dashboard =
        TestFixtures.persist_dashboard_document!(mission,
          name: "Events Overlay Removed",
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

      document =
        org
        |> fetch_dashboard_document!(mission, dashboard)
        |> without_widget_overlay("Counter Trend", :events)

      replace_dashboard_row_document!(org, mission, document)
      trend_widget = render_item_by_title(document, "Counter Trend").widget

      {:ok, view, _html} = live(conn, show_path(mission, dashboard))
      initial_html = render_dashboard_async(view)
      initial_chart_id = chart_dom_id(initial_html, trend_widget.widget_id)

      assert initial_chart_id == "tlm-chart-#{trend_widget.widget_id}-none-0"
      assert chart_event_markers(initial_html, trend_widget.widget_id) == []

      scheduled_contact =
        ScheduledContact.new(%{
          scheduled_contact_id: "dashboard-skip-trend-contact",
          mission_id: mission.mission_id,
          source_endpoint_refs: ["source-endpoint-alpha"],
          paths: contact_paths("source-endpoint-alpha"),
          starts_at: DateTime.from_unix!(1_700_000_080, :second),
          ends_at: DateTime.from_unix!(1_700_000_220, :second)
        })

      assert {:ok, _scheduled_contact} =
               Cadence.persist_scheduled_contact(org.organization_id, scheduled_contact)

      skipped_html = render_dashboard_async(view)

      assert chart_dom_id(skipped_html, trend_widget.widget_id) == initial_chart_id
      assert chart_event_markers(skipped_html, trend_widget.widget_id) == []

      refute has_element?(
               view,
               ~s(#ops-dashboard-show-page[data-runtime-last-invalidation-boundary="events_changed"])
             )
    end

    test "limit definition runtime invalidation refreshes live dashboard limit overlays" do
      {conn, org, mission} = signed_in_org_and_mission()
      spacecraft = TestFixtures.persist_spacecraft!(mission, display_name: "SC Limit Refresh")
      binding_set = persist_binding_set!(org, mission)
      ingest!(mission, binding_set, spacecraft.spacecraft_id, 15, 1_700_000_100)
      persist_counter_limit_definition!(mission, 1, %{"yellow_high" => 10, "red_high" => 20})
      assert {:ok, _run} = Cadence.evaluate_telemetry_limits(mission.mission_id)

      dashboard =
        TestFixtures.persist_dashboard_document!(mission,
          name: "Limit Refresh",
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

      assert initial_chart_id == "tlm-chart-#{trend_widget.widget_id}-none-0"
      assert chart_limit_markers(initial_html, trend_widget.widget_id) != []

      persist_counter_limit_definition!(mission, 2, %{"yellow_high" => 12, "red_high" => 25})

      refreshed_html = render_dashboard_async(view)

      assert has_element?(
               view,
               ~s(#ops-dashboard-show-page[data-engine-resolve-mode="context_change"][data-runtime-last-invalidation-boundary="limit_definition_changed"][data-runtime-last-invalidation-refresh-reason="runtime_invalidation"])
             )

      assert chart_dom_id(refreshed_html, trend_widget.widget_id) == initial_chart_id
    end

    test "limit definition runtime invalidation skips dashboards without limit overlays" do
      {conn, org, mission} = signed_in_org_and_mission()
      spacecraft = TestFixtures.persist_spacecraft!(mission, display_name: "SC No Limits")
      binding_set = persist_binding_set!(org, mission)
      ingest!(mission, binding_set, spacecraft.spacecraft_id, 15, 1_700_000_100)
      persist_counter_limit_definition!(mission, 1, %{"yellow_high" => 10, "red_high" => 20})
      assert {:ok, _run} = Cadence.evaluate_telemetry_limits(mission.mission_id)

      dashboard =
        TestFixtures.persist_dashboard_document!(mission,
          name: "Limit Overlay Removed",
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

      document =
        org
        |> fetch_dashboard_document!(mission, dashboard)
        |> without_widget_overlay("Counter Trend", :limits)

      replace_dashboard_row_document!(org, mission, document)
      trend_widget = render_item_by_title(document, "Counter Trend").widget

      {:ok, view, _html} = live(conn, show_path(mission, dashboard))
      initial_html = render_dashboard_async(view)
      initial_chart_id = chart_dom_id(initial_html, trend_widget.widget_id)

      assert initial_chart_id == "tlm-chart-#{trend_widget.widget_id}-none-0"
      assert chart_limit_markers(initial_html, trend_widget.widget_id) == []

      persist_counter_limit_definition!(mission, 2, %{"yellow_high" => 12, "red_high" => 25})

      skipped_html = render_dashboard_async(view)

      assert chart_dom_id(skipped_html, trend_widget.widget_id) == initial_chart_id

      refute has_element?(
               view,
               ~s(#ops-dashboard-show-page[data-runtime-last-invalidation-boundary="limit_definition_changed"])
             )
    end

    test "limit definition runtime invalidation skips unrelated observables" do
      {conn, org, mission} = signed_in_org_and_mission()
      spacecraft = TestFixtures.persist_spacecraft!(mission, display_name: "SC Other Limit")
      binding_set = persist_binding_set!(org, mission)
      ingest!(mission, binding_set, spacecraft.spacecraft_id, 15, 1_700_000_100)
      persist_counter_limit_definition!(mission, 1, %{"yellow_high" => 10, "red_high" => 20})
      assert {:ok, _run} = Cadence.evaluate_telemetry_limits(mission.mission_id)

      dashboard =
        TestFixtures.persist_dashboard_document!(mission,
          name: "Limit Observable Mismatch",
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

      other_limit_definition =
        Definition.new(%{
          mission_id: mission.mission_id,
          limit_definition_id: "voltage-limits",
          point_id: "HK.voltage",
          thresholds: %{"yellow_high" => 12, "red_high" => 25}
        })

      assert {:ok, ^other_limit_definition} =
               Cadence.persist_limit_definition(other_limit_definition)

      skipped_html = render_dashboard_async(view)

      assert chart_dom_id(skipped_html, trend_widget.widget_id) == initial_chart_id

      refute has_element?(
               view,
               ~s(#ops-dashboard-show-page[data-runtime-last-invalidation-boundary="limit_definition_changed"])
             )
    end

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

    test "data source binding runtime invalidation skips dashboards without telemetry primary data" do
      {conn, org, mission} = signed_in_org_and_mission()

      dashboard =
        TestFixtures.persist_dashboard_document!(mission,
          name: "Non Telemetry Binding",
          widgets: [
            %{type: :constellation_health, title: "Fleet", binding: %{mode: :constellation}}
          ]
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
               ~s(#ops-dashboard-show-page[data-engine-resolve-mode="initial"])
             )

      refute has_element?(
               view,
               ~s(#ops-dashboard-show-page[data-runtime-last-invalidation-boundary="data_source_binding_changed"])
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

    test "source health runtime invalidation skips dashboards without telemetry primary data" do
      {conn, org, mission} = signed_in_org_and_mission()

      dashboard =
        TestFixtures.persist_dashboard_document!(mission,
          name: "Non Telemetry Health",
          widgets: [
            %{type: :constellation_health, title: "Fleet", binding: %{mode: :constellation}}
          ]
        )

      {:ok, view, _html} = live(conn, show_path(mission, dashboard))
      render_dashboard_async(view)

      assert %{plans: _plans, source_results: _source_results, frames: _frames} =
               RuntimeInvalidation.source_health_changed(%{
                 organization_id: org.organization_id,
                 mission_id: mission.mission_id,
                 logical_source: :telemetry,
                 data_source_id: DataSources.default_managed_data_source().data_source_id,
                 source_health: :unavailable,
                 previous_source_health: :healthy,
                 reason: :source_probe_failed
               })

      render_dashboard_async(view)

      assert has_element?(
               view,
               ~s(#ops-dashboard-show-page[data-engine-resolve-mode="initial"])
             )

      refute has_element?(
               view,
               ~s(#ops-dashboard-show-page[data-runtime-last-invalidation-boundary="source_health_changed"])
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

    test "source watermark runtime invalidation skips dashboards without telemetry primary data" do
      {conn, org, mission} = signed_in_org_and_mission()

      dashboard =
        TestFixtures.persist_dashboard_document!(mission,
          name: "Non Telemetry Watermark",
          widgets: [
            %{type: :constellation_health, title: "Fleet", binding: %{mode: :constellation}}
          ]
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
               ~s(#ops-dashboard-show-page[data-engine-resolve-mode="initial"])
             )

      refute has_element?(
               view,
               ~s(#ops-dashboard-show-page[data-runtime-last-invalidation-boundary="source_watermark_changed"])
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

    test "runtime invalidation refreshes only when realm matches active data context" do
      {conn, org, mission} = signed_in_org_and_mission()
      spacecraft = TestFixtures.persist_spacecraft!(mission, display_name: "SC Realm")
      binding_set = persist_binding_set!(org, mission)
      persist_dashboard_realm!(mission, :flight)
      rehearsal_identity = persist_dashboard_realm!(mission, :rehearsal)
      ingest!(mission, binding_set, spacecraft.spacecraft_id, 15, 1_700_000_100)

      dashboard =
        TestFixtures.persist_dashboard_document!(mission,
          name: "Realm Watermark Refresh",
          widgets: [value_tile("HK.counter", :fixed, spacecraft.spacecraft_id)]
        )

      {:ok, view, _html} = live(conn, show_path(mission, dashboard) <> "?realm=rehearsal")
      render_dashboard_async(view)

      assert has_element?(
               view,
               ~s(#ops-dashboard-show-page[data-dashboard-data-realm="rehearsal"][data-engine-data-realm="rehearsal"])
             )

      assert %{plans: _plans, source_results: _source_results, frames: _frames} =
               RuntimeInvalidation.source_watermark_changed(%{
                 organization_id: org.organization_id,
                 mission_id: mission.mission_id,
                 logical_source: :telemetry,
                 observable: "HK.counter",
                 realm: :flight,
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

      assert %{plans: _plans, source_results: _source_results, frames: _frames} =
               RuntimeInvalidation.source_watermark_changed(%{
                 organization_id: org.organization_id,
                 mission_id: mission.mission_id,
                 logical_source: :telemetry,
                 observable: "HK.counter",
                 realm: "rehearsal",
                 data_source_id: rehearsal_identity.data_source_id
               })

      render_dashboard_async(view)

      assert has_element?(
               view,
               ~s(#ops-dashboard-show-page[data-engine-resolve-mode="context_change"][data-runtime-last-invalidation-boundary="source_watermark_changed"][data-runtime-last-invalidation-refresh-reason="runtime_invalidation"])
             )
    end

    test "runtime invalidation refreshes only when data source matches active data context" do
      {conn, org, mission} = signed_in_org_and_mission()
      spacecraft = TestFixtures.persist_spacecraft!(mission, display_name: "SC Data Source")
      binding_set = persist_binding_set!(org, mission)
      unique = System.unique_integer([:positive])

      identity =
        persist_dashboard_realm_source!(
          mission,
          :flight,
          "identity-flight-source-#{unique}",
          "identity-flight-binding-#{unique}"
        )

      ingest!(mission, binding_set, spacecraft.spacecraft_id, 15, 1_700_000_100)

      dashboard =
        TestFixtures.persist_dashboard_document!(mission,
          name: "Data Source Watermark Refresh",
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
                 realm: :flight,
                 source_id: "unrelated-flight-source-#{unique}"
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

      assert %{plans: _plans, source_results: _source_results, frames: _frames} =
               RuntimeInvalidation.source_watermark_changed(%{
                 organization_id: org.organization_id,
                 mission_id: mission.mission_id,
                 logical_source: :telemetry,
                 observable: "HK.counter",
                 realm: :flight,
                 source_id: identity.data_source_id
               })

      render_dashboard_async(view)

      assert has_element?(
               view,
               ~s(#ops-dashboard-show-page[data-engine-resolve-mode="context_change"][data-runtime-last-invalidation-boundary="source_watermark_changed"][data-runtime-last-invalidation-refresh-reason="runtime_invalidation"])
             )
    end

    test "runtime invalidation refreshes only when source binding matches active data context" do
      {conn, org, mission} = signed_in_org_and_mission()
      spacecraft = TestFixtures.persist_spacecraft!(mission, display_name: "SC Binding")
      binding_set = persist_binding_set!(org, mission)
      unique = System.unique_integer([:positive])

      identity =
        persist_dashboard_realm_source!(
          mission,
          :flight,
          "binding-flight-source-#{unique}",
          "binding-flight-binding-#{unique}"
        )

      ingest!(mission, binding_set, spacecraft.spacecraft_id, 15, 1_700_000_100)

      dashboard =
        TestFixtures.persist_dashboard_document!(mission,
          name: "Binding Watermark Refresh",
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
                 realm: :flight,
                 binding_id: "unrelated-flight-binding-#{unique}"
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

      assert %{plans: _plans, source_results: _source_results, frames: _frames} =
               RuntimeInvalidation.source_watermark_changed(%{
                 organization_id: org.organization_id,
                 mission_id: mission.mission_id,
                 logical_source: :telemetry,
                 observable: "HK.counter",
                 realm: :flight,
                 binding_id: identity.binding_id
               })

      render_dashboard_async(view)

      assert has_element?(
               view,
               ~s(#ops-dashboard-show-page[data-engine-resolve-mode="context_change"][data-runtime-last-invalidation-boundary="source_watermark_changed"][data-runtime-last-invalidation-refresh-reason="runtime_invalidation"])
             )
    end

    test "runtime context resolves reuse source result and frame caches" do
      enable_dashboard_runtime_cache!()

      {conn, org, mission} = signed_in_org_and_mission()
      spacecraft = TestFixtures.persist_spacecraft!(mission, display_name: "SC Cache")
      binding_set = persist_binding_set!(org, mission)
      ingest!(mission, binding_set, spacecraft.spacecraft_id, 5, 1_700_000_100)

      dashboard =
        TestFixtures.persist_dashboard_document!(mission,
          name: "Runtime Cache",
          widgets: [value_tile("HK.counter", :fixed, spacecraft.spacecraft_id)]
        )

      from = DateTime.from_unix!(1_700_000_095, :second) |> DateTime.to_iso8601()
      to = DateTime.from_unix!(1_700_000_105, :second) |> DateTime.to_iso8601()

      {:ok, view, _html} =
        live(
          conn,
          show_path(mission, dashboard) <>
            "?time_mode=archive&from=#{from}&to=#{to}&limit_mode=current"
        )

      render_dashboard_async(view)

      assert has_element?(
               view,
               ~s(#ops-dashboard-show-page[data-engine-source-cache-statuses*="miss"][data-engine-frame-cache-statuses*="miss"])
             )

      assert has_element?(
               view,
               ~s(#dashboard-source-health[data-source-execution*="Telemetry:cache_miss"])
             )

      view
      |> element("#runtime-context-form")
      |> render_change(%{
        "time_mode" => "live",
        "from" => from,
        "to" => to,
        "realm" => "flight",
        "limit_mode" => "observed"
      })

      assert_patch(view, show_path(mission, dashboard))
      render_dashboard_async(view)

      view
      |> element("#runtime-context-form")
      |> render_change(%{
        "time_mode" => "archive",
        "from" => from,
        "to" => to,
        "realm" => "flight",
        "limit_mode" => "current"
      })

      patched_path = assert_patch(view)
      assert patched_path =~ "time_mode=archive"
      assert patched_path =~ "limit_mode=current"

      render_dashboard_async(view)

      assert has_element?(
               view,
               ~s(#ops-dashboard-show-page[data-engine-source-cache-statuses*="hit"][data-engine-frame-cache-statuses*="hit"])
             )

      assert has_element?(
               view,
               ~s(#dashboard-source-health[data-source-execution*="Telemetry:cache_hit"])
             )

      assert has_element?(
               view,
               ~s(#dashboard-source-health[data-source-execution-severity*="Telemetry:ok"][data-source-execution-action*="Telemetry:none"])
             )
    end

    test "operator surface exposes scoped runtime invalidation diagnostics" do
      {conn, _org, mission} = signed_in_org_and_mission()

      dashboard =
        TestFixtures.persist_dashboard_document!(mission,
          name: "Invalidation Health",
          widgets: [value_tile("HK.counter")]
        )

      assert [%{placement_id: affected_placement_id}] = dashboard.placements

      reset_runtime_health!()

      occurred_at = ~U[2026-06-24 12:00:00Z]
      source_watermark_measurements = %{plans: 0, source_results: 2, frames: 2, total: 4}

      source_watermark_metadata = %{
        boundary: :source_watermark_changed,
        domain_fact: :source_watermark_changed,
        layers: [:source_result, :frame],
        occurred_at: occurred_at,
        filters: %{
          organization_id: mission.organization_id,
          mission_id: mission.mission_id,
          logical_source: :telemetry,
          realm: :flight,
          data_source_id: DataSources.default_managed_data_source().data_source_id,
          source_binding_id: "default_flight_telemetry",
          observable: "HK.counter"
        }
      }

      emit_runtime_invalidation!(
        source_watermark_measurements,
        source_watermark_metadata
      )

      source_watermark_event_id =
        runtime_invalidation_test_event_id(
          :source_watermark_changed,
          mission.mission_id,
          "HK.counter",
          4,
          occurred_at
        )

      source_watermark_event =
        RuntimeInvalidation.Event.new(
          :source_watermark_changed,
          [:source_result, :frame],
          source_watermark_metadata.filters,
          %{},
          source_watermark_measurements,
          occurred_at: occurred_at
        )

      assert {:ok, persisted_decision_event} =
               Cadence.record_dashboard_runtime_invalidation_decision(
                 source_watermark_event,
                 %{
                   dashboard_id: dashboard.dashboard_id,
                   organization_id: mission.organization_id,
                   mission_id: mission.mission_id,
                   affected_placement_count: 1,
                   affected_placement_ids: [affected_placement_id],
                   affected_widget_type_ids: ["cadence.value_tile"],
                   affected_impact_reasons: [:primary_source],
                   source_cache_evidence_state_summary: %{
                     total: 2,
                     resolved: 1,
                     context_only: 1,
                     missing: 0
                   },
                   source_cache_evidence_target_ids: [
                     "source_watermark_event:source-watermark-event-1"
                   ],
                   source_cache_evidence_request_ids: ["req-telemetry"],
                   source_execution_retryable_count: 3,
                   source_execution_actionable_count: 2,
                   source_execution_degraded_count: 2,
                   source_execution_status_summary: %{
                     cache_stale: 1,
                     source_unavailable: 1,
                     source_degraded: 1
                   },
                   source_execution_severity_summary: %{warning: 2, error: 1},
                   source_execution_runtime_action_summary: %{
                     refresh_source_result: 1,
                     wait_for_source_health: 2
                   },
                   source_execution_operator_action_summary: %{
                     wait_for_refresh: 1,
                     inspect_source_health: 2
                   },
                   source_execution_degraded_identities: [
                     "telemetry:req-circuit:source_degraded",
                     "telemetry:req-unavailable:source_unavailable"
                   ],
                   source_execution_degraded_actions: [
                     "telemetry:req-circuit:wait_for_source_health:inspect_source_health",
                     "telemetry:req-unavailable:wait_for_source_health:inspect_source_health"
                   ],
                   matches?: true,
                   dashboard_matches?: true,
                   context_matches?: true,
                   context_reason: :matched,
                   refresh_allowed?: false,
                   refresh_reason: :stale_for_context,
                   decision_status: :refresh_suppressed
                 },
                 invalidation_event_id: source_watermark_event_id,
                 decision_observed_at: ~U[2026-06-24 12:00:05Z]
               )

      emit_runtime_invalidation!(
        %{plans: 0, source_results: 5, frames: 5, total: 10},
        %{
          boundary: :source_watermark_changed,
          domain_fact: :source_watermark_changed,
          layers: [:source_result, :frame],
          filters: %{
            organization_id: mission.organization_id,
            mission_id: "other-mission",
            logical_source: :telemetry
          }
        }
      )

      {:ok, view, _html} = live(conn, show_path(mission, dashboard))
      render_dashboard_async(view)

      assert has_element?(
               view,
               ~s(#ops-dashboard-show-page[data-runtime-invalidation-events="1"][data-runtime-invalidation-artifacts="4"][data-runtime-invalidation-boundaries*="source_watermark_changed:1"][data-runtime-invalidation-context-matches="1"][data-runtime-invalidation-context-filtered="0"][data-runtime-invalidation-context-filter-reasons="-"][data-runtime-invalidation-refresh-allowed="0"][data-runtime-invalidation-refresh-suppressed="1"][data-runtime-invalidation-refresh-suppress-reasons*="stale_for_context:1"])
             )

      view
      |> element("#dashboard-diagnostics-button")
      |> render_click()

      assert has_element?(
               view,
               ~s(#dashboard-diagnostics-panel[data-runtime-invalidation-events="1"][data-runtime-invalidation-artifacts="4"][data-runtime-invalidation-boundaries*="source_watermark_changed:1"][data-runtime-invalidation-context-matches="1"][data-runtime-invalidation-context-filtered="0"][data-runtime-invalidation-context-filter-reasons="-"][data-runtime-invalidation-refresh-allowed="0"][data-runtime-invalidation-refresh-suppressed="1"][data-runtime-invalidation-refresh-suppress-reasons*="stale_for_context:1"])
             )

      assert has_element?(
               view,
               ~s(#dashboard-no-refresh-summary[data-no-refresh-status="refresh_suppressed"][data-no-refresh-context="Context: all recent invalidations matched"][data-no-refresh-refresh="Refresh: stale before current context:1"]),
               "Invalidations matched, but refresh was suppressed."
             )

      assert has_element?(
               view,
               ~s(#dashboard-no-refresh-summary[data-no-refresh-blocking-boundary="source_watermark_changed"][data-no-refresh-blocking-source="durable_projection"][data-no-refresh-blocking-decision-id="#{persisted_decision_event.dashboard_runtime_invalidation_decision_event_id}"][data-no-refresh-blocking-observable="HK.counter"][data-no-refresh-blocking-context="matched"][data-no-refresh-blocking-refresh="stale before current context"][data-no-refresh-blocking-placements="#{affected_placement_id}"][data-no-refresh-blocking-impact="primary_source"][data-no-refresh-blocking-source-cache-evidence-total="2"][data-no-refresh-blocking-source-cache-evidence-resolved="1"][data-no-refresh-blocking-source-cache-evidence-context-only="1"][data-no-refresh-blocking-source-cache-evidence-missing="0"][data-no-refresh-blocking-source-cache-evidence-targets="source_watermark_event:source-watermark-event-1"][data-no-refresh-blocking-source-cache-evidence-requests="req-telemetry"][data-no-refresh-blocking-source-execution-statuses="cache_stale:1 source_degraded:1 source_unavailable:1"][data-no-refresh-blocking-source-execution-actions="refresh_source_result:1 wait_for_source_health:2"])
             )

      assert has_element?(
               view,
               ~s(#dashboard-no-refresh-blocker [data-no-refresh-blocker-field="Placements"]),
               affected_placement_id
             )

      assert has_element?(
               view,
               ~s(#dashboard-no-refresh-blocker [data-no-refresh-blocker-field="Refresh"]),
               "stale before current context"
             )

      assert has_element?(
               view,
               ~s(#dashboard-no-refresh-blocker [data-no-refresh-blocker-field="Source cache evidence"]),
               "total:2 resolved:1 context:1 missing:0"
             )

      assert has_element?(
               view,
               ~s(#dashboard-no-refresh-blocker [data-no-refresh-blocker-field="Source cache evidence targets"]),
               "source_watermark_event:source-watermark-event-1"
             )

      assert has_element?(
               view,
               ~s(#dashboard-no-refresh-blocker [data-no-refresh-blocker-field="Source execution"]),
               "cache_stale:1 source_degraded:1 source_unavailable:1"
             )

      assert has_element?(
               view,
               ~s(#dashboard-no-refresh-blocker [data-no-refresh-blocker-field="Source execution actions"]),
               "refresh_source_result:1 wait_for_source_health:2"
             )

      assert has_element?(
               view,
               ~s(#dashboard-no-refresh-blocker [data-no-refresh-blocker-field="Source execution degraded"]),
               "telemetry:req-circuit:source_degraded telemetry:req-unavailable:source_unavailable"
             )

      assert has_element?(
               view,
               ~s(#dashboard-diagnostics-panel [data-diagnostics-field="Invalidation events"]),
               "1"
             )

      assert has_element?(
               view,
               ~s(#dashboard-diagnostics-panel [data-diagnostics-field="Invalidated artifacts"]),
               "4"
             )

      assert has_element?(
               view,
               ~s(#dashboard-diagnostics-panel [data-diagnostics-field="Boundaries"]),
               "source_watermark_changed:1"
             )

      assert has_element?(
               view,
               ~s(#dashboard-diagnostics-panel [data-diagnostics-field="Context matches"]),
               "1"
             )

      assert has_element?(
               view,
               ~s(#dashboard-diagnostics-panel [data-diagnostics-field="Refresh suppressed"]),
               "1"
             )

      assert has_element?(
               view,
               ~s(#dashboard-diagnostics-panel [data-diagnostics-field="Refresh suppress reasons"]),
               "stale before current context:1"
             )

      assert has_element?(
               view,
               ~s(#dashboard-recent-invalidations [data-runtime-invalidation-boundary="source_watermark_changed"][data-runtime-invalidation-source="telemetry"][data-runtime-invalidation-realm="flight"][data-runtime-invalidation-data-source="#{DataSources.default_managed_data_source().data_source_id}"][data-runtime-invalidation-binding="default_flight_telemetry"][data-runtime-invalidation-observable="HK.counter"][data-runtime-invalidation-context-match="true"][data-runtime-invalidation-context-reason="matched"][data-runtime-invalidation-refresh-allowed="false"][data-runtime-invalidation-refresh-allowed-reason="stale_for_context"][data-runtime-invalidation-refresh-reason="runtime_invalidation"][data-runtime-invalidation-refresh-action="refresh_source_result"][data-runtime-invalidation-decision-status="refresh_suppressed"][data-runtime-invalidation-decision-source="durable_projection"][data-runtime-invalidation-decision-event-id="#{persisted_decision_event.dashboard_runtime_invalidation_decision_event_id}"][data-runtime-invalidation-affected-placement-count="1"][data-runtime-invalidation-affected-placement-ids="#{affected_placement_id}"][data-runtime-invalidation-affected-widget-types="cadence.value_tile"][data-runtime-invalidation-affected-impact-reasons="primary_source"][data-runtime-invalidation-source-cache-evidence-total="2"][data-runtime-invalidation-source-cache-evidence-resolved="1"][data-runtime-invalidation-source-cache-evidence-context-only="1"][data-runtime-invalidation-source-cache-evidence-missing="0"][data-runtime-invalidation-source-cache-evidence-targets="source_watermark_event:source-watermark-event-1"][data-runtime-invalidation-source-cache-evidence-requests="req-telemetry"][data-runtime-invalidation-source-execution-statuses="cache_stale:1 source_degraded:1 source_unavailable:1"][data-runtime-invalidation-source-execution-actions="refresh_source_result:1 wait_for_source_health:2"][data-runtime-invalidation-artifacts="4"])
             )

      assert has_element?(
               view,
               ~s(#dashboard-recent-invalidations [data-runtime-invalidation-boundary="source_watermark_changed"] [data-invalidation-field="Refresh"]),
               "refresh_source_result"
             )

      assert has_element?(
               view,
               ~s(#dashboard-recent-invalidations [data-runtime-invalidation-boundary="source_watermark_changed"] [data-invalidation-field="Allowed reason"]),
               "stale before current context"
             )

      assert has_element?(
               view,
               ~s(#dashboard-recent-invalidations [data-runtime-invalidation-boundary="source_watermark_changed"] [data-invalidation-field="Impacted"]),
               "1"
             )

      assert has_element?(
               view,
               ~s(#dashboard-recent-invalidations [data-runtime-invalidation-boundary="source_watermark_changed"] [data-invalidation-field="Placements"]),
               affected_placement_id
             )

      assert has_element?(
               view,
               ~s(#dashboard-recent-invalidations [data-runtime-invalidation-boundary="source_watermark_changed"] [data-invalidation-field="Widgets"]),
               "cadence.value_tile"
             )

      assert has_element?(
               view,
               ~s(#dashboard-recent-invalidations [data-runtime-invalidation-boundary="source_watermark_changed"] [data-invalidation-field="Impact"]),
               "primary_source"
             )

      assert has_element?(
               view,
               ~s(#dashboard-recent-invalidations [data-runtime-invalidation-boundary="source_watermark_changed"] [data-invalidation-field="Source cache evidence"]),
               "total:2 resolved:1 context:1 missing:0"
             )

      assert has_element?(
               view,
               ~s(#dashboard-recent-invalidations [data-runtime-invalidation-boundary="source_watermark_changed"] [data-invalidation-field="Source cache evidence targets"]),
               "source_watermark_event:source-watermark-event-1"
             )

      assert has_element?(
               view,
               ~s(#dashboard-recent-invalidations [data-runtime-invalidation-boundary="source_watermark_changed"] [data-invalidation-field="Source execution"]),
               "cache_stale:1 source_degraded:1 source_unavailable:1"
             )

      assert has_element?(
               view,
               ~s(#dashboard-recent-invalidations [data-runtime-invalidation-boundary="source_watermark_changed"] [data-invalidation-field="Source execution actions"]),
               "refresh_source_result:1 wait_for_source_health:2"
             )

      assert has_element?(
               view,
               ~s(#dashboard-recent-invalidations [data-runtime-invalidation-boundary="source_watermark_changed"] [data-invalidation-field="Source execution degraded"]),
               "telemetry:req-circuit:source_degraded telemetry:req-unavailable:source_unavailable"
             )
    end

    test "operator surface exposes replay invalidation context matching" do
      {conn, _org, mission} = signed_in_org_and_mission()

      spacecraft =
        TestFixtures.persist_spacecraft!(mission, display_name: "SC Replay Diagnostics")

      _source = persist_dashboard_realm!(mission, :replay)

      dashboard =
        TestFixtures.persist_dashboard_document!(mission,
          name: "Replay Invalidation Diagnostics",
          widgets: [value_tile("HK.counter", :fixed, spacecraft.spacecraft_id)]
        )

      reset_runtime_health!()

      emit_runtime_invalidation!(
        %{plans: 0, source_results: 1, frames: 1, total: 2},
        %{
          boundary: :historical_data_changed,
          domain_fact: :historical_data_changed,
          layers: [:source_result, :frame],
          filters: %{
            organization_id: mission.organization_id,
            mission_id: mission.mission_id,
            logical_source: :telemetry,
            observable: "HK.counter",
            replay_run_id: "replay_run_001"
          }
        }
      )

      emit_runtime_invalidation!(
        %{plans: 0, source_results: 3, frames: 3, total: 6},
        %{
          boundary: :historical_data_changed,
          domain_fact: :historical_data_changed,
          layers: [:source_result, :frame],
          filters: %{
            organization_id: mission.organization_id,
            mission_id: mission.mission_id,
            logical_source: :telemetry,
            observable: "HK.counter",
            replay_run_id: "replay_run_002"
          }
        }
      )

      {:ok, view, _html} =
        live(
          conn,
          show_path(mission, dashboard) <>
            "?time_mode=replay_run&replay_run_id=replay_run_001"
        )

      render_dashboard_async(view)

      view
      |> element("#dashboard-diagnostics-button")
      |> render_click()

      assert has_element?(
               view,
               ~s(#ops-dashboard-show-page[data-runtime-invalidation-events="2"][data-runtime-invalidation-artifacts="8"][data-runtime-invalidation-boundaries*="historical_data_changed:2"][data-runtime-invalidation-context-matches="1"][data-runtime-invalidation-context-filtered="1"][data-runtime-invalidation-context-filter-reasons*="replay_run_mismatch:1"][data-runtime-invalidation-refresh-allowed="0"][data-runtime-invalidation-refresh-suppressed="2"][data-runtime-invalidation-refresh-suppress-reasons*="stale_for_context:2"])
             )

      assert has_element?(
               view,
               ~s(#dashboard-diagnostics-panel[data-runtime-invalidation-events="2"][data-runtime-invalidation-artifacts="8"][data-runtime-invalidation-boundaries*="historical_data_changed:2"][data-runtime-invalidation-context-matches="1"][data-runtime-invalidation-context-filtered="1"][data-runtime-invalidation-context-filter-reasons*="replay_run_mismatch:1"][data-runtime-invalidation-refresh-allowed="0"][data-runtime-invalidation-refresh-suppressed="2"][data-runtime-invalidation-refresh-suppress-reasons*="stale_for_context:2"])
             )

      assert has_element?(
               view,
               ~s(#dashboard-no-refresh-summary[data-no-refresh-status="mixed_context_suppressed"][data-no-refresh-context="Context: filtered by replay run:1"][data-no-refresh-refresh="Refresh: stale before current context:2"]),
               "Some invalidations were filtered; matched invalidations were suppressed."
             )

      assert has_element?(
               view,
               ~s(#dashboard-recent-invalidations [data-runtime-invalidation-boundary="historical_data_changed"][data-runtime-invalidation-replay-run-id="replay_run_001"][data-runtime-invalidation-context-match="true"][data-runtime-invalidation-context-reason="matched"][data-runtime-invalidation-refresh-allowed="false"][data-runtime-invalidation-refresh-allowed-reason="stale_for_context"][data-runtime-invalidation-artifacts="2"])
             )

      assert has_element?(
               view,
               ~s(#dashboard-recent-invalidations [data-runtime-invalidation-boundary="historical_data_changed"][data-runtime-invalidation-replay-run-id="replay_run_002"][data-runtime-invalidation-context-match="false"][data-runtime-invalidation-context-reason="replay_run_mismatch"][data-runtime-invalidation-refresh-allowed="false"][data-runtime-invalidation-refresh-allowed-reason="stale_for_context"][data-runtime-invalidation-artifacts="6"])
             )

      assert has_element?(
               view,
               ~s(#dashboard-recent-invalidations [data-runtime-invalidation-replay-run-id="replay_run_001"] [data-invalidation-field="Replay"]),
               "replay_run_001"
             )

      assert has_element?(
               view,
               ~s(#dashboard-recent-invalidations [data-runtime-invalidation-replay-run-id="replay_run_002"] [data-invalidation-field="Context"]),
               "false"
             )

      assert has_element?(
               view,
               ~s(#dashboard-diagnostics-panel [data-diagnostics-field="Context filtered"]),
               "1"
             )

      assert has_element?(
               view,
               ~s(#dashboard-diagnostics-panel [data-diagnostics-field="Context filter reasons"]),
               "filtered by replay run:1"
             )

      assert has_element?(
               view,
               ~s(#dashboard-diagnostics-panel [data-diagnostics-field="Refresh suppressed"]),
               "2"
             )

      assert has_element?(
               view,
               ~s(#dashboard-diagnostics-panel [data-diagnostics-field="Refresh suppress reasons"]),
               "stale before current context:2"
             )

      assert has_element?(
               view,
               ~s(#dashboard-recent-invalidations [data-runtime-invalidation-replay-run-id="replay_run_002"] [data-invalidation-field="Context reason"]),
               "filtered by replay run"
             )

      assert has_element?(
               view,
               ~s(#dashboard-recent-invalidations [data-runtime-invalidation-replay-run-id="replay_run_001"] [data-invalidation-field="Allowed reason"]),
               "stale before current context"
             )
    end

    test "operator diagnostics surface persisted runtime invalidation decisions" do
      {conn, _org, mission} = signed_in_org_and_mission()

      spacecraft =
        TestFixtures.persist_spacecraft!(mission, display_name: "SC Persisted Decision")

      _source = persist_dashboard_realm!(mission, :replay)

      dashboard =
        TestFixtures.persist_dashboard_document!(mission,
          name: "Persisted Invalidation Decision",
          widgets: [value_tile("HK.counter", :fixed, spacecraft.spacecraft_id)]
        )

      reset_runtime_health!()

      occurred_at = ~U[2026-06-24 12:00:00Z]

      invalidation_metadata = %{
        boundary: :historical_data_changed,
        domain_fact: :historical_data_changed,
        layers: [:source_result, :frame],
        occurred_at: occurred_at,
        filters: %{
          organization_id: mission.organization_id,
          mission_id: mission.mission_id,
          logical_source: :telemetry,
          observable: "HK.counter",
          replay_run_id: "replay_run_001"
        }
      }

      emit_runtime_invalidation!(
        %{plans: 0, source_results: 1, frames: 1, total: 2},
        invalidation_metadata
      )

      invalidation_event_id =
        runtime_invalidation_test_event_id(
          :historical_data_changed,
          mission.mission_id,
          "HK.counter",
          2,
          occurred_at
        )

      persisted_decision = %{
        dashboard_id: dashboard.dashboard_id,
        organization_id: mission.organization_id,
        mission_id: mission.mission_id,
        affected_placement_count: 1,
        affected_placement_ids: ["placement-persisted-decision"],
        affected_widget_type_ids: ["cadence.value_tile"],
        affected_impact_reasons: [:primary_source],
        matches?: false,
        dashboard_matches?: true,
        context_matches?: false,
        context_reason: :replay_run_mismatch,
        refresh_allowed?: false,
        refresh_reason: :stale_for_context,
        decision_status: :filtered
      }

      persisted_invalidation =
        RuntimeInvalidation.Event.new(
          :historical_data_changed,
          [:source_result, :frame],
          invalidation_metadata.filters,
          %{},
          %{plans: 0, source_results: 1, frames: 1, total: 2},
          occurred_at: occurred_at
        )

      assert {:ok, persisted_decision_event} =
               Cadence.record_dashboard_runtime_invalidation_decision(
                 persisted_invalidation,
                 persisted_decision,
                 invalidation_event_id: invalidation_event_id,
                 decision_observed_at: ~U[2026-06-24 12:00:05Z]
               )

      emit_runtime_invalidation_decision!(
        Map.put(invalidation_metadata, :invalidation_event_id, "runtime-health-decision-ignored"),
        %{
          dashboard_id: dashboard.dashboard_id,
          organization_id: mission.organization_id,
          mission_id: mission.mission_id,
          affected_placement_count: 1,
          affected_placement_ids: ["placement-persisted-decision"],
          affected_widget_type_ids: ["cadence.value_tile"],
          affected_impact_reasons: [:primary_source],
          matches?: false,
          dashboard_matches?: true,
          context_matches?: false,
          context_reason: :replay_run_mismatch,
          refresh_allowed?: false,
          refresh_reason: :stale_for_context,
          decision_status: :filtered
        }
      )

      {:ok, view, _html} =
        live(
          conn,
          show_path(mission, dashboard) <>
            "?time_mode=replay_run&replay_run_id=replay_run_001"
        )

      render_dashboard_async(view)

      view
      |> element("#dashboard-diagnostics-button")
      |> render_click()

      assert has_element?(
               view,
               ~s(#dashboard-diagnostics-panel[data-runtime-invalidation-events="1"][data-runtime-invalidation-context-matches="0"][data-runtime-invalidation-context-filtered="1"][data-runtime-invalidation-context-filter-reasons*="replay_run_mismatch:1"])
             )

      assert has_element?(
               view,
               ~s(#dashboard-recent-invalidations [data-runtime-invalidation-boundary="historical_data_changed"][data-runtime-invalidation-replay-run-id="replay_run_001"][data-runtime-invalidation-context-match="false"][data-runtime-invalidation-context-reason="replay_run_mismatch"][data-runtime-invalidation-refresh-allowed="false"][data-runtime-invalidation-refresh-allowed-reason="stale_for_context"][data-runtime-invalidation-decision-status="filtered"][data-runtime-invalidation-decision-source="durable_projection"][data-runtime-invalidation-decision-event-id="#{persisted_decision_event.dashboard_runtime_invalidation_decision_event_id}"][data-runtime-invalidation-decision-observed-at="2026-06-24T12:00:05Z"][data-runtime-invalidation-affected-placement-count="1"][data-runtime-invalidation-affected-placement-ids="placement-persisted-decision"][data-runtime-invalidation-affected-widget-types="cadence.value_tile"][data-runtime-invalidation-affected-impact-reasons="primary_source"])
             )

      assert has_element?(
               view,
               ~s(#dashboard-no-refresh-summary[data-no-refresh-blocking-source="durable_projection"][data-no-refresh-blocking-decision-id="#{persisted_decision_event.dashboard_runtime_invalidation_decision_event_id}"][data-no-refresh-blocking-boundary="historical_data_changed"][data-no-refresh-blocking-observable="HK.counter"][data-no-refresh-blocking-context="filtered by replay run"][data-no-refresh-blocking-refresh="stale before current context"][data-no-refresh-blocking-placements="placement-persisted-decision"][data-no-refresh-blocking-impact="primary_source"])
             )

      assert has_element?(
               view,
               ~s(#dashboard-no-refresh-blocker [data-no-refresh-blocker-field="Decision ID"]),
               persisted_decision_event.dashboard_runtime_invalidation_decision_event_id
             )

      assert has_element?(
               view,
               ~s(#dashboard-no-refresh-summary [data-no-refresh-admin-decision-link-action][href*="/admin/runtime"][href*="decision=#{persisted_decision_event.dashboard_runtime_invalidation_decision_event_id}"])
             )

      assert has_element?(
               view,
               ~s(#dashboard-recent-invalidations [data-runtime-invalidation-replay-run-id="replay_run_001"] [data-invalidation-field="Decision source"]),
               "durable_projection"
             )

      assert has_element?(
               view,
               ~s(#dashboard-recent-invalidations [data-runtime-invalidation-replay-run-id="replay_run_001"] [data-invalidation-field="Decision ID"]),
               persisted_decision_event.dashboard_runtime_invalidation_decision_event_id
             )

      assert has_element?(
               view,
               ~s(#dashboard-recent-invalidations [data-runtime-invalidation-replay-run-id="replay_run_001"] [data-invalidation-field="Decision observed"]),
               "2026-06-24T12:00:05Z"
             )

      assert has_element?(
               view,
               ~s(#dashboard-recent-invalidations [data-runtime-invalidation-replay-run-id="replay_run_001"] [data-invalidation-field="Placements"]),
               "placement-persisted-decision"
             )
    end

    test "context changes cancel obsolete in-flight dashboard resolves" do
      delay_dashboard_engine_resolves!(100)

      {conn, org, mission} = signed_in_org_and_mission()
      spacecraft = TestFixtures.persist_spacecraft!(mission, display_name: "SC Cancel")
      binding_set = persist_binding_set!(org, mission)
      ingest!(mission, binding_set, spacecraft.spacecraft_id, 5, 1_700_000_100)

      dashboard =
        TestFixtures.persist_dashboard_document!(mission,
          name: "Runtime Cancel",
          widgets: [value_tile("HK.counter", :fixed, spacecraft.spacecraft_id)]
        )

      {:ok, view, _html} = live(conn, show_path(mission, dashboard))

      view
      |> element("#runtime-context-form")
      |> render_change(%{
        "time_mode" => "archive",
        "from" => "2026-06-17T12:00:00Z",
        "to" => "2026-06-17T12:05:00Z",
        "realm" => "flight",
        "limit_mode" => "current"
      })

      patched_path = assert_patch(view)
      assert patched_path =~ "time_mode=archive"
      assert patched_path =~ "limit_mode=current"

      render_dashboard_async(view)

      assert has_element?(
               view,
               ~s(#ops-dashboard-show-page[data-runtime-decision-actions*="cancel_obsolete"][data-runtime-decision-actions*="start_resolve"][data-runtime-decision-actions*="accept_result"])
             )

      assert has_element?(
               view,
               ~s(#ops-dashboard-show-page[data-runtime-refresh-status="settled"][data-runtime-refresh-reason="accepted"][data-runtime-visible-refresh-action="accept_result"][data-runtime-refresh-starts*="runtime_context_changed:1"][data-runtime-refresh-cancellations*="runtime_context_changed:1"][data-runtime-canceled-resolves="1"][data-runtime-failed-resolves="0"])
             )

      assert has_element?(
               view,
               ~s(#ops-dashboard-show-page[data-dashboard-time-mode="archive"][data-engine-time-mode="archive"][data-dashboard-limit-mode="current"][data-engine-limit-mode="current"])
             )

      view
      |> element("#dashboard-diagnostics-button")
      |> render_click()

      assert has_element?(
               view,
               ~s(#dashboard-diagnostics-panel[data-runtime-refresh-status="settled"][data-runtime-refresh-reason="accepted"][data-runtime-visible-refresh-action="accept_result"][data-runtime-refresh-starts*="runtime_context_changed:1"][data-runtime-refresh-cancellations*="runtime_context_changed:1"][data-runtime-canceled-resolves="1"])
             )

      assert has_element?(
               view,
               ~s(#dashboard-diagnostics-panel[data-runtime-last-refresh-duration-ms])
             )

      assert has_element?(
               view,
               ~s(#dashboard-diagnostics-panel [data-diagnostics-field="Refresh status"]),
               "settled"
             )

      assert has_element?(
               view,
               ~s(#dashboard-diagnostics-panel [data-diagnostics-field="Last refresh duration ms"])
             )

      assert has_element?(
               view,
               ~s(#dashboard-diagnostics-panel [data-diagnostics-field="Refresh cancellations"]),
               "runtime_context_changed:1"
             )
    end

    test "data realm control is source-binding aware" do
      {conn, org, mission} = signed_in_org_and_mission()
      spacecraft = TestFixtures.persist_spacecraft!(mission, display_name: "SC Realm")
      binding_set = persist_binding_set!(org, mission)
      ingest!(mission, binding_set, spacecraft.spacecraft_id, 5, 1_700_000_100)
      _defaults = DataSources.ensure_default_managed_sources!()
      persist_dashboard_realm!(mission, :rehearsal)

      dashboard =
        TestFixtures.persist_dashboard_document!(mission,
          name: "Realm",
          widgets: [value_tile("HK.counter", :fixed, spacecraft.spacecraft_id)]
        )

      {:ok, view, _html} = live(conn, show_path(mission, dashboard) <> "?realm=rehearsal")
      render_dashboard_async(view)

      assert has_element?(view, ~s(#dashboard-data-realm option[value="rehearsal"]))

      assert has_element?(
               view,
               ~s(#ops-dashboard-show-page[data-dashboard-data-realm="rehearsal"][data-engine-data-realm="rehearsal"])
             )

      {:ok, invalid_view, _html} =
        live(conn, show_path(mission, dashboard) <> "?realm=simulation")

      render_dashboard_async(invalid_view)

      assert has_element?(
               invalid_view,
               ~s(#ops-dashboard-show-page[data-dashboard-data-realm="flight"][data-engine-data-realm="flight"])
             )
    end

    test "runtime context control selects an explicit source binding" do
      {conn, org, mission} = signed_in_org_and_mission()
      spacecraft = TestFixtures.persist_spacecraft!(mission, display_name: "SC Source Select")
      binding_set = persist_binding_set!(org, mission)
      unique = System.unique_integer([:positive])

      persist_dashboard_realm!(mission, :flight)

      source_context =
        persist_dashboard_realm_source!(
          mission,
          :rehearsal,
          "dashboard-selector-source-#{unique}",
          "dashboard-selector-binding-#{unique}"
        )

      configure_telemetry_storage_source!(
        :rehearsal,
        source_context.data_source_id,
        source_context.binding_id
      )

      ingest!(mission, binding_set, spacecraft.spacecraft_id, 23, 1_700_000_100)

      dashboard =
        TestFixtures.persist_dashboard_document!(mission,
          name: "Source Selector",
          widgets: [
            %{
              type: :time_series,
              title: "Source Trend",
              binding: %{
                mode: :fixed,
                spacecraft_id: spacecraft.spacecraft_id,
                point_id: "HK.counter"
              }
            }
          ]
        )

      document = fetch_dashboard_document!(org, mission, dashboard)
      trend_widget = render_item_by_title(document, "Source Trend").widget

      {:ok, view, _html} = live(conn, show_path(mission, dashboard) <> "?realm=rehearsal")
      render_dashboard_async(view)

      assert has_element?(
               view,
               ~s(#dashboard-source-binding option[value="#{source_context.binding_id}"])
             )

      view
      |> element("#runtime-context-form")
      |> render_change(%{
        "time_mode" => "live",
        "from" => "",
        "to" => "",
        "realm" => "rehearsal",
        "source_binding_id" => source_context.binding_id,
        "data_view" => "all_revisions",
        "limit_mode" => "observed"
      })

      patched_path = assert_patch(view)
      assert patched_path =~ "realm=rehearsal"
      assert patched_path =~ "data_view=all_revisions"
      assert patched_path =~ "data_source_id=#{source_context.data_source_id}"
      assert patched_path =~ "source_binding_id=#{source_context.binding_id}"

      render_dashboard_async(view)

      assert has_element?(
               view,
               ~s(#dashboard-active-source[data-dashboard-active-data-source="#{source_context.data_source_id}"][data-dashboard-active-source-binding="#{source_context.binding_id}"]),
               source_context.binding_id
             )

      assert has_element?(
               view,
               ~s(#ops-dashboard-show-page[data-dashboard-data-view="all_revisions"][data-engine-data-view="all_revisions"][data-dashboard-data-source-id="#{source_context.data_source_id}"][data-dashboard-source-binding-id="#{source_context.binding_id}"][data-engine-data-source-id="#{source_context.data_source_id}"][data-engine-source-binding-id="#{source_context.binding_id}"])
             )

      html = render(view)
      [selected_point] = chart_backfill(html, trend_widget.widget_id)
      selected_meta = point_meta(selected_point)
      selected_link_id = selected_meta["link_id"]
      selected_sample_id = selected_meta["sample_id"]
      selected_timestamp_ms = List.first(selected_point)
      source_data_source_id = source_context.data_source_id
      source_binding_id = source_context.binding_id
      spacecraft_id = spacecraft.spacecraft_id
      placement_id = trend_widget.widget_id
      trend_chart_id = chart_dom_id(html, trend_widget.widget_id)

      view
      |> element("##{trend_chart_id}")
      |> render_hook("open_data_link", %{
        "link-id" => selected_link_id,
        "placement-id" => trend_widget.widget_id,
        "target" => "telemetry_sample",
        "target-id" => selected_sample_id,
        "timestamp-ms" => selected_timestamp_ms
      })

      assert_push_event(
        view,
        "tlm:select",
        %{
          "selection" => %{
            "data_source_id" => ^source_data_source_id,
            "data_view" => "all_revisions",
            "limit_mode" => "observed",
            "link_id" => ^selected_link_id,
            "observable_id" => "HK.counter",
            "placement_id" => ^placement_id,
            "realm" => "rehearsal",
            "source" => "frame",
            "source_binding_id" => ^source_binding_id,
            "spacecraft_id" => ^spacecraft_id,
            "target" => "telemetry_sample",
            "target_id" => ^selected_sample_id,
            "target_text" => "telemetry sample",
            "timestamp_ms" => ^selected_timestamp_ms
          }
        },
        1_000
      )

      selected_source_path = assert_patch(view)
      assert selected_source_path =~ "selected_target=telemetry_sample"
      assert selected_source_path =~ "selected_time=#{selected_timestamp_ms}"
      assert selected_source_path =~ "source_binding_id=#{source_context.binding_id}"

      assert has_element?(
               view,
               ~s(#dashboard-data-link-inspector[data-data-link-target="telemetry_sample"][data-data-link-status="resolved"])
             )

      assert has_element?(
               view,
               ~s(#ops-dashboard-show-page[data-dashboard-selection-state="active"][data-dashboard-selection-target="telemetry_sample"][data-dashboard-selection-source-binding="#{source_context.binding_id}"])
             )

      view
      |> element("#runtime-context-form")
      |> render_change(%{
        "time_mode" => "live",
        "from" => "",
        "to" => "",
        "realm" => "flight",
        "source_binding_id" => "primary",
        "data_view" => "canonical",
        "limit_mode" => "observed"
      })

      assert_push_event(
        view,
        "tlm:select",
        %{"selection" => nil},
        1_000
      )

      switched_source_path = assert_patch(view)
      refute switched_source_path =~ "selected_target="
      refute switched_source_path =~ "selected_id="
      refute switched_source_path =~ "selected_placement="
      refute has_element?(view, "#dashboard-data-link-inspector")

      assert has_element?(
               view,
               ~s(#ops-dashboard-show-page[data-dashboard-selection-state="stale_context"])
             )

      assert has_element?(view, "#dashboard-pause-at-selection[disabled]")
      assert has_element?(view, "#dashboard-clear-selection[disabled]")
    end

    test "saves and applies dashboard runtime data defaults" do
      {conn, org, mission} = signed_in_org_and_mission()
      spacecraft = TestFixtures.persist_spacecraft!(mission, display_name: "SC Defaults")
      binding_set = persist_binding_set!(org, mission)
      unique = System.unique_integer([:positive])

      persist_dashboard_realm!(mission, :flight)

      source_context =
        persist_dashboard_realm_source!(
          mission,
          :rehearsal,
          "dashboard-default-source-#{unique}",
          "dashboard-default-binding-#{unique}"
        )

      configure_telemetry_storage_source!(
        :rehearsal,
        source_context.data_source_id,
        source_context.binding_id
      )

      ingest!(mission, binding_set, spacecraft.spacecraft_id, 31, 1_700_000_100)

      dashboard =
        TestFixtures.persist_dashboard_document!(mission,
          name: "Runtime Defaults",
          widgets: [value_tile("HK.counter", :fixed, spacecraft.spacecraft_id)]
        )

      {:ok, view, _html} =
        live(
          conn,
          show_path(mission, dashboard) <>
            "?realm=rehearsal&source_binding_id=#{source_context.binding_id}"
        )

      render_dashboard_async(view)

      view
      |> element(~s(#dashboard-menu button[phx-click="save_runtime_defaults"]))
      |> render_click()

      saved_document = fetch_dashboard_document!(org, mission, dashboard)

      assert get_in(saved_document.defaults, ["data", "realm"]) == "rehearsal"

      assert get_in(saved_document.defaults, [
               "data",
               "source_contexts",
               "telemetry",
               "source_binding_id"
             ]) == source_context.binding_id

      {:ok, default_view, _html} = live(conn, show_path(mission, dashboard))
      render_dashboard_async(default_view)

      assert has_element?(
               default_view,
               ~s(#ops-dashboard-show-page[data-dashboard-data-realm="rehearsal"][data-dashboard-source-binding-id="#{source_context.binding_id}"][data-engine-source-binding-id="#{source_context.binding_id}"])
             )

      {:ok, override_view, _html} = live(conn, show_path(mission, dashboard) <> "?realm=flight")
      render_dashboard_async(override_view)

      assert has_element?(
               override_view,
               ~s(#ops-dashboard-show-page[data-dashboard-data-realm="flight"])
             )

      assert has_element?(override_view, "#dashboard-active-source", "Primary source")

      {:ok, clear_view, _html} =
        live(conn, show_path(mission, dashboard) <> "?source_binding_id=primary")

      render_dashboard_async(clear_view)

      clear_view
      |> element(~s(#dashboard-menu button[phx-click="save_runtime_defaults"]))
      |> render_click()

      render_dashboard_async(view)
      render_dashboard_async(default_view)
      render_dashboard_async(override_view)
      render_dashboard_async(clear_view)

      cleared_document = fetch_dashboard_document!(org, mission, dashboard)
      assert get_in(cleared_document.defaults, ["data", "realm"]) == "rehearsal"
      assert get_in(cleared_document.defaults, ["data", "source_contexts"]) == %{}

      stop_dashboard_view(view)
      stop_dashboard_view(default_view)
      stop_dashboard_view(override_view)
      stop_dashboard_view(clear_view)
    end

    test "runtime default saves create drafts without changing published operator defaults" do
      {conn, org, mission} = signed_in_org_and_mission()

      spacecraft =
        TestFixtures.persist_spacecraft!(mission, display_name: "SC Published Defaults")

      binding_set = persist_binding_set!(org, mission)
      unique = System.unique_integer([:positive])

      persist_dashboard_realm!(mission, :flight)

      source_context =
        persist_dashboard_realm_source!(
          mission,
          :rehearsal,
          "published-default-source-#{unique}",
          "published-default-binding-#{unique}"
        )

      configure_telemetry_storage_source!(
        :rehearsal,
        source_context.data_source_id,
        source_context.binding_id
      )

      ingest!(mission, binding_set, spacecraft.spacecraft_id, 41, 1_700_000_100)

      dashboard =
        TestFixtures.persist_dashboard_document!(mission,
          name: "Published Runtime Defaults",
          widgets: [value_tile("HK.counter", :fixed, spacecraft.spacecraft_id)]
        )

      assert {:ok, %Cadence.Dashboards.Version{}} =
               Cadence.Dashboards.publish_document(
                 org.organization_id,
                 mission.mission_id,
                 dashboard.dashboard_id,
                 Document.version(dashboard),
                 expected_version: Document.version(dashboard)
               )

      {:ok, view, _html} =
        live(
          conn,
          show_path(mission, dashboard) <>
            "?realm=rehearsal&source_binding_id=#{source_context.binding_id}"
        )

      render_dashboard_async(view)

      assert has_element?(
               view,
               ~s(#ops-dashboard-show-page[data-dashboard-document-mode="published"])
             )

      view
      |> element(~s(#dashboard-menu button[phx-click="save_runtime_defaults"]))
      |> render_click()

      render_dashboard_async(view)

      assert has_element?(
               view,
               ~s(#ops-dashboard-show-page[data-dashboard-document-mode="published"][data-dashboard-draft-defaults-differ="true"])
             )

      assert {:ok, published_document} =
               Cadence.Dashboards.fetch_published_document(
                 org.organization_id,
                 mission.mission_id,
                 dashboard.dashboard_id
               )

      assert get_in(published_document.defaults, ["data", "source_contexts"]) == nil

      draft_document = fetch_dashboard_document!(org, mission, dashboard)
      assert Document.version(draft_document) == 2

      assert get_in(draft_document.defaults, [
               "data",
               "source_contexts",
               "telemetry",
               "source_binding_id"
             ]) == source_context.binding_id

      assert [%Cadence.Dashboards.DashboardSummary{} = summary] =
               Cadence.Dashboards.list_dashboard_summaries(
                 org.organization_id,
                 mission.mission_id
               )

      assert summary.latest_version == 2
      assert summary.draft_version == 2
      assert summary.published_version == 1

      {:ok, published_view, _html} = live(conn, show_path(mission, dashboard))
      render_dashboard_async(published_view)

      assert has_element?(
               published_view,
               ~s(#ops-dashboard-show-page[data-dashboard-document-mode="published"][data-dashboard-data-realm="flight"])
             )

      published_view |> element("#edit-layout-toggle") |> render_click()

      assert has_element?(
               published_view,
               ~s(#ops-dashboard-show-page[data-dashboard-document-mode="draft"][data-dashboard-data-realm="rehearsal"][data-dashboard-source-binding-id="#{source_context.binding_id}"])
             )

      published_view |> element("#edit-layout-toggle") |> render_click()
      render_dashboard_async(published_view)

      assert has_element?(
               published_view,
               ~s(#ops-dashboard-show-page[data-dashboard-document-mode="published"][data-dashboard-data-realm="flight"])
             )
    end

    test "surfaces source-binding warnings on dashboard and widgets" do
      {conn, org, mission} = signed_in_org_and_mission()
      spacecraft = TestFixtures.persist_spacecraft!(mission, display_name: "SC Warning")
      binding_set = persist_binding_set!(org, mission)
      ingest!(mission, binding_set, spacecraft.spacecraft_id, 5, 1_700_000_100)
      _defaults = DataSources.ensure_default_managed_sources!()
      persist_dashboard_realm!(mission, :rehearsal)

      dashboard =
        TestFixtures.persist_dashboard_document!(mission,
          name: "Warnings",
          widgets: [value_tile("HK.counter", :fixed, spacecraft.spacecraft_id)]
        )

      document = fetch_dashboard_document!(org, mission, dashboard)
      widget = render_item_by_title(document, "Counter").widget
      {:ok, view, _html} = live(conn, show_path(mission, dashboard) <> "?realm=rehearsal")
      render_dashboard_async(view)

      assert has_element?(
               view,
               ~s(#dashboard-engine-warnings[data-engine-degraded="true"][data-warning-codes*="missing_source_binding"])
             )

      assert has_element?(
               view,
               ~s(#dashboard-source-health[data-source-health*="Telemetry:unknown"])
             )

      assert has_element?(
               view,
               ~s([data-source-health-detail="Telemetry:unknown"] [data-source-health-field="Data source"]),
               "test-rehearsal-questdb"
             )

      assert has_element?(
               view,
               ~s(#widget-#{widget.widget_id} [data-warning-codes*="missing_source_binding"])
             )

      assert has_element?(
               view,
               ~s([data-engine-warning="missing_source_binding"]),
               "Source missing"
             )

      assert has_element?(
               view,
               ~s([data-engine-warning-detail="missing_source_binding"] [data-warning-detail="Logical source"]),
               "limits"
             )

      assert has_element?(
               view,
               ~s([data-engine-warning-detail="missing_source_binding"] [data-warning-detail="Realm"]),
               "rehearsal"
             )

      assert has_element?(
               view,
               ~s([data-engine-warning-detail="missing_source_binding"] [data-warning-detail="Source request id"])
             )

      assert has_element?(
               view,
               ~s([data-engine-warning-detail="missing_source_binding"] [data-warning-link-target="telemetry point"][data-warning-link-id="HK.counter"])
             )

      view
      |> element(
        ~s(#widget-#{widget.widget_id} [data-warning-evidence-open][phx-value-warning-code="missing_source_binding"][phx-value-logical-source="limits"][phx-value-realm="rehearsal"][phx-value-source-request-id])
      )
      |> render_click()

      warning_evidence_path = assert_patch(view)
      assert warning_evidence_path =~ "panel=evidence"
      assert warning_evidence_path =~ "selected_evidence_kind=warning"
      assert warning_evidence_path =~ "selected_warning_code=missing_source_binding"
      assert warning_evidence_path =~ "selected_logical_source=limits"
      assert warning_evidence_path =~ "selected_realm=rehearsal"
      assert warning_evidence_path =~ "selected_source_request="

      assert warning_evidence_path =~
               "selected_placement=#{URI.encode_www_form(widget.widget_id)}"

      assert has_element?(
               view,
               ~s(#dashboard-evidence-inspector[data-evidence-kind="warning"][data-evidence-subject="missing_source_binding"])
             )

      assert has_element?(
               view,
               ~s(#ops-dashboard-show-page[data-dashboard-evidence-state="active"][data-dashboard-evidence-kind="warning"][data-dashboard-evidence-logical-source="limits"][data-dashboard-evidence-realm="rehearsal"][data-dashboard-selection-state="none"])
             )

      assert has_element?(
               view,
               ~s(#dashboard-evidence-inspector [data-evidence-detail="Logical source"]),
               "limits"
             )

      assert has_element?(
               view,
               ~s(#dashboard-evidence-inspector [data-evidence-link-target="telemetry point"][data-evidence-link-id="HK.counter"][phx-value-realm="rehearsal"])
             )

      assert has_element?(
               view,
               ~s(#dashboard-evidence-copy-link[phx-hook="ClipboardButton"][data-clipboard-text*="panel=evidence"][data-clipboard-text*="selected_evidence_kind=warning"][data-clipboard-text*="selected_warning_code=missing_source_binding"][data-clipboard-text*="selected_placement=#{URI.encode_www_form(widget.widget_id)}"])
             )

      refute has_element?(
               view,
               ~s(#dashboard-evidence-copy-link[data-clipboard-text*="selected_target="])
             )

      assert has_element?(
               view,
               ~s(#dashboard-evidence-explore[data-dashboard-action-target="telemetry_explore"][data-dashboard-action-source="evidence_panel"][href*="/ops/telemetry/explore"][href*="point_id=HK.counter"][href*="source_dashboard_id=#{dashboard.dashboard_id}"])
             )

      assert has_element?(
               view,
               ~s(#dashboard-evidence-inspector [data-evidence-empty="refs"])
             )

      view
      |> element(
        ~s(#dashboard-evidence-inspector [data-evidence-link-target="telemetry point"][data-evidence-link-id="HK.counter"])
      )
      |> render_click()

      data_link_path = assert_patch(view)
      assert data_link_path =~ "panel=data_link"
      assert data_link_path =~ "selected_target=telemetry_point"
      assert data_link_path =~ "realm=rehearsal"
      refute data_link_path =~ "selected_evidence_kind="

      assert has_element?(
               view,
               ~s(#dashboard-data-link-inspector[data-data-link-target="telemetry_point"][data-data-link-status="context_only"])
             )

      assert has_element?(
               view,
               ~s(#ops-dashboard-show-page[data-dashboard-evidence-state="none"])
             )

      view
      |> element(
        ~s(#dashboard-source-health [data-source-evidence-open][phx-value-logical-source="telemetry"])
      )
      |> render_click()

      source_evidence_path = assert_patch(view)
      assert source_evidence_path =~ "panel=evidence"
      assert source_evidence_path =~ "selected_evidence_kind=source"
      assert source_evidence_path =~ "selected_source_evidence_mode=health"
      assert source_evidence_path =~ "selected_logical_source=telemetry"
      assert source_evidence_path =~ "realm=rehearsal"
      refute source_evidence_path =~ "selected_link="

      assert has_element?(
               view,
               ~s(#dashboard-evidence-inspector[data-evidence-kind="source"][data-evidence-status="unknown"])
             )

      assert has_element?(
               view,
               ~s(#dashboard-evidence-copy-link[data-clipboard-text*="panel=evidence"][data-clipboard-text*="selected_evidence_kind=source"][data-clipboard-text*="selected_logical_source=telemetry"][data-clipboard-text*="realm=rehearsal"])
             )

      refute has_element?(
               view,
               ~s(#dashboard-evidence-copy-link[data-clipboard-text*="selected_target="])
             )

      assert has_element?(
               view,
               ~s(#ops-dashboard-show-page[data-dashboard-evidence-state="active"][data-dashboard-evidence-kind="source"][data-dashboard-evidence-source-request][data-dashboard-evidence-logical-source="telemetry"][data-dashboard-evidence-realm="rehearsal"])
             )

      assert has_element?(
               view,
               ~s(#dashboard-evidence-inspector [data-evidence-subject-field="Data source"]),
               "test-rehearsal-questdb"
             )

      assert has_element?(
               view,
               ~s(#dashboard-evidence-inspector [data-evidence-subject-field="Source request"])
             )

      assert has_element?(
               view,
               ~s(#dashboard-evidence-source-inventory[data-dashboard-action-target="source_inventory"][data-dashboard-action-source="evidence_panel"][href*="/ops/data-sources"][href*="realm=rehearsal"][href*="data_source_id=test-rehearsal-questdb"][href*="source_binding_id="][href*="source_dashboard_id=#{dashboard.dashboard_id}"])
             )

      assert has_element?(
               view,
               ~s(#dashboard-evidence-inspector [data-evidence-empty="links"])
             )

      {:ok, source_evidence_view, _html} = live(conn, source_evidence_path)
      render_dashboard_async(source_evidence_view)

      assert has_element?(
               source_evidence_view,
               ~s(#dashboard-evidence-inspector[data-evidence-kind="source"][data-evidence-status="unknown"])
             )

      missing_warning_path =
        ~p"/missions/#{mission.mission_id}/ops/dashboards/#{dashboard.dashboard_id}?#{%{panel: "evidence", selected_evidence_kind: "warning", selected_placement: widget.widget_id, selected_warning_code: "missing_warning", selected_source_request: "stale-source-request", selected_logical_source: "limits", selected_realm: "rehearsal"}}"

      {:ok, missing_warning_view, _html} = live(conn, missing_warning_path)
      render_dashboard_async(missing_warning_view)

      assert has_element?(
               missing_warning_view,
               ~s(#dashboard-evidence-inspector[data-evidence-kind="warning"][data-evidence-status="missing"][data-evidence-subject="missing_warning"])
             )

      assert has_element?(
               missing_warning_view,
               ~s(#ops-dashboard-show-page[data-dashboard-evidence-state="missing"][data-dashboard-evidence-kind="warning"][data-dashboard-evidence-logical-source="limits"][data-dashboard-evidence-realm="rehearsal"])
             )

      assert has_element?(
               missing_warning_view,
               ~s(#dashboard-evidence-inspector [data-evidence-subject-field="Warning"]),
               "missing_warning"
             )

      assert has_element?(
               missing_warning_view,
               ~s(#dashboard-evidence-inspector [data-evidence-subject-field="Source request"]),
               "stale-source-request"
             )

      assert has_element?(
               missing_warning_view,
               ~s(#dashboard-evidence-inspector [data-evidence-subject-field="Logical source"]),
               "limits"
             )

      assert has_element?(
               missing_warning_view,
               ~s(#dashboard-evidence-inspector [data-evidence-detail="Realm"]),
               "rehearsal"
             )

      assert has_element?(
               missing_warning_view,
               ~s(#dashboard-evidence-copy-link[data-clipboard-text*="panel=evidence"][data-clipboard-text*="selected_evidence_kind=warning"][data-clipboard-text*="selected_warning_code=missing_warning"][data-clipboard-text*="selected_source_request=stale-source-request"][data-clipboard-text*="selected_logical_source=limits"][data-clipboard-text*="selected_realm=rehearsal"])
             )

      missing_source_path =
        ~p"/missions/#{mission.mission_id}/ops/dashboards/#{dashboard.dashboard_id}?#{%{panel: "evidence", selected_evidence_kind: "source", selected_logical_source: "telemetry", selected_realm: "missing-realm", selected_data_source: "missing-source", selected_source_binding: "missing-binding"}}"

      {:ok, missing_source_view, _html} = live(conn, missing_source_path)
      render_dashboard_async(missing_source_view)

      assert has_element?(
               missing_source_view,
               ~s(#dashboard-evidence-inspector[data-evidence-kind="source"][data-evidence-status="missing"][data-evidence-subject="telemetry"])
             )

      assert has_element?(
               missing_source_view,
               ~s(#ops-dashboard-show-page[data-dashboard-evidence-state="missing"][data-dashboard-evidence-kind="source"][data-dashboard-evidence-logical-source="telemetry"][data-dashboard-evidence-realm="missing-realm"][data-dashboard-evidence-data-source-id="missing-source"][data-dashboard-evidence-source-binding-id="missing-binding"])
             )

      assert has_element?(
               missing_source_view,
               ~s(#dashboard-evidence-inspector [data-evidence-subject-field="Logical source"]),
               "telemetry"
             )

      assert has_element?(
               missing_source_view,
               ~s(#dashboard-evidence-copy-link[data-clipboard-text*="panel=evidence"][data-clipboard-text*="selected_evidence_kind=source"][data-clipboard-text*="selected_logical_source=telemetry"][data-clipboard-text*="selected_realm=missing-realm"][data-clipboard-text*="selected_data_source=missing-source"][data-clipboard-text*="selected_source_binding=missing-binding"])
             )

      view |> element(~s(#dashboard-panel button[aria-label="Close panel"])) |> render_click()
      cleared_source_evidence_path = assert_patch(view)
      assert cleared_source_evidence_path =~ "realm=rehearsal"
      refute cleared_source_evidence_path =~ "panel="
      refute cleared_source_evidence_path =~ "selected_evidence_kind="
    end

    test "surfaces unsupported source capability warnings on widgets" do
      {conn, org, mission} = signed_in_org_and_mission()
      spacecraft = TestFixtures.persist_spacecraft!(mission, display_name: "SC Capability")
      binding_set = persist_binding_set!(org, mission)
      ingest!(mission, binding_set, spacecraft.spacecraft_id, 5, 1_700_000_100)
      _defaults = DataSources.ensure_default_managed_sources!()
      persist_dashboard_realm!(mission, :flight, %{latest?: true, range_scan?: false})

      dashboard =
        TestFixtures.persist_dashboard_document!(mission,
          name: "Capability",
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
      widget = render_item_by_title(document, "Counter Trend").widget
      {:ok, view, _html} = live(conn, show_path(mission, dashboard))
      render_dashboard_async(view)

      assert has_element?(
               view,
               ~s(#dashboard-engine-warnings[data-engine-degraded="true"][data-warning-codes*="unsupported_source_capability"])
             )

      assert has_element?(
               view,
               ~s(#ops-dashboard-show-page[data-runtime-refresh-status="degraded"][data-runtime-refresh-reason="source_execution_degraded"][data-runtime-visible-refresh-action="accept_result"][data-runtime-source-execution-degraded="1"])
             )

      assert has_element?(
               view,
               ~s(#ops-dashboard-show-page[data-runtime-source-execution-degraded-identities*="telemetry"][data-runtime-source-execution-degraded-identities*="unsupported_capability"])
             )

      assert has_element?(
               view,
               ~s(#ops-dashboard-show-page[data-runtime-source-execution-degraded-actions*="requires_configuration_change"][data-runtime-source-execution-degraded-actions*="inspect_source_capability"])
             )

      view
      |> element("#dashboard-diagnostics-button")
      |> render_click()

      assert has_element?(
               view,
               ~s(#dashboard-diagnostics-panel[data-runtime-source-execution-degraded-identities*="telemetry"][data-runtime-source-execution-degraded-actions*="requires_configuration_change"])
             )

      assert has_element?(
               view,
               ~s(#dashboard-source-execution-degraded-summary[data-source-execution-degraded-count="1"][data-source-execution-degraded-identity*="telemetry"][data-source-execution-degraded-identity*="unsupported_capability"][data-source-execution-degraded-status="unsupported_capability"][data-source-execution-runtime-action="requires_configuration_change"][data-source-execution-operator-action="inspect_source_capability"])
             )

      assert has_element?(
               view,
               ~s(#dashboard-source-execution-degraded-summary [data-source-execution-field="Runtime"]),
               "requires_configuration_change"
             )

      assert has_element?(
               view,
               ~s(#dashboard-source-execution-degraded-summary [data-source-execution-field="Operator"]),
               "inspect_source_capability"
             )

      assert has_element?(
               view,
               ~s(#dashboard-diagnostics-panel [data-diagnostics-field="Degraded source identities"]),
               "telemetry"
             )

      assert has_element?(
               view,
               ~s(#dashboard-degraded-source-drilldowns [data-degraded-source-logical-source="telemetry"][data-degraded-source-status="unsupported_capability"][data-degraded-source-runtime-action="requires_configuration_change"])
             )

      view
      |> element(
        ~s(#dashboard-degraded-source-drilldowns [data-degraded-source-logical-source="telemetry"])
      )
      |> render_click()

      degraded_source_evidence_path = assert_patch(view)
      assert degraded_source_evidence_path =~ "panel=evidence"
      assert degraded_source_evidence_path =~ "selected_evidence_kind=source"
      assert degraded_source_evidence_path =~ "selected_source_evidence_mode=execution"
      assert degraded_source_evidence_path =~ "selected_logical_source=telemetry"
      assert degraded_source_evidence_path =~ "selected_source_request="

      assert has_element?(
               view,
               ~s(#dashboard-evidence-inspector[data-evidence-kind="source"])
             )

      assert has_element?(
               view,
               ~s(#ops-dashboard-show-page[data-dashboard-evidence-state="active"][data-dashboard-evidence-kind="source"][data-dashboard-evidence-source-request])
             )

      assert has_element?(
               view,
               ~s(#dashboard-evidence-inspector [data-evidence-subject-field="Source request"])
             )

      assert has_element?(
               view,
               ~s(#dashboard-evidence-inspector [data-evidence-detail="Execution status"]),
               "unsupported_capability"
             )

      assert has_element?(
               view,
               ~s(#dashboard-evidence-inspector [data-evidence-detail="Execution runtime action"]),
               "requires_configuration_change"
             )

      view |> element(~s(#dashboard-panel button[aria-label="Close panel"])) |> render_click()
      refute assert_patch(view) =~ "panel="

      assert has_element?(
               view,
               ~s(#widget-#{widget.widget_id} [data-warning-codes*="unsupported_source_capability"])
             )

      assert has_element?(
               view,
               ~s([data-engine-warning="unsupported_source_capability"]),
               "Unsupported source capability"
             )

      assert has_element?(
               view,
               ~s([data-engine-warning-detail="unsupported_source_capability"] [data-warning-detail="Requested sampling"]),
               "raw_series"
             )

      assert has_element?(
               view,
               ~s([data-engine-warning-detail="unsupported_source_capability"] [data-warning-detail="Supported sampling 1"]),
               "latest"
             )

      assert has_element?(
               view,
               ~s([data-engine-warning-detail="unsupported_source_capability"] [data-warning-detail="Source execution action"]),
               "inspect_source_capability"
             )

      assert has_element?(
               view,
               ~s([data-engine-warning-detail="unsupported_source_capability"] [data-warning-link-target="telemetry point"][data-warning-link-id="HK.counter"][phx-value-data-source-id][phx-value-source-binding-id])
             )

      view
      |> element(
        ~s(#widget-#{widget.widget_id} [data-engine-warning-detail="unsupported_source_capability"] [data-warning-link-target="telemetry point"][data-warning-link-id="HK.counter"][phx-value-data-source-id][phx-value-source-binding-id])
      )
      |> render_click()

      unsupported_link_path = assert_patch(view)
      assert unsupported_link_path =~ "panel=data_link"
      assert unsupported_link_path =~ "selected_target=telemetry_point"
      assert unsupported_link_path =~ "data_source_id="
      assert unsupported_link_path =~ "source_binding_id="

      assert has_element?(
               view,
               ~s(#dashboard-data-link-inspector[data-data-link-target="telemetry_point"][data-data-link-status="context_only"])
             )

      assert has_element?(
               view,
               ~s(#dashboard-data-link-inspector [data-data-link-field="Point"]),
               "HK.counter"
             )

      assert has_element?(
               view,
               ~s(#dashboard-data-link-inspector [data-data-link-context="Source request"])
             )
    end

    test "adds a widget through the slide-over panel" do
      enable_dashboard_engine_inline_resolves!()

      {conn, user, org, mission} = signed_in_user_org_and_mission()
      binding_set = persist_binding_set!(org, mission)
      activate_binding_set!(org, mission, binding_set)
      %Document{} = dashboard = TestFixtures.persist_dashboard_document!(mission, name: "Power")

      {:ok, view, _html} = live(conn, show_path(mission, dashboard))
      render_dashboard_async(view)

      view |> element("#add-widget-button") |> render_click()
      assert has_element?(view, "#dashboard-panel")

      view |> element(~s(button[phx-value-point-id="HK.counter"])) |> render_click()

      view
      |> form("#widget-form", widget: %{type: "value_tile", title: "Counter", mode: "context"})
      |> render_submit()

      render_dashboard_async(view)

      refute has_element?(view, "#dashboard-panel")
      assert has_element?(view, ~s(.grid-stack-item[gs-auto-position="true"]))

      view |> element("#dashboard-versions-button") |> render_click()

      assert has_element?(
               view,
               ~s(#dashboard-version-2 [data-version-field="Summary"]),
               "Added widget"
             )

      assert has_element?(
               view,
               ~s(#dashboard-version-2 [data-version-field="Author"]),
               user.user_id
             )

      stop_dashboard_view(view)

      document = fetch_dashboard_document!(org, mission, dashboard)

      assert [%{placement_id: placement_id, layout: %{x: nil, y: nil}} = placement] =
               document.placements

      assert placement.widget_def.title == "Counter"

      assert [%{placement_id: ^placement_id, widget: %{widget_id: ^placement_id}}] =
               RenderItem.from_document(document)

      assert Document.version(document) == 2

      version = fetch_dashboard_version!(org, mission, dashboard, 2)
      assert version.change_summary == "Added widget"
      assert version.created_by == user.user_id
    end

    test "binding source selector follows widget frame contracts" do
      {conn, _org, mission} = signed_in_org_and_mission()
      %Document{} = dashboard = TestFixtures.persist_dashboard_document!(mission, name: "Power")

      {:ok, view, _html} = live(conn, show_path(mission, dashboard))
      render_dashboard_async(view)

      view |> element("#add-widget-button") |> render_click()

      assert has_element?(
               view,
               ~s(#widget-form select[name="widget[binding_source]"] option[value="telemetry"])
             )

      assert has_element?(
               view,
               ~s(#widget-form select[name="widget[binding_source]"] option[value="operational_observables"])
             )

      view
      |> form("#widget-form", widget: %{type: "time_series", title: "Trend"})
      |> render_change()

      assert has_element?(
               view,
               ~s(#widget-form select[name="widget[binding_source]"] option[value="operational_observables"])
             )

      view
      |> form("#widget-form", widget: %{type: "status_matrix", title: "Matrix"})
      |> render_change()

      assert has_element?(
               view,
               ~s(#widget-form select[name="widget[binding_source]"] option[value="operational_observables"])
             )

      view
      |> form("#widget-form", widget: %{type: "data_table", title: "Table"})
      |> render_change()

      assert has_element?(
               view,
               ~s(#widget-form select[name="widget[binding_source]"] option[value="operational_observables"])
             )

      stop_dashboard_view(view)
    end

    test "adds an event timeline widget without selecting telemetry points" do
      enable_dashboard_engine_inline_resolves!()

      {conn, org, mission} = signed_in_org_and_mission()
      %Document{} = dashboard = TestFixtures.persist_dashboard_document!(mission, name: "Power")

      {:ok, view, _html} = live(conn, show_path(mission, dashboard))
      render_dashboard_async(view)

      view |> element("#add-widget-button") |> render_click()

      view
      |> form("#widget-form", widget: %{type: "event_timeline", title: "Mission Events"})
      |> render_submit()

      render_dashboard_async(view)

      refute has_element?(view, "#dashboard-panel")
      assert has_element?(view, ~s([data-event-timeline]))

      stop_dashboard_view(view)

      document = fetch_dashboard_document!(org, mission, dashboard)
      assert [placement] = document.placements
      assert placement.widget_def.widget_type_id == "cadence.event_timeline"

      assert Map.take(placement.widget_def.binding, [
               :source,
               :observables,
               :scope_mode,
               :data_mode,
               :value_type,
               :sampling,
               :overlays
             ]) == %{
               source: :events,
               observables: [],
               scope_mode: :context,
               data_mode: :context,
               value_type: nil,
               sampling: :event_history,
               overlays: []
             }
    end

    test "adds a state timeline widget from a selected telemetry point" do
      enable_dashboard_engine_inline_resolves!()

      {conn, org, mission} = signed_in_org_and_mission()
      binding_set = persist_binding_set!(org, mission)
      activate_binding_set!(org, mission, binding_set)
      %Document{} = dashboard = TestFixtures.persist_dashboard_document!(mission, name: "Power")

      {:ok, view, _html} = live(conn, show_path(mission, dashboard))
      render_dashboard_async(view)

      view |> element("#add-widget-button") |> render_click()
      view |> element(~s(button[phx-value-point-id="HK.counter"])) |> render_click()

      view
      |> form("#widget-form",
        widget: %{type: "state_timeline", title: "Counter State", mode: "context"}
      )
      |> render_submit()

      render_dashboard_async(view)

      refute has_element?(view, "#dashboard-panel")
      assert has_element?(view, ~s([data-state-timeline]))

      stop_dashboard_view(view)

      document = fetch_dashboard_document!(org, mission, dashboard)
      assert [placement] = document.placements
      assert placement.widget_def.widget_type_id == "cadence.state_timeline"

      assert Map.take(placement.widget_def.binding, [
               :source,
               :observables,
               :scope_mode,
               :data_mode,
               :value_type,
               :sampling,
               :overlays
             ]) == %{
               source: :limits,
               observables: ["HK.counter"],
               scope_mode: :context,
               data_mode: :context,
               value_type: :engineering,
               sampling: :event_history,
               overlays: [:quality]
             }
    end

    test "adds a state timeline widget from selected operational observables" do
      enable_dashboard_engine_inline_resolves!()

      {conn, org, mission} = signed_in_org_and_mission()
      %Document{} = dashboard = TestFixtures.persist_dashboard_document!(mission, name: "Power")

      {:ok, view, _html} = live(conn, show_path(mission, dashboard))
      render_dashboard_async(view)

      view |> element("#add-widget-button") |> render_click()

      view
      |> form("#widget-form",
        widget: %{
          type: "state_timeline",
          title: "Operations State",
          binding_source: "operational_observables"
        }
      )
      |> render_change()

      view |> element(~s(button[phx-value-point-id="contacts.phase"])) |> render_click()

      view
      |> element(~s(button[phx-value-point-id="comms.transport.connection_state"]))
      |> render_click()

      assert has_element?(view, ~s([data-selected-operational-observable="contacts.phase"]))

      assert has_element?(
               view,
               ~s([data-selected-operational-observable="comms.transport.connection_state"])
             )

      view
      |> form("#widget-form",
        widget: %{
          type: "state_timeline",
          title: "Operations State",
          binding_source: "operational_observables"
        }
      )
      |> render_submit()

      render_dashboard_async(view)

      refute has_element?(view, "#dashboard-panel")
      assert has_element?(view, ~s([data-state-timeline]))

      stop_dashboard_view(view)

      document = fetch_dashboard_document!(org, mission, dashboard)
      assert [placement] = document.placements
      assert placement.widget_def.widget_type_id == "cadence.state_timeline"

      assert Map.take(placement.widget_def.binding, [
               :source,
               :observables,
               :scope_mode,
               :data_mode,
               :value_type,
               :sampling,
               :overlays
             ]) == %{
               source: :operational_observables,
               observables: ["contacts.phase", "comms.transport.connection_state"],
               scope_mode: :context,
               data_mode: :context,
               value_type: :engineering,
               sampling: :event_history,
               overlays: []
             }
    end

    test "operational observable picker follows widget frame products and value kinds" do
      {conn, _org, mission} = signed_in_org_and_mission()
      %Document{} = dashboard = TestFixtures.persist_dashboard_document!(mission, name: "Power")

      {:ok, view, _html} = live(conn, show_path(mission, dashboard))
      render_dashboard_async(view)

      view |> element("#add-widget-button") |> render_click()

      view
      |> form("#widget-form",
        widget: %{
          type: "value_tile",
          title: "Downlink Bitrate",
          binding_source: "operational_observables"
        }
      )
      |> render_change()

      assert has_element?(
               view,
               ~s([data-operational-observable="comms.transport.downlink_bitrate"])
             )

      refute has_element?(view, ~s([data-operational-observable="contacts.phase"]))

      refute has_element?(
               view,
               ~s([data-operational-observable="comms.transport.connection_state"])
             )

      view
      |> form("#widget-form",
        widget: %{
          type: "status_matrix",
          title: "Operational Matrix",
          binding_source: "operational_observables"
        }
      )
      |> render_change()

      assert has_element?(view, ~s([data-operational-observable="contacts.phase"]))

      assert has_element?(
               view,
               ~s([data-operational-observable="comms.transport.connection_state"])
             )

      assert has_element?(
               view,
               ~s([data-operational-observable="comms.transport.downlink_bitrate"])
             )

      view
      |> form("#widget-form",
        widget: %{
          type: "data_table",
          title: "Operational Table",
          binding_source: "operational_observables"
        }
      )
      |> render_change()

      assert has_element?(view, ~s([data-operational-observable="contacts.phase"]))

      assert has_element?(
               view,
               ~s([data-operational-observable="comms.transport.connection_state"])
             )

      assert has_element?(
               view,
               ~s([data-operational-observable="comms.transport.downlink_bitrate"])
             )

      view
      |> form("#widget-form",
        widget: %{
          type: "state_timeline",
          title: "Operational State",
          binding_source: "operational_observables"
        }
      )
      |> render_change()

      assert has_element?(view, ~s([data-operational-observable="contacts.phase"]))

      assert has_element?(
               view,
               ~s([data-operational-observable="comms.transport.connection_state"])
             )

      refute has_element?(
               view,
               ~s([data-operational-observable="comms.transport.downlink_bitrate"])
             )

      stop_dashboard_view(view)
    end

    test "adds a status matrix with multiple points through the slide-over panel" do
      enable_dashboard_engine_inline_resolves!()

      {conn, user, org, mission} = signed_in_user_org_and_mission()
      binding_set = persist_matrix_binding_set!(org, mission)
      activate_binding_set!(org, mission, binding_set)
      %Document{} = dashboard = TestFixtures.persist_dashboard_document!(mission, name: "Power")

      {:ok, view, _html} = live(conn, show_path(mission, dashboard))
      render_dashboard_async(view)

      view |> element("#add-widget-button") |> render_click()

      view
      |> form("#widget-form",
        widget: %{
          type: "status_matrix",
          title: "HK Matrix",
          mode: "context",
          precision: "0"
        }
      )
      |> render_change()

      view |> element(~s(button[phx-value-point-id="HK.counter"])) |> render_click()
      view |> element(~s(button[phx-value-point-id="HK.voltage"])) |> render_click()

      assert has_element?(view, ~s([data-selected-point="HK.counter"]))
      assert has_element?(view, ~s([data-selected-point="HK.voltage"]))

      view
      |> form("#widget-form",
        widget: %{
          type: "status_matrix",
          title: "HK Matrix",
          mode: "context",
          precision: "0"
        }
      )
      |> render_submit()

      render_dashboard_async(view)
      refute has_element?(view, "#dashboard-panel")
      stop_dashboard_view(view)

      document = fetch_dashboard_document!(org, mission, dashboard)

      assert [%{placement_id: placement_id, widget_def: widget_def}] = document.placements
      assert widget_def.widget_type_id == "cadence.status_matrix"
      assert widget_def.binding.observables == ["HK.counter", "HK.voltage"]

      version = fetch_dashboard_version!(org, mission, dashboard, 2)
      assert version.change_summary == "Added widget"
      assert version.created_by == user.user_id

      assert [%{placement_id: ^placement_id, widget: %{binding: %{point_ids: point_ids}}}] =
               RenderItem.from_document(document)

      assert point_ids == ["HK.counter", "HK.voltage"]
    end

    test "adds a data table with multiple points through the slide-over panel" do
      enable_dashboard_engine_inline_resolves!()

      {conn, user, org, mission} = signed_in_user_org_and_mission()
      binding_set = persist_matrix_binding_set!(org, mission)
      activate_binding_set!(org, mission, binding_set)
      %Document{} = dashboard = TestFixtures.persist_dashboard_document!(mission, name: "Power")

      {:ok, view, _html} = live(conn, show_path(mission, dashboard))
      render_dashboard_async(view)

      view |> element("#add-widget-button") |> render_click()

      view
      |> form("#widget-form",
        widget: %{
          type: "data_table",
          title: "HK Table",
          mode: "context",
          precision: "1"
        }
      )
      |> render_change()

      view |> element(~s(button[phx-value-point-id="HK.counter"])) |> render_click()
      view |> element(~s(button[phx-value-point-id="HK.voltage"])) |> render_click()

      assert has_element?(view, ~s([data-selected-point="HK.counter"]))
      assert has_element?(view, ~s([data-selected-point="HK.voltage"]))

      view
      |> form("#widget-form",
        widget: %{
          type: "data_table",
          title: "HK Table",
          mode: "context",
          precision: "1"
        }
      )
      |> render_submit()

      render_dashboard_async(view)
      refute has_element?(view, "#dashboard-panel")
      stop_dashboard_view(view)

      document = fetch_dashboard_document!(org, mission, dashboard)

      assert [%{placement_id: placement_id, widget_def: widget_def}] = document.placements
      assert widget_def.widget_type_id == "cadence.data_table"
      assert widget_def.binding.observables == ["HK.counter", "HK.voltage"]

      version = fetch_dashboard_version!(org, mission, dashboard, 2)
      assert version.change_summary == "Added widget"
      assert version.created_by == user.user_id

      assert [
               %{
                 placement_id: ^placement_id,
                 widget: %{type: :data_table, binding: %{point_ids: point_ids}}
               }
             ] =
               RenderItem.from_document(document)

      assert point_ids == ["HK.counter", "HK.voltage"]
    end

    test "adds an operational observable status matrix through the slide-over panel" do
      enable_dashboard_engine_inline_resolves!()

      {conn, user, org, mission} = signed_in_user_org_and_mission()
      %Document{} = dashboard = TestFixtures.persist_dashboard_document!(mission, name: "Ops")

      {:ok, view, _html} = live(conn, show_path(mission, dashboard))
      render_dashboard_async(view)

      view |> element("#add-widget-button") |> render_click()

      view
      |> form("#widget-form",
        widget: %{
          type: "status_matrix",
          title: "Contact Phase",
          mode: "context",
          precision: "0"
        }
      )
      |> render_change()

      view
      |> form("#widget-form",
        widget: %{
          type: "status_matrix",
          title: "Contact Phase",
          binding_source: "operational_observables",
          precision: "0"
        }
      )
      |> render_change()

      assert has_element?(
               view,
               ~s([data-operational-observable="contacts.phase"])
             )

      assert has_element?(
               view,
               ~s([data-operational-observable="comms.transport.connection_state"])
             )

      assert has_element?(
               view,
               ~s([data-operational-observable="ground.station.connection_state"])
             )

      assert has_element?(
               view,
               ~s([data-operational-observable="comms.transport.downlink_bitrate"])
             )

      view |> element(~s(button[phx-value-point-id="contacts.phase"])) |> render_click()

      assert has_element?(
               view,
               ~s([data-selected-operational-observable="contacts.phase"])
             )

      view
      |> form("#widget-form",
        widget: %{
          type: "status_matrix",
          title: "Contact Phase",
          binding_source: "operational_observables",
          precision: "0"
        }
      )
      |> render_submit()

      render_dashboard_async(view)
      refute has_element?(view, "#dashboard-panel")
      stop_dashboard_view(view)

      document = fetch_dashboard_document!(org, mission, dashboard)

      assert [%{placement_id: placement_id, widget_def: widget_def}] = document.placements
      assert widget_def.widget_type_id == "cadence.status_matrix"
      assert widget_def.binding.source == :operational_observables
      assert widget_def.binding.observables == ["contacts.phase"]
      assert widget_def.binding.overlays == []

      version = fetch_dashboard_version!(org, mission, dashboard, 2)
      assert version.change_summary == "Added widget"
      assert version.created_by == user.user_id

      assert [
               %{
                 placement_id: ^placement_id,
                 widget: %{binding: %{source: :operational_observables, point_ids: point_ids}}
               }
             ] = RenderItem.from_document(document)

      assert point_ids == ["contacts.phase"]
    end

    test "reloads the latest dashboard when a stale widget edit conflicts" do
      {conn, org, mission} = signed_in_org_and_mission()
      binding_set = persist_binding_set!(org, mission)
      activate_binding_set!(org, mission, binding_set)
      %Document{} = dashboard = TestFixtures.persist_dashboard_document!(mission, name: "Power")

      {:ok, view, _html} = live(conn, show_path(mission, dashboard))
      render_dashboard_async(view)

      assert {:ok, %Document{} = _current} =
               Cadence.Dashboards.update_document(
                 org.organization_id,
                 mission.mission_id,
                 dashboard.dashboard_id,
                 %Document{dashboard | name: "Power Updated"},
                 expected_version: Document.version(dashboard)
               )

      view |> element("#add-widget-button") |> render_click()
      view |> element(~s(button[phx-value-point-id="HK.counter"])) |> render_click()

      html =
        view
        |> form("#widget-form", widget: %{type: "value_tile", title: "Counter", mode: "context"})
        |> render_submit()

      assert html =~ "Dashboard changed in another session"
      assert has_element?(view, "h1", "Power Updated")

      document = fetch_dashboard_document!(org, mission, dashboard)

      assert document.name == "Power Updated"
      assert document.placements == []
      assert Document.version(document) == 2
    end

    test "rejects widgets without a point binding" do
      {conn, _org, mission} = signed_in_org_and_mission()
      dashboard = TestFixtures.persist_dashboard_document!(mission, name: "Power")

      {:ok, view, _html} = live(conn, show_path(mission, dashboard))
      render_dashboard_async(view)
      view |> element("#add-widget-button") |> render_click()

      html =
        view
        |> form("#widget-form", widget: %{type: "value_tile", title: "Counter", mode: "context"})
        |> render_submit()

      assert html =~ "a telemetry point is required"
    end

    test "edit mode persists layout changes and pauses live data" do
      {conn, user, org, mission} = signed_in_user_org_and_mission()
      spacecraft = TestFixtures.persist_spacecraft!(mission, display_name: "SC Gamma")
      binding_set = persist_binding_set!(org, mission)
      ingest!(mission, binding_set, spacecraft.spacecraft_id, 1234, 1_700_000_100)

      dashboard =
        TestFixtures.persist_dashboard_document!(mission,
          name: "Power",
          widgets: [value_tile("HK.counter", :fixed, spacecraft.spacecraft_id)]
        )

      initial_document = fetch_dashboard_document!(org, mission, dashboard)
      widget_id = placement_by_title(initial_document, "Counter").placement_id
      {:ok, view, _html} = live(conn, show_path(mission, dashboard))
      render_dashboard_async(view)
      assert has_element?(view, "#widget-#{widget_id} [data-widget-value]", "1234")

      view |> element("#edit-layout-toggle") |> render_click()
      assert has_element?(view, "#edit-paused-note")

      # Layout changes autosave while editing.
      view
      |> element("#dashboard-grid-#{dashboard.dashboard_id}")
      |> render_hook("layout_changed", %{
        "layouts" => [%{"widget_id" => widget_id, "x" => 2, "y" => 1, "w" => 6, "h" => 3}]
      })

      document = fetch_dashboard_document!(org, mission, dashboard)

      assert [%{placement_id: ^widget_id, layout: %{x: 2, y: 1, w: 6, h: 3}}] =
               document.placements

      assert Document.version(document) == 2
      version = fetch_dashboard_version!(org, mission, dashboard, 2)
      assert version.change_summary == "Updated layout"
      assert version.created_by == user.user_id

      assert has_element?(view, ~s(.grid-stack-item[gs-x="2"][gs-y="1"][gs-w="6"][gs-h="3"]))

      # Live data is frozen while editing…
      ingest!(mission, binding_set, spacecraft.spacecraft_id, 5678, 1_700_000_110)
      send(view.pid, :tick)
      render_dashboard_async(view)
      assert has_element?(view, "#widget-#{widget_id} [data-widget-value]", "1234")
      refute has_element?(view, "#widget-#{widget_id} [data-widget-value]", "5678")

      # …and resumes when editing ends.
      view |> element("#edit-layout-toggle") |> render_click()
      render_dashboard_async(view)
      refute has_element?(view, "#edit-paused-note")
      assert has_element?(view, "#widget-#{widget_id} [data-widget-value]", "5678")
    end

    test "removes and reconfigures widgets in edit mode" do
      {conn, user, org, mission} = signed_in_user_org_and_mission()
      binding_set = persist_binding_set!(org, mission)
      activate_binding_set!(org, mission, binding_set)

      dashboard =
        TestFixtures.persist_dashboard_document!(mission,
          name: "Power",
          widgets: [
            Map.put(value_tile("HK.counter"), :layout, %{x: 0, y: 0, w: 4, h: 2}),
            %{type: :constellation_health, title: "Fleet", binding: %{mode: :constellation}}
          ]
        )

      initial_document = fetch_dashboard_document!(org, mission, dashboard)

      tile = placement_by_title(initial_document, "Counter")
      fleet = placement_by_title(initial_document, "Fleet")

      {:ok, view, _html} = live(conn, show_path(mission, dashboard))
      render_dashboard_async(view)

      view |> element("#edit-layout-toggle") |> render_click()

      # Reconfigure: prefilled form, save preserves placement identity and layout.
      view
      |> element(
        ~s(button[phx-click="open_widget_config"][phx-value-widget-id="#{tile.placement_id}"])
      )
      |> render_click()

      assert has_element?(view, ~s(#widget-form input[name="widget[title]"][value="Counter"]))

      view
      |> form("#widget-form",
        widget: %{type: "value_tile", title: "Renamed Tile", mode: "context"}
      )
      |> render_submit()

      render_dashboard_async(view)

      document = fetch_dashboard_document!(org, mission, dashboard)

      renamed = placement_by_title(document, "Renamed Tile")
      assert renamed.placement_id == tile.placement_id
      assert Map.take(renamed.layout, [:x, :y, :w, :h]) == %{x: 0, y: 0, w: 4, h: 2}

      assert Document.version(document) == 2
      version = fetch_dashboard_version!(org, mission, dashboard, 2)
      assert version.change_summary == "Updated widget"
      assert version.created_by == user.user_id

      # Remove the constellation widget.
      view
      |> element(
        ~s(button[phx-click="remove_widget"][phx-value-widget-id="#{fleet.placement_id}"])
      )
      |> render_click()

      render_dashboard_async(view)

      document = fetch_dashboard_document!(org, mission, dashboard)
      widget_id = tile.placement_id

      assert [%{placement_id: ^widget_id}] = document.placements
      assert Document.version(document) == 3
      version = fetch_dashboard_version!(org, mission, dashboard, 3)
      assert version.change_summary == "Removed widget"
      assert version.created_by == user.user_id
    end

    test "renames the dashboard from the toolbar menu without exposing hard delete" do
      {conn, user, org, mission} = signed_in_user_org_and_mission()
      dashboard = TestFixtures.persist_dashboard_document!(mission, name: "Power")

      {:ok, view, _html} = live(conn, show_path(mission, dashboard))
      render_dashboard_async(view)

      view |> element(~s(#dashboard-menu button[phx-click="open_rename"])) |> render_click()

      view
      |> form("#rename-dashboard-form", dashboard: %{name: "Power North", description: "EPS"})
      |> render_submit()

      renamed = fetch_dashboard_document!(org, mission, dashboard)

      assert renamed.name == "Power North"
      version = fetch_dashboard_version!(org, mission, dashboard, 2)
      assert version.change_summary == "Renamed dashboard"
      assert version.created_by == user.user_id

      assert has_element?(view, "h1", "Power North")
      assert has_element?(view, ~s(#ops-nav-rail), "Power North")

      assert has_element?(
               view,
               ~s(#dashboard-menu button[data-dashboard-lifecycle-action="archive"][data-dashboard-action-available="true"])
             )

      refute has_element?(view, ~s(#dashboard-menu button[phx-click="delete_dashboard"]))
    end

    test "archives and restores a dashboard from ops surfaces" do
      {conn, user, org, mission} = signed_in_user_org_and_mission()
      dashboard = TestFixtures.persist_dashboard_document!(mission, name: "Archive Me")

      {:ok, view, _html} = live(conn, show_path(mission, dashboard))
      render_dashboard_async(view)

      view
      |> element(~s(#dashboard-menu button[phx-click="archive_dashboard"]))
      |> render_click()

      flash = assert_redirect(view, ~p"/missions/#{mission.mission_id}/ops/dashboards")
      assert %{"info" => "Dashboard archived."} = flash

      assert [] =
               Cadence.Dashboards.list_dashboard_summaries(
                 org.organization_id,
                 mission.mission_id
               )

      assert [%Cadence.Dashboards.DashboardSummary{lifecycle_state: "archived"}] =
               Cadence.Dashboards.list_archived_dashboard_summaries(
                 org.organization_id,
                 mission.mission_id
               )

      assert [%Cadence.Dashboards.Version{version: 1}] =
               Cadence.Dashboards.list_versions(
                 org.organization_id,
                 mission.mission_id,
                 dashboard.dashboard_id
               )

      assert [%Cadence.Dashboards.LifecycleEvent{} = archived] =
               Cadence.Dashboards.list_lifecycle_events(
                 org.organization_id,
                 mission.mission_id,
                 dashboard.dashboard_id
               )

      assert archived.event_type == :archived
      assert archived.dashboard_version == 1
      assert archived.previous_lifecycle_state == "active"
      assert archived.current_lifecycle_state == "archived"
      assert archived.actor_id == user.user_id

      {:ok, list_view, _html} = live(conn, ~p"/missions/#{mission.mission_id}/ops/dashboards")

      assert has_element?(list_view, "#archived-dashboards", "Archive Me")

      assert has_element?(
               list_view,
               ~s(#archived-dashboard-#{dashboard.dashboard_id}[data-dashboard-publication-state="archived"][data-dashboard-archive-available="false"][data-dashboard-restore-available="true"])
             )

      assert has_element?(
               list_view,
               ~s(#restore-dashboard-#{dashboard.dashboard_id}[data-dashboard-lifecycle-action="restore"][data-dashboard-action-available="true"])
             )

      refute has_element?(list_view, ~s(#ops-nav-rail a[href="#{show_path(mission, dashboard)}"]))

      list_view
      |> element("#restore-dashboard-#{dashboard.dashboard_id}")
      |> render_click()

      assert has_element?(list_view, ~s(#ops-nav-rail a[href="#{show_path(mission, dashboard)}"]))
      refute has_element?(list_view, "#archived-dashboard-#{dashboard.dashboard_id}")

      assert has_element?(
               list_view,
               ~s(#active-dashboard-#{dashboard.dashboard_id}[data-dashboard-publication-state="unpublished"][data-dashboard-archive-available="true"][data-dashboard-restore-available="false"])
             )

      assert [%Cadence.Dashboards.DashboardSummary{lifecycle_state: "active"}] =
               Cadence.Dashboards.list_dashboard_summaries(
                 org.organization_id,
                 mission.mission_id
               )

      assert [%Cadence.Dashboards.Version{version: 1}] =
               Cadence.Dashboards.list_versions(
                 org.organization_id,
                 mission.mission_id,
                 dashboard.dashboard_id
               )

      assert [
               %Cadence.Dashboards.LifecycleEvent{event_type: :archived},
               %Cadence.Dashboards.LifecycleEvent{} = restored
             ] =
               Cadence.Dashboards.list_lifecycle_events(
                 org.organization_id,
                 mission.mission_id,
                 dashboard.dashboard_id
               )

      assert restored.event_type == :restored
      assert restored.dashboard_version == 1
      assert restored.previous_lifecycle_state == "archived"
      assert restored.current_lifecycle_state == "active"
      assert restored.actor_id == user.user_id

      html =
        render_click(list_view, "restore_dashboard", %{"dashboard-id" => dashboard.dashboard_id})

      assert html =~ "Dashboard is already active."

      assert [
               %Cadence.Dashboards.LifecycleEvent{event_type: :archived},
               %Cadence.Dashboards.LifecycleEvent{event_type: :restored}
             ] =
               Cadence.Dashboards.list_lifecycle_events(
                 org.organization_id,
                 mission.mission_id,
                 dashboard.dashboard_id
               )
    end

    test "refreshes archived list when a stale restore conflicts" do
      {conn, _user, org, mission} = signed_in_user_org_and_mission()
      dashboard = TestFixtures.persist_dashboard_document!(mission, name: "Restore Conflict")

      assert :ok =
               Cadence.Dashboards.archive_document(
                 org.organization_id,
                 mission.mission_id,
                 dashboard.dashboard_id,
                 expected_version: 1
               )

      {:ok, list_view, _html} = live(conn, ~p"/missions/#{mission.mission_id}/ops/dashboards")

      assert has_element?(
               list_view,
               ~s(#restore-dashboard-#{dashboard.dashboard_id}[phx-value-expected-version="1"])
             )

      bump_dashboard_row_latest_version!(org, mission, dashboard, 2)

      html =
        list_view
        |> element("#restore-dashboard-#{dashboard.dashboard_id}")
        |> render_click()

      assert html =~ "Dashboard changed in another session. Reloaded version 2"
      assert has_element?(list_view, "#archived-dashboard-#{dashboard.dashboard_id}")

      assert [] =
               Cadence.Dashboards.list_dashboard_summaries(
                 org.organization_id,
                 mission.mission_id
               )

      assert [%Cadence.Dashboards.DashboardSummary{} = archived_summary] =
               Cadence.Dashboards.list_archived_dashboard_summaries(
                 org.organization_id,
                 mission.mission_id
               )

      assert archived_summary.lifecycle_state == "archived"
      assert archived_summary.latest_version == 2

      assert [%Cadence.Dashboards.LifecycleEvent{event_type: :archived}] =
               Cadence.Dashboards.list_lifecycle_events(
                 org.organization_id,
                 mission.mission_id,
                 dashboard.dashboard_id
               )
    end
  end
end
