defmodule Cadence.Replay do
  @moduledoc """
  Replay services over persisted evidence and governed binding sets.
  """

  alias Ecto.Changeset
  alias Ecto.Multi

  alias Cadence.ApplicationDispatch.{DispatchDecision, WorkItem}
  alias Cadence.Governance
  alias Cadence.Jobs
  alias Cadence.OperationalEvents
  alias Cadence.OperationalEvents.Event, as: OperationalEvent

  alias Cadence.Control.Replay.Store.{
    ReplayDispatchDecisionRow,
    ReplayDispatchWorkItemRow,
    ReplayManagedActionRequestRow,
    ReplayManagedCapabilityRecordRow,
    ReplayManagedTimerEventRow,
    ReplayRunRow,
    ReplayTelemetrySampleRow
  }

  alias Cadence.Protocol.PacketRecord
  alias Cadence.Replay.Run
  alias Cadence.Replay.Scope
  alias Cadence.Repo

  alias Cadence.Runtime.{
    ManagedActionRequest,
    ManagedCapabilityRecord,
    ManagedTimerEvent,
    MissionRuntimeSpec,
    ReplaySession
  }

  alias Cadence.Runtime.Missions, as: RuntimeMissions

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
    with {:ok, replay_runtime_spec} <- replay_runtime_spec(run, binding_set) do
      ReplaySession.process(raw_evidences, replay_runtime_spec)
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
    |> add_replay_managed_operational_events(run.replay_run_id, replay_result.runtime_records)
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

  defp add_replay_managed_operational_events(%Multi{} = multi, replay_run_id, runtime_records) do
    Multi.run(multi, :replay_managed_operational_events, fn repo, _changes ->
      runtime_records
      |> replay_managed_operational_events(replay_run_id)
      |> persist_operational_events(repo)
    end)
  end

  defp replay_managed_operational_events(runtime_records, replay_run_id) do
    capability_events =
      runtime_records.capability_records
      |> Enum.map(&OperationalEvent.from_managed_capability_record(&1, replay_run_id))

    action_events =
      runtime_records.action_requests
      |> Enum.map(&OperationalEvent.from_managed_action_request(&1, replay_run_id))

    timer_events =
      runtime_records.timer_events
      |> Enum.map(&OperationalEvent.from_managed_timer_event(&1, replay_run_id))

    capability_events ++ action_events ++ timer_events
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

  defp replay_runtime_spec(%Run{} = run, binding_set) do
    with {:ok, active_spec} <- RuntimeMissions.applied_spec(run.mission_id) do
      MissionRuntimeSpec.new(%{
        activation_id: run.replay_run_id <> ":replay",
        mission_id: run.mission_id,
        generation: 1,
        binding_set_id: run.binding_set_id,
        binding_set_version: run.binding_set_version,
        binding_set: binding_set,
        mission_model_revision_id: active_spec.mission_model_revision_id,
        mission_model_content_sha256: active_spec.mission_model_content_sha256,
        runtime_plans: active_spec.runtime_plans,
        activated_at: run.started_at,
        metadata: %{"replay" => true, "replay_run_id" => run.replay_run_id}
      })
    end
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
