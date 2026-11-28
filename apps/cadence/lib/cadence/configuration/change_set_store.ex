defmodule Cadence.Configuration.ChangeSetStore do
  @moduledoc "Queries and row updates for change sets, their changes and ops."

  import Ecto.Query

  alias Cadence.Configuration.{ChangeRow, ChangeSetRow, OpRow, ReviewRow}
  alias Cadence.Ids
  alias Cadence.Repo

  # The states that make a set its lane's active one (U108): a configuration set is active while
  # open or in review (it freezes in review); a monitoring set only while open, so review never
  # closes the monitoring lane.
  @active_states %{"configuration" => ["open", "in_review"], "monitoring" => ["open"]}

  @doc "The mission's active set in `lane` (configuration by default), if any (no lock)."
  @spec active(String.t(), String.t()) :: ChangeSetRow.t() | nil
  def active(mission_id, lane \\ "configuration") do
    mission_id |> active_query(lane) |> Repo.one()
  end

  @doc """
  The mission's monitoring sets in review (any number can be, U108), oldest first: at most `limit`
  of them and how many there are, `{sets, total}`. Two queries however many there are.
  """
  @spec in_review(String.t(), String.t(), pos_integer()) ::
          {[ChangeSetRow.t()], non_neg_integer()}
  def in_review(mission_id, "monitoring", limit) when is_integer(limit) and limit > 0 do
    query =
      where(
        ChangeSetRow,
        [set],
        set.mission_id == ^mission_id and set.lane == "monitoring" and set.state == "in_review"
      )

    sets =
      query
      |> order_by([set], asc: set.submitted_at, asc: set.change_set_id)
      |> limit(^limit)
      |> Repo.all()

    {sets, Repo.aggregate(query, :count)}
  end

  @doc "How many staged changes each of `change_set_ids` has, in one query (absent when none)."
  @spec staged_counts([String.t()]) :: %{String.t() => pos_integer()}
  def staged_counts([]), do: %{}

  def staged_counts(change_set_ids) do
    ChangeRow
    |> where([change], change.change_set_id in ^change_set_ids and change.state == "staged")
    |> group_by([change], change.change_set_id)
    |> select([change], {change.change_set_id, count(change.change_id)})
    |> Repo.all()
    |> Map.new()
  end

  @doc "Locks the active set in `lane` for update. Must run inside a transaction."
  @spec lock_active(String.t(), String.t()) :: ChangeSetRow.t() | nil
  def lock_active(mission_id, lane \\ "configuration") do
    mission_id |> active_query(lane) |> lock("FOR UPDATE") |> Repo.one()
  end

  defp active_query(mission_id, lane) do
    states = Map.fetch!(@active_states, lane)

    where(
      ChangeSetRow,
      [set],
      set.mission_id == ^mission_id and set.lane == ^lane and set.state in ^states
    )
  end

  @doc "Locks one set of the mission for update. Must run inside a transaction."
  @spec lock_set(String.t(), String.t()) ::
          {:ok, ChangeSetRow.t()} | {:error, :change_set_not_found}
  def lock_set(mission_id, change_set_id) do
    ChangeSetRow
    |> where([set], set.mission_id == ^mission_id and set.change_set_id == ^change_set_id)
    |> lock("FOR UPDATE")
    |> Repo.one()
    |> found(:change_set_not_found)
  end

  @spec fetch(String.t(), String.t()) :: {:ok, ChangeSetRow.t()} | {:error, :change_set_not_found}
  def fetch(mission_id, change_set_id) do
    ChangeSetRow
    |> Repo.get_by(mission_id: mission_id, change_set_id: change_set_id)
    |> found(:change_set_not_found)
  end

  @doc "Locks `lane`'s active set, opening a new one on `base_revision` when there is none."
  @spec lock_or_open(String.t(), String.t(), integer(), map(), String.t()) :: ChangeSetRow.t()
  def lock_or_open(organization_id, mission_id, base_revision, actor, lane \\ "configuration") do
    case lock_active(mission_id, lane) do
      %ChangeSetRow{} = set ->
        set

      nil ->
        now = DateTime.utc_now()

        Repo.insert(
          %ChangeSetRow{
            change_set_id: Ids.new("change_set"),
            organization_id: organization_id,
            mission_id: mission_id,
            lane: lane,
            state: "open",
            version: 1,
            base_revision_number: base_revision,
            opened_by: actor,
            opened_at: now
          },
          on_conflict: :nothing
        )

        lock_active(mission_id, lane)
    end
  end

  @spec changes(String.t(), [String.t()]) :: [ChangeRow.t()]
  def changes(change_set_id, states \\ ["staged"]) do
    ChangeRow
    |> where([change], change.change_set_id == ^change_set_id and change.state in ^states)
    |> order_by([change], asc: change.position)
    |> Repo.all()
  end

  @spec fetch_change(String.t(), String.t()) :: {:ok, ChangeRow.t()} | {:error, :change_not_found}
  def fetch_change(mission_id, change_id) do
    ChangeRow
    |> Repo.get_by(mission_id: mission_id, change_id: change_id)
    |> found(:change_not_found)
  end

  @spec fetch_op(String.t(), String.t()) :: {:ok, OpRow.t()} | {:error, :op_not_found}
  def fetch_op(mission_id, op_id) do
    OpRow
    |> Repo.get_by(mission_id: mission_id, op_id: op_id)
    |> found(:op_not_found)
  end

  @doc "Ops of the set's staged changes, in apply order, as pipeline ops."
  @spec staged_ops(String.t()) :: [map()]
  def staged_ops(change_set_id) do
    OpRow
    |> join(:inner, [op], change in ChangeRow, on: change.change_id == op.change_id)
    |> where([op, change], op.change_set_id == ^change_set_id and change.state == "staged")
    |> order_by([op, change], asc: change.position, asc: op.position)
    |> select([op, change], %{
      op: op,
      author: change.author,
      author_key: change.author_key,
      source: change.source
    })
    |> Repo.all()
    |> Enum.map(fn %{op: op} = row ->
      op
      |> to_pipeline_op()
      |> Map.merge(%{author: row.author, author_key: row.author_key, source: row.source || %{}})
    end)
  end

  @spec ops_for_change(String.t()) :: [OpRow.t()]
  def ops_for_change(change_id) do
    OpRow
    |> where([op], op.change_id == ^change_id)
    |> order_by([op], asc: op.position)
    |> Repo.all()
  end

  @spec next_change_position(String.t()) :: non_neg_integer()
  def next_change_position(change_set_id) do
    ChangeRow
    |> where([change], change.change_set_id == ^change_set_id)
    |> select([change], max(change.position))
    |> Repo.one()
    |> case do
      nil -> 0
      position -> position + 1
    end
  end

  @spec reviews(String.t()) :: [ReviewRow.t()]
  def reviews(change_set_id) do
    ReviewRow
    |> where([review], review.change_set_id == ^change_set_id)
    |> order_by([review], asc: review.decided_at)
    |> Repo.all()
  end

  @doc "Updates a set's fields and bumps its version."
  @spec update_set(ChangeSetRow.t(), keyword()) :: ChangeSetRow.t()
  def update_set(%ChangeSetRow{} = set, fields) do
    fields = Keyword.merge([version: set.version + 1, updated_at: DateTime.utc_now()], fields)

    {1, [updated]} =
      ChangeSetRow
      |> where([row], row.change_set_id == ^set.change_set_id)
      |> select([row], row)
      |> Repo.update_all(set: fields)

    updated
  end

  @spec set_change_states(String.t(), [String.t()], String.t()) :: non_neg_integer()
  def set_change_states(_change_set_id, [], _state), do: 0

  def set_change_states(change_set_id, change_ids, state) do
    {count, nil} =
      ChangeRow
      |> where(
        [change],
        change.change_set_id == ^change_set_id and change.change_id in ^change_ids
      )
      |> Repo.update_all(set: [state: state, updated_at: DateTime.utc_now()])

    count
  end

  @spec to_pipeline_op(OpRow.t()) :: map()
  def to_pipeline_op(%OpRow{} = op) do
    %{
      op_id: op.op_id,
      change_id: op.change_id,
      kind: op.kind,
      entity_id: op.entity_id,
      action: op.action,
      payload: op.payload,
      base: op.base,
      touched_paths: op.touched_paths
    }
  end

  defp found(nil, reason), do: {:error, reason}
  defp found(row, _reason), do: {:ok, row}
end
