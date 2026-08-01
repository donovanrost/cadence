defmodule Cadence.IngressBenchmark.FullFlowRunner do
  @moduledoc false

  import Ecto.Query

  alias Cadence.ApplicationDispatch.BindingSet
  alias Cadence.Contacts.{Path, ProviderBinding, RealizedContact}
  alias Cadence.IngressBenchmark.{EphemeralIngressArchive, EphemeralProtocolRecordArchive}
  alias Cadence.Missions.Mission
  alias Cadence.Organizations.Organization
  alias Cadence.Protocol.RecordArchive.Postgres.ProtocolAnomalyRow
  alias Cadence.Runtime.MissionRuntimeSpec
  alias Cadence.SourceEndpoints.SourceEndpoint
  alias Cadence.Spacecraft
  alias Cadence.Telemetry.Profiler
  alias CadenceSimulator.IngressBenchmark.{Manifest, Preflight}

  @manifest_path "/benchmark/config/run-manifest.yaml"
  @result_path "/benchmark/results/cadence-result.json"
  @listen_port 4_601
  @poll_ms 1_000
  @heartbeat_ms 5_000
  @drain_timeout_ms 120_000

  def run! do
    Logger.configure(level: :warning)

    started_at = DateTime.utc_now()
    started_ms = System.monotonic_time(:millisecond)

    try do
      result = run(started_at, started_ms)
      write_result!(result)
      IO.puts("CADENCE_INGRESS_RESULT " <> Jason.encode!(result))
      if result.status == "passed", do: System.halt(0), else: System.halt(1)
    rescue
      exception ->
        result = %{
          status: "failed",
          stage: "runner",
          started_at: DateTime.to_iso8601(started_at),
          finished_at: DateTime.utc_now() |> DateTime.to_iso8601(),
          error: Exception.format(:error, exception, __STACKTRACE__)
        }

        write_result!(result)
        IO.puts(:stderr, "CADENCE_INGRESS_RESULT " <> Jason.encode!(result))
        reraise(exception, __STACKTRACE__)
    end
  end

  defp run(started_at, started_ms) do
    configure_runtime()

    {:ok, manifest} = Manifest.load(@manifest_path)
    {:ok, preflight} = Preflight.evaluate(manifest, component: "cadence")

    frame_size = Manifest.get(manifest, [:traffic, :pattern_size_bytes])
    expected_bytes = preflight.safety.planned_source_bytes
    [measure_phase] = Manifest.get(manifest, [:traffic, :phases])
    target_bps = Map.fetch!(measure_phase, "target_bps")
    minimum_rate_ratio = Manifest.get(manifest, [:traffic, :minimum_rate_ratio], 0.99)

    if rem(expected_bytes, frame_size) != 0 do
      raise "planned source bytes must be divisible by the fixed TM frame size"
    end

    expected_messages = div(expected_bytes, frame_size)
    :ok = EphemeralIngressArchive.reset()
    :ok = EphemeralProtocolRecordArchive.reset()

    migrate!()
    {:ok, _started} = Application.ensure_all_started(:cadence)

    ids = setup_runtime!(frame_size)
    snapshot = path_snapshot!(ids)
    [provider] = snapshot.provider_runtimes

    IO.puts(
      "CADENCE_INGRESS_READY " <>
        Jason.encode!(%{
          run_id: Manifest.get(manifest, [:run_id]),
          port: provider.port,
          frame_size_bytes: frame_size,
          expected_bytes: expected_bytes,
          expected_messages: expected_messages
        })
    )

    receive_deadline_ms =
      System.monotonic_time(:millisecond) + preflight.safety.max_wall_clock_seconds * 1_000

    {receive_snapshot, receive_observation} =
      await_receive!(ids, expected_bytes, receive_deadline_ms)

    {final_snapshot, drained_at_ms} = await_drain!(ids, expected_bytes, expected_messages)
    [final_provider] = final_snapshot.provider_runtimes
    journal = final_provider.ingress_journal
    journal_consumer = final_provider.ingress_journal_consumer
    archive_consumer = final_provider.ingress_archive_consumer
    ingress_archive = EphemeralIngressArchive.snapshot()
    protocol_archive = EphemeralProtocolRecordArchive.snapshot()
    profiler = Profiler.snapshot(ids.mission_id)
    anomaly_count = anomaly_count(ids.mission_id)
    finished_at = DateTime.utc_now()

    invariants = %{
      received_expected_bytes: final_provider.downlink_bytes_received == expected_bytes,
      receive_target_rate_met:
        receive_observation.observed_receive_bps >= target_bps * minimum_rate_ratio,
      framed_expected_messages: final_provider.downlink_message_count == expected_messages,
      executor_drained: final_provider.ingress_executor.queue_depth == 0,
      executor_processed_all:
        final_provider.ingress_executor.processed_count == journal_consumer.acknowledged_batches and
          final_provider.ingress_executor.failed_count == 0,
      projector_drained: final_provider.ingress_persistence_projector.queue_depth == 0,
      projector_persisted_all:
        final_provider.ingress_persistence_projector.persisted_count ==
          journal_consumer.acknowledged_batches and
          final_provider.ingress_persistence_projector.failed_count == 0,
      journal_captured_all:
        journal.appended_bytes == expected_bytes and journal.next_offset == expected_bytes,
      journal_capture_records_bounded:
        journal.max_appended_entry_bytes <= journal.capture_record_bytes,
      processing_batches_bounded:
        journal_consumer.max_delivered_batch_entries <= journal_consumer.max_batch_entries and
          journal_consumer.max_delivered_batch_bytes <= journal_consumer.max_batch_bytes,
      journal_consumers_acked_all:
        journal.cursors.processing == expected_bytes and journal.cursors.archive == expected_bytes and
          journal.lag_bytes.processing == 0 and journal.lag_bytes.archive == 0,
      archive_consumer_acked_all:
        archive_consumer.archived_entries == journal.appended_entries and
          archive_consumer.archived_bytes == expected_bytes and archive_consumer.failed_count == 0,
      ingress_archive_acked_all:
        ingress_archive.persisted_count == journal.appended_entries and
          ingress_archive.persisted_bytes == expected_bytes,
      protocol_archive_acked_all:
        protocol_archive.evidence_count == journal_consumer.acknowledged_batches and
          protocol_archive.frame_count == expected_messages and
          protocol_archive.packet_count == expected_messages and
          protocol_archive.represented_bytes == expected_bytes,
      no_protocol_anomalies: anomaly_count == 0
    }

    %{
      status:
        if(Enum.all?(invariants, fn {_name, passed?} -> passed? end),
          do: "passed",
          else: "failed"
        ),
      qualification: "capture_first_semantic_path_ephemeral_archives",
      durable_storage_qualified: false,
      run_id: Manifest.get(manifest, [:run_id]),
      manifest_sha256: manifest.sha256,
      started_at: DateTime.to_iso8601(started_at),
      finished_at: DateTime.to_iso8601(finished_at),
      total_duration_ms: System.monotonic_time(:millisecond) - started_ms,
      drain_duration_ms: drained_at_ms - receive_observation.completed_at_ms,
      expected: %{
        bytes: expected_bytes,
        messages: expected_messages,
        frame_size_bytes: frame_size,
        target_bps: target_bps,
        minimum_rate_ratio: minimum_rate_ratio,
        minimum_acceptable_bps: target_bps * minimum_rate_ratio
      },
      receive:
        Map.drop(receive_observation, [
          :completed_at_ms,
          :first_byte_at_ms,
          :last_heartbeat_at_ms
        ]),
      provider: provider_report(final_provider),
      executor: final_provider.ingress_executor,
      projector: final_provider.ingress_persistence_projector,
      ingress_journal: journal,
      ingress_journal_consumer: journal_consumer,
      ingress_archive_consumer: archive_consumer,
      ingress_archive: ingress_archive,
      protocol_archive: protocol_archive,
      profiler: profiler,
      persisted_protocol_anomaly_count: anomaly_count,
      invariants: invariants,
      receive_snapshot: provider_report(List.first(receive_snapshot.provider_runtimes)),
      erlang_memory_bytes: Map.new(:erlang.memory())
    }
  end

  defp configure_runtime do
    repo_config = [
      username: System.get_env("POSTGRES_USER", "postgres"),
      password: System.get_env("POSTGRES_PASSWORD", "postgres"),
      hostname: System.get_env("POSTGRES_HOST", "postgres"),
      database: System.get_env("POSTGRES_DB", "cadence_ingress_benchmark"),
      pool_size: 20,
      queue_target: 5_000,
      queue_interval: 10_000,
      timeout: 60_000
    ]

    Application.put_env(:cadence, Cadence.Repo, repo_config)
    Application.put_env(:cadence, :start_background_jobs, false)
    Application.put_env(:cadence, :contact_scheduler, enabled: false)
    Application.put_env(:cadence, :provider_reservation_reconciler, enabled: false)
    Application.put_env(:cadence, :command_dispatcher, enabled: false)
    Application.put_env(:cadence, :command_verifier_scheduler, enabled: false)
    Application.put_env(:cadence, :dashboard_source_probe_scheduler, enabled?: false)
    Application.put_env(:cadence, :dashboard_source_watermark_events, enabled?: false)
    Application.put_env(:cadence, :ingress_archive, module: EphemeralIngressArchive)

    Application.put_env(:cadence, :ingress_archive_consumer,
      required_completion: :accepted,
      max_batch_entries: 128,
      max_batch_bytes: 8 * 1_024 * 1_024,
      max_dwell_ms: 25,
      poll_interval_ms: 1,
      retry_initial_ms: 10,
      retry_max_ms: 1_000
    )

    Application.put_env(:cadence, :ingress_journal,
      enabled?: true,
      base_path: "/benchmark/journal",
      max_bytes: 900 * 1_024 * 1_024,
      segment_bytes: 64 * 1_024 * 1_024,
      capture_record_bytes: 256 * 1_024,
      processing_max_batch_entries: 8,
      processing_max_batch_bytes: 2 * 1_024 * 1_024,
      durability: :page_cache,
      checkpoint_interval_ms: 100,
      consumers: [:processing, :archive]
    )

    Application.put_env(:cadence, :protocol_record_archive,
      module: EphemeralProtocolRecordArchive
    )

    Application.put_env(:cadence, :telemetry_storage,
      writer: Cadence.Telemetry.Storage.Writers.Noop,
      realm: :flight,
      data_source_id: "ingress_benchmark",
      binding_id: "ingress_benchmark"
    )

    Application.put_env(:cadence, :telemetry_current_value_store,
      module: Cadence.Telemetry.CurrentValueStore.ETS
    )
  end

  defp migrate! do
    Mix.Task.run("ecto.migrate", ["--quiet", "-r", "Cadence.Repo"])
  end

  defp setup_runtime!(frame_size) do
    run_suffix = Integer.to_string(System.system_time(:millisecond))

    ids = %{
      organization_id: "org-ingress-benchmark-" <> run_suffix,
      mission_id: "mission-ingress-benchmark-" <> run_suffix,
      spacecraft_id: "spacecraft-ingress-benchmark-" <> run_suffix,
      source_endpoint_id: "source-ingress-benchmark-" <> run_suffix,
      realized_contact_id: "contact-ingress-benchmark-" <> run_suffix,
      path_id: "path-ingress-benchmark-" <> run_suffix,
      provider_binding_id: "provider-ingress-benchmark-" <> run_suffix
    }

    organization =
      Organization.new(%{
        organization_id: ids.organization_id,
        slug: ids.organization_id,
        display_name: "Ingress Benchmark"
      })

    {:ok, _organization} = Cadence.Organizations.persist_organization(organization)

    mission =
      Mission.new(%{
        mission_id: ids.mission_id,
        organization_id: ids.organization_id,
        slug: ids.mission_id,
        display_name: "Ingress Benchmark"
      })

    {:ok, _mission} = Cadence.Missions.persist_mission(mission)

    spacecraft =
      Spacecraft.new(%{
        spacecraft_id: ids.spacecraft_id,
        mission_id: ids.mission_id,
        display_name: "INGRESS-BENCHMARK",
        scid: 11
      })

    {:ok, _spacecraft} =
      Cadence.SpacecraftStore.persist_spacecraft(ids.organization_id, spacecraft)

    source_endpoint =
      SourceEndpoint.new(%{
        source_endpoint_id: ids.source_endpoint_id,
        mission_id: ids.mission_id,
        spacecraft_id: ids.spacecraft_id,
        source_ref: "benchmark/tcp/downlink",
        display_name: "Ingress benchmark source"
      })

    {:ok, _source_endpoint} =
      Cadence.SourceEndpoints.persist_source_endpoint(ids.organization_id, source_endpoint)

    binding_set =
      BindingSet.new(%{
        organization_id: ids.organization_id,
        mission_id: ids.mission_id,
        binding_set_id: "binding-ingress-benchmark-" <> run_suffix,
        version: 1,
        rules: []
      })

    {:ok, runtime_spec} =
      MissionRuntimeSpec.new(%{
        activation_id: "activation-ingress-benchmark-" <> run_suffix,
        organization_id: ids.organization_id,
        mission_id: ids.mission_id,
        generation: 1,
        binding_set_id: binding_set.binding_set_id,
        binding_set_version: binding_set.version,
        binding_set_content_sha256: MissionRuntimeSpec.content_sha256(binding_set),
        binding_set: binding_set,
        activated_at: DateTime.utc_now(),
        metadata: %{"source" => "ingress_benchmark"}
      })

    {:ok, _generation} = Cadence.Runtime.Missions.apply(runtime_spec)

    realized_contact =
      RealizedContact.new(%{
        realized_contact_id: ids.realized_contact_id,
        organization_id: ids.organization_id,
        mission_id: ids.mission_id,
        source_endpoint_refs: [ids.source_endpoint_id],
        contact_intents: [:telemetry_downlink],
        clock_mode: :live,
        initial_time: DateTime.utc_now(),
        paths: [
          Path.new(%{
            path_id: ids.path_id,
            direction: :downlink,
            selection_role: :selected,
            source_endpoint_ref: ids.source_endpoint_id,
            provider_bindings: [
              ProviderBinding.new(%{
                provider_binding_id: ids.provider_binding_id,
                adapter_key: :tcp_socket,
                configuration: %{
                  mode: :listen,
                  host: "0.0.0.0",
                  port: @listen_port,
                  ingress_protocol_family: :tm,
                  frame_size: frame_size,
                  ingress_metadata: %{frame_size: frame_size, ocf_length: 0, fecf: false}
                }
              })
            ]
          })
        ]
      })

    {:ok, _contact} =
      Cadence.Contacts.persist_realized_contact(ids.organization_id, realized_contact)

    {:ok, _runtime} =
      Cadence.Contacts.start_realized_contact(
        ids.organization_id,
        ids.mission_id,
        ids.realized_contact_id
      )

    wait_until!(
      fn ->
        case path_snapshot(ids) do
          {:ok, %{provider_runtimes: [%{port: @listen_port}]}} -> {:ok, :ready}
          _not_ready -> :retry
        end
      end,
      30_000,
      "provider did not become ready"
    )

    ids
  end

  defp await_receive!(ids, expected_bytes, deadline_ms) do
    initial = %{
      first_byte_at_ms: nil,
      last_heartbeat_at_ms: System.monotonic_time(:millisecond) - @heartbeat_ms,
      max_executor_queue_bytes: 0,
      max_executor_queue_depth: 0,
      max_projector_queue_depth: 0,
      max_journal_retained_bytes: 0,
      max_journal_processing_lag_bytes: 0,
      max_journal_archive_lag_bytes: 0,
      max_archive_pending_bytes: 0,
      max_journal_utilization: 0.0
    }

    do_await_receive(ids, expected_bytes, deadline_ms, initial)
  end

  defp do_await_receive(ids, expected_bytes, deadline_ms, observation) do
    now_ms = System.monotonic_time(:millisecond)

    if now_ms >= deadline_ms do
      raise "Cadence did not receive the planned byte count before the wall-clock fuse"
    end

    snapshot = path_snapshot!(ids)
    [provider] = snapshot.provider_runtimes
    executor = provider.ingress_executor
    projector = provider.ingress_persistence_projector

    observation = %{
      observation
      | first_byte_at_ms:
          observation.first_byte_at_ms ||
            if(provider.downlink_bytes_received > 0, do: now_ms, else: nil),
        max_executor_queue_bytes: max(observation.max_executor_queue_bytes, executor.queue_bytes),
        max_executor_queue_depth: max(observation.max_executor_queue_depth, executor.queue_depth),
        max_projector_queue_depth:
          max(observation.max_projector_queue_depth, projector.queue_depth),
        max_journal_retained_bytes:
          max(observation.max_journal_retained_bytes, provider.ingress_journal.retained_bytes),
        max_journal_processing_lag_bytes:
          max(
            observation.max_journal_processing_lag_bytes,
            provider.ingress_journal.lag_bytes.processing
          ),
        max_journal_archive_lag_bytes:
          max(
            observation.max_journal_archive_lag_bytes,
            provider.ingress_journal.lag_bytes.archive
          ),
        max_archive_pending_bytes:
          max(
            observation.max_archive_pending_bytes,
            provider.ingress_archive_consumer.pending_bytes
          ),
        max_journal_utilization:
          max(observation.max_journal_utilization, provider.ingress_journal.utilization_ratio)
    }

    observation = maybe_heartbeat(provider, observation, now_ms)

    if provider.downlink_bytes_received >= expected_bytes do
      completed_at_ms = now_ms
      active_duration_ms = completed_at_ms - observation.first_byte_at_ms

      {snapshot,
       observation
       |> Map.put(:completed_at_ms, completed_at_ms)
       |> Map.put(:active_duration_ms, active_duration_ms)
       |> Map.put(:observed_receive_bps, expected_bytes * 8 * 1_000 / max(active_duration_ms, 1))}
    else
      Process.sleep(@poll_ms)
      do_await_receive(ids, expected_bytes, deadline_ms, observation)
    end
  end

  defp maybe_heartbeat(provider, observation, now_ms) do
    if now_ms - observation.last_heartbeat_at_ms >= @heartbeat_ms do
      IO.puts(
        "CADENCE_INGRESS_HEARTBEAT " <>
          Jason.encode!(%{
            bytes_received: provider.downlink_bytes_received,
            messages_received: provider.downlink_message_count,
            executor_queue_bytes: provider.ingress_executor.queue_bytes,
            executor_queue_depth: provider.ingress_executor.queue_depth,
            executor_processed: provider.ingress_executor.processed_count,
            executor_failed: provider.ingress_executor.failed_count,
            projector_queue_depth: provider.ingress_persistence_projector.queue_depth,
            projector_persisted: provider.ingress_persistence_projector.persisted_count,
            journal_retained_bytes: provider.ingress_journal.retained_bytes,
            journal_processing_lag_bytes: provider.ingress_journal.lag_bytes.processing,
            journal_archive_lag_bytes: provider.ingress_journal.lag_bytes.archive,
            archive_pending_bytes: provider.ingress_archive_consumer.pending_bytes,
            archive_batches: provider.ingress_archive_consumer.batch_count,
            archive_failures: provider.ingress_archive_consumer.failed_count,
            journal_utilization: provider.ingress_journal.utilization_ratio,
            reads_paused: provider.reads_paused?
          })
      )

      %{observation | last_heartbeat_at_ms: now_ms}
    else
      observation
    end
  end

  defp await_drain!(ids, expected_bytes, expected_messages) do
    deadline_ms = System.monotonic_time(:millisecond) + @drain_timeout_ms

    wait_until!(
      fn ->
        snapshot = path_snapshot!(ids)
        [provider] = snapshot.provider_runtimes
        executor = provider.ingress_executor
        projector = provider.ingress_persistence_projector
        journal = provider.ingress_journal
        protocol_archive = EphemeralProtocolRecordArchive.snapshot()

        if executor.queue_depth == 0 and projector.queue_depth == 0 and
             journal.cursors.processing == expected_bytes and
             journal.cursors.archive == expected_bytes and
             protocol_archive.frame_count >= expected_messages do
          {:ok, {snapshot, System.monotonic_time(:millisecond)}}
        else
          :retry
        end
      end,
      deadline_ms - System.monotonic_time(:millisecond),
      "Cadence queues did not drain before the drain timeout"
    )
  end

  defp wait_until!(fun, timeout_ms, error_message) when is_function(fun, 0) do
    deadline_ms = System.monotonic_time(:millisecond) + max(timeout_ms, 0)
    do_wait_until!(fun, deadline_ms, error_message)
  end

  defp do_wait_until!(fun, deadline_ms, error_message) do
    case fun.() do
      {:ok, value} ->
        value

      :retry ->
        if System.monotonic_time(:millisecond) >= deadline_ms do
          raise error_message
        else
          Process.sleep(100)
          do_wait_until!(fun, deadline_ms, error_message)
        end
    end
  end

  defp path_snapshot!(ids) do
    {:ok, snapshot} = path_snapshot(ids)
    snapshot
  end

  defp path_snapshot(ids) do
    Cadence.path_runtime_snapshot(
      ids.organization_id,
      ids.mission_id,
      ids.realized_contact_id,
      ids.path_id
    )
  end

  defp provider_report(provider) do
    provider
    |> Map.take([
      :connected?,
      :downlink_bytes_received,
      :downlink_message_count,
      :tcp_read_count,
      :avg_tcp_read_bytes,
      :last_ingress_at,
      :last_ingress_error,
      :reads_paused?
    ])
    |> Map.put(:ingress_journal, provider.ingress_journal)
    |> Map.put(:ingress_journal_consumer, provider.ingress_journal_consumer)
    |> Map.put(:ingress_archive_consumer, provider.ingress_archive_consumer)
  end

  defp anomaly_count(mission_id) do
    ProtocolAnomalyRow
    |> where([row], row.mission_id == ^mission_id)
    |> Cadence.Repo.aggregate(:count, :anomaly_id)
  end

  defp write_result!(result) do
    File.mkdir_p!(Elixir.Path.dirname(@result_path))
    File.write!(@result_path, Jason.encode!(result, pretty: true))
  end
end
