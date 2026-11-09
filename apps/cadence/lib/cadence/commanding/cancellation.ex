defmodule Cadence.Commanding.Cancellation do
  @moduledoc """
  Operator cancel and group abort (M20), plus failing a lane head closed when
  its basis no longer resolves (DECISIONS #31). Only work that hasn't started
  to radiate can be canceled: requests that are `validated`, `approval_pending`
  or `approved`, or `queued` with their queue entry still `pending`. Released
  or releasing work is never touched; in-flight attempts keep the existing
  release-resolution path.

  The reason, actor and time are recorded in the request's
  `metadata["cancellation"]`. Callers own the transaction and the read update.
  """

  import Ecto.Query

  alias Cadence.Commanding.{CommandQueueEntryRow, CommandRequestRow}
  alias Cadence.Persistence.JsonDocument
  alias Cadence.Repo

  @cancelable_request_states ~w(validated approval_pending approved)
  @ended_unstarted_states ~w(canceled rejected)

  @type outcome :: %{canceled: [binary()], already_started: [binary()], lanes: [binary()]}

  @doc """
  Cancels whichever of `request_ids` haven't started. Returns the canceled ids,
  the ids that had already started or finished radiating (requests that were
  already canceled or rejected are in neither list), and the lanes to kick.
  """
  @spec cancel(binary(), binary(), [binary()], binary(), map()) :: outcome()
  def cancel(org, mission, request_ids, reason, actor) do
    requests = lock_requests(org, mission, request_ids)
    entries = lock_entries(org, mission, request_ids)

    {cancelable, others} =
      Enum.split_with(requests, &cancelable?(&1, Map.get(entries, &1.command_request_id)))

    # Requests that ended without radiating (already canceled or rejected) are neither.
    started = Enum.reject(others, &(&1.lifecycle_state in @ended_unstarted_states))

    now = DateTime.utc_now()

    Enum.each(cancelable, fn row ->
      cancellation = %{"reason" => reason, "actor" => actor, "at" => DateTime.to_iso8601(now)}

      metadata =
        row.metadata_document
        |> JsonDocument.unwrap_value()
        |> Map.put("cancellation", cancellation)

      row
      |> Ecto.Changeset.change(
        lifecycle_state: "canceled",
        metadata_document: JsonDocument.wrap_value(metadata)
      )
      |> Repo.update!()
    end)

    canceled_entries =
      cancelable |> Enum.map(&Map.get(entries, &1.command_request_id)) |> Enum.reject(&is_nil/1)

    ids = Enum.map(canceled_entries, & &1.command_queue_entry_id)

    if ids != [] do
      CommandQueueEntryRow
      |> where(
        [q],
        q.organization_id == ^org and q.mission_id == ^mission and
          q.command_queue_entry_id in ^ids
      )
      |> Repo.update_all(set: [lifecycle_state: "canceled", updated_at: now])
    end

    %{
      canceled: Enum.map(cancelable, & &1.command_request_id),
      already_started: Enum.map(started, & &1.command_request_id),
      lanes: canceled_entries |> Enum.map(& &1.queue_lane_key) |> Enum.uniq()
    }
  end

  @doc "Cancels the request behind a pending queue entry whose basis no longer resolves."
  @spec fail_closed(binary(), binary(), binary(), binary()) :: :ok | {:error, :not_pending}
  def fail_closed(org, mission, command_request_id, reason) do
    case cancel(org, mission, [command_request_id], reason, %{
           "actor_kind" => "system",
           "id" => "cadence:release"
         }) do
      %{canceled: [_]} -> :ok
      _other -> {:error, :not_pending}
    end
  end

  defp cancelable?(%{lifecycle_state: state}, _entry) when state in @cancelable_request_states,
    do: true

  defp cancelable?(%{lifecycle_state: "queued"}, %{lifecycle_state: "pending"}), do: true
  defp cancelable?(_request, _entry), do: false

  defp lock_requests(org, mission, ids) do
    ids
    |> Enum.chunk_every(500)
    |> Enum.flat_map(fn chunk ->
      CommandRequestRow
      |> where(
        [r],
        r.organization_id == ^org and r.mission_id == ^mission and r.command_request_id in ^chunk
      )
      |> order_by([r], asc: r.command_request_id)
      |> lock("FOR UPDATE")
      |> Repo.all()
    end)
  end

  defp lock_entries(org, mission, ids) do
    ids
    |> Enum.chunk_every(500)
    |> Enum.flat_map(fn chunk ->
      CommandQueueEntryRow
      |> where(
        [q],
        q.organization_id == ^org and q.mission_id == ^mission and q.command_request_id in ^chunk
      )
      |> order_by([q], asc: q.command_queue_entry_id)
      |> lock("FOR UPDATE")
      |> Repo.all()
    end)
    |> Map.new(&{&1.command_request_id, &1})
  end
end
