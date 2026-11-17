defmodule Cadence.Runtime.ReplayConflicts do
  @moduledoc """
  The durable record of a TRIPPED unit (#99 follow-up, director GO 11-17): its public reads, for
  the `replay_conflict` attention source and devops' poller. `ReplayId.check_replay/4` logs
  `MM_REPLAY_ID_CONFLICT` and returns an error inside the write's transaction, which rolls back;
  the stalled unit then records it, after that transaction returned, through the runtime-internal
  `ReplayConflicts.Recorder`, and resolves it when the unit next commits. Paths:

  - `storage`: the ingress persistence projector (alarm effects; one stream);
  - `processing`: the ingress journal consumer (action requests from evidence; one stream);
  - `timer`: the partition owner, on a timer's failed persist, an activation reconcile or a failed
    start (then `partition_stopped`, with `stopped_while`: it stays down until its next start).

  Public surface (lead, 11-17): the reads and acknowledge. The writes are the Recorder's.
  """

  # todo(authz): rows carry no organization_id (mission-scoped runtime rows, like
  # partition_stream_keys); reads are scoped through the mission until Cedar (domain).

  import Ecto.Query

  alias Cadence.Repo
  alias Cadence.Runtime.ReplayConflicts.Row

  @doc "A mission's open records, oldest first."
  @spec open(binary()) :: [Row.t()]
  def open(mission_id) do
    Row
    |> where([row], row.mission_id == ^mission_id and is_nil(row.resolved_at))
    |> order_by([row], asc: row.first_seen_at, asc: row.id)
    |> Repo.all()
  end

  @doc "A mission's records resolved at or after `since`."
  @spec resolved_since(binary(), DateTime.t()) :: [Row.t()]
  def resolved_since(mission_id, %DateTime{} = since) do
    Row
    |> where([row], row.mission_id == ^mission_id and row.resolved_at >= ^since)
    |> Repo.all()
  end

  @doc """
  Acknowledge every open record of the unit `id` names, with the actor and an optional note. A
  later acknowledgement overwrites them (newest only).
  """
  @spec acknowledge(binary(), [binary()], map(), binary() | nil, DateTime.t()) :: :ok
  def acknowledge(mission_id, ids, actor, note, now \\ DateTime.utc_now()) do
    Row
    |> where([row], row.mission_id == ^mission_id and row.id in ^ids)
    |> where([row], is_nil(row.resolved_at))
    |> Repo.update_all(
      set: [
        acknowledged_at: now,
        acknowledged_by: actor,
        acknowledged_note: note,
        updated_at: now
      ]
    )

    :ok
  end
end
