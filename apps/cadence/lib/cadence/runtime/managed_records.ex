defmodule Cadence.Runtime.ManagedRecords do
  @moduledoc "Data-plane persistence boundary for managed-capability execution records."

  import Ecto.Query

  alias Cadence.Platform.ReplayId
  alias Cadence.Repo
  alias Cadence.Runtime.{ManagedActionRequest, ManagedCapabilityRecord, ManagedTimerEvent}

  alias Cadence.Runtime.ManagedRecords.{
    ManagedActionRequestRow,
    ManagedCapabilityRecordRow,
    ManagedTimerEventRow
  }

  alias Ecto.Multi

  @spec add_capability_record_inserts(Multi.t(), [ManagedCapabilityRecord.t()]) :: Multi.t()
  def add_capability_record_inserts(%Multi{} = multi, records) when is_list(records) do
    Enum.reduce(records, multi, fn %ManagedCapabilityRecord{} = record, %Multi{} = acc ->
      Multi.insert(
        acc,
        {:managed_capability_record, record.capability_record_id},
        ManagedCapabilityRecordRow.changeset(record)
      )
    end)
  end

  @doc """
  Inserts the requests in one statement, insert-or-get (DECISIONS #99): a request whose
  replay-safe id is already stored is a replay, checked to be the same request
  (`ReplayId.check_replay/4`) and not inserted again.
  """
  @spec add_action_request_inserts(Multi.t(), [ManagedActionRequest.t()]) :: Multi.t()
  def add_action_request_inserts(%Multi{} = multi, []), do: multi

  def add_action_request_inserts(%Multi{} = multi, requests) when is_list(requests) do
    Multi.run(multi, :managed_action_requests, fn repo, _changes ->
      insert_or_get_requests(repo, requests)
    end)
  end

  defp insert_or_get_requests(repo, requests) do
    now = DateTime.utc_now()

    with {:ok, rows} <- request_rows(requests, now) do
      {_count, inserted} =
        repo.insert_all(ManagedActionRequestRow, rows,
          on_conflict: :nothing,
          returning: [:action_request_id]
        )

      inserted = MapSet.new(inserted, & &1.action_request_id)
      replayed = Enum.reject(rows, &MapSet.member?(inserted, &1.action_request_id))

      with :ok <- check_replayed_requests(repo, replayed) do
        {:ok, %{inserted: MapSet.size(inserted), replayed: length(replayed)}}
      end
    end
  end

  defp request_rows(requests, now) do
    Enum.reduce_while(requests, {:ok, []}, fn %ManagedActionRequest{} = request, {:ok, rows} ->
      case request
           |> ManagedActionRequestRow.changeset()
           |> Ecto.Changeset.apply_action(:insert) do
        {:ok, row} ->
          row = row |> Map.from_struct() |> Map.delete(:__meta__) |> Map.put(:inserted_at, now)
          {:cont, {:ok, [row | rows]}}

        {:error, changeset} ->
          {:halt, {:error, changeset}}
      end
    end)
    |> case do
      {:ok, rows} -> {:ok, Enum.reverse(rows)}
      error -> error
    end
  end

  defp check_replayed_requests(_repo, []), do: :ok

  defp check_replayed_requests(repo, rows) do
    stored =
      ManagedActionRequestRow
      |> where([row], row.action_request_id in ^Enum.map(rows, & &1.action_request_id))
      |> repo.all()
      |> Map.new(&{&1.action_request_id, &1})

    Enum.reduce_while(rows, :ok, fn row, :ok ->
      existing = Map.fetch!(stored, row.action_request_id)

      case ReplayId.check_replay(
             :managed_action_request,
             row.action_request_id,
             request_effect(existing),
             request_effect(row)
           ) do
        :ok -> {:cont, :ok}
        error -> {:halt, error}
      end
    end)
  end

  # What a request derives from its input: the action and its document (not times or ids).
  defp request_effect(row), do: %{action_kind: row.action_kind, document: row.request_document}

  @spec add_timer_event_inserts(Multi.t(), [ManagedTimerEvent.t()]) :: Multi.t()
  def add_timer_event_inserts(%Multi{} = multi, events) when is_list(events) do
    Enum.reduce(events, multi, fn %ManagedTimerEvent{} = event, %Multi{} = acc ->
      Multi.insert(
        acc,
        {:managed_timer_event, event.timer_event_id},
        ManagedTimerEventRow.changeset(event)
      )
    end)
  end

  @spec list_action_requests(binary()) :: [ManagedActionRequest.t()]
  def list_action_requests(mission_id) when is_binary(mission_id) do
    ManagedActionRequestRow
    |> where([row], row.mission_id == ^mission_id)
    |> Repo.all()
    |> Enum.map(&ManagedActionRequestRow.to_domain/1)
  end
end
