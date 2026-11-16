defmodule Cadence.Configuration.Editing do
  @moduledoc """
  Edits to an open change set: withdraw one change, discard changes, rebase an op onto live.

  Withdrawn changes keep their ops, so the surface where they were made can give them back to
  their author as unstaged edits.

  A set left with nothing staged (its last change withdrawn, discarded, or emptied by a take-live
  rebase) closes in the same transaction, under its row lock: state `discarded` with `closed_at`,
  as a discard of everything always did (lead, ux 11-16). Staging takes the same row lock, so a
  concurrent stage opens a fresh set instead of joining a closed one. The set's history still
  shows the withdrawals.
  """

  import Ecto.Query

  alias Cadence.Configuration.{ChangeSetStore, Document, Kinds, OpRow}
  alias Cadence.Repo

  @spec withdraw(String.t(), String.t(), map(), boolean()) :: {:ok, map()} | {:error, term()}
  def withdraw(mission_id, change_id, actor, discard_any?) do
    Repo.transaction(fn ->
      with {:ok, change} <- ChangeSetStore.fetch_change(mission_id, change_id),
           {:ok, set} <- ChangeSetStore.lock_set(mission_id, change.change_set_id),
           :ok <- open(set),
           :ok <- staged(change),
           :ok <- may_edit(change, actor, discard_any?) do
        ChangeSetStore.set_change_states(set.change_set_id, [change_id], "withdrawn")
        result(close_if_empty(set))
      else
        {:error, reason} -> Repo.rollback(reason)
      end
    end)
  end

  @doc "Discards the staged changes the actor may discard; closes the set when none remain."
  @spec discard(String.t(), String.t(), integer(), map(), boolean()) ::
          {:ok, map()} | {:error, term()}
  def discard(mission_id, change_set_id, expected_version, actor, discard_any?) do
    Repo.transaction(fn ->
      with {:ok, set} <- ChangeSetStore.lock_set(mission_id, change_set_id),
           :ok <- open(set),
           :ok <- expected(set, expected_version) do
        discard_locked(set, actor, discard_any?)
      else
        {:error, reason} -> Repo.rollback(reason)
      end
    end)
  end

  defp discard_locked(set, actor, discard_any?) do
    changes = ChangeSetStore.changes(set.change_set_id)
    mine = Enum.filter(changes, &(may_edit(&1, actor, discard_any?) == :ok))
    ids = Enum.map(mine, & &1.change_id)
    ChangeSetStore.set_change_states(set.change_set_id, ids, "discarded")
    remaining = length(changes) - length(mine)

    set
    |> close_if_empty()
    |> result()
    |> Map.merge(%{discarded: length(mine), remaining: remaining})
  end

  # Under the caller's lock on the set row.
  defp close_if_empty(set) do
    if ChangeSetStore.changes(set.change_set_id) == [],
      do: ChangeSetStore.update_set(set, state: "discarded", closed_at: DateTime.utc_now()),
      else: ChangeSetStore.update_set(set, [])
  end

  @doc """
  Resolves an op's conflict with live values: `:keep_mine` re-bases the op on the live values;
  `:take_live` drops the conflicting paths from the op (and the op, once it changes nothing).
  """
  @spec rebase(String.t(), String.t(), String.t(), :keep_mine | :take_live, map(), boolean()) ::
          {:ok, map()} | {:error, term()}
  def rebase(organization_id, mission_id, op_id, resolution, actor, discard_any?)
      when resolution in [:keep_mine, :take_live] do
    Repo.transaction(fn ->
      with {:ok, op} <- ChangeSetStore.fetch_op(mission_id, op_id),
           {:ok, change} <- ChangeSetStore.fetch_change(mission_id, op.change_id),
           {:ok, set} <- ChangeSetStore.lock_set(mission_id, op.change_set_id),
           :ok <- open(set),
           :ok <- may_edit(change, actor, discard_any?),
           {:ok, current} <- current(organization_id, mission_id, op) do
        apply_resolution(op, current, resolution)
        maybe_withdraw_empty(set, change.change_id)
        result(close_if_empty(set))
      else
        {:error, reason} -> Repo.rollback(reason)
      end
    end)
  end

  def rebase(_org, _mission, _op, _resolution, _actor, _any?), do: {:error, :invalid_resolution}

  defp apply_resolution(%OpRow{action: "delete"} = op, current, :keep_mine),
    do: update_op(op, base: %{"sha256" => Document.sha256(current)})

  defp apply_resolution(%OpRow{action: "update"} = op, current, :keep_mine) do
    values = Map.new(op.touched_paths, &{&1, Document.get(current, &1)})
    update_op(op, base: %{"values" => values})
  end

  defp apply_resolution(%OpRow{action: "update"} = op, current, :take_live) do
    values = op.base["values"]
    keep = Enum.filter(op.touched_paths, &(Map.get(values, &1) == Document.get(current, &1)))
    shrink(op, keep)
  end

  defp apply_resolution(%OpRow{} = op, _current, :take_live), do: shrink(op, [])
  defp apply_resolution(%OpRow{}, _current, :keep_mine), do: :ok

  defp shrink(op, []), do: Repo.delete_all(where(OpRow, [row], row.op_id == ^op.op_id))

  defp shrink(op, keep) do
    update_op(op,
      touched_paths: keep,
      payload:
        Map.put(op.payload, "changes", Enum.filter(op.payload["changes"], &(&1["path"] in keep))),
      base: %{"values" => Map.take(op.base["values"], keep)}
    )
  end

  defp update_op(op, fields),
    do: Repo.update_all(where(OpRow, [row], row.op_id == ^op.op_id), set: fields)

  defp maybe_withdraw_empty(set, change_id) do
    if ChangeSetStore.ops_for_change(change_id) == [],
      do: ChangeSetStore.set_change_states(set.change_set_id, [change_id], "withdrawn")
  end

  defp current(organization_id, mission_id, op) do
    {:ok, kind} = Kinds.fetch(op.kind)

    case Map.get(kind.load(organization_id, mission_id, [op.entity_id]), op.entity_id) do
      nil -> {:error, :entity_gone}
      document -> {:ok, Document.normalize(document)}
    end
  end

  defp open(%{state: "open"}), do: :ok
  defp open(%{state: "in_review"}), do: {:error, :frozen_in_review}
  defp open(_set), do: {:error, :change_set_not_found}

  defp staged(%{state: "staged"}), do: :ok
  defp staged(_change), do: {:error, :change_not_found}

  defp expected(%{version: version}, version), do: :ok
  defp expected(_set, _expected), do: {:error, :change_set_changed}

  defp may_edit(%{author_key: key}, %{"kind" => kind, "id" => id}, discard_any?) do
    if discard_any? or key == kind <> ":" <> id, do: :ok, else: {:error, :forbidden}
  end

  defp result(set),
    do: %{change_set_id: set.change_set_id, version: set.version, state: set.state}
end
