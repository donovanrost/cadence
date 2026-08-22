defmodule Cadence.Runtime.ReplaySession do
  @moduledoc """
  Public data-plane boundary for isolated deterministic replay execution.

  A replay session owns unregistered partition processes for the duration of a
  bounded evidence set, drains their runtime records, and stops every process
  before returning. Callers never depend on partition identity or process
  implementation details.
  """

  alias Cadence.ApplicationDispatch.BindingSet
  alias Cadence.Ingress.RawEvidence
  alias Cadence.Runtime.{MissionRuntimeSpec, PartitionKey, PartitionOwner}

  @type runtime_records :: %{
          capability_records: [term()],
          action_requests: [term()],
          timer_events: [term()]
        }

  @spec process([RawEvidence.t()], MissionRuntimeSpec.t()) ::
          {:ok, %{processing_results: [map()], runtime_records: runtime_records()}}
          | {:error, term()}
  def process(raw_evidences, %MissionRuntimeSpec{binding_set: %BindingSet{} = binding_set} = spec)
      when is_list(raw_evidences) do
    case process_all(raw_evidences, spec, binding_set, %{}, []) do
      {:ok, processing_results, partition_owners} ->
        finalize(processing_results, partition_owners)

      {:error, reason, partition_owners} ->
        stop_partition_owners(partition_owners)
        {:error, reason}
    end
  end

  defp process_all([], _spec, _binding_set, partition_owners, acc) do
    {:ok, acc, partition_owners}
  end

  defp process_all(
         [%RawEvidence{} = raw_evidence | remaining],
         spec,
         binding_set,
         partition_owners,
         acc
       ) do
    partition_key = PartitionKey.from_raw_evidence(raw_evidence)

    case ensure_partition_owner(
           partition_owners,
           partition_key,
           spec,
           binding_set,
           raw_evidence
         ) do
      {:ok, partition_owner, next_partition_owners} ->
        case PartitionOwner.process_raw_evidence(partition_owner, raw_evidence) do
          {:ok, processing_result} ->
            process_all(
              remaining,
              spec,
              binding_set,
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

  defp ensure_partition_owner(
         partition_owners,
         %PartitionKey{} = partition_key,
         spec,
         binding_set,
         raw_evidence
       ) do
    case Map.fetch(partition_owners, partition_key) do
      {:ok, partition_owner} ->
        {:ok, partition_owner, partition_owners}

      :error ->
        start_partition_owner(partition_owners, partition_key, spec, binding_set, raw_evidence)
    end
  end

  defp start_partition_owner(partition_owners, partition_key, spec, binding_set, raw_evidence) do
    case PartitionOwner.start_link(
           mission_id: spec.mission_id,
           partition_key: partition_key,
           active_activation: spec,
           binding_set: binding_set,
           register?: false,
           persist_runtime_records?: false,
           profiler: :disabled,
           clock_mode: :replay,
           initial_time: replay_time_for_raw_evidence(raw_evidence)
         ) do
      {:ok, partition_owner} ->
        {:ok, partition_owner, Map.put(partition_owners, partition_key, partition_owner)}

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp finalize(processing_results, partition_owners) do
    result =
      with {:ok, runtime_records} <- drain_partition_owners(partition_owners) do
        {:ok,
         %{
           processing_results: Enum.reverse(processing_results),
           runtime_records: runtime_records
         }}
      end

    stop_partition_owners(partition_owners)
    result
  end

  defp drain_partition_owners(partition_owners) do
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

  defp stop_partition_owners(partition_owners) do
    Enum.each(partition_owners, fn
      {_partition_key, partition_owner} when is_pid(partition_owner) ->
        if Process.alive?(partition_owner), do: PartitionOwner.stop(partition_owner)
    end)
  end

  defp empty_runtime_records do
    %{capability_records: [], action_requests: [], timer_events: []}
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
end
