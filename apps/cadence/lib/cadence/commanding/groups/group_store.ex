defmodule Cadence.Commanding.Groups.GroupStore do
  @moduledoc """
  Persistence for command groups. Writes are bulk (`insert_all` in chunks of
  500) so a 5,000-member submit stays short under the command-basis lock
  (docs/apogee/domain/group-requests-q5.md). Every row is still built through
  its own changeset, so it gets the same validation and document wrapping as a
  single insert. Callers own the transaction.
  """

  import Ecto.Query

  alias Cadence.Commanding.{
    CommandApproval,
    CommandApprovalRow,
    CommandQueueEntry,
    CommandQueueEntryRow,
    CommandRequest,
    CommandRequestRow,
    QueueLaneLock
  }

  alias Cadence.Commanding.Groups.{CommandGroup, CommandGroupEventRow, CommandGroupRow}
  alias Cadence.Persistence.JsonDocument
  alias Cadence.Repo

  @chunk 500

  @spec insert_group(CommandGroup.t()) :: {:ok, CommandGroup.t()} | {:error, term()}
  def insert_group(%CommandGroup{} = group) do
    case Repo.insert(CommandGroupRow.changeset(group)) do
      {:ok, row} -> {:ok, CommandGroupRow.to_domain(row)}
      {:error, %Ecto.Changeset{errors: errors}} -> {:error, {:invalid_command_group, errors}}
    end
  end

  @spec update_group(CommandGroup.t()) :: {:ok, CommandGroup.t()} | {:error, term()}
  def update_group(%CommandGroup{} = group) do
    with {:ok, row} <- lock_row(group.organization_id, group.mission_id, group.command_group_id),
         {:ok, updated} <- Repo.update(CommandGroupRow.update_changeset(row, group)) do
      {:ok, CommandGroupRow.to_domain(updated)}
    end
  end

  @spec insert_members([CommandRequest.t()]) :: :ok
  def insert_members(requests),
    do: bulk(CommandRequestRow, Enum.map(requests, &CommandRequestRow.changeset/1))

  @spec insert_approvals([CommandApproval.t()]) :: :ok
  def insert_approvals(approvals),
    do: bulk(CommandApprovalRow, Enum.map(approvals, &CommandApprovalRow.changeset/1))

  @spec insert_queue_entries([CommandQueueEntry.t()]) :: :ok
  def insert_queue_entries(entries),
    do: bulk(CommandQueueEntryRow, Enum.map(entries, &CommandQueueEntryRow.changeset/1))

  @spec append_events([map()]) :: :ok
  def append_events(events),
    do: bulk(CommandGroupEventRow, Enum.map(events, &CommandGroupEventRow.changeset/1), false)

  @doc "Sets the lifecycle state of the given member requests."
  @spec set_member_state(binary(), binary(), [binary()], atom()) :: :ok
  def set_member_state(_org, _mission, [], _state), do: :ok

  def set_member_state(org, mission, request_ids, state) do
    now = DateTime.utc_now()

    request_ids
    |> Enum.chunk_every(@chunk)
    |> Enum.each(fn chunk ->
      CommandRequestRow
      |> where(
        [r],
        r.organization_id == ^org and r.mission_id == ^mission and r.command_request_id in ^chunk
      )
      |> Repo.update_all(set: [lifecycle_state: Atom.to_string(state), updated_at: now])
    end)
  end

  @doc """
  Reserves the next queue sequences for each lane under the existing per-lane
  advisory lock (`QueueLaneLock`, all the lanes in one statement, in key order so concurrent
  submits can't deadlock), returning `%{lane => first_free_sequence}`.
  """
  @spec reserve_lanes(binary(), binary(), [binary()]) :: %{binary() => pos_integer()}
  def reserve_lanes(org, mission, lanes) do
    lanes = lanes |> Enum.uniq() |> Enum.sort()
    :ok = QueueLaneLock.acquire_all(org, mission, lanes)

    taken =
      CommandQueueEntryRow
      |> where(
        [q],
        q.organization_id == ^org and q.mission_id == ^mission and q.queue_lane_key in ^lanes
      )
      |> group_by([q], q.queue_lane_key)
      |> select([q], {q.queue_lane_key, max(q.queue_sequence)})
      |> Repo.all()
      |> Map.new()

    Map.new(lanes, &{&1, Map.get(taken, &1, 0) + 1})
  end

  @spec fetch(binary(), binary(), binary(), keyword()) ::
          {:ok, CommandGroup.t()} | {:error, :command_group_not_found}
  def fetch(org, mission, id, opts \\ []) do
    query = scoped(org, mission) |> where([g], g.command_group_id == ^id)
    query = if Keyword.get(opts, :lock), do: lock(query, "FOR UPDATE"), else: query

    case Repo.one(query) do
      nil -> {:error, :command_group_not_found}
      row -> {:ok, CommandGroupRow.to_domain(row)}
    end
  end

  @spec fetch_by_operation(binary(), binary(), binary()) ::
          {:ok, CommandGroup.t()} | {:error, :command_group_not_found}
  def fetch_by_operation(org, mission, operation_id) do
    case Repo.one(scoped(org, mission) |> where([g], g.operation_id == ^operation_id)) do
      nil -> {:error, :command_group_not_found}
      row -> {:ok, CommandGroupRow.to_domain(row)}
    end
  end

  @spec list(binary(), binary(), keyword()) :: [CommandGroup.t()]
  def list(org, mission, opts \\ []) do
    scoped(org, mission)
    |> filter_states(Keyword.get(opts, :states))
    |> order_by([g], desc: g.requested_at, desc: g.command_group_id)
    |> limit(^Keyword.get(opts, :limit, 100))
    |> Repo.all()
    |> Enum.map(&CommandGroupRow.to_domain/1)
  end

  @spec members(binary(), binary(), binary()) :: [CommandRequest.t()]
  def members(org, mission, id) do
    CommandRequestRow
    |> where(
      [r],
      r.organization_id == ^org and r.mission_id == ^mission and r.command_group_id == ^id
    )
    |> order_by([r], asc: r.group_target_index, asc: r.group_position)
    |> Repo.all()
    |> Enum.map(&CommandRequestRow.to_domain/1)
  end

  @doc """
  What the GO that armed a member recorded about withdrawn model approvals (E2, #546): the basis
  string of its craft's withdrawal it knew of, or nil when its craft ran an approved model. A
  member with no GO row, or one that predates the record, answers `:unrecorded`, which never
  equals a basis (fail closed).
  """
  @spec withdrawn_seen(binary(), binary(), binary()) :: binary() | nil | :unrecorded
  def withdrawn_seen(org, mission, request_id) do
    CommandApprovalRow
    |> where(
      [a],
      a.organization_id == ^org and a.mission_id == ^mission and
        a.command_request_id == ^request_id and a.decision in ["approved", "not_required"]
    )
    |> order_by([a], desc: a.decided_at)
    |> limit(1)
    |> select([a], a.metadata_document)
    |> Repo.one()
    |> case do
      nil ->
        :unrecorded

      document ->
        document |> JsonDocument.unwrap_value() |> Map.get("withdrawn_seen", :unrecorded)
    end
  end

  @doc """
  `withdrawn_seen/3` for many requests in one query: `%{request_id => basis | nil}`; a request
  with no GO row, or one that predates the record, is absent (read it as `:unrecorded`).
  """
  @spec withdrawn_seen_for(binary(), binary(), [binary()]) :: %{binary() => binary() | nil}
  def withdrawn_seen_for(_org, _mission, []), do: %{}

  def withdrawn_seen_for(org, mission, request_ids) do
    CommandApprovalRow
    |> where(
      [a],
      a.organization_id == ^org and a.mission_id == ^mission and
        a.command_request_id in ^request_ids and a.decision in ["approved", "not_required"]
    )
    |> order_by([a], asc: a.decided_at)
    |> select([a], {a.command_request_id, a.metadata_document})
    |> Repo.all()
    |> Enum.reduce(%{}, fn {request_id, document}, acc ->
      case document |> JsonDocument.unwrap_value() |> Map.fetch("withdrawn_seen") do
        {:ok, seen} -> Map.put(acc, request_id, seen)
        :error -> Map.delete(acc, request_id)
      end
    end)
  end

  @doc "`%{command_request_id => command_queue_entry_id}` for the requests' pending queue entries."
  @spec pending_entry_ids(binary(), binary(), [binary()]) :: %{binary() => binary()}
  def pending_entry_ids(_org, _mission, []), do: %{}

  def pending_entry_ids(org, mission, request_ids) do
    CommandQueueEntryRow
    |> where(
      [q],
      q.organization_id == ^org and q.mission_id == ^mission and
        q.command_request_id in ^request_ids and q.lifecycle_state == "pending"
    )
    |> select([q], {q.command_request_id, q.command_queue_entry_id})
    |> Repo.all()
    |> Map.new()
  end

  @doc "Members of several groups at once, `%{command_group_id => [request]}`."
  @spec members_of(binary(), binary(), [binary()]) :: %{binary() => [CommandRequest.t()]}
  def members_of(_org, _mission, []), do: %{}

  def members_of(org, mission, ids) do
    CommandRequestRow
    |> where(
      [r],
      r.organization_id == ^org and r.mission_id == ^mission and r.command_group_id in ^ids
    )
    |> order_by([r], asc: r.group_target_index, asc: r.group_position)
    |> Repo.all()
    |> Enum.group_by(& &1.command_group_id, &CommandRequestRow.to_domain/1)
  end

  @spec events(binary(), binary()) :: [map()]
  def events(mission, id) do
    CommandGroupEventRow
    |> where([e], e.mission_id == ^mission and e.command_group_id == ^id)
    |> order_by([e], asc: e.at, asc: e.event_id)
    |> Repo.all()
    |> Enum.map(&CommandGroupEventRow.to_domain/1)
  end

  defp scoped(org, mission),
    do: where(CommandGroupRow, [g], g.organization_id == ^org and g.mission_id == ^mission)

  defp filter_states(query, nil), do: query

  defp filter_states(query, states),
    do: where(query, [g], g.state in ^Enum.map(states, &to_string/1))

  defp lock_row(org, mission, id) do
    case Repo.one(
           scoped(org, mission)
           |> where([g], g.command_group_id == ^id)
           |> lock("FOR UPDATE")
         ) do
      nil -> {:error, :command_group_not_found}
      row -> {:ok, row}
    end
  end

  defp bulk(schema, changesets, timestamps? \\ true) do
    now = DateTime.utc_now()
    fields = schema.__schema__(:fields)

    changesets
    |> Enum.map(fn changeset ->
      row = Ecto.Changeset.apply_action!(changeset, :insert)
      base = Map.take(row, fields)
      if timestamps?, do: %{base | inserted_at: now, updated_at: now}, else: base
    end)
    |> Enum.chunk_every(@chunk)
    |> Enum.each(&Repo.insert_all(schema, &1))
  end
end
