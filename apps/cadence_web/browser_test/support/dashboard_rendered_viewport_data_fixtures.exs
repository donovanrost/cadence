defmodule CadenceWeb.Assets.DashboardRenderedViewportDataFixtures do
  @moduledoc false

  import Ecto.Query
  import ExUnit.Assertions
  import ExUnit.Callbacks

  import CadenceWeb.Assets.DashboardRenderedViewportOperationalFixtures,
    only: [build_space_packet: 3]

  alias Cadence.ApplicationDispatch.BindingRule
  alias Cadence.ApplicationDispatch.BindingSet
  alias Cadence.ApplicationDispatch.CapabilityConfig
  alias Cadence.ApplicationDispatch.CapabilityInstance
  alias Cadence.Catalog.Revision
  alias Cadence.Commanding.CommandQueueEntry
  alias Cadence.Commanding.CommandRequest
  alias Cadence.Contacts.Path, as: ContactPath
  alias Cadence.Dashboards.DataBinding
  alias Cadence.Dashboards.DataSource
  alias Cadence.Dashboards.DataSources
  alias Cadence.Ingress.RawEvidence
  alias Cadence.Limits.Definition, as: LimitDefinition
  alias Cadence.Limits.Event, as: LimitEvent
  alias Cadence.OperationalEvents
  alias Cadence.OperationalEvents.Event
  alias Cadence.Commanding.CommandQueueEntryRow
  alias Cadence.Commanding.CommandRequestRow
  alias Cadence.Control.Replay.Store.ReplayRunRow
  alias Cadence.Control.Replay.Store.ReplayTelemetrySampleRow
  alias Cadence.Limits.Store.LimitEventRow, as: TelemetryLimitEventRow
  alias Cadence.Telemetry.SampleRecords.TelemetrySampleRow
  alias Cadence.Replay.Run
  alias Cadence.Repo
  alias Cadence.Runtime.ManagedActionRequest
  alias Cadence.Runtime.Persistence, as: RuntimePersistence
  alias Cadence.Telemetry.PacketDefinition

  def reset_runtime_health! do
    Cadence.reset_runtime_health()

    on_exit(fn ->
      Cadence.reset_runtime_health()
    end)
  end

  def persist_command_queue_entry!(
        org,
        mission,
        command_queue_entry_id,
        source_endpoint_ref,
        lifecycle_state \\ :pending,
        opts \\ []
      ) do
    requested_at = DateTime.from_unix!(1_700_000_000, :second)
    command_request_id = command_queue_entry_id <> "-request"

    metadata =
      opts
      |> Keyword.take([:spacecraft_id])
      |> Map.new(fn {key, value} -> {to_string(key), value} end)

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
        requested_by: %{"user_id" => "dashboard-browser-test"},
        requested_at: requested_at,
        metadata: metadata
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
        enqueued_by: %{"user_id" => "dashboard-browser-test"},
        enqueued_at: requested_at,
        metadata: metadata
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

  def persist_ingress_latency_through_write_path!(org, mission, source_endpoint_id, opts) do
    spacecraft_id = Keyword.get(opts, :spacecraft_id)
    contact_id = Keyword.get(opts, :contact_id)
    receipt_time = Keyword.fetch!(opts, :receipt_time)
    packet_value = Keyword.get(opts, :packet_value, 31)

    raw_evidence =
      RawEvidence.new(%{
        mission_id: mission.mission_id,
        source_endpoint_ref: source_endpoint_id,
        spacecraft_id: spacecraft_id,
        receipt_time: receipt_time,
        metadata: %{
          "contact_id" => contact_id,
          "scheduled_contact_id" => Keyword.get(opts, :scheduled_contact_id, contact_id),
          "realized_contact_id" => Keyword.get(opts, :realized_contact_id)
        },
        raw: build_space_packet(42, Keyword.get(opts, :sequence_count, 1), <<packet_value::16>>)
      })

    assert {:ok, _processing_result} = Cadence.process_and_persist_telemetry_ingress(raw_evidence)

    runtime_sample =
      wait_for_runtime_ingress_latency_sample(mission.mission_id, source_endpoint_id)

    # ADR-019 moved new ingress-latency observations out of the operational
    # event store. Browser history scenarios still exercise the migration-era
    # reader, so seed that compatibility boundary explicitly from the live
    # runtime sample instead of implying that ingress persistence wrote it.
    latency_event =
      Event.from_operational_observable_metric_sample(%{
        sample_id: raw_evidence.evidence_id <> ":browser_history_fixture",
        organization_id: org.organization_id,
        mission_id: mission.mission_id,
        observable_id: "ingress.processing_latency_ms",
        resource_id: source_endpoint_id,
        scope_kind: :source_endpoint,
        spacecraft_id: spacecraft_id,
        contact_id: contact_id,
        scheduled_contact_id: Keyword.get(opts, :scheduled_contact_id, contact_id),
        realized_contact_id: Keyword.get(opts, :realized_contact_id),
        source_endpoint_id: source_endpoint_id,
        value: runtime_sample.value,
        unit: "ms",
        observed_at: receipt_time,
        metadata: %{
          evidence_id: raw_evidence.evidence_id,
          fixture_source: :runtime_health_history_adapter
        }
      })

    assert {:ok, _event} = OperationalEvents.persist_event(latency_event)

    [latency_sample | _] =
      Cadence.OperationalEvents.operational_observable_metric_samples(
        org.organization_id,
        mission.mission_id,
        observable_id: "ingress.processing_latency_ms",
        source_endpoint_id: source_endpoint_id,
        order: :desc
      )

    assert latency_sample.resource_id == source_endpoint_id
    assert latency_sample.source_endpoint_id == source_endpoint_id
    assert latency_sample.spacecraft_id == spacecraft_id
    assert Map.get(latency_sample, :contact_id) == contact_id
    assert latency_sample.unit == "ms"
    assert is_number(latency_sample.value)
    assert latency_sample.value > 0

    latency_sample
  end

  defp wait_for_runtime_ingress_latency_sample(mission_id, source_endpoint_id, attempts \\ 40)

  defp wait_for_runtime_ingress_latency_sample(mission_id, source_endpoint_id, attempts)
       when attempts > 1 do
    case runtime_ingress_latency_sample(mission_id, source_endpoint_id) do
      nil ->
        Process.sleep(25)
        wait_for_runtime_ingress_latency_sample(mission_id, source_endpoint_id, attempts - 1)

      sample ->
        sample
    end
  end

  defp wait_for_runtime_ingress_latency_sample(mission_id, source_endpoint_id, 1) do
    runtime_ingress_latency_sample(mission_id, source_endpoint_id)
  end

  defp runtime_ingress_latency_sample(mission_id, source_endpoint_id) do
    Cadence.runtime_health_snapshot()
    |> get_in([:metrics, :ingress_processing_latency_ms])
    |> Enum.find(
      &(Map.get(&1, :mission_id) == mission_id and
          Map.get(&1, :source_endpoint_id) == source_endpoint_id)
    )
  end

  def persist_binding_set!(org, mission) do
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
        binding_set_id: mission.mission_id <> "-browser-viewport-binding-set",
        version: 1,
        rules: [
          BindingRule.new(%{
            handler_key: :definition_bound_telemetry,
            packet_kind: :space_packet,
            apid: 42,
            handler_configuration: packet_definition
          })
        ]
      })

    {:ok, persisted} = Cadence.Governance.persist_binding_set(org.organization_id, binding_set)

    assert {:ok, _events_source} =
             DataSources.persist_data_source(DataSources.default_events_data_source())

    assert {:ok, _events_binding} =
             DataSources.persist_data_binding(DataSources.default_flight_events_binding())

    persisted
  end

  def persist_application_binding_set!(org, mission, source_endpoint_ref, opts) do
    suffix = Keyword.get(opts, :suffix, "browser-application-binding")
    binding_set_id = "#{mission.mission_id}-#{suffix}-binding-set"

    binding_set =
      BindingSet.new(%{
        mission_id: mission.mission_id,
        binding_set_id: binding_set_id,
        version: 1,
        capability_instances: [
          CapabilityInstance.new(%{
            capability_instance_id: "#{binding_set_id}-packet-counter",
            family_key: :packet_counter,
            target_scope: :source_endpoint,
            source_endpoint_ref: source_endpoint_ref,
            capability_config:
              CapabilityConfig.inline(%{
                "metric_name" => "browser_replay_packets",
                "flush_interval_ms" => 25
              })
          })
        ],
        rules: [
          BindingRule.new(%{
            binding_rule_id: "#{binding_set_id}-packet-counter-rule",
            capability_instance_id: "#{binding_set_id}-packet-counter",
            selector: %{
              scope: %{target_scope: :source_endpoint, source_endpoint_ref: source_endpoint_ref},
              match: %{packet_kind: :space_packet, apid: 42}
            },
            priority: 10,
            fanout_mode: :multi
          })
        ]
      })

    {:ok, persisted} = Cadence.Governance.persist_binding_set(org.organization_id, binding_set)

    persisted
  end

  def ingest!(mission, binding_set, spacecraft_id, value, unix_seconds, opts \\ []) do
    evidence =
      RawEvidence.new(%{
        mission_id: mission.mission_id,
        spacecraft_id: spacecraft_id,
        receipt_time: DateTime.from_unix!(unix_seconds, :second),
        raw: build_space_packet(42, 1, <<value::16>>)
      })

    {:ok, result} =
      Cadence.process_telemetry_ingress(
        evidence,
        binding_set.binding_set_id,
        binding_set.version
      )

    RuntimePersistence.persist_processing_result(result, opts)
  end

  def browser_retention_gap_watermark(_organization_id, _mission_id, _point_id, _opts) do
    {:ok,
     %{
       complete_through: ~U[2026-06-16 00:30:00Z],
       latest_receipt_time: ~U[2026-06-16 00:30:00Z],
       retention_starts_at: ~U[2026-06-16 00:20:00Z],
       sample_count: 2,
       confidence: :best_effort
     }}
  end

  def browser_source_unavailable_latest(_organization_id, _mission_id, _point_id, _opts) do
    raise "browser source unavailable latest failure"
  end

  def browser_source_unavailable_history(_organization_id, _mission_id, _point_id, _opts) do
    {:error, :browser_source_unavailable_history_failure}
  end

  def browser_ingress_latency_history_source_unavailable(_organization_id, _mission_id, _opts) do
    raise "browser ingress latency history source unavailable"
  end

  def browser_fresh_watermark(_organization_id, _mission_id, _point_id, _opts) do
    {:ok,
     %{
       complete_through: ~U[2026-06-16 00:40:00Z],
       latest_receipt_time: ~U[2026-06-16 00:30:00Z],
       retention_starts_at: ~U[2026-06-16 00:00:00Z],
       sample_count: 2,
       confidence: :best_effort
     }}
  end

  def browser_stale_watermark(_organization_id, _mission_id, _point_id, _opts) do
    {:ok,
     %{
       complete_through: ~U[2026-06-16 00:00:01Z],
       latest_receipt_time: ~U[2026-06-16 00:00:01Z],
       retention_starts_at: ~U[2026-06-15 00:00:00Z],
       sample_count: 2,
       confidence: :best_effort
     }}
  end

  def browser_unknown_watermark(_organization_id, _mission_id, _point_id, _opts) do
    {:error, :browser_watermark_unknown_failure}
  end

  def contact_paths(source_endpoint_ref) do
    [
      ContactPath.new(%{
        path_id: "browser-dashboard-uplink-path",
        direction: :uplink,
        selection_role: :selected,
        source_endpoint_ref: source_endpoint_ref
      }),
      ContactPath.new(%{
        path_id: "browser-dashboard-downlink-path",
        direction: :downlink,
        selection_role: :selected,
        source_endpoint_ref: source_endpoint_ref
      })
    ]
  end

  def seed_limit_definition!(mission) do
    limit_definition =
      LimitDefinition.new(%{
        mission_id: mission.mission_id,
        limit_definition_id: "browser-viewport-counter-limits",
        point_id: "HK.counter",
        limit_set_name: "browser-smoke",
        thresholds: %{"yellow_high" => 20, "red_high" => 30}
      })

    assert {:ok, ^limit_definition} = Cadence.Limits.persist_limit_definition(limit_definition)
  end

  def seed_catalog_revision_event!(org, mission, %DateTime{} = occurred_at) do
    catalog_revision_id = "browser-viewport-catalog-revision"

    revision =
      Revision.new(%{
        catalog_revision_id: catalog_revision_id,
        organization_id: org.organization_id,
        mission_id: mission.mission_id,
        catalog_database_id: "browser-viewport-catalog",
        revision_number: 1,
        revision_label: "Browser Viewport Catalog",
        catalog_family: :telemetry,
        artifact_id: "#{catalog_revision_id}-artifact",
        import_run_id: "#{catalog_revision_id}-import-run",
        telemetry_snapshot_id: "#{catalog_revision_id}-telemetry-snapshot",
        command_snapshot_id: nil,
        content_sha256: "#{catalog_revision_id}-sha",
        created_by: %{"service_identity_id" => "dashboard-browser-smoke"},
        metadata: %{"source_artifact_name" => "#{catalog_revision_id}.json"}
      })

    assert {:ok, _event} =
             revision
             |> Event.from_catalog_revision(occurred_at)
             |> OperationalEvents.persist_event()

    catalog_revision_id
  end

  def evaluate_limit_events!(org, mission, spacecraft) do
    assert {:ok, _mission} =
             Cadence.Missions.fetch_mission(org.organization_id, mission.mission_id)

    assert {:ok, run} =
             Cadence.Limits.evaluate(mission.mission_id,
               spacecraft_id: spacecraft.spacecraft_id
             )

    assert run.status == :completed
    assert run.emitted_event_count >= 1
  end

  def persist_replay_dashboard_sources!(organization_id, mission_id) do
    replay_telemetry_source = %DataSource{
      DataSources.default_managed_data_source()
      | data_source_id: "managed_questdb_replay",
        organization_id: organization_id,
        mission_id: mission_id,
        isolation_level: :mission_isolated,
        metadata: %{storage: :postgres_replay, bootstrap_default?: false}
    }

    replay_telemetry_binding = %DataBinding{
      DataSources.default_flight_telemetry_binding()
      | binding_id: "replay_telemetry",
        organization_id: organization_id,
        mission_id: mission_id,
        realm: :replay,
        data_source_id: "managed_questdb_replay",
        dataset: "replay",
        metadata: %{bootstrap_default?: false}
    }

    replay_limits_binding = %DataBinding{
      DataSources.default_flight_limits_binding()
      | binding_id: "replay_limits",
        organization_id: organization_id,
        mission_id: mission_id,
        realm: :replay,
        dataset: "telemetry_limit_events",
        metadata: %{bootstrap_default?: false}
    }

    replay_operational_binding = %DataBinding{
      DataSources.default_flight_operational_observables_binding()
      | binding_id: "replay_operational_observables",
        organization_id: organization_id,
        mission_id: mission_id,
        realm: :replay,
        dataset: "operational_observables_replay",
        metadata: %{bootstrap_default?: false}
    }

    replay_events_binding = %DataBinding{
      DataSources.default_flight_events_binding()
      | binding_id: "replay_events",
        organization_id: organization_id,
        mission_id: mission_id,
        realm: :replay,
        dataset: "mission_events_replay",
        metadata: %{bootstrap_default?: false}
    }

    assert {:ok, persisted_source} = DataSources.persist_data_source(replay_telemetry_source)
    assert persisted_source.data_source_id == "managed_questdb_replay"
    assert persisted_source.isolation_level == :mission_isolated

    assert {:ok, persisted_telemetry_binding} =
             DataSources.persist_data_binding(replay_telemetry_binding)

    assert persisted_telemetry_binding.binding_id == "replay_telemetry"
    assert persisted_telemetry_binding.realm == :replay

    assert {:ok, persisted_limits_source} =
             DataSources.persist_data_source(DataSources.default_limits_data_source())

    assert persisted_limits_source.data_source_id == "managed_limits_projection"

    assert {:ok, persisted_operational_source} =
             DataSources.persist_data_source(
               DataSources.default_operational_observables_data_source()
             )

    assert persisted_operational_source.data_source_id == "managed_operational_observables"

    assert {:ok, persisted_events_source} =
             DataSources.persist_data_source(DataSources.default_events_data_source())

    assert persisted_events_source.data_source_id == "managed_events_projection"

    assert {:ok, persisted_limits_binding} =
             DataSources.persist_data_binding(replay_limits_binding)

    assert persisted_limits_binding.binding_id == "replay_limits"
    assert persisted_limits_binding.realm == :replay

    assert {:ok, persisted_operational_binding} =
             DataSources.persist_data_binding(replay_operational_binding)

    assert persisted_operational_binding.binding_id == "replay_operational_observables"
    assert persisted_operational_binding.realm == :replay

    assert {:ok, persisted_events_binding} =
             DataSources.persist_data_binding(replay_events_binding)

    assert persisted_events_binding.binding_id == "replay_events"
    assert persisted_events_binding.realm == :replay

    %{
      telemetry_data_source_id: replay_telemetry_source.data_source_id,
      telemetry_binding_id: replay_telemetry_binding.binding_id,
      limits_data_source_id: DataSources.default_limits_data_source().data_source_id,
      limits_binding_id: replay_limits_binding.binding_id,
      operational_data_source_id:
        DataSources.default_operational_observables_data_source().data_source_id,
      operational_binding_id: replay_operational_binding.binding_id,
      events_data_source_id: DataSources.default_events_data_source().data_source_id,
      events_binding_id: replay_events_binding.binding_id
    }
  end

  def persist_replay_run!(mission, replay_run_id, event_time) do
    replay_run =
      Run.new(%{
        replay_run_id: replay_run_id,
        mission_id: mission.mission_id,
        binding_set_id: "#{mission.mission_id}-#{replay_run_id}-binding-set",
        binding_set_version: 1,
        status: :completed,
        replayed_evidence_count: 1,
        replayed_packet_count: 1,
        replayed_sample_count: 0,
        started_at: DateTime.add(event_time, -60, :second),
        completed_at: DateTime.add(event_time, 60, :second)
      })

    Repo.insert!(ReplayRunRow.changeset(replay_run))
  end

  def persist_transport_capability_event!(
        organization_id,
        mission_id,
        transport_record_id,
        transport_id,
        event_kind,
        recorded_at,
        opts
      ) do
    replay_run_id = Keyword.get(opts, :replay_run_id)

    payload =
      %{
        transport_record_id: transport_record_id,
        contact_id: Keyword.get(opts, :contact_id),
        realized_contact_id: Keyword.get(opts, :contact_id),
        path_id: Keyword.get(opts, :path_id),
        capability_instance_id: transport_id,
        binding_set_id: Keyword.get(opts, :binding_set_id, "browser-binding-set-alpha"),
        binding_set_version: Keyword.get(opts, :binding_set_version, 1),
        activation_id: Keyword.get(opts, :activation_id, "browser-activation-alpha"),
        family_key: Keyword.get(opts, :family_key, :heartbeat_monitor),
        partition_affinity: :source_endpoint,
        partition_value: Keyword.fetch!(opts, :source_endpoint_id),
        event_kind: event_kind,
        timer_key: Keyword.get(opts, :timer_key),
        emitted_record_kinds: Keyword.get(opts, :emitted_record_kinds, []),
        emitted_record_count: Keyword.get(opts, :emitted_record_count, 0),
        action_request_count: Keyword.get(opts, :action_request_count, 0),
        state_snapshot: Keyword.get(opts, :state_snapshot, %{active?: true}),
        recorded_at: recorded_at,
        source_endpoint_id: Keyword.fetch!(opts, :source_endpoint_id),
        ground_station_id: Keyword.fetch!(opts, :ground_station_id),
        link_id: Keyword.fetch!(opts, :link_id),
        replay_run_id: replay_run_id
      }
      |> Enum.reject(fn {_key, value} -> is_nil(value) end)
      |> Map.new()

    event =
      Event.new(%{
        event_id:
          [
            "transport-capability-record",
            transport_record_id,
            replay_run_id
          ]
          |> Enum.reject(&is_nil/1)
          |> Enum.join(":"),
        organization_id: organization_id,
        mission_id: mission_id,
        occurred_at: recorded_at,
        recorded_at: recorded_at,
        effective_at: recorded_at,
        category: :comms,
        kind: transport_capability_event_kind(event_kind),
        severity: :info,
        actor: if(replay_run_id, do: %{kind: :replay, id: replay_run_id}, else: %{kind: :system}),
        subject: %{kind: :transport, id: transport_id},
        scope:
          %{
            contact_id: Keyword.get(opts, :contact_id),
            realized_contact_id: Keyword.get(opts, :contact_id),
            path_id: Keyword.get(opts, :path_id),
            capability_instance_id: transport_id,
            binding_set_id: payload.binding_set_id,
            activation_id: payload.activation_id,
            timer_key: Keyword.get(opts, :timer_key),
            replay_run_id: replay_run_id
          }
          |> Enum.reject(fn {_key, value} -> is_nil(value) end)
          |> Map.new(),
        causality:
          %{
            correlation_id: transport_id,
            source_record_kind: :transport_capability_record,
            source_record_id: transport_record_id,
            replay_run_id: replay_run_id
          }
          |> Enum.reject(fn {_key, value} -> is_nil(value) end)
          |> Map.new(),
        payload: payload,
        current: payload,
        metadata:
          %{replay_run_id: replay_run_id}
          |> Enum.reject(fn {_key, value} -> is_nil(value) end)
          |> Map.new()
      })

    assert {:ok, _event} = OperationalEvents.persist_event(event)
  end

  def transport_capability_event_kind(:initialized), do: :transport_initialized

  def transport_capability_event_kind(:transport_event_handled),
    do: :transport_event_handled

  def transport_capability_event_kind(:control_input_handled),
    do: :transport_control_input_handled

  def transport_capability_event_kind(:timer_handled), do: :transport_timer_handled

  def persist_operational_observable_state_event!(
        organization_id,
        mission_id,
        snapshot_id,
        observable_id,
        link_id,
        state,
        observed_at,
        opts
      ) do
    resource_id = Keyword.get(opts, :resource_id, link_id)

    event =
      Event.from_operational_observable_state_snapshot(%{
        snapshot_id: snapshot_id,
        organization_id: organization_id,
        mission_id: mission_id,
        observable_id: observable_id,
        resource_id: resource_id,
        scope_kind: Keyword.get(opts, :scope_kind, :link),
        transport_id: Keyword.get(opts, :transport_id, "browser-transport-alpha"),
        source_endpoint_id:
          Keyword.get(opts, :source_endpoint_id, "browser-source-endpoint-alpha"),
        ground_station_id: Keyword.get(opts, :ground_station_id, "dss-14"),
        link_id: link_id,
        adapter_key: :tcp_socket,
        connection_state: connection_state(observable_id, state),
        state: operational_observable_state(observable_id, state),
        replay_run_id: Keyword.get(opts, :replay_run_id),
        observed_at: observed_at
      })

    assert {:ok, _event} = OperationalEvents.persist_event(event)
  end

  def connection_state(observable_id, state)
      when observable_id in [
             "comms.transport.connection_state",
             "ground.station.connection_state"
           ],
      do: state

  def connection_state(_observable_id, _state), do: nil

  def operational_observable_state(observable_id, state)
      when observable_id in [
             "link.rf_lock_state",
             "link.frame_sync_state",
             "ground.station.antenna_pointing_state"
           ],
      do: state

  def operational_observable_state(_observable_id, _state), do: nil

  def persist_operational_observable_metric_event!(
        organization_id,
        mission_id,
        sample_id,
        observable_id,
        resource_id,
        value,
        observed_at,
        opts
      ) do
    metric_attrs = %{
      sample_id: sample_id,
      organization_id: organization_id,
      mission_id: mission_id,
      observable_id: observable_id,
      resource_id: resource_id,
      scope_kind: operational_observable_metric_scope_kind(observable_id),
      transport_id: Keyword.get(opts, :transport_id, "browser-transport-alpha"),
      source_endpoint_id: Keyword.get(opts, :source_endpoint_id, "browser-source-endpoint-alpha"),
      ground_station_id: Keyword.get(opts, :ground_station_id, "dss-14"),
      link_id:
        Keyword.get(
          opts,
          :link_id,
          operational_observable_metric_link_id(observable_id, resource_id)
        ),
      adapter_key: :tcp_socket,
      unit: operational_observable_metric_unit(observable_id),
      replay_run_id: Keyword.get(opts, :replay_run_id),
      observed_at: observed_at
    }

    event =
      metric_attrs
      |> Map.put(operational_observable_metric_value_key(observable_id), value)
      |> Event.from_operational_observable_metric_sample()

    assert {:ok, _event} = OperationalEvents.persist_event(event)
  end

  def operational_observable_metric_scope_kind(observable_id)
      when observable_id in [
             "link.snr_db",
             "link.eb_n0_db",
             "link.symbol_rate_sps",
             "link.doppler_hz"
           ],
      do: :link

  def operational_observable_metric_scope_kind("ingress.processing_latency_ms"),
    do: :source_endpoint

  def operational_observable_metric_scope_kind(_observable_id), do: :transport

  def operational_observable_metric_link_id(observable_id, resource_id)
      when observable_id in [
             "link.snr_db",
             "link.eb_n0_db",
             "link.symbol_rate_sps",
             "link.doppler_hz"
           ],
      do: resource_id

  def operational_observable_metric_link_id(_observable_id, _resource_id), do: "link-alpha"

  def operational_observable_metric_value_key("link.snr_db"), do: :snr_db
  def operational_observable_metric_value_key("link.eb_n0_db"), do: :eb_n0_db
  def operational_observable_metric_value_key("link.symbol_rate_sps"), do: :symbol_rate_sps
  def operational_observable_metric_value_key("link.doppler_hz"), do: :doppler_hz

  def operational_observable_metric_value_key("ingress.processing_latency_ms"), do: :value

  def operational_observable_metric_value_key("comms.transport.uplink_bitrate"),
    do: :uplink_bitrate

  def operational_observable_metric_value_key(_observable_id), do: :downlink_bitrate

  def operational_observable_metric_unit("link.snr_db"), do: "dB"
  def operational_observable_metric_unit("link.eb_n0_db"), do: "dB"
  def operational_observable_metric_unit("link.symbol_rate_sps"), do: "sym/s"
  def operational_observable_metric_unit("link.doppler_hz"), do: "Hz"
  def operational_observable_metric_unit("ingress.processing_latency_ms"), do: "ms"
  def operational_observable_metric_unit("comms.transport.downlink_bitrate"), do: "bit/s"
  def operational_observable_metric_unit("comms.transport.uplink_bitrate"), do: "bit/s"
  def operational_observable_metric_unit(_observable_id), do: nil

  def managed_action_operational_event(
        organization_id,
        mission_id,
        suffix,
        occurred_at,
        replay_run_id
      ) do
    %ManagedActionRequest{
      action_request_id: "browser-managed-action-#{suffix}",
      mission_id: mission_id,
      capability_instance_id: "browser-packet-counter-#{suffix}",
      family_key: :packet_counter,
      activation_id: "activation-#{suffix}",
      binding_set_id: "binding-set-#{suffix}",
      binding_set_version: 7,
      partition_affinity: :source_endpoint,
      partition_value: "endpoint-#{suffix}",
      action_kind: :schedule_timer,
      packet_id: "packet-#{suffix}",
      evidence_id: "evidence-#{suffix}",
      request_document: %{"timer_key" => "flush"},
      requested_at: occurred_at
    }
    |> Event.from_managed_action_request(replay_run_id)
    |> Map.put(:organization_id, organization_id)
  end

  def contact_interval_operational_event(
        organization_id,
        mission_id,
        contact_id,
        source_endpoint_ref,
        starts_at,
        ends_at,
        replay_run_id
      ) do
    Event.new(%{
      event_id: "operational_event:scheduled_contact_interval:#{contact_id}:#{replay_run_id}",
      organization_id: organization_id,
      mission_id: mission_id,
      occurred_at: starts_at,
      recorded_at: starts_at,
      effective_at: starts_at,
      category: :contact,
      kind: :scheduled_contact_interval,
      severity: :info,
      actor: %{kind: :replay, id: replay_run_id},
      subject: %{kind: :contact, id: contact_id},
      scope: %{
        replay_run_id: replay_run_id,
        source_endpoint_ref: source_endpoint_ref
      },
      causality: %{
        correlation_id: contact_id,
        replay_run_id: replay_run_id
      },
      payload: %{
        scheduled_contact_id: contact_id,
        starts_at: starts_at,
        ends_at: ends_at,
        status: :scheduled,
        source_endpoint_refs: [source_endpoint_ref]
      }
    })
  end

  def insert_replay_telemetry_samples!(samples, replay_run_id) do
    sample_ids = Enum.map(samples, & &1.sample_id)
    provenance = replay_storage_provenance(replay_run_id)

    {count, _rows} =
      TelemetrySampleRow
      |> where([row], row.sample_id in ^sample_ids)
      |> Repo.update_all(set: [provenance: provenance])

    assert count == length(sample_ids)

    Enum.each(samples, fn sample ->
      replay_sample = %{sample | provenance: provenance}

      assert {:ok, _row} =
               Repo.insert(ReplayTelemetrySampleRow.changeset(replay_run_id, replay_sample))
    end)
  end

  def insert_replay_persisted_telemetry_samples!(sample_ids, replay_run_id) do
    rows =
      TelemetrySampleRow
      |> where([row], row.sample_id in ^sample_ids)
      |> Repo.all()

    assert length(rows) == length(sample_ids)

    rows
    |> Enum.map(&TelemetrySampleRow.to_domain/1)
    |> Enum.each(fn sample ->
      assert {:ok, _row} =
               Repo.insert(ReplayTelemetrySampleRow.changeset(replay_run_id, sample))
    end)
  end

  def insert_replay_limit_events!(mission, spacecraft, samples, replay_run_id) do
    samples
    |> Enum.with_index(1)
    |> Enum.each(fn {sample, index} ->
      value = if index == 1, do: 25, else: 35

      event = %LimitEvent{
        limit_event_id: "browser-smoke-replay-limit-#{index}",
        mission_id: mission.mission_id,
        spacecraft_id: spacecraft.spacecraft_id,
        point_id: "HK.counter",
        point_name: "HK.counter",
        source_sample_type: :telemetry_sample,
        sample_id: sample.sample_id,
        limit_definition_id: "browser-viewport-counter-limits",
        limit_definition_version: 1,
        limit_set_name: "browser-smoke",
        evaluated_value: value,
        limit_state: if(value >= 30, do: :red_high, else: :yellow_high),
        normalized_state: if(value >= 30, do: :red, else: :yellow),
        violation: true,
        generation_time: sample.generation_time,
        receipt_time: sample.receipt_time,
        provenance: replay_storage_provenance(replay_run_id)
      }

      assert {:ok, _row} = Repo.insert(TelemetryLimitEventRow.changeset(event))
    end)
  end

  def replay_storage_provenance(replay_run_id) do
    %{
      "storage" => %{
        "realm" => "replay",
        "data_source_id" => "managed_questdb_replay",
        "binding_id" => "replay_telemetry",
        "replay_run_id" => replay_run_id,
        "dataset" => "replay"
      }
    }
  end

  def record_completed_late_data_policy_source_event!(
        org,
        mission,
        dashboard,
        spacecraft,
        samples,
        limit_mode,
        opts \\ []
      ) do
    [first_sample | _rest] = samples
    last_sample = List.last(samples)

    assert {:ok, event} =
             Cadence.record_telemetry_historical_data_workflow_event(
               "backfill",
               "completed",
               %{
                 backfill_run_id: "browser-smoke-late-data-policy-#{limit_mode}",
                 organization_id: org.organization_id,
                 mission_id: mission.mission_id,
                 realm: :flight,
                 data_source_id: DataSources.default_managed_data_source().data_source_id,
                 binding_id: "default_flight_telemetry",
                 observable_id: "HK.counter",
                 point_id: "HK.counter",
                 spacecraft_id: spacecraft.spacecraft_id,
                 source_from: sample_observed_at(first_sample),
                 source_to: sample_observed_at(last_sample),
                 receipt_from: first_sample.receipt_time,
                 receipt_to: last_sample.receipt_time,
                 sample_count: length(samples),
                 authority: :authoritative,
                 reason: "historical_data_job_completed",
                 actor_id: "system",
                 actor_kind: "system",
                 payload: %{
                   "workflow" => "backfill",
                   "stage" => "completed",
                   "workflow_job_status" => "completed",
                   "dashboard_context" => %{
                     "dashboard_id" => dashboard.dashboard_id,
                     "dashboard_limit_mode" => limit_mode,
                     "dashboard_data_view" => "canonical",
                     "dashboard_time_mode" => Keyword.get(opts, :dashboard_time_mode, "live"),
                     "dashboard_replay_run_id" => Keyword.get(opts, :dashboard_replay_run_id)
                   }
                 }
               },
               dashboard_runtime_invalidation?: false
             )

    event
  end

  def sample_observed_at(%{generation_time: %DateTime{} = generation_time}), do: generation_time
  def sample_observed_at(%{receipt_time: %DateTime{} = receipt_time}), do: receipt_time
end
