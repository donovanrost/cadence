defmodule Cadence.Platform.RootLifecycleTest do
  use Cadence.UnitCase, async: false

  alias Cadence.Commanding.{Dispatcher, DispatchSupervisor, ProcessNamespace, VerifierScheduler}
  alias Cadence.Contacts.RealizedContact
  alias Cadence.Control.MissionRuntime, as: ControlMissionRuntime
  alias Cadence.Control.MissionRuntimeReconciler
  alias Cadence.Control.Missions, as: ControlMissions
  alias Cadence.Control.ProcessNamespace, as: ControlProcessNamespace
  alias Cadence.Dashboards.{DashboardResolveResult, RuntimeCache, RuntimeCacheKey}
  alias Cadence.Dashboards.{RuntimeComposition, SourceCircuitBreaker}
  alias Cadence.IngressArchive
  alias Cadence.IngressJournal.{FileSystem, Identity}
  alias Cadence.Platform.RootComposition
  alias Cadence.Protocol.RecordArchive
  alias Cadence.Runtime.{IngressArchiveConsumer, ManagedRecordsPersisted}
  alias Cadence.Runtime.{MissionRuntime, ProcessingResultsPersisted, RealizedContactRuntimeSpec}
  alias Cadence.Runtime.ProcessNamespace, as: RuntimeProcessNamespace
  alias Cadence.Telemetry.{CurrentValueStore, HistoryStore, Profiler, RuntimeHealth, Sample}

  setup tags do
    owner = Cadence.DataCase.start_sandbox_owner!(tags, shared?: true)
    on_exit(fn -> Cadence.DataCase.stop_sandbox_owner(owner) end)
    :ok
  end

  test "two composed roots isolate same-identity behavior and survivor lifecycle" do
    unique = System.unique_integer([:positive])
    test_root = Path.join(System.tmp_dir!(), "cadence-root-lifecycle-#{unique}")
    organization_id = "root-lifecycle-org-#{unique}"
    mission_id = "root-lifecycle-mission-#{unique}"
    test_pid = self()

    on_exit(fn -> File.rm_rf!(test_root) end)
    Cadence.DataCase.persist_mission_scope(organization_id, mission_id)

    alpha = instance(:alpha, test_root, organization_id, mission_id, test_pid)
    bravo = instance(:bravo, test_root, organization_id, mission_id, test_pid)

    alpha_roots = start_roots(alpha.composition, organization_id)
    bravo_roots = start_roots(bravo.composition, organization_id)

    assert_root_behavior(alpha, mission_id, organization_id, 10)
    assert_root_behavior(bravo, mission_id, organization_id, 20)
    assert_fact_routing(alpha, mission_id)
    refute_received {:root_contact, :bravo, _contact_id}
    assert_fact_routing(bravo, mission_id)

    {alpha_runtime, alpha_control, alpha_scheduler} =
      start_same_identity_missions(alpha, mission_id)

    {bravo_runtime, bravo_control, bravo_scheduler} =
      start_same_identity_missions(bravo, mission_id)

    refute alpha_runtime == bravo_runtime
    refute alpha_control == bravo_control
    refute alpha_scheduler == bravo_scheduler

    assert_command_owner(alpha, organization_id, mission_id)
    assert_command_owner(bravo, organization_id, mission_id)

    {alpha_journal, alpha_journal_pid, alpha_entry} =
      start_and_append_path(alpha, mission_id, "alpha")

    {bravo_journal, bravo_journal_pid, bravo_entry} =
      start_and_append_path(bravo, mission_id, "bravo")

    assert Identity.evidence_id(alpha_entry) == Identity.evidence_id(bravo_entry)
    assert {:ok, alpha_snapshot} = FileSystem.snapshot(alpha_journal)
    assert {:ok, bravo_snapshot} = FileSystem.snapshot(bravo_journal)
    assert alpha_snapshot.stream_id == bravo_snapshot.stream_id
    refute alpha_snapshot.stream_path == bravo_snapshot.stream_path

    assert_archived(alpha, mission_id, alpha_entry, "alpha")
    assert_archived(bravo, mission_id, bravo_entry, "bravo")

    stop_root_set(alpha.composition)

    refute Process.alive?(alpha_roots.platform)
    refute Process.alive?(alpha_roots.runtime)
    refute Process.alive?(alpha_roots.control)
    refute Process.alive?(alpha_roots.projections)
    refute Process.alive?(alpha_journal_pid)
    refute Process.alive?(alpha_scheduler)
    assert_stopped(alpha)

    assert Process.alive?(bravo_roots.platform)
    assert Process.alive?(bravo_roots.runtime)
    assert Process.alive?(bravo_roots.control)
    assert Process.alive?(bravo_roots.projections)
    assert Process.alive?(bravo_journal_pid)

    assert_surviving_behavior(
      bravo,
      mission_id,
      organization_id,
      bravo_runtime,
      bravo_control,
      bravo_scheduler
    )

    receipt_time = DateTime.add(bravo_entry.receipt_time, 1, :second)
    metadata = %{mission_id: mission_id, protocol_family: :tm, ingress_metadata: %{}}

    assert {:ok, bravo_after_stop} =
             FileSystem.append(bravo_journal, "alive", receipt_time, metadata)

    assert {:ok, survivor_snapshot} = FileSystem.snapshot(bravo_journal)
    assert survivor_snapshot.next_offset == bravo_after_stop.end_offset
    assert String.starts_with?(survivor_snapshot.stream_path, bravo.journal_root)
  end

  defp start_roots(composition, organization_id) do
    %{
      platform:
        start_supervised!(
          {Cadence.Platform.Supervisor,
           root_composition: composition, event_bus_child_opts: [name: Cadence.Platform.EventBus]}
        ),
      runtime:
        start_supervised!(
          {Cadence.Runtime.Supervisor,
           root_composition: composition,
           process_namespace: RuntimeProcessNamespace.default(),
           persistence_policy: %{event_bus: Cadence.Platform.EventBus},
           mission_runtime_opts: [
             organization_id: organization_id,
             persist_runtime_records?: false,
             ingress_journal_policy: FileSystem.policy(enabled?: false)
           ]}
        ),
      control:
        start_supervised!(
          {Cadence.Control.Supervisor,
           root_composition: composition,
           process_namespace: ControlProcessNamespace.default(),
           runtime_process_namespace: RuntimeProcessNamespace.default(),
           start_mission_recovery?: false,
           mission_runtime_opts: [
             start_contact_scheduler?: false,
             reconciler_opts: [reconcile_on_start?: false, safety_poll?: false]
           ]}
        ),
      projections:
        start_supervised!(
          {Cadence.Projections.Supervisor,
           root_composition: composition,
           dashboard_runtime_composition: RuntimeComposition.new!(),
           runtime_fact_consumer_opts: [event_bus: Cadence.Platform.EventBus]}
        )
    }
  end

  defp assert_root_behavior(instance, mission_id, organization_id, raw_value) do
    composition = instance.composition
    sample = sample(mission_id, raw_value)

    assert :ok =
             CurrentValueStore.record_samples(composition.current_value_store_policy, [sample])

    assert :ok = HistoryStore.persist_samples(composition.history_store_policy, [sample])

    assert CurrentValueStore.latest_value(
             composition.current_value_store_policy,
             mission_id,
             sample.point_id,
             []
           ).raw_value == raw_value

    assert [stored] =
             HistoryStore.sample_history(
               composition.history_store_policy,
               mission_id,
               sample.point_id,
               order: :asc,
               limit: 10
             )

    assert stored.raw_value == raw_value

    profiler = composition.profiler_child_opts[:name]
    count = if instance.owner == :alpha, do: 1, else: 2
    assert :ok = Profiler.record_projected_persistence(profiler, mission_id, count, count * 100)
    assert Profiler.snapshot(profiler, mission_id).stages.persistence.count == count

    runtime_health = composition.runtime_health_child_opts[:name]

    assert :ok =
             RuntimeHealth.execute(
               runtime_health,
               [:cadence, :commanding, :dispatcher, :reconcile],
               %{pending_lane_count: count},
               %{reason: :manual, organization_id: organization_id, mission_id: mission_id}
             )

    assert RuntimeHealth.snapshot(runtime_health).total_events == 1

    cache = composition.dashboard_runtime_composition.runtime_cache
    key = cache_key(mission_id)
    result = %DashboardResolveResult{dashboard_id: Atom.to_string(instance.owner)}
    assert :ok = RuntimeCache.put_plan(key, result, cache)
    assert {:ok, ^result} = RuntimeCache.get_plan(key, cache)

    breaker = composition.dashboard_runtime_composition.source_circuit_breaker
    source_key = {organization_id, mission_id, :telemetry, "shared-source", :flight, "shared"}
    assert %{state: :open} = SourceCircuitBreaker.record_failure(breaker, source_key, :failed, [])

    assert is_pid(Process.whereis(instance.addresses.ingress_writer))
    assert is_pid(Process.whereis(instance.addresses.record_writer))
    assert IngressArchive.stats(composition.ingress_archive_policy, mission_id).queue_depth == 0
    assert RecordArchive.stats(composition.record_archive_policy, mission_id).queue_depth == 0
  end

  defp assert_fact_routing(instance, mission_id) do
    contact_id = "shared-fact-contact"
    contact = RealizedContact.new(%{realized_contact_id: contact_id, mission_id: mission_id})
    assert :ok = Cadence.Contacts.Facts.publish(instance.composition.event_bus, contact)
    assert_receive {:root_contact, owner, ^contact_id} when owner == instance.owner

    samples = [%{sample_id: "shared-fact-sample"}]

    assert :ok =
             Cadence.Runtime.Facts.publish(
               instance.composition.event_bus,
               %ProcessingResultsPersisted{
                 batch_id: "shared-batch",
                 evidence_ids: [],
                 telemetry_samples: samples,
                 persisted_at: DateTime.utc_now()
               }
             )

    assert_receive {:root_control_runtime, owner, ^samples} when owner == instance.owner

    records = [%{request_id: "shared-action"}]

    assert :ok =
             Cadence.Runtime.Facts.publish(
               instance.composition.event_bus,
               %ManagedRecordsPersisted{
                 capability_records: [],
                 action_requests: records,
                 timer_events: [],
                 persisted_at: DateTime.utc_now()
               }
             )

    assert_receive {:root_projection_runtime, owner, ^records} when owner == instance.owner
  end

  defp start_same_identity_missions(instance, mission_id) do
    runtime_namespace = instance.composition.runtime_process_namespace
    control_namespace = instance.composition.control_process_namespace

    assert {:ok, runtime} = Cadence.Runtime.ensure_mission_started(runtime_namespace, mission_id)
    assert {:ok, control} = ControlMissions.ensure_started(control_namespace, mission_id)

    assert %{mission_id: ^mission_id, safety_timer_scheduled?: false} =
             MissionRuntimeReconciler.snapshot(control_namespace, mission_id)

    scheduler =
      GenServer.whereis(
        ControlMissionRuntime.contact_scheduler_name(control_namespace, mission_id)
      )

    assert is_pid(scheduler)

    {runtime, control, scheduler}
  end

  defp assert_command_owner(instance, organization_id, mission_id) do
    namespace = instance.composition.command_process_namespace
    assert {:ok, %{pending_lane_count: 1}} = Dispatcher.reconcile_now(namespace)
    assert_receive {:root_pending_lanes, owner} when owner == instance.owner

    assert {:ok, lane} =
             DispatchSupervisor.lane_dispatcher(
               namespace,
               organization_id,
               mission_id,
               "shared-lane"
             )

    assert Process.alive?(lane)

    assert %{projected_verifier_count: 0, timeout_timer_count: 0} =
             VerifierScheduler.snapshot(namespace)
  end

  defp start_and_append_path(instance, mission_id, payload) do
    namespace = instance.composition.runtime_process_namespace
    assert {:ok, spec} = realized_contact_spec(mission_id)
    assert {:ok, _contact} = Cadence.Runtime.start_realized_contact(namespace, spec)

    journal =
      MissionRuntime.provider_ingress_journal_name(
        namespace,
        mission_id,
        "shared-contact",
        "shared-path",
        "shared-provider"
      )

    assert {:ok, journal_pid} = FileSystem.lookup(journal)
    receipt_time = DateTime.from_unix!(1_703_000_000, :second)
    metadata = %{mission_id: mission_id, protocol_family: :tm, ingress_metadata: %{}}
    assert {:ok, entry} = FileSystem.append(journal, payload, receipt_time, metadata)
    {journal, journal_pid, entry}
  end

  defp assert_archived(instance, mission_id, entry, expected_payload) do
    namespace = instance.composition.runtime_process_namespace

    consumer =
      MissionRuntime.provider_ingress_archive_consumer_name(
        namespace,
        mission_id,
        "shared-contact",
        "shared-path",
        "shared-provider"
      )

    assert {:ok, %{status: :quiesced, archived_entries: 1}} =
             IngressArchiveConsumer.quiesce(consumer)

    assert {:ok, evidence} =
             IngressArchive.fetch_raw_evidence(
               instance.composition.ingress_archive_policy,
               mission_id,
               Identity.evidence_id(entry)
             )

    assert evidence.raw == expected_payload
  end

  defp assert_stopped(instance) do
    composition = instance.composition

    for name <- [
          composition.event_bus,
          instance.addresses.current_store,
          instance.addresses.history_store,
          composition.profiler_child_opts[:name],
          composition.runtime_health_child_opts[:name],
          RuntimeCache.server(composition.dashboard_runtime_composition.runtime_cache),
          composition.dashboard_runtime_composition.source_circuit_breaker,
          composition.command_process_namespace.dispatcher,
          composition.command_process_namespace.verifier_scheduler
        ] do
      assert Process.whereis(name) == nil
    end
  end

  defp assert_surviving_behavior(
         instance,
         mission_id,
         organization_id,
         runtime,
         control,
         scheduler
       ) do
    composition = instance.composition
    assert Process.whereis(composition.event_bus) |> Process.alive?()

    assert {:ok, ^runtime} =
             Cadence.Runtime.ensure_mission_started(
               composition.runtime_process_namespace,
               mission_id
             )

    assert {:ok, ^control} =
             ControlMissions.ensure_started(composition.control_process_namespace, mission_id)

    assert ^scheduler =
             GenServer.whereis(
               ControlMissionRuntime.contact_scheduler_name(
                 composition.control_process_namespace,
                 mission_id
               )
             )

    assert_fact_routing(instance, mission_id)
    assert_command_owner(instance, organization_id, mission_id)

    survivor_sample = sample(mission_id, 30)

    assert :ok =
             CurrentValueStore.record_samples(composition.current_value_store_policy, [
               survivor_sample
             ])

    assert CurrentValueStore.latest_value(
             composition.current_value_store_policy,
             mission_id,
             survivor_sample.point_id,
             []
           ).raw_value == 30

    cache = composition.dashboard_runtime_composition.runtime_cache

    assert {:ok, %DashboardResolveResult{dashboard_id: "bravo"}} =
             RuntimeCache.get_plan(cache_key(mission_id), cache)

    assert %{projected_verifier_count: 0} =
             VerifierScheduler.snapshot(composition.command_process_namespace)
  end

  defp instance(owner, test_root, organization_id, mission_id, test_pid) do
    addresses = addresses(owner)
    instance_root = Path.join(test_root, Atom.to_string(owner))
    ingress_root = Path.join(instance_root, "ingress")
    record_root = Path.join(instance_root, "records")
    journal_root = Path.join(instance_root, "journal")
    cache = RuntimeCache.client(addresses.dashboard_cache)

    dashboard_runtime =
      RuntimeComposition.new!(
        runtime_cache: cache,
        runtime_cache_child_opts: [id: addresses.dashboard_cache, name: addresses.dashboard_cache],
        runtime_invalidation_cache: cache,
        source_circuit_breaker: addresses.source_circuit_breaker,
        source_circuit_breaker_child_opts: [
          id: addresses.source_circuit_breaker,
          name: addresses.source_circuit_breaker,
          runtime_composed?: true,
          failure_threshold: 1,
          backoff_ms: 60_000
        ]
      )

    composition =
      RootComposition.new!(
        platform_supervisor_name: addresses.platform_supervisor,
        platform_children: [],
        event_bus: addresses.event_bus,
        event_bus_child_opts: [delivery: :sync, before_notify: nil],
        runtime_process_namespace: runtime_namespace(owner),
        control_process_namespace: control_namespace(owner),
        command_process_namespace: command_namespace(owner),
        projections_supervisor_name: addresses.projections_supervisor,
        ingress_archive_config: [
          module: Cadence.IngressArchive.FileSystem,
          name: addresses.ingress_writer,
          instance_id: "root-lifecycle-#{owner}-#{mission_id}",
          base_path: ingress_root,
          repo: Cadence.Repo,
          flush_interval_ms: 60_000,
          flush_count: 100
        ],
        record_archive_config: [
          module: Cadence.Protocol.RecordArchive.FileSystem,
          name: addresses.record_writer,
          instance_id: "root-lifecycle-records-#{owner}-#{mission_id}",
          base_path: record_root,
          repo: Cadence.Repo,
          flush_interval_ms: 60_000,
          flush_count: 100
        ],
        current_value_store_config: [
          module: Cadence.Telemetry.CurrentValueStore.ETS,
          name: addresses.current_store,
          child_id: addresses.current_child_id,
          table_name: addresses.current_table
        ],
        telemetry_storage_config: [writer: Cadence.Telemetry.Storage.Writers.Noop],
        history_store_config: [
          module: Cadence.Telemetry.HistoryStore.ETS,
          name: addresses.history_store,
          child_id: addresses.history_child_id,
          table_name: addresses.history_table,
          config_table_name: addresses.history_config_table,
          max_samples_per_point: 10
        ],
        ingress_archive_consumer_config: [
          required_completion: :durable,
          poll_interval_ms: 60_000,
          max_batch_entries: 10,
          max_batch_bytes: 1_024,
          max_dwell_ms: 60_000,
          retry_initial_ms: 1,
          retry_max_ms: 10
        ],
        ingress_journal_policy:
          FileSystem.policy(
            enabled?: true,
            base_path: journal_root,
            durability: :page_cache,
            consumers: [:processing, :archive],
            max_bytes: 1_024 * 1_024,
            segment_bytes: 64 * 1_024,
            capture_record_bytes: 1_024,
            checkpoint_interval_ms: 60_000,
            processing_poll_interval_ms: 60_000,
            processing_max_batch_entries: 10,
            processing_max_batch_bytes: 1_024
          ),
        profiler_child_opts: [name: addresses.profiler],
        runtime_health_child_opts: [
          name: addresses.runtime_health,
          event_route: addresses.runtime_health_route
        ],
        dashboard_runtime_composition: dashboard_runtime,
        dashboard_runtime_fact_consumer_opts: [name: addresses.dashboard_fact_consumer],
        control_contact_fact_consumer_opts: [
          notify_release_target: fn contact ->
            send(test_pid, {:root_contact, owner, contact.realized_contact_id})
          end
        ],
        control_runtime_fact_consumer_opts: [
          evaluate_telemetry: fn samples ->
            send(test_pid, {:root_control_runtime, owner, samples})
          end,
          evaluate_transport: fn _records, _requests -> :ok end
        ],
        projections_runtime_fact_consumer_opts: [
          name: addresses.projections_runtime_consumer,
          project_records: fn records ->
            send(test_pid, {:root_projection_runtime, owner, records})
          end
        ],
        projections_telemetry_fact_consumer_opts: [
          name: addresses.projections_telemetry_consumer,
          refresh_point: fn _mission_id, _point_id, _opts -> {:ok, nil} end
        ],
        projections_domain_fact_consumer_opts: [
          name: addresses.projections_domain_consumer,
          project_fact: fn _fact -> :ok end
        ],
        contact_scheduler_config: [
          enabled: true,
          auto_schedule?: false,
          run_on_boot?: false,
          safety_poll_interval_ms: :timer.hours(1)
        ],
        contact_scheduler_global_safety_config: [enabled: false],
        provider_reservation_reconciler_config: [enabled: false],
        provider_event_ingestion_config: [enabled: false],
        command_dispatch_supervisor_child_opts: [
          auto_schedule?: false,
          run_on_boot?: false,
          requeue_release_pending_fun: fn -> 0 end,
          list_pending_queue_lanes_fun: fn ->
            send(test_pid, {:root_pending_lanes, owner})

            [
              %{
                organization_id: organization_id,
                mission_id: mission_id,
                queue_lane_key: "shared-lane"
              }
            ]
          end,
          lane_dispatcher_opts: [run_on_boot?: false]
        ],
        command_verifier_scheduler_child_opts: [
          auto_schedule?: false,
          run_on_boot?: false,
          projection_query_fun: fn -> [] end,
          timeout_reconcile_fun: fn _reference_time -> {:ok, []} end
        ],
        data_source_probe_scheduler_config: [enabled?: false],
        mission_health_observability_children: []
      )

    %{
      addresses: addresses,
      composition: composition,
      journal_root: journal_root,
      owner: owner
    }
  end

  defp realized_contact_spec(mission_id) do
    RealizedContactRuntimeSpec.new(%{
      realized_contact_id: "shared-contact",
      mission_id: mission_id,
      source_endpoint_refs: ["shared-source"],
      contact_intents: [:telemetry],
      clock_mode: :live,
      initial_time: DateTime.from_unix!(1_703_000_000, :second),
      paths: [
        %{
          path_id: "shared-path",
          direction: :downlink,
          selection_role: :selected,
          source_endpoint_ref: "shared-source",
          provider_bindings: [
            %{
              provider_binding_id: "shared-provider",
              adapter_key: :tcp_socket,
              configuration: %{
                mode: :listen,
                port: 0,
                ingress_protocol_family: :tm,
                frame_size: 5,
                ingress_metadata: %{frame_size: 5, ocf_length: 0}
              }
            }
          ]
        }
      ]
    })
  end

  defp stop_root_set(composition) do
    assert :ok = stop_supervised(composition.control_process_namespace.root_supervisor)
    assert :ok = stop_supervised(composition.projections_supervisor_name)
    assert :ok = stop_supervised(composition.runtime_process_namespace.root_supervisor)
    assert :ok = stop_supervised(composition.platform_supervisor_name)
  end

  defp cache_key(mission_id),
    do: %RuntimeCacheKey{
      layer: :plan,
      fingerprint: "shared-root-plan",
      parts: %{mission_id: mission_id}
    }

  defp sample(mission_id, raw_value) do
    receipt_time = DateTime.from_unix!(1_703_000_100 + raw_value, :second)

    %Sample{
      sample_id: "shared-sample",
      mission_id: mission_id,
      point_id: "HK.shared",
      point_name: "HK.shared",
      packet_definition_id: "shared-packet-definition",
      packet_definition_version: 1,
      packet_id: "shared-packet",
      evidence_id: "shared-evidence",
      raw_value: raw_value,
      engineering_value: raw_value,
      quality_state: :good,
      receipt_time: receipt_time,
      generation_time: receipt_time,
      provenance: %{}
    }
  end

  defp runtime_namespace(:alpha) do
    RuntimeProcessNamespace.new!(
      root_supervisor: __MODULE__.AlphaRuntimeSupervisor,
      registry: __MODULE__.AlphaRuntimeRegistry,
      mission_supervisor: __MODULE__.AlphaRuntimeMissionSupervisor,
      capability_registry: __MODULE__.AlphaRuntimeCapabilityRegistry
    )
  end

  defp runtime_namespace(:bravo) do
    RuntimeProcessNamespace.new!(
      root_supervisor: __MODULE__.BravoRuntimeSupervisor,
      registry: __MODULE__.BravoRuntimeRegistry,
      mission_supervisor: __MODULE__.BravoRuntimeMissionSupervisor,
      capability_registry: __MODULE__.BravoRuntimeCapabilityRegistry
    )
  end

  defp control_namespace(:alpha) do
    ControlProcessNamespace.new!(
      root_supervisor: __MODULE__.AlphaControlSupervisor,
      registry: __MODULE__.AlphaControlRegistry,
      mission_supervisor: __MODULE__.AlphaControlMissionSupervisor,
      mission_recovery: __MODULE__.AlphaMissionRecovery,
      contact_fact_consumer: __MODULE__.AlphaContactFactConsumer,
      runtime_fact_consumer: __MODULE__.AlphaControlRuntimeFactConsumer
    )
  end

  defp control_namespace(:bravo) do
    ControlProcessNamespace.new!(
      root_supervisor: __MODULE__.BravoControlSupervisor,
      registry: __MODULE__.BravoControlRegistry,
      mission_supervisor: __MODULE__.BravoControlMissionSupervisor,
      mission_recovery: __MODULE__.BravoMissionRecovery,
      contact_fact_consumer: __MODULE__.BravoContactFactConsumer,
      runtime_fact_consumer: __MODULE__.BravoControlRuntimeFactConsumer
    )
  end

  defp command_namespace(:alpha) do
    ProcessNamespace.new!(
      root_supervisor: __MODULE__.AlphaCommandSupervisor,
      registry: __MODULE__.AlphaCommandRegistry,
      lane_supervisor: __MODULE__.AlphaCommandLaneSupervisor,
      dispatcher: __MODULE__.AlphaCommandDispatcher,
      verifier_scheduler: __MODULE__.AlphaCommandVerifierScheduler
    )
  end

  defp command_namespace(:bravo) do
    ProcessNamespace.new!(
      root_supervisor: __MODULE__.BravoCommandSupervisor,
      registry: __MODULE__.BravoCommandRegistry,
      lane_supervisor: __MODULE__.BravoCommandLaneSupervisor,
      dispatcher: __MODULE__.BravoCommandDispatcher,
      verifier_scheduler: __MODULE__.BravoCommandVerifierScheduler
    )
  end

  defp addresses(:alpha) do
    %{
      platform_supervisor: __MODULE__.AlphaPlatformSupervisor,
      event_bus: __MODULE__.AlphaEventBus,
      projections_supervisor: __MODULE__.AlphaProjectionsSupervisor,
      ingress_writer: __MODULE__.AlphaIngressWriter,
      record_writer: __MODULE__.AlphaRecordWriter,
      current_store: __MODULE__.AlphaCurrentStore,
      current_child_id: {__MODULE__, :alpha_current_store},
      current_table: :cadence_root_lifecycle_alpha_current,
      history_store: __MODULE__.AlphaHistoryStore,
      history_child_id: {__MODULE__, :alpha_history_store},
      history_table: :cadence_root_lifecycle_alpha_history,
      history_config_table: :cadence_root_lifecycle_alpha_history_config,
      profiler: __MODULE__.AlphaProfiler,
      runtime_health: __MODULE__.AlphaRuntimeHealth,
      runtime_health_route: {__MODULE__, :alpha_runtime_health},
      dashboard_cache: __MODULE__.AlphaDashboardCache,
      source_circuit_breaker: __MODULE__.AlphaSourceCircuitBreaker,
      dashboard_fact_consumer: __MODULE__.AlphaDashboardFactConsumer,
      projections_runtime_consumer: __MODULE__.AlphaProjectionsRuntimeConsumer,
      projections_telemetry_consumer: __MODULE__.AlphaProjectionsTelemetryConsumer,
      projections_domain_consumer: __MODULE__.AlphaProjectionsDomainConsumer
    }
  end

  defp addresses(:bravo) do
    %{
      platform_supervisor: __MODULE__.BravoPlatformSupervisor,
      event_bus: __MODULE__.BravoEventBus,
      projections_supervisor: __MODULE__.BravoProjectionsSupervisor,
      ingress_writer: __MODULE__.BravoIngressWriter,
      record_writer: __MODULE__.BravoRecordWriter,
      current_store: __MODULE__.BravoCurrentStore,
      current_child_id: {__MODULE__, :bravo_current_store},
      current_table: :cadence_root_lifecycle_bravo_current,
      history_store: __MODULE__.BravoHistoryStore,
      history_child_id: {__MODULE__, :bravo_history_store},
      history_table: :cadence_root_lifecycle_bravo_history,
      history_config_table: :cadence_root_lifecycle_bravo_history_config,
      profiler: __MODULE__.BravoProfiler,
      runtime_health: __MODULE__.BravoRuntimeHealth,
      runtime_health_route: {__MODULE__, :bravo_runtime_health},
      dashboard_cache: __MODULE__.BravoDashboardCache,
      source_circuit_breaker: __MODULE__.BravoSourceCircuitBreaker,
      dashboard_fact_consumer: __MODULE__.BravoDashboardFactConsumer,
      projections_runtime_consumer: __MODULE__.BravoProjectionsRuntimeConsumer,
      projections_telemetry_consumer: __MODULE__.BravoProjectionsTelemetryConsumer,
      projections_domain_consumer: __MODULE__.BravoProjectionsDomainConsumer
    }
  end
end
