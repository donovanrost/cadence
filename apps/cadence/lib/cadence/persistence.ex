defmodule Cadence.Persistence do
  @moduledoc """
  Persistence boundary for the first Cadence telemetry slice.
  """

  alias Ecto.Changeset
  alias Ecto.Multi

  alias Cadence.Contacts.{CombinedDownlinkRecord, DownlinkDiagnostic, DownlinkObservation}
  alias Cadence.Ingress.RawEvidence
  alias Cadence.Projections.MissionEvents, as: MissionEventProjection

  alias Cadence.Protocol.{RecordArchive, ProtocolAnomaly}

  alias Cadence.Repo

  alias Cadence.Runtime.{
    ManagedActionRequest,
    ManagedCapabilityRecord,
    ManagedTimerEvent,
    TransportActionRequest,
    TransportCapabilityRecord,
    TransportTimerEvent
  }

  alias Cadence.Telemetry.Sample

  alias Cadence.Persistence.Schemas.{
    CombinedDownlinkRecordRow,
    DownlinkDiagnosticRow,
    DownlinkObservationRow,
    ManagedActionRequestRow,
    ManagedCapabilityRecordRow,
    ManagedTimerEventRow,
    ProtocolAnomalyRow,
    TransportActionRequestRow,
    TransportCapabilityRecordRow,
    TransportTimerEventRow
  }

  @spec persist_processing_result(Cadence.processing_result(), keyword()) ::
          {:ok, Cadence.processing_result()} | {:error, term()}
  def persist_processing_result(
        %{
          raw_evidence: %RawEvidence{} = raw_evidence,
          packet_records: packet_records,
          transfer_frame_records: transfer_frame_records,
          protocol_anomalies: protocol_anomalies,
          outputs: outputs
        } = processing_result,
        opts \\ []
      ) do
    with {:ok, telemetry_samples} <- telemetry_samples(outputs) do
      case persist_canonical_processing_result(
             raw_evidence,
             transfer_frame_records,
             protocol_anomalies,
             packet_records,
             telemetry_samples
           ) do
        {:ok, _changes} ->
          with :ok <- Cadence.IngressArchive.persist_raw_evidence(raw_evidence),
               :ok <-
                 RecordArchive.persist_records(
                   raw_evidence,
                   transfer_frame_records,
                   packet_records
                 ),
               :ok <- maybe_record_current_values(telemetry_samples, opts),
               :ok <- Cadence.Telemetry.HistoryStore.persist_samples(telemetry_samples) do
            {:ok, processing_result}
          end

        {:error, _operation, %Changeset{} = changeset, _changes_so_far} ->
          {:error, changeset}

        {:error, _operation, reason, _changes_so_far} ->
          {:error, reason}
      end
    end
  end

  @spec telemetry_samples([term()]) :: {:ok, [Sample.t()]} | {:error, term()}
  def telemetry_samples(outputs) when is_list(outputs) do
    validate_outputs(outputs)
  end

  @spec persist_managed_runtime_records(
          [ManagedCapabilityRecord.t()],
          [ManagedActionRequest.t()],
          [ManagedTimerEvent.t()]
        ) ::
          :ok | {:error, term()}
  def persist_managed_runtime_records(capability_records, action_requests, timer_events)
      when is_list(capability_records) and is_list(action_requests) and is_list(timer_events) do
    projected_events = MissionEventProjection.project_many(action_requests)

    Multi.new()
    |> add_managed_capability_record_inserts(capability_records)
    |> add_managed_action_request_inserts(action_requests)
    |> add_managed_timer_event_inserts(timer_events)
    |> Multi.run(:mission_events, fn repo, _changes ->
      MissionEventProjection.persist_entries(repo, projected_events)
    end)
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

  @spec persist_transport_runtime_records(
          [TransportCapabilityRecord.t()],
          [TransportActionRequest.t()],
          [TransportTimerEvent.t()]
        ) ::
          :ok | {:error, term()}
  def persist_transport_runtime_records(capability_records, action_requests, timer_events)
      when is_list(capability_records) and is_list(action_requests) and is_list(timer_events) do
    Multi.new()
    |> add_transport_capability_record_inserts(capability_records)
    |> add_transport_action_request_inserts(action_requests)
    |> add_transport_timer_event_inserts(timer_events)
    |> Multi.run(:command_verifier_evaluations, fn repo, _changes ->
      Cadence.Commanding.evaluate_transport_command_verifiers(
        repo,
        capability_records,
        action_requests
      )
    end)
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

  @spec persist_downlink_combiner_records(
          [DownlinkObservation.t()],
          [CombinedDownlinkRecord.t()],
          [DownlinkDiagnostic.t()]
        ) ::
          :ok | {:error, term()}
  def persist_downlink_combiner_records(observations, combined_records, diagnostics)
      when is_list(observations) and is_list(combined_records) and is_list(diagnostics) do
    projected_events = MissionEventProjection.project_many(combined_records ++ diagnostics)

    Multi.new()
    |> add_downlink_observation_inserts(observations)
    |> add_combined_downlink_record_inserts(combined_records)
    |> add_downlink_diagnostic_inserts(diagnostics)
    |> Multi.run(:mission_events, fn repo, _changes ->
      MissionEventProjection.persist_entries(repo, projected_events)
    end)
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

  defp maybe_record_current_values(telemetry_samples, opts) when is_list(opts) do
    if Keyword.get(opts, :record_current_values?, true) do
      Cadence.Telemetry.CurrentValueStore.record_samples(telemetry_samples)
    else
      :ok
    end
  end

  defp add_protocol_anomaly_inserts(%Multi{} = multi, protocol_anomalies)
       when is_list(protocol_anomalies) do
    inserted_at = DateTime.utc_now()

    organization_id =
      case protocol_anomalies do
        [%ProtocolAnomaly{mission_id: mission_id} | _rest] ->
          Cadence.Persistence.OrganizationScope.organization_id_for_mission(mission_id)

        _other ->
          nil
      end

    rows =
      Enum.map(protocol_anomalies, fn %ProtocolAnomaly{} = protocol_anomaly ->
        ProtocolAnomalyRow.row_attrs(
          protocol_anomaly,
          organization_id: organization_id,
          inserted_at: inserted_at
        )
      end)

    maybe_insert_all(multi, :protocol_anomalies, ProtocolAnomalyRow, rows)
  end

  defp maybe_insert_all(%Multi{} = multi, _operation, _schema, []), do: multi

  defp maybe_insert_all(%Multi{} = multi, operation, schema, rows)
       when is_atom(operation) and is_list(rows) do
    Multi.run(multi, operation, fn repo, _changes ->
      case repo.insert_all(schema, rows) do
        {count, _returned_rows} when count == length(rows) -> {:ok, count}
        {count, _returned_rows} -> {:error, {:insert_all_count_mismatch, operation, count}}
      end
    end)
  end

  defp add_managed_capability_record_inserts(%Multi{} = multi, capability_records) do
    Enum.reduce(capability_records, multi, fn %ManagedCapabilityRecord{} = capability_record,
                                              %Multi{} = acc ->
      Multi.insert(
        acc,
        {:managed_capability_record, capability_record.capability_record_id},
        ManagedCapabilityRecordRow.changeset(capability_record)
      )
    end)
  end

  defp add_managed_action_request_inserts(%Multi{} = multi, action_requests) do
    Enum.reduce(action_requests, multi, fn %ManagedActionRequest{} = action_request,
                                           %Multi{} = acc ->
      Multi.insert(
        acc,
        {:managed_action_request, action_request.action_request_id},
        ManagedActionRequestRow.changeset(action_request)
      )
    end)
  end

  defp add_managed_timer_event_inserts(%Multi{} = multi, timer_events) do
    Enum.reduce(timer_events, multi, fn %ManagedTimerEvent{} = timer_event, %Multi{} = acc ->
      Multi.insert(
        acc,
        {:managed_timer_event, timer_event.timer_event_id},
        ManagedTimerEventRow.changeset(timer_event)
      )
    end)
  end

  defp add_transport_capability_record_inserts(%Multi{} = multi, capability_records) do
    Enum.reduce(capability_records, multi, fn %TransportCapabilityRecord{} = capability_record,
                                              %Multi{} = acc ->
      Multi.insert(
        acc,
        {:transport_capability_record, capability_record.transport_record_id},
        TransportCapabilityRecordRow.changeset(capability_record)
      )
    end)
  end

  defp add_transport_action_request_inserts(%Multi{} = multi, action_requests) do
    Enum.reduce(action_requests, multi, fn %TransportActionRequest{} = action_request,
                                           %Multi{} = acc ->
      Multi.insert(
        acc,
        {:transport_action_request, action_request.action_request_id},
        TransportActionRequestRow.changeset(action_request)
      )
    end)
  end

  defp add_transport_timer_event_inserts(%Multi{} = multi, timer_events) do
    Enum.reduce(timer_events, multi, fn %TransportTimerEvent{} = timer_event, %Multi{} = acc ->
      Multi.insert(
        acc,
        {:transport_timer_event, timer_event.timer_event_id},
        TransportTimerEventRow.changeset(timer_event)
      )
    end)
  end

  defp add_downlink_observation_inserts(%Multi{} = multi, observations) do
    Enum.reduce(observations, multi, fn %DownlinkObservation{} = observation, %Multi{} = acc ->
      Multi.insert(
        acc,
        {:downlink_observation, observation.observation_id},
        DownlinkObservationRow.changeset(observation)
      )
    end)
  end

  defp add_combined_downlink_record_inserts(%Multi{} = multi, combined_records) do
    Enum.reduce(combined_records, multi, fn %CombinedDownlinkRecord{} = combined_record,
                                            %Multi{} = acc ->
      Multi.insert(
        acc,
        {:combined_downlink_record, combined_record.merged_record_id},
        CombinedDownlinkRecordRow.changeset(combined_record)
      )
    end)
  end

  defp add_downlink_diagnostic_inserts(%Multi{} = multi, diagnostics) do
    Enum.reduce(diagnostics, multi, fn %DownlinkDiagnostic{} = diagnostic, %Multi{} = acc ->
      Multi.insert(
        acc,
        {:downlink_diagnostic, diagnostic.diagnostic_id},
        DownlinkDiagnosticRow.changeset(diagnostic)
      )
    end)
  end

  defp persist_canonical_processing_result(
         raw_evidence,
         transfer_frame_records,
         protocol_anomalies,
         packet_records,
         telemetry_samples
       ) do
    Multi.new()
    |> Cadence.IngressArchive.persist_raw_evidence_multi(raw_evidence)
    |> RecordArchive.persist_records_multi(raw_evidence, transfer_frame_records, packet_records)
    |> add_protocol_anomaly_inserts(protocol_anomalies)
    |> Multi.run(:command_verifier_evaluations, fn repo, _changes ->
      Cadence.Commanding.evaluate_command_verifiers(repo, telemetry_samples)
    end)
    |> Repo.transaction()
  end
end
