defmodule Cadence.Application.Commanding.QueueSnapshotLoader do
  @moduledoc """
  Loads persisted queue entries and adjudicates in-flight execution.

  This module runs in the control plane to ensure data plane startup
  uses an in-memory snapshot without database access.
  """

  import Ecto.Query

  alias Cadence.Adapters.Persistence.Ecto.Commanding.EctoQueueRepository
  alias Cadence.Application.Commanding.QueueSnapshot
  alias Cadence.Commands.QueueEntry
  alias Cadence.Recordings.Recording
  alias Cadence.Repo

  @spec load_for_mission(String.t(), list()) :: {:ok, %{String.t() => QueueSnapshot.t()}}
  def load_for_mission(mission_id, targets) when is_binary(mission_id) do
    target_ids = Enum.map(targets, & &1.id)

    entries = fetch_entries(mission_id)
    pending_entries = adjudicate_executing(entries)
    pending_entities = Enum.map(pending_entries, &EctoQueueRepository.to_entity/1)

    {:ok, build_snapshots(target_ids, pending_entities)}
  end

  defp fetch_entries(mission_id) do
    from(q in QueueEntry,
      where: q.mission_id == ^mission_id,
      where: q.status in [:pending, :executing],
      order_by: [asc: q.priority, asc: q.sequence_number]
    )
    |> Repo.all()
  end

  defp build_snapshots(target_ids, pending_entities) do
    Enum.reduce(target_ids, %{}, fn target_id, acc ->
      snapshot = build_snapshot(target_id, pending_entities)
      Map.put(acc, target_id, snapshot)
    end)
  end

  defp build_snapshot(target_id, pending_entities) do
    entries_for_target =
      pending_entities
      |> Enum.filter(&(&1.target_id == target_id))
      |> Enum.sort_by(&{&1.priority, &1.sequence_number})

    sequence_counter =
      case Enum.max_by(entries_for_target, & &1.sequence_number, fn -> nil end) do
        nil -> 0
        entry -> entry.sequence_number || 0
      end

    %QueueSnapshot{
      target_id: target_id,
      pending_entries: entries_for_target,
      sequence_counter: sequence_counter
    }
  end

  defp adjudicate_executing(entries) do
    {executing, pending} = Enum.split_with(entries, &(&1.status == :executing))

    recovered =
      Enum.flat_map(executing, fn entry ->
        case adjudicate_entry(entry) do
          {:pending, updated} -> [updated]
          :drop -> []
        end
      end)

    pending ++ recovered
  end

  defp adjudicate_entry(%QueueEntry{command_log_id: command_log_id} = entry)
       when is_binary(command_log_id) do
    if command_sent?(command_log_id) do
      update_entry(entry, %{status: :completed, last_error: nil})
      :drop
    else
      update_entry(entry, %{
        status: :failed,
        last_error: "Dispatch interrupted before send confirmation"
      })

      :drop
    end
  end

  defp adjudicate_entry(%QueueEntry{} = entry) do
    reason = "Restarted while executing with no command log reference"

    update_entry(entry, %{
      status: :pending,
      last_error: reason
    })

    {:pending, %{entry | status: :pending, last_error: reason}}
  end

  defp command_sent?(aggregate_id) do
    from(r in Recording,
      where: r.aggregate_type == "Command",
      where: r.aggregate_id == ^aggregate_id,
      where: r.recordable_type == "CommandSent",
      select: 1,
      limit: 1
    )
    |> Repo.one() == 1
  end

  defp update_entry(%QueueEntry{} = entry, attrs) do
    entry
    |> QueueEntry.execution_changeset(attrs)
    |> Repo.update()
  end
end
