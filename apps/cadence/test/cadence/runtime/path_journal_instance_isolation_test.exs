defmodule Cadence.Runtime.PathJournalInstanceIsolationTest do
  use Cadence.ProcessDataCase, async: false

  alias Cadence.IngressArchive
  alias Cadence.IngressArchive.FileSystem, as: ArchiveFileSystem
  alias Cadence.IngressJournal.{Evidence, FileSystem, Identity}
  alias Cadence.Repo
  alias Cadence.Runtime.IngressArchiveConsumer
  alias Cadence.TestSupport.TelemetryPersistencePolicies

  alias Cadence.Runtime.{
    MissionRuntime,
    Persistence,
    ProcessNamespace,
    RealizedContactRuntimeSpec,
    Supervisor
  }

  @alpha_archive_writer __MODULE__.AlphaArchiveWriter
  @bravo_archive_writer __MODULE__.BravoArchiveWriter

  test "same-identity path journals and archives remain isolated after one runtime stops" do
    unique = System.unique_integer([:positive])
    test_root = Path.join(System.tmp_dir!(), "cadence_path_journal_instances_#{unique}")
    mission_id = "shared-journal-mission-#{unique}"
    organization_id = "shared-journal-org-#{unique}"
    realized_contact_id = "shared-journal-contact"
    path_id = "shared-journal-path"
    provider_binding_id = "shared-journal-provider"

    alpha =
      instance(
        :alpha,
        test_root,
        mission_id,
        organization_id,
        realized_contact_id,
        path_id,
        provider_binding_id
      )

    bravo =
      instance(
        :bravo,
        test_root,
        mission_id,
        organization_id,
        realized_contact_id,
        path_id,
        provider_binding_id
      )

    on_exit(fn -> File.rm_rf!(test_root) end)
    Cadence.DataCase.persist_mission_scope(organization_id, mission_id)

    alpha_root = start_runtime_root(alpha, organization_id)
    bravo_root = start_runtime_root(bravo, organization_id)

    {:ok, realized_contact} =
      realized_contact(mission_id, realized_contact_id, path_id, provider_binding_id)

    assert {:ok, alpha_contact} =
             Cadence.Runtime.start_realized_contact(alpha.namespace, realized_contact)

    assert {:ok, bravo_contact} =
             Cadence.Runtime.start_realized_contact(bravo.namespace, realized_contact)

    alpha_journal =
      journal_name(alpha, mission_id, realized_contact_id, path_id, provider_binding_id)

    bravo_journal =
      journal_name(bravo, mission_id, realized_contact_id, path_id, provider_binding_id)

    alpha_archive_consumer =
      archive_consumer_name(alpha, mission_id, realized_contact_id, path_id, provider_binding_id)

    bravo_archive_consumer =
      archive_consumer_name(bravo, mission_id, realized_contact_id, path_id, provider_binding_id)

    assert {:ok, alpha_journal_pid} = FileSystem.lookup(alpha_journal)
    assert {:ok, bravo_journal_pid} = FileSystem.lookup(bravo_journal)

    assert {:ok, alpha_archive_consumer_pid} =
             IngressArchiveConsumer.lookup(alpha_archive_consumer)

    assert {:ok, bravo_archive_consumer_pid} =
             IngressArchiveConsumer.lookup(bravo_archive_consumer)

    assert alpha_journal_pid != bravo_journal_pid
    assert alpha_archive_consumer_pid != bravo_archive_consumer_pid

    receipt_time = DateTime.from_unix!(1_703_000_000, :second)
    metadata = %{mission_id: mission_id, protocol_family: :tm, ingress_metadata: %{}}

    assert {:ok, alpha_first} = FileSystem.append(alpha_journal, "alpha", receipt_time, metadata)
    assert {:ok, bravo_first} = FileSystem.append(bravo_journal, "bravo", receipt_time, metadata)
    assert Identity.evidence_id(alpha_first) == Identity.evidence_id(bravo_first)

    second_receipt_time = DateTime.add(receipt_time, 1, :second)

    assert {:ok, alpha_second} =
             FileSystem.append(alpha_journal, "extra", second_receipt_time, metadata)

    assert {:ok,
            %{
              status: :quiesced,
              batch_count: 2,
              archived_entries: 2,
              archived_bytes: 10
            }} = IngressArchiveConsumer.quiesce(alpha_archive_consumer)

    assert {:ok, %{lifecycle_status: :quiesced, failed_count: 0}} =
             IngressArchiveConsumer.snapshot(alpha_archive_consumer)

    assert {:ok, alpha_snapshot} = FileSystem.snapshot(alpha_journal)
    assert {:ok, bravo_snapshot} = FileSystem.snapshot(bravo_journal)
    assert alpha_snapshot.stream_id == bravo_snapshot.stream_id
    assert alpha_snapshot.stream_path != bravo_snapshot.stream_path
    assert alpha_snapshot.next_offset == 10
    assert bravo_snapshot.next_offset == 5
    assert alpha_snapshot.cursors.archive == alpha_second.end_offset
    assert String.starts_with?(alpha_snapshot.stream_path, alpha.journal_root)
    assert String.starts_with?(bravo_snapshot.stream_path, bravo.journal_root)
    assert File.exists?(alpha_first.segment_path)
    assert File.exists?(bravo_first.segment_path)

    first_evidence_id = Identity.evidence_id(alpha_first)

    assert {:ok, alpha_first_evidence} =
             IngressArchive.fetch_raw_evidence(
               alpha.archive_policy,
               mission_id,
               first_evidence_id
             )

    second_evidence_id = Identity.evidence_id(alpha_second)

    assert {:ok, alpha_second_evidence} =
             IngressArchive.fetch_raw_evidence(
               alpha.archive_policy,
               mission_id,
               second_evidence_id
             )

    assert alpha_first_evidence.raw == "alpha"
    assert alpha_second_evidence.raw == "extra"
    assert length(Path.wildcard(Path.join(alpha.archive_root, "**/*.bin"))) == 2

    assert :ok = stop_supervised(alpha.namespace.root_supervisor)
    refute Process.alive?(alpha_root)
    refute Process.alive?(alpha_contact)
    refute Process.alive?(alpha_journal_pid)
    refute Process.alive?(alpha_archive_consumer_pid)

    assert Process.alive?(bravo_root)
    assert Process.alive?(bravo_contact)
    assert Process.alive?(bravo_journal_pid)
    assert Process.alive?(bravo_archive_consumer_pid)
    assert Process.alive?(Process.whereis(@bravo_archive_writer))

    assert {:ok, bravo_second} =
             FileSystem.append(bravo_journal, "alive", second_receipt_time, metadata)

    assert Identity.evidence_id(alpha_second) == Identity.evidence_id(bravo_second)

    assert {:ok,
            %{
              status: :quiesced,
              batch_count: 2,
              archived_entries: 2,
              archived_bytes: 10
            }} = IngressArchiveConsumer.quiesce(bravo_archive_consumer)

    assert {:ok, %{lifecycle_status: :quiesced, failed_count: 0}} =
             IngressArchiveConsumer.snapshot(bravo_archive_consumer)

    assert {:ok, bravo_snapshot_after_alpha_stop} = FileSystem.snapshot(bravo_journal)
    assert bravo_snapshot_after_alpha_stop.next_offset == 10
    assert bravo_snapshot_after_alpha_stop.cursors.archive == bravo_second.end_offset

    assert {:ok, bravo_first_evidence} =
             IngressArchive.fetch_raw_evidence(
               bravo.archive_policy,
               mission_id,
               first_evidence_id
             )

    assert {:ok, bravo_second_evidence} =
             IngressArchive.fetch_raw_evidence(
               bravo.archive_policy,
               mission_id,
               second_evidence_id
             )

    assert {:ok, [alpha_second_journal_evidence]} = Evidence.from_entries([alpha_second])
    assert alpha_first_evidence.evidence_id == bravo_first_evidence.evidence_id
    assert alpha_first_evidence.raw == "alpha"
    assert bravo_first_evidence.raw == "bravo"
    assert alpha_second_journal_evidence.evidence_id == alpha_second_evidence.evidence_id
    assert alpha_second_evidence.evidence_id == bravo_second_evidence.evidence_id
    assert alpha_second_evidence.raw == "extra"
    assert bravo_second_evidence.raw == "alive"
    assert length(Path.wildcard(Path.join(bravo.archive_root, "**/*.bin"))) == 2
  end

  defp instance(
         instance,
         test_root,
         mission_id,
         organization_id,
         _realized_contact_id,
         _path_id,
         _provider_binding_id
       ) do
    namespace = namespace(instance)
    journal_root = Path.join(test_root, "journal-#{instance}")
    archive_root = Path.join(test_root, "archive-#{instance}")
    archive_writer = archive_writer(instance)

    archive_policy =
      IngressArchive.policy(
        module: ArchiveFileSystem,
        name: archive_writer,
        instance_id: "path-journal-#{instance}-#{mission_id}",
        base_path: archive_root,
        repo: Repo,
        flush_interval_ms: 60_000,
        flush_count: 100
      )

    journal_policy =
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
        processing_max_batch_entries: 1,
        processing_max_batch_bytes: 1_024
      )

    archive_consumer_policy =
      IngressArchiveConsumer.policy(
        [
          required_completion: :durable,
          poll_interval_ms: 1,
          max_batch_entries: 1,
          max_batch_bytes: 1_024,
          max_dwell_ms: 1,
          retry_initial_ms: 1,
          retry_max_ms: 10
        ],
        archive_policy
      )

    base_policies = TelemetryPersistencePolicies.postgres(organization_id: organization_id)

    %{
      archive_consumer_policy: archive_consumer_policy,
      archive_policy: archive_policy,
      archive_root: archive_root,
      base_policies: base_policies,
      journal_policy: journal_policy,
      journal_root: journal_root,
      namespace: namespace,
      persistence_policy:
        Persistence.policy(
          archive_policy,
          base_policies.record_archive,
          base_policies.telemetry_storage
        )
    }
  end

  defp start_runtime_root(instance, organization_id) do
    start_supervised!(
      {Supervisor,
       process_namespace: instance.namespace,
       resource_children: [IngressArchive.child_spec(instance.archive_policy)],
       ingress_archive_policy: instance.archive_policy,
       record_archive_policy: instance.base_policies.record_archive,
       current_value_store_policy: instance.base_policies.current_value_store,
       telemetry_storage_policy: instance.base_policies.telemetry_storage,
       history_store_policy: instance.base_policies.history_store,
       persistence_policy: instance.persistence_policy,
       ingress_archive_consumer_policy: instance.archive_consumer_policy,
       mission_runtime_opts: [
         organization_id: organization_id,
         ingress_journal_policy: instance.journal_policy,
         persist_runtime_records?: false
       ]}
    )
  end

  defp realized_contact(mission_id, realized_contact_id, path_id, provider_binding_id) do
    RealizedContactRuntimeSpec.new(%{
      realized_contact_id: realized_contact_id,
      mission_id: mission_id,
      source_endpoint_refs: ["shared-source"],
      contact_intents: [:telemetry],
      clock_mode: :live,
      initial_time: DateTime.from_unix!(1_703_000_000, :second),
      paths: [
        %{
          path_id: path_id,
          direction: :downlink,
          selection_role: :selected,
          source_endpoint_ref: "shared-source",
          provider_bindings: [
            %{
              provider_binding_id: provider_binding_id,
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

  defp journal_name(instance, mission_id, realized_contact_id, path_id, provider_binding_id) do
    MissionRuntime.provider_ingress_journal_name(
      instance.namespace,
      mission_id,
      realized_contact_id,
      path_id,
      provider_binding_id
    )
  end

  defp archive_consumer_name(
         instance,
         mission_id,
         realized_contact_id,
         path_id,
         provider_binding_id
       ) do
    MissionRuntime.provider_ingress_archive_consumer_name(
      instance.namespace,
      mission_id,
      realized_contact_id,
      path_id,
      provider_binding_id
    )
  end

  defp namespace(:alpha) do
    ProcessNamespace.new!(
      root_supervisor: __MODULE__.AlphaSupervisor,
      registry: __MODULE__.AlphaRegistry,
      mission_supervisor: __MODULE__.AlphaMissionSupervisor,
      capability_registry: __MODULE__.AlphaCapabilityRegistry
    )
  end

  defp namespace(:bravo) do
    ProcessNamespace.new!(
      root_supervisor: __MODULE__.BravoSupervisor,
      registry: __MODULE__.BravoRegistry,
      mission_supervisor: __MODULE__.BravoMissionSupervisor,
      capability_registry: __MODULE__.BravoCapabilityRegistry
    )
  end

  defp archive_writer(:alpha), do: @alpha_archive_writer
  defp archive_writer(:bravo), do: @bravo_archive_writer
end
