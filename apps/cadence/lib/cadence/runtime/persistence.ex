defmodule Cadence.Runtime.Persistence do
  @moduledoc """
  Data-plane persistence boundary for runtime evidence and observations.
  """

  alias Ecto.Changeset
  alias Ecto.Multi

  alias Cadence.Contacts.{CombinedDownlinkRecord, DownlinkDiagnostic, DownlinkObservation}
  alias Cadence.Ingress.RawEvidence
  alias Cadence.IngressArchive
  alias Cadence.OperationalEvents
  alias Cadence.OperationalEvents.Event, as: OperationalEvent
  alias Cadence.Platform.ContentHash
  alias Cadence.Platform.EventBus
  alias Cadence.Protocol.RecordArchive
  alias Cadence.Repo
  alias Cadence.SemanticObservations
  alias Cadence.SemanticRuntime.Result

  alias Cadence.Runtime.{
    DownlinkRecords,
    DownlinkRecordsPersisted,
    Facts,
    ManagedRecords,
    ManagedRecordsPersisted,
    MissionRuntimeSpec,
    ProcessingResultsPersisted,
    TransportRecords,
    TransportRecordsPersisted
  }

  alias Cadence.Telemetry.{Sample, Storage}

  @type policy :: %{
          required(:ingress_archive) => IngressArchive.policy(),
          required(:record_archive) => RecordArchive.policy(),
          required(:telemetry_storage) => Storage.policy(),
          required(:event_bus) => EventBus.server()
        }

  @doc """
  Persists a processing result with current application configuration.

  This compatibility arity reads configuration when called. Supervised runtime
  workers use `persist_processing_result/3` with a startup-captured policy.
  """
  @spec persist_processing_result(map(), keyword()) :: {:ok, map()} | {:error, term()}
  def persist_processing_result(
        %{
          raw_evidence: %RawEvidence{},
          packet_records: _packet_records,
          transfer_frame_records: _transfer_frame_records,
          protocol_anomalies: _protocol_anomalies,
          outputs: _outputs
        } = processing_result,
        opts \\ []
      ) do
    persist_processing_result(configured_policy(), processing_result, opts)
  end

  @spec persist_processing_result(policy(), map(), keyword()) ::
          {:ok, map()} | {:error, term()}
  def persist_processing_result(
        %{} = policy,
        %{
          raw_evidence: %RawEvidence{},
          packet_records: _packet_records,
          transfer_frame_records: _transfer_frame_records,
          protocol_anomalies: _protocol_anomalies,
          outputs: _outputs
        } = processing_result,
        opts
      )
      when is_list(opts) do
    with :ok <- persist_processing_results(policy, [processing_result], opts) do
      {:ok, processing_result}
    end
  end

  @spec persist_processing_results([map()], keyword()) :: :ok | {:error, term()}
  def persist_processing_results(processing_results, opts \\ [])
      when is_list(processing_results) and is_list(opts) do
    persist_processing_results(configured_policy(), processing_results, opts)
  end

  @spec persist_processing_results(policy(), [map()], keyword()) :: :ok | {:error, term()}
  def persist_processing_results(%{} = policy, processing_results, opts)
      when is_list(processing_results) and is_list(opts) do
    with {:ok, prepared_results} <- prepare_processing_results(processing_results) do
      persist_prepared_processing_results(policy, prepared_results, opts,
        archive_raw_evidence?: true
      )
    end
  end

  @doc """
  Persists only semantic outputs for evidence already owned by a capture
  journal. The independent raw-archive consumer owns archive completion.
  """
  @spec persist_semantic_processing_results([map()], keyword()) :: :ok | {:error, term()}
  def persist_semantic_processing_results(processing_results, opts \\ [])
      when is_list(processing_results) and is_list(opts) do
    persist_semantic_processing_results(configured_policy(), processing_results, opts)
  end

  @spec persist_semantic_processing_results(policy(), [map()], keyword()) ::
          :ok | {:error, term()}
  def persist_semantic_processing_results(%{} = policy, processing_results, opts)
      when is_list(processing_results) and is_list(opts) do
    with {:ok, prepared_results} <- prepare_processing_results(processing_results) do
      persist_prepared_processing_results(policy, prepared_results, opts,
        archive_raw_evidence?: false
      )
    end
  end

  @spec telemetry_samples([term()]) :: {:ok, [Sample.t()]} | {:error, term()}
  def telemetry_samples(outputs) when is_list(outputs) do
    validate_outputs(outputs)
  end

  @spec persist_semantic_timer_result(MissionRuntimeSpec.t(), Result.t(), [Sample.t()], keyword()) ::
          :ok | {:error, term()}
  def persist_semantic_timer_result(
        %MissionRuntimeSpec{} = runtime_spec,
        %Result{} = result,
        samples,
        opts \\ []
      )
      when is_list(samples) and is_list(opts) do
    persist_semantic_timer_result(configured_policy(), runtime_spec, result, samples, opts)
  end

  @spec persist_semantic_timer_result(
          policy(),
          MissionRuntimeSpec.t(),
          Result.t(),
          [Sample.t()],
          keyword()
        ) :: :ok | {:error, term()}
  def persist_semantic_timer_result(
        %{} = policy,
        %MissionRuntimeSpec{} = runtime_spec,
        %Result{} = result,
        samples,
        opts
      )
      when is_list(samples) and is_list(opts) do
    at = Keyword.fetch!(opts, :at)
    timer_key = Keyword.fetch!(opts, :timer_key)

    evidence =
      RawEvidence.new(%{
        evidence_id: ContentHash.term_sha256({runtime_spec.runtime_basis_sha256, timer_key, at}),
        mission_id: runtime_spec.mission_id,
        source_ref: "semantic_timer:" <> timer_key,
        source_time: at,
        receipt_time: at,
        raw: <<>>
      })

    prepared = %{
      raw_evidence: evidence,
      telemetry_samples: samples,
      semantic_result: result,
      runtime_spec: runtime_spec
    }

    case Storage.persist_prepared_results(policy.telemetry_storage, [prepared], recorded_at: at) do
      :ok -> SemanticObservations.persist_many([prepared])
      {:error, reason} -> {:error, reason}
    end
  end

  @spec persist_managed_runtime_records(
          [ManagedCapabilityRecord.t()],
          [ManagedActionRequest.t()],
          [ManagedTimerEvent.t()]
        ) ::
          :ok | {:error, term()}
  def persist_managed_runtime_records(capability_records, action_requests, timer_events)
      when is_list(capability_records) and is_list(action_requests) and is_list(timer_events) do
    persist_managed_runtime_records(EventBus, capability_records, action_requests, timer_events)
  end

  @spec persist_managed_runtime_records(
          EventBus.server(),
          [ManagedCapabilityRecord.t()],
          [ManagedActionRequest.t()],
          [ManagedTimerEvent.t()]
        ) :: :ok | {:error, term()}
  def persist_managed_runtime_records(
        event_bus,
        capability_records,
        action_requests,
        timer_events
      )
      when is_list(capability_records) and is_list(action_requests) and is_list(timer_events) do
    Multi.new()
    |> add_managed_capability_record_inserts(capability_records)
    |> add_managed_action_request_inserts(action_requests)
    |> add_managed_timer_event_inserts(timer_events)
    |> Repo.transaction()
    |> case do
      {:ok, _changes} ->
        Facts.publish(event_bus, %ManagedRecordsPersisted{
          capability_records: capability_records,
          action_requests: action_requests,
          timer_events: timer_events,
          persisted_at: DateTime.utc_now()
        })

      {:error, _operation, %Changeset{} = changeset, _changes_so_far} ->
        {:error, changeset}

      {:error, _operation, reason, _changes_so_far} ->
        {:error, reason}
    end
  end

  @spec persist_transport_runtime_records(
          [TransportCapabilityRecord.t()],
          [TransportActionRequest.t()],
          [TransportTimerEvent.t()]
        ) ::
          :ok | {:error, term()}
  def persist_transport_runtime_records(capability_records, action_requests, timer_events)
      when is_list(capability_records) and is_list(action_requests) and is_list(timer_events) do
    persist_transport_runtime_records(EventBus, capability_records, action_requests, timer_events)
  end

  @spec persist_transport_runtime_records(
          EventBus.server(),
          [TransportCapabilityRecord.t()],
          [TransportActionRequest.t()],
          [TransportTimerEvent.t()]
        ) :: :ok | {:error, term()}
  def persist_transport_runtime_records(
        event_bus,
        capability_records,
        action_requests,
        timer_events
      )
      when is_list(capability_records) and is_list(action_requests) and is_list(timer_events) do
    Multi.new()
    |> add_transport_capability_record_inserts(capability_records)
    |> add_transport_action_request_inserts(action_requests)
    |> add_transport_timer_event_inserts(timer_events)
    |> Multi.run(:transport_capability_operational_events, fn repo, _changes ->
      capability_records
      |> Enum.map(&OperationalEvent.from_transport_capability_record/1)
      |> persist_operational_events(repo)
    end)
    |> Multi.run(:transport_action_operational_events, fn repo, _changes ->
      action_requests
      |> Enum.map(&OperationalEvent.from_transport_action_request/1)
      |> persist_operational_events(repo)
    end)
    |> Multi.run(:transport_timer_operational_events, fn repo, _changes ->
      timer_events
      |> Enum.map(&OperationalEvent.from_transport_timer_event/1)
      |> persist_operational_events(repo)
    end)
    |> Repo.transaction()
    |> case do
      {:ok, _changes} ->
        Facts.publish(event_bus, %TransportRecordsPersisted{
          capability_records: capability_records,
          action_requests: action_requests,
          timer_events: timer_events,
          persisted_at: DateTime.utc_now()
        })

      {:error, _operation, %Changeset{} = changeset, _changes_so_far} ->
        {:error, changeset}

      {:error, _operation, reason, _changes_so_far} ->
        {:error, reason}
    end
  end

  @spec persist_downlink_combiner_records(
          [DownlinkObservation.t()],
          [CombinedDownlinkRecord.t()],
          [DownlinkDiagnostic.t()]
        ) ::
          :ok | {:error, term()}
  def persist_downlink_combiner_records(observations, combined_records, diagnostics)
      when is_list(observations) and is_list(combined_records) and is_list(diagnostics) do
    persist_downlink_combiner_records(EventBus, observations, combined_records, diagnostics)
  end

  @spec persist_downlink_combiner_records(
          EventBus.server(),
          [DownlinkObservation.t()],
          [CombinedDownlinkRecord.t()],
          [DownlinkDiagnostic.t()]
        ) :: :ok | {:error, term()}
  def persist_downlink_combiner_records(event_bus, observations, combined_records, diagnostics)
      when is_list(observations) and is_list(combined_records) and is_list(diagnostics) do
    Multi.new()
    |> add_downlink_observation_inserts(observations)
    |> add_combined_downlink_record_inserts(combined_records)
    |> add_downlink_diagnostic_inserts(diagnostics)
    |> Repo.transaction()
    |> case do
      {:ok, _changes} ->
        Facts.publish(event_bus, %DownlinkRecordsPersisted{
          observations: observations,
          combined_records: combined_records,
          diagnostics: diagnostics,
          persisted_at: DateTime.utc_now()
        })

      {:error, _operation, %Changeset{} = changeset, _changes_so_far} ->
        {:error, changeset}

      {:error, _operation, reason, _changes_so_far} ->
        {:error, reason}
    end
  end

  defp validate_outputs(outputs) when is_list(outputs) do
    outputs
    |> Enum.reduce_while({:ok, []}, fn
      %Sample{} = sample, {:ok, acc} ->
        {:cont, {:ok, [sample | acc]}}

      output, _acc ->
        {:halt, {:error, {:unsupported_output, output}}}
    end)
    |> case do
      {:ok, samples} -> {:ok, Enum.reverse(samples)}
      {:error, reason} -> {:error, reason}
    end
  end

  defp add_managed_capability_record_inserts(%Multi{} = multi, capability_records) do
    ManagedRecords.add_capability_record_inserts(multi, capability_records)
  end

  defp add_managed_action_request_inserts(%Multi{} = multi, action_requests) do
    ManagedRecords.add_action_request_inserts(multi, action_requests)
  end

  defp add_managed_timer_event_inserts(%Multi{} = multi, timer_events) do
    ManagedRecords.add_timer_event_inserts(multi, timer_events)
  end

  defp add_transport_capability_record_inserts(%Multi{} = multi, capability_records) do
    TransportRecords.add_capability_record_inserts(multi, capability_records)
  end

  defp add_transport_action_request_inserts(%Multi{} = multi, action_requests) do
    TransportRecords.add_action_request_inserts(multi, action_requests)
  end

  defp add_transport_timer_event_inserts(%Multi{} = multi, timer_events) do
    TransportRecords.add_timer_event_inserts(multi, timer_events)
  end

  defp add_downlink_observation_inserts(%Multi{} = multi, observations) do
    DownlinkRecords.add_observation_inserts(multi, observations)
  end

  defp add_combined_downlink_record_inserts(%Multi{} = multi, combined_records) do
    DownlinkRecords.add_combined_record_inserts(multi, combined_records)
  end

  defp add_downlink_diagnostic_inserts(%Multi{} = multi, diagnostics) do
    DownlinkRecords.add_diagnostic_inserts(multi, diagnostics)
  end

  defp persist_operational_events(events, repo) when is_list(events) do
    Enum.reduce_while(events, {:ok, []}, fn %OperationalEvent{} = event, {:ok, acc} ->
      case OperationalEvents.persist_event(repo, event) do
        {:ok, %OperationalEvent{} = persisted_event} ->
          {:cont, {:ok, [persisted_event | acc]}}

        {:error, reason} ->
          {:halt, {:error, reason}}
      end
    end)
  end

  @doc false
  @spec policy(IngressArchive.policy(), RecordArchive.policy(), Storage.policy(), keyword()) ::
          policy()
  def policy(%{} = ingress_archive, %{} = record_archive, %{} = telemetry_storage, opts \\ [])
      when is_list(opts) do
    event_bus = Keyword.get(opts, :event_bus, Map.get(telemetry_storage, :event_bus, EventBus))

    %{
      ingress_archive: ingress_archive,
      record_archive: record_archive,
      telemetry_storage: Map.put(telemetry_storage, :event_bus, event_bus),
      event_bus: event_bus
    }
  end

  @doc false
  @spec configured_policy() :: policy()
  def configured_policy do
    policy(
      IngressArchive.configured_policy(),
      RecordArchive.configured_policy(),
      Storage.configured_policy()
    )
  end

  defp add_prepared_processing_result_inserts(policy, %Multi{} = multi, prepared_results)
       when is_list(prepared_results) do
    Enum.reduce(prepared_results, multi, fn prepared_result, acc ->
      multi =
        IngressArchive.persist_raw_evidence_multi(
          policy.ingress_archive,
          acc,
          prepared_result.raw_evidence
        )

      RecordArchive.persist_records_multi(
        policy.record_archive,
        multi,
        prepared_result.raw_evidence,
        prepared_result.transfer_frame_records,
        prepared_result.packet_records
      )
    end)
  end

  defp persist_prepared_processing_results(policy, prepared_results, opts,
         archive_raw_evidence?: archive?
       ) do
    with :ok <- persist_canonical_processing_results(policy, prepared_results),
         :ok <- maybe_archive_raw_evidence(policy.ingress_archive, prepared_results, archive?),
         :ok <-
           RecordArchive.persist_records_many(
             policy.record_archive,
             archive_records_batch(prepared_results)
           ),
         :ok <- Storage.persist_prepared_results(policy.telemetry_storage, prepared_results, opts),
         :ok <- SemanticObservations.persist_many(prepared_results) do
      publish_processing_results(policy.event_bus, prepared_results)
    end
  end

  defp maybe_archive_raw_evidence(_archive_policy, _prepared_results, false), do: :ok

  defp maybe_archive_raw_evidence(archive_policy, prepared_results, true) do
    IngressArchive.persist_raw_evidences(
      archive_policy,
      Enum.map(prepared_results, & &1.raw_evidence)
    )
  end

  defp prepare_processing_results(processing_results) do
    Enum.reduce_while(processing_results, {:ok, []}, fn
      %{
        raw_evidence: %RawEvidence{} = raw_evidence,
        packet_records: packet_records,
        transfer_frame_records: transfer_frame_records,
        protocol_anomalies: protocol_anomalies,
        outputs: outputs
      } = processing_result,
      {:ok, acc}
      when is_list(packet_records) and is_list(transfer_frame_records) and
             is_list(protocol_anomalies) and is_list(outputs) ->
        case telemetry_samples(outputs) do
          {:ok, telemetry_samples} ->
            {:cont,
             {:ok,
              [
                %{
                  raw_evidence: raw_evidence,
                  packet_records: packet_records,
                  transfer_frame_records: transfer_frame_records,
                  protocol_anomalies: protocol_anomalies,
                  telemetry_samples: telemetry_samples,
                  semantic_result: Map.get(processing_result, :semantic_result),
                  runtime_spec: Map.get(processing_result, :runtime_spec)
                }
                | acc
              ]}}

          {:error, reason} ->
            {:halt, {:error, reason}}
        end

      _other, {:ok, _acc} ->
        {:halt, {:error, :invalid_processing_results_batch}}
    end)
    |> case do
      {:ok, prepared_results} -> {:ok, Enum.reverse(prepared_results)}
      {:error, reason} -> {:error, reason}
    end
  end

  defp persist_canonical_processing_results(policy, prepared_results) do
    multi =
      Multi.new()
      |> then(&add_prepared_processing_result_inserts(policy, &1, prepared_results))
      |> RecordArchive.add_anomaly_inserts(protocol_anomalies_from_prepared(prepared_results))

    persist_non_empty_multi(multi)
  end

  defp persist_non_empty_multi(%Multi{} = multi) do
    case Multi.to_list(multi) do
      [] ->
        :ok

      _operations ->
        run_multi(multi)
    end
  end

  defp run_multi(%Multi{} = multi) do
    multi
    |> Repo.transaction()
    |> case do
      {:ok, _changes} ->
        :ok

      {:error, _operation, %Changeset{} = changeset, _changes_so_far} ->
        {:error, changeset}

      {:error, _operation, reason, _changes_so_far} ->
        {:error, reason}
    end
  end

  defp archive_records_batch(prepared_results) when is_list(prepared_results) do
    Enum.map(prepared_results, fn prepared ->
      {
        prepared.raw_evidence,
        prepared.transfer_frame_records,
        prepared.packet_records
      }
    end)
  end

  defp telemetry_samples_from_prepared(prepared_results) when is_list(prepared_results) do
    Enum.flat_map(prepared_results, & &1.telemetry_samples)
  end

  defp publish_processing_results(event_bus, prepared_results) do
    evidence_ids = Enum.map(prepared_results, & &1.raw_evidence.evidence_id)

    Facts.publish(event_bus, %ProcessingResultsPersisted{
      batch_id: ContentHash.term_sha256(evidence_ids),
      evidence_ids: evidence_ids,
      telemetry_samples: telemetry_samples_from_prepared(prepared_results),
      persisted_at: DateTime.utc_now()
    })
  end

  defp protocol_anomalies_from_prepared(prepared_results) when is_list(prepared_results) do
    Enum.flat_map(prepared_results, & &1.protocol_anomalies)
  end
end
