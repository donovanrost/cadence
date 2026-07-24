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
  alias Cadence.Persistence.OrganizationScope
  alias Cadence.Platform.ContentHash
  alias Cadence.Protocol.RecordArchive
  alias Cadence.Repo

  alias Cadence.Runtime.{
    DownlinkRecords,
    DownlinkRecordsPersisted,
    Facts,
    ManagedRecords,
    ManagedRecordsPersisted,
    ProcessingResultsPersisted,
    TransportRecords,
    TransportRecordsPersisted
  }

  alias Cadence.Telemetry.{Sample, Storage}

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
    with :ok <- persist_processing_results([processing_result], opts) do
      {:ok, processing_result}
    end
  end

  @spec persist_processing_results([map()], keyword()) :: :ok | {:error, term()}
  def persist_processing_results(processing_results, opts \\ [])
      when is_list(processing_results) and is_list(opts) do
    with {:ok, prepared_results} <- prepare_processing_results(processing_results),
         :ok <- persist_canonical_processing_results(prepared_results),
         :ok <-
           IngressArchive.persist_raw_evidences(Enum.map(prepared_results, & &1.raw_evidence)),
         :ok <- RecordArchive.persist_records_many(archive_records_batch(prepared_results)),
         :ok <- Storage.persist_prepared_results(prepared_results, opts) do
      publish_processing_results(prepared_results)
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
    Multi.new()
    |> add_managed_capability_record_inserts(capability_records)
    |> add_managed_action_request_inserts(action_requests)
    |> add_managed_timer_event_inserts(timer_events)
    |> Repo.transaction()
    |> case do
      {:ok, _changes} ->
        Facts.publish(%ManagedRecordsPersisted{
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
        Facts.publish(%TransportRecordsPersisted{
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
    Multi.new()
    |> add_downlink_observation_inserts(observations)
    |> add_combined_downlink_record_inserts(combined_records)
    |> add_downlink_diagnostic_inserts(diagnostics)
    |> Repo.transaction()
    |> case do
      {:ok, _changes} ->
        Facts.publish(%DownlinkRecordsPersisted{
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
      } = processing_result,
      {:ok, acc}
      when is_list(packet_records) and is_list(transfer_frame_records) and
             is_list(protocol_anomalies) and is_list(outputs) ->
        case telemetry_samples(outputs) do
          {:ok, telemetry_samples} ->
            ingress_latency_metric = Map.get(processing_result, :ingress_latency_metric)

            {:cont,
             {:ok,
              [
                %{
                  raw_evidence: raw_evidence,
                  packet_records: packet_records,
                  transfer_frame_records: transfer_frame_records,
                  protocol_anomalies: protocol_anomalies,
                  telemetry_samples: telemetry_samples,
                  ingress_latency_metric: ingress_latency_metric
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
    |> RecordArchive.add_anomaly_inserts(protocol_anomalies_from_prepared(prepared_results))
    |> Multi.run(:ingress_latency_operational_events, fn repo, _changes ->
      prepared_results
      |> ingress_latency_operational_events()
      |> persist_operational_events(repo)
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

  defp publish_processing_results(prepared_results) do
    evidence_ids = Enum.map(prepared_results, & &1.raw_evidence.evidence_id)

    Facts.publish(%ProcessingResultsPersisted{
      batch_id: ContentHash.term_sha256(evidence_ids),
      evidence_ids: evidence_ids,
      telemetry_samples: telemetry_samples_from_prepared(prepared_results),
      persisted_at: DateTime.utc_now()
    })
  end

  defp protocol_anomalies_from_prepared(prepared_results) when is_list(prepared_results) do
    Enum.flat_map(prepared_results, & &1.protocol_anomalies)
  end

  defp ingress_latency_operational_events(prepared_results) when is_list(prepared_results) do
    prepared_results
    |> Enum.flat_map(&ingress_latency_operational_event/1)
  end

  defp ingress_latency_operational_event(%{
         raw_evidence: %RawEvidence{} = raw_evidence,
         ingress_latency_metric: %{value_ms: value_ms} = metric
       })
       when is_number(value_ms) do
    [
      OperationalEvent.from_operational_observable_metric_sample(%{
        sample_id: ingress_latency_sample_id(raw_evidence),
        organization_id: OrganizationScope.organization_id_for_mission(raw_evidence.mission_id),
        mission_id: raw_evidence.mission_id,
        observable_id: "ingress.processing_latency_ms",
        resource_id: ingress_latency_resource_id(raw_evidence),
        scope_kind: ingress_latency_scope_kind(raw_evidence),
        spacecraft_id: raw_evidence.spacecraft_id,
        source_endpoint_id: raw_evidence.source_endpoint_ref || raw_evidence.source_ref,
        contact_id: ingress_latency_contact_id(raw_evidence),
        scheduled_contact_id: ingress_latency_scheduled_contact_id(raw_evidence),
        realized_contact_id: ingress_latency_realized_contact_id(raw_evidence),
        value: value_ms,
        unit: "ms",
        observed_at: Map.get(metric, :observed_at) || raw_evidence.receipt_time,
        metadata: ingress_latency_metadata(raw_evidence, metric)
      })
    ]
  end

  defp ingress_latency_operational_event(_prepared_result), do: []

  defp ingress_latency_sample_id(%RawEvidence{} = raw_evidence) do
    raw_evidence.evidence_id <> ":ingress_processing_latency"
  end

  defp ingress_latency_resource_id(%RawEvidence{} = raw_evidence) do
    raw_evidence.source_endpoint_ref ||
      raw_evidence.source_ref ||
      raw_evidence.spacecraft_id ||
      raw_evidence.mission_id
  end

  defp ingress_latency_scope_kind(%RawEvidence{source_endpoint_ref: source_endpoint_ref})
       when is_binary(source_endpoint_ref) and source_endpoint_ref != "",
       do: :source_endpoint

  defp ingress_latency_scope_kind(%RawEvidence{source_ref: source_ref})
       when is_binary(source_ref) and source_ref != "",
       do: :source_endpoint

  defp ingress_latency_scope_kind(%RawEvidence{spacecraft_id: spacecraft_id})
       when is_binary(spacecraft_id) and spacecraft_id != "",
       do: :spacecraft

  defp ingress_latency_scope_kind(%RawEvidence{}), do: :mission

  defp ingress_latency_contact_id(%RawEvidence{} = raw_evidence) do
    ingress_latency_metadata_value(raw_evidence, :contact_id) ||
      ingress_latency_scheduled_contact_id(raw_evidence) ||
      ingress_latency_realized_contact_id(raw_evidence)
  end

  defp ingress_latency_scheduled_contact_id(%RawEvidence{} = raw_evidence) do
    ingress_latency_metadata_value(raw_evidence, :scheduled_contact_id)
  end

  defp ingress_latency_realized_contact_id(%RawEvidence{} = raw_evidence) do
    ingress_latency_metadata_value(raw_evidence, :realized_contact_id)
  end

  defp ingress_latency_metadata_value(%RawEvidence{metadata: metadata}, key)
       when is_map(metadata) do
    Map.get(metadata, key) || Map.get(metadata, Atom.to_string(key))
  end

  defp ingress_latency_metadata_value(%RawEvidence{}, _key), do: nil

  defp ingress_latency_metadata(%RawEvidence{} = raw_evidence, metric) do
    %{
      evidence_id: raw_evidence.evidence_id,
      source_endpoint_ref: raw_evidence.source_endpoint_ref,
      source_ref: raw_evidence.source_ref,
      contact_id: ingress_latency_contact_id(raw_evidence),
      scheduled_contact_id: ingress_latency_scheduled_contact_id(raw_evidence),
      realized_contact_id: ingress_latency_realized_contact_id(raw_evidence),
      protocol_family: raw_evidence.protocol_family,
      direction: raw_evidence.direction,
      error?: Map.get(metric, :error?, false),
      end_to_end_us: Map.get(metric, :end_to_end_us)
    }
    |> Enum.reject(fn {_key, value} -> is_nil(value) end)
    |> Map.new()
  end
end
