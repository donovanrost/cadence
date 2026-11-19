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
  alias Cadence.Commanding.Groups.ExpiryEvent
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

    # U75: a group whose members expired says so once on its timeline.
    if reason == "expired", do: ExpiryEvent.record(org, mission, cancelable)

    %{
      canceled: Enum.map(cancelable, & &1.command_request_id),
      already_started: Enum.map(started, & &1.command_request_id),
      lanes: canceled_entries |> Enum.map(& &1.queue_lane_key) |> Enum.uniq()
    }
  end

  @sweep_limit 1_000
  @system_actor %{"actor_kind" => "system", "id" => "cadence:expiry"}

  @doc """
  The expiry sweep: cancels, with reason `expired`, work past its `expires_at`
  that never started (the same cancelable states as `cancel/5`), at most
  #{@sweep_limit} requests per sweep. Release already skips expired entries;
  this makes them end visibly instead of staying queued. Returns
  `%{{organization_id, mission_id} => canceled_count}` so the caller can publish
  read updates.
  """
  @spec expire_due(DateTime.t()) :: %{{binary(), binary()} => pos_integer()}
  def expire_due(now \\ DateTime.utc_now()) do
    unqueued =
      CommandRequestRow
      |> where([r], r.lifecycle_state in ^@cancelable_request_states and r.expires_at < ^now)
      |> select([r], {r.organization_id, r.mission_id, r.command_request_id})
      |> limit(@sweep_limit)
      |> Repo.all()

    queued =
      CommandQueueEntryRow
      |> where([q], q.lifecycle_state == "pending" and q.expires_at < ^now)
      |> select([q], {q.organization_id, q.mission_id, q.command_request_id})
      |> limit(@sweep_limit)
      |> Repo.all()

    (unqueued ++ queued)
    |> Enum.uniq()
    |> Enum.group_by(fn {org, mission, _id} -> {org, mission} end, fn {_org, _mission, id} ->
      id
    end)
    |> Enum.reduce(%{}, fn {{org, mission} = key, ids}, acc ->
      {:ok, %{canceled: canceled}} =
        Repo.transaction(fn -> cancel(org, mission, ids, "expired", @system_actor) end)

      if canceled == [], do: acc, else: Map.put(acc, key, length(canceled))
    end)
  end

  @doc """
  Ends one lane's expired, unstarted entries as `expired`, so the dispatcher closes them
  before it picks the lane's head: a member past `expires_at` ends visibly at dispatch,
  not on the next sweep. The release claim refuses expired work on its own (under the
  request and lane locks); this only makes the outcome immediate. Returns the canceled
  request ids. Owns its transaction.
  """
  @spec expire_lane(binary(), binary(), binary(), DateTime.t()) :: [binary()]
  def expire_lane(org, mission, queue_lane_key, now \\ DateTime.utc_now()),
    do: expire_queued(org, mission, now, dynamic([q], q.queue_lane_key == ^queue_lane_key))

  @doc "As `expire_lane/4`, for the queued entries of `request_ids` (a named-contact release)."
  @spec expire_requests(binary(), binary(), [binary()], DateTime.t()) :: [binary()]
  def expire_requests(org, mission, request_ids, now \\ DateTime.utc_now()),
    do: expire_queued(org, mission, now, dynamic([q], q.command_request_id in ^request_ids))

  defp expire_queued(org, mission, now, scope) do
    ids =
      from(q in CommandQueueEntryRow,
        join: r in CommandRequestRow,
        on:
          r.organization_id == q.organization_id and r.mission_id == q.mission_id and
            r.command_request_id == q.command_request_id,
        where:
          q.organization_id == ^org and q.mission_id == ^mission and
            q.lifecycle_state == "pending" and (q.expires_at < ^now or r.expires_at < ^now),
        where: ^scope,
        select: q.command_request_id,
        limit: @sweep_limit
      )
      |> Repo.all()

    expire_ids(org, mission, ids)
  end

  defp expire_ids(_org, _mission, []), do: []

  defp expire_ids(org, mission, ids) do
    {:ok, %{canceled: canceled}} =
      Repo.transaction(fn -> cancel(org, mission, ids, "expired", @system_actor) end)

    canceled
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
