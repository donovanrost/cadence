defmodule Cadence.Replay do
  @moduledoc """
  Replay services over persisted evidence and governed binding sets.
  """

  alias Ecto.Changeset
  alias Ecto.Multi

  alias Cadence.Activations.BindingSetActivation
  alias Cadence.ApplicationDispatch.{DispatchDecision, WorkItem}
  alias Cadence.Governance
  alias Cadence.Jobs

  alias Cadence.Persistence.Schemas.{
    ReplayDispatchDecisionRow,
    ReplayDispatchWorkItemRow,
    ReplayManagedActionRequestRow,
    ReplayManagedCapabilityRecordRow,
    ReplayManagedTimerEventRow,
    ReplayRunRow,
    ReplayTelemetrySampleRow
  }

  alias Cadence.Protocol.PacketRecord
  alias Cadence.Replay.Scope
  alias Cadence.Replay.Run
  alias Cadence.Repo
  alias Cadence.Runtime.{ManagedActionRequest, ManagedCapabilityRecord, ManagedTimerEvent}
  alias Cadence.Runtime.{PartitionKey, PartitionOwner}
  alias Cadence.Telemetry.Sample

  @spec replay_telemetry_evidence(binary(), binary() | [binary()], binary(), pos_integer()) ::
          {:ok, Run.t()} | {:error, term()}
  def replay_telemetry_evidence(mission_id, evidence_id, binding_set_id, version)
      when is_binary(mission_id) and is_binary(evidence_id) and is_binary(binding_set_id) and
             is_integer(version) and version > 0 do
    replay_telemetry_evidence(mission_id, [evidence_id], binding_set_id, version)
  end

  def replay_telemetry_evidence(mission_id, evidence_ids, binding_set_id, version)
      when is_binary(mission_id) and is_list(evidence_ids) and is_binary(binding_set_id) and
             is_integer(version) and version > 0 do
    replay_telemetry_scope(
      mission_id,
      Scope.new(%{evidence_ids: evidence_ids}),
      binding_set_id,
      version
    )
  end

  @spec replay_telemetry_scope(binary(), Scope.t(), binary(), pos_integer()) ::
          {:ok, Run.t()} | {:error, term()}
  def replay_telemetry_scope(mission_id, %Scope{} = scope, binding_set_id, version)
      when is_binary(mission_id) and is_binary(binding_set_id) and is_integer(version) and
             version > 0 do
    run = build_run(mission_id, scope, binding_set_id, version)

    with {:ok, persisted_run} <- insert_run(run) do
      execute_run(persisted_run, scope)
    end
  end

  @spec start_replay_telemetry_evidence(binary(), binary() | [binary()], binary(), pos_integer()) ::
          {:ok, Run.t()} | {:error, term()}
  def start_replay_telemetry_evidence(mission_id, evidence_id, binding_set_id, version)
      when is_binary(mission_id) and is_binary(evidence_id) and is_binary(binding_set_id) and
             is_integer(version) and version > 0 do
    start_replay_telemetry_evidence(mission_id, [evidence_id], binding_set_id, version)
  end

  def start_replay_telemetry_evidence(mission_id, evidence_ids, binding_set_id, version)
      when is_binary(mission_id) and is_list(evidence_ids) and is_binary(binding_set_id) and
             is_integer(version) and version > 0 do
    start_replay_telemetry_scope(
      mission_id,
      Scope.new(%{evidence_ids: evidence_ids}),
      binding_set_id,
      version
    )
  end

  @spec start_replay_telemetry_scope(binary(), Scope.t(), binary(), pos_integer()) ::
          {:ok, Run.t()} | {:error, term()}
  def start_replay_telemetry_scope(mission_id, %Scope{} = scope, binding_set_id, version)
      when is_binary(mission_id) and is_binary(binding_set_id) and is_integer(version) and
             version > 0 do
    run = build_run(mission_id, scope, binding_set_id, version)

    with {:ok, %Run{} = persisted_run} <- insert_run(run) do
      case Jobs.enqueue(
             :replay_telemetry_scope,
             mission_id,
             persisted_run.replay_run_id,
             %{"replay_run_id" => persisted_run.replay_run_id}
           ) do
        {:ok, _job} ->
          {:ok, persisted_run}

        {:error, reason} ->
          failed_run =
            %Run{
              persisted_run
              | status: :failed,
                failure_reason: {:job_enqueue_failed, reason},
                completed_at: DateTime.utc_now()
            }

          _ = update_run(failed_run)
          {:error, reason}
      end
    end
  end

  @doc false
  @spec execute_enqueued_run(binary()) :: {:ok, Run.t()} | {:error, term()}
  def execute_enqueued_run(replay_run_id) when is_binary(replay_run_id) do
    with {:ok, %Run{} = run} <- fetch_persisted_run(replay_run_id) do
      execute_run(run, scope_from_run(run))
    end
  end

  defp build_run(mission_id, %Scope{} = scope, binding_set_id, version) do
    Run.new(%{
      mission_id: mission_id,
      binding_set_id: binding_set_id,
      binding_set_version: version,
      metadata: %{"scope" => Scope.metadata(scope)}
    })
  end

  defp execute_run(%Run{} = run, %Scope{} = scope) do
    with {:ok, binding_set} <-
           Governance.fetch_binding_set(
             run.mission_id,
             run.binding_set_id,
             run.binding_set_version
           ),
         {:ok, raw_evidences} <- fetch_raw_evidences(run.mission_id, scope),
         {:ok, replay_result} <- process_raw_evidences(run, raw_evidences, binding_set) do
      completed_run =
        %Run{
          run
          | status: :completed,
            replayed_evidence_count: length(raw_evidences),
            replayed_packet_count: replay_packet_count(replay_result.processing_results),
            replayed_sample_count: replay_sample_count(replay_result.processing_results),
            completed_at: DateTime.utc_now()
        }

      persist_completed_run(completed_run, replay_result)
    else
      {:error, reason} ->
        failed_run =
          %Run{
            run
            | status: :failed,
              failure_reason: reason,
              completed_at: DateTime.utc_now()
          }

        _ = update_run(failed_run)
        {:error, reason}
    end
  rescue
    exception ->
      failed_run =
        %Run{
          run
          | status: :failed,
            failure_reason: {:exception, Exception.message(exception)},
            completed_at: DateTime.utc_now()
        }

      _ = update_run(failed_run)
      {:error, {:exception, exception}}
  catch
    kind, reason ->
      failed_run =
        %Run{
          run
          | status: :failed,
            failure_reason: {kind, reason},
            completed_at: DateTime.utc_now()
        }

      _ = update_run(failed_run)
      {:error, {kind, reason}}
  end

  defp fetch_raw_evidences(mission_id, %Scope{evidence_ids: evidence_ids} = scope)
       when is_list(evidence_ids) and evidence_ids != [] do
    Cadence.IngressArchive.fetch_raw_evidences(mission_id, scope)
  end

  defp fetch_raw_evidences(mission_id, %Scope{} = scope) do
    Cadence.IngressArchive.fetch_raw_evidences(mission_id, scope)
  end

  defp process_raw_evidences(%Run{} = run, raw_evidences, binding_set) do
    replay_activation = replay_activation(run)

    case process_replay_raw_evidences(
           raw_evidences,
           binding_set,
           replay_activation,
           %{},
           []
         ) do
      {:ok, processing_results, partition_owners} ->
        result =
          with {:ok, runtime_records} <- drain_replay_partition_owners(partition_owners) do
            {:ok,
             %{
               processing_results: Enum.reverse(processing_results),
               runtime_records: runtime_records
             }}
          end

        stop_replay_partition_owners(partition_owners)
        result

      {:error, reason, partition_owners} ->
        stop_replay_partition_owners(partition_owners)
        {:error, reason}
    end
  end

  defp persist_completed_run(%Run{} = run, replay_result) do
    Multi.new()
    |> Multi.run(:replay_run, fn repo, _changes ->
      repo_run_update(repo, run)
    end)
    |> add_replay_dispatch_decision_inserts(run.replay_run_id, replay_result.processing_results)
    |> add_replay_telemetry_sample_inserts(run.replay_run_id, replay_result.processing_results)
    |> add_replay_managed_capability_record_inserts(
      run.replay_run_id,
      replay_result.runtime_records.capability_records
    )
    |> add_replay_managed_action_request_inserts(
      run.replay_run_id,
      replay_result.runtime_records.action_requests
    )
    |> add_replay_managed_timer_event_inserts(
      run.replay_run_id,
      replay_result.runtime_records.timer_events
    )
    |> Repo.transaction()
    |> case do
      {:ok, _changes} ->
        {:ok, run}

      {:error, _operation, %Changeset{} = changeset, _changes_so_far} ->
        {:error, changeset}

      {:error, _operation, reason, _changes_so_far} ->
        {:error, reason}
    end
  end

  defp insert_run(%Run{} = run) do
    case Repo.insert(ReplayRunRow.changeset(run)) do
      {:ok, %ReplayRunRow{} = replay_run_row} -> {:ok, ReplayRunRow.to_domain(replay_run_row)}
      {:error, %Changeset{} = changeset} -> {:error, changeset}
      {:error, reason} -> {:error, reason}
    end
  end

  defp update_run(%Run{} = run) do
    case repo_run_update(Repo, run) do
      {:ok, %ReplayRunRow{} = replay_run_row} -> {:ok, ReplayRunRow.to_domain(replay_run_row)}
      {:error, %Changeset{} = changeset} -> {:error, changeset}
      {:error, reason} -> {:error, reason}
    end
  end

  defp fetch_persisted_run(replay_run_id) do
    case Repo.get(ReplayRunRow, replay_run_id) do
      nil -> {:error, :replay_run_not_found}
      %ReplayRunRow{} = replay_run_row -> {:ok, ReplayRunRow.to_domain(replay_run_row)}
    end
  end

  defp scope_from_run(%Run{metadata: metadata}) when is_map(metadata) do
    metadata
    |> Map.get("scope", Map.get(metadata, :scope, %{}))
    |> Scope.from_metadata()
  end

  defp repo_run_update(repo, %Run{} = run) do
    case repo.get(ReplayRunRow, run.replay_run_id) do
      nil -> {:error, :replay_run_not_found}
      %ReplayRunRow{} = replay_run_row -> repo.update(ReplayRunRow.changeset(replay_run_row, run))
    end
  end

  defp add_replay_dispatch_decision_inserts(%Multi{} = multi, replay_run_id, replay_results) do
    replay_results
    |> Enum.flat_map(&processing_result_packet_decision_pairs/1)
    |> Enum.reduce(multi, fn {packet_record, dispatch_decision}, %Multi{} = acc ->
      acc
      |> Multi.insert(
        {:replay_dispatch_decision, dispatch_decision.dispatch_decision_id},
        ReplayDispatchDecisionRow.changeset(replay_run_id, packet_record, dispatch_decision)
      )
      |> add_replay_dispatch_work_item_inserts(dispatch_decision)
    end)
  end

  defp add_replay_dispatch_work_item_inserts(
         %Multi{} = multi,
         %DispatchDecision{} = dispatch_decision
       ) do
    Enum.reduce(dispatch_decision.work_items, multi, fn %WorkItem{} = work_item, %Multi{} = acc ->
      Multi.insert(
        acc,
        {:replay_dispatch_work_item, dispatch_decision.dispatch_decision_id,
         work_item.binding_rule_id},
        ReplayDispatchWorkItemRow.changeset(dispatch_decision.dispatch_decision_id, work_item)
      )
    end)
  end

  defp add_replay_telemetry_sample_inserts(%Multi{} = multi, replay_run_id, replay_results) do
    replay_results
    |> Enum.flat_map(fn %{outputs: outputs} -> outputs end)
    |> Enum.reduce(multi, fn
      %Sample{} = sample, %Multi{} = acc ->
        Multi.insert(
          acc,
          {:replay_telemetry_sample, sample.sample_id},
          ReplayTelemetrySampleRow.changeset(replay_run_id, sample)
        )

      output, _acc ->
        raise ArgumentError, "unsupported replay output: #{inspect(output)}"
    end)
  end

  defp add_replay_managed_capability_record_inserts(%Multi{} = multi, replay_run_id, records) do
    Enum.reduce(records, multi, fn %ManagedCapabilityRecord{} = record, %Multi{} = acc ->
      Multi.insert(
        acc,
        {:replay_managed_capability_record, record.capability_record_id},
        ReplayManagedCapabilityRecordRow.changeset(replay_run_id, record)
      )
    end)
  end

  defp add_replay_managed_action_request_inserts(%Multi{} = multi, replay_run_id, requests) do
    Enum.reduce(requests, multi, fn %ManagedActionRequest{} = request, %Multi{} = acc ->
      Multi.insert(
        acc,
        {:replay_managed_action_request, request.action_request_id},
        ReplayManagedActionRequestRow.changeset(replay_run_id, request)
      )
    end)
  end

  defp add_replay_managed_timer_event_inserts(%Multi{} = multi, replay_run_id, timer_events) do
    Enum.reduce(timer_events, multi, fn %ManagedTimerEvent{} = timer_event, %Multi{} = acc ->
      Multi.insert(
        acc,
        {:replay_managed_timer_event, timer_event.timer_event_id},
        ReplayManagedTimerEventRow.changeset(replay_run_id, timer_event)
      )
    end)
  end

  defp replay_sample_count(replay_results) do
    Enum.reduce(replay_results, 0, fn %{outputs: outputs}, acc ->
      acc + Enum.count(outputs, &match?(%Sample{}, &1))
    end)
  end

  defp replay_packet_count(replay_results) do
    Enum.reduce(replay_results, 0, fn processing_result, acc ->
      acc + length(processing_result_packet_records(processing_result))
    end)
  end

  defp replay_activation(%Run{} = run) do
    BindingSetActivation.new(%{
      activation_id: run.replay_run_id <> ":replay",
      mission_id: run.mission_id,
      binding_set_id: run.binding_set_id,
      binding_set_version: run.binding_set_version,
      activated_at: run.started_at,
      metadata: %{"replay" => true, "replay_run_id" => run.replay_run_id}
    })
  end

  defp process_replay_raw_evidences([], _binding_set, _activation, partition_owners, acc) do
    {:ok, acc, partition_owners}
  end

  defp process_replay_raw_evidences(
         [raw_evidence | remaining_raw_evidences],
         binding_set,
         %BindingSetActivation{} = activation,
         partition_owners,
         acc
       ) do
    partition_key = PartitionKey.from_raw_evidence(raw_evidence)

    case ensure_replay_partition_owner(
           partition_owners,
           partition_key,
           activation,
           binding_set,
           raw_evidence
         ) do
      {:ok, partition_owner, next_partition_owners} ->
        case PartitionOwner.process_raw_evidence(partition_owner, raw_evidence) do
          {:ok, processing_result} ->
            process_replay_raw_evidences(
              remaining_raw_evidences,
              binding_set,
              activation,
              next_partition_owners,
              [processing_result | acc]
            )

          {:error, reason} ->
            {:error, {raw_evidence.evidence_id, reason}, next_partition_owners}
        end

      {:error, reason} ->
        {:error, {raw_evidence.evidence_id, reason}, partition_owners}
    end
  end

  defp ensure_replay_partition_owner(
         partition_owners,
         %PartitionKey{} = partition_key,
         %BindingSetActivation{} = activation,
         binding_set,
         raw_evidence
       ) do
    case Map.fetch(partition_owners, partition_key) do
      {:ok, partition_owner} ->
        {:ok, partition_owner, partition_owners}

      :error ->
        case PartitionOwner.start_link(
               mission_id: activation.mission_id,
               partition_key: partition_key,
               active_activation: activation,
               binding_set: binding_set,
               register?: false,
               persist_runtime_records?: false,
               clock_mode: :replay,
               initial_time: replay_time_for_raw_evidence(raw_evidence)
             ) do
          {:ok, partition_owner} ->
            {:ok, partition_owner, Map.put(partition_owners, partition_key, partition_owner)}

          {:error, reason} ->
            {:error, reason}
        end
    end
  end

  defp drain_replay_partition_owners(partition_owners) do
    Enum.reduce_while(partition_owners, {:ok, empty_runtime_records()}, fn
      {_partition_key, partition_owner}, {:ok, runtime_records} ->
        case PartitionOwner.drain_runtime_records(partition_owner) do
          {:ok, partition_runtime_records} ->
            {:cont, {:ok, merge_runtime_records(runtime_records, partition_runtime_records)}}

          {:error, reason} ->
            {:halt, {:error, reason}}
        end
    end)
  end

  defp stop_replay_partition_owners(partition_owners) do
    Enum.each(partition_owners, fn
      {_partition_key, partition_owner} when is_pid(partition_owner) ->
        if Process.alive?(partition_owner) do
          PartitionOwner.stop(partition_owner)
        end
    end)
  end

  defp empty_runtime_records do
    %{
      capability_records: [],
      action_requests: [],
      timer_events: []
    }
  end

  defp merge_runtime_records(left, right) do
    %{
      capability_records: left.capability_records ++ right.capability_records,
      action_requests: left.action_requests ++ right.action_requests,
      timer_events: left.timer_events ++ right.timer_events
    }
  end

  defp replay_time_for_raw_evidence(raw_evidence) do
    raw_evidence.source_time || raw_evidence.receipt_time
  end

  defp processing_result_packet_records(%{packet_records: packet_records})
       when is_list(packet_records),
       do: packet_records

  defp processing_result_packet_records(_processing_result), do: []

  defp processing_result_dispatch_decisions(%{dispatch_decisions: dispatch_decisions})
       when is_list(dispatch_decisions),
       do: dispatch_decisions

  defp processing_result_dispatch_decisions(_processing_result), do: []

  defp processing_result_packet_decision_pairs(processing_result) do
    packet_records = processing_result_packet_records(processing_result)

    dispatch_decisions =
      processing_result
      |> processing_result_dispatch_decisions()
      |> Map.new(fn %DispatchDecision{} = dispatch_decision ->
        {dispatch_decision.packet_id, dispatch_decision}
      end)

    Enum.flat_map(packet_records, fn %PacketRecord{} = packet_record ->
      case Map.fetch(dispatch_decisions, packet_record.packet_id) do
        {:ok, %DispatchDecision{} = dispatch_decision} ->
          [{packet_record, dispatch_decision}]

        :error ->
          []
      end
    end)
  end
end
