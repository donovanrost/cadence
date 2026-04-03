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
          raw_evidence: %RawEvidence{},
          packet_records: _packet_records,
          transfer_frame_records: _transfer_frame_records,
          protocol_anomalies: _protocol_anomalies,
          outputs: _outputs
        } = processing_result,
        opts \\ []
      ) do
    with :ok <- persist_processing_results([processing_result], opts) do
      {:ok, processing_result}
    end
  end

  @spec persist_processing_results([Cadence.processing_result()], keyword()) ::
          :ok | {:error, term()}
  def persist_processing_results(processing_results, opts \\ [])
      when is_list(processing_results) and is_list(opts) do
    with {:ok, prepared_results} <- prepare_processing_results(processing_results),
         telemetry_samples = telemetry_samples_from_prepared(prepared_results),
         :ok <- persist_canonical_processing_results(prepared_results),
         :ok <-
           Cadence.IngressArchive.persist_raw_evidences(
             Enum.map(prepared_results, & &1.raw_evidence)
           ),
         :ok <-
           RecordArchive.persist_records_many(archive_records_batch(prepared_results)),
         :ok <- maybe_record_current_values(telemetry_samples, opts),
         :ok <- Cadence.Telemetry.HistoryStore.persist_samples(telemetry_samples) do
      :ok
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

    maybe_insert_all(multi, :protocol_anomalies, ProtocolAnomalyRow, rows,
      on_conflict: :nothing,
      conflict_target: [:anomaly_id]
    )
  end

  defp maybe_insert_all(%Multi{} = multi, _operation, _schema, [], _opts), do: multi

  defp maybe_insert_all(%Multi{} = multi, operation, schema, rows, opts)
       when is_atom(operation) and is_list(rows) and is_list(opts) do
    Multi.run(multi, operation, fn repo, _changes ->
      count_matches? = Keyword.get(opts, :on_conflict) == :nothing

      case repo.insert_all(schema, rows, opts) do
        {count, _returned_rows} when count == length(rows) ->
          {:ok, count}

        {count, _returned_rows} ->
          if count_matches? do
            {:ok, count}
          else
            {:error, {:insert_all_count_mismatch, operation, count}}
          end
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

  defp add_prepared_processing_result_inserts(%Multi{} = multi, prepared_results)
       when is_list(prepared_results) do
    Enum.reduce(prepared_results, multi, fn prepared_result, acc ->
      acc
      |> Cadence.IngressArchive.persist_raw_evidence_multi(prepared_result.raw_evidence)
      |> RecordArchive.persist_records_multi(
        prepared_result.raw_evidence,
        prepared_result.transfer_frame_records,
        prepared_result.packet_records
      )
    end)
  end

  defp prepare_processing_results(processing_results) do
    Enum.reduce_while(processing_results, {:ok, []}, fn
      %{
        raw_evidence: %RawEvidence{} = raw_evidence,
        packet_records: packet_records,
        transfer_frame_records: transfer_frame_records,
        protocol_anomalies: protocol_anomalies,
        outputs: outputs
      },
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
                  telemetry_samples: telemetry_samples
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

  defp persist_canonical_processing_results(prepared_results) do
    Multi.new()
    |> add_prepared_processing_result_inserts(prepared_results)
    |> add_protocol_anomaly_inserts(protocol_anomalies_from_prepared(prepared_results))
    |> Multi.run(:command_verifier_evaluations, fn repo, _changes ->
      Cadence.Commanding.evaluate_command_verifiers(
        repo,
        telemetry_samples_from_prepared(prepared_results)
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

  defp protocol_anomalies_from_prepared(prepared_results) when is_list(prepared_results) do
    Enum.flat_map(prepared_results, & &1.protocol_anomalies)
  end
end
