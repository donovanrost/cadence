defmodule Cadence.Configuration.Status do
  @moduledoc """
  Read models for change sets and revisions: the head and staged bar (`current/2`), the revision
  list and detail, compare, and per-entity history. Returns plain maps; times are `DateTime`,
  revision numbers integers, actors `%{kind, id, name}`.
  """

  alias Cadence.Configuration.{ActorNames, ChangeSetStore, Document, Ledger}

  @doc """
  The head and `lane`'s staged bar (ADR-020 P3, #451; U108). `change_set` is the lane's active
  set: configuration's open or in-review set, or monitoring's open set. A monitoring read also
  carries `in_review`, its sets in review (any number), oldest first. Both lanes share the head:
  revisions from both are one sequence.
  """
  @spec current(String.t(), String.t(), String.t()) :: map()
  def current(organization_id, mission_id, lane \\ "configuration") do
    head = Ledger.ensure_head(organization_id, mission_id)
    {:ok, revision} = Ledger.fetch_revision(mission_id, head.revision_number)

    %{
      head: revision_view(revision, head.revision_number),
      lane: lane,
      change_set: mission_id |> ChangeSetStore.active(lane) |> change_set_view()
    }
    |> put_in_review(mission_id, lane)
    |> ActorNames.named(mission_id)
  end

  defp put_in_review(view, mission_id, "monitoring"),
    do:
      Map.put(
        view,
        :in_review,
        mission_id |> ChangeSetStore.in_review("monitoring") |> Enum.map(&change_set_view/1)
      )

  defp put_in_review(view, _mission_id, _lane), do: view

  @spec change_set(String.t(), String.t()) :: {:ok, map()} | {:error, term()}
  def change_set(mission_id, change_set_id) do
    with {:ok, set} <- ChangeSetStore.fetch(mission_id, change_set_id),
         do: {:ok, set |> change_set_view() |> ActorNames.named(mission_id)}
  end

  @spec list_revisions(String.t(), String.t(), keyword()) :: [map()]
  def list_revisions(organization_id, mission_id, opts \\ []) do
    head = Ledger.ensure_head(organization_id, mission_id)

    mission_id
    |> Ledger.list_revisions(opts)
    |> Enum.map(&revision_view(&1, head.revision_number))
    |> ActorNames.named(mission_id)
  end

  @spec get_revision(String.t(), String.t(), pos_integer()) :: {:ok, map()} | {:error, term()}
  def get_revision(organization_id, mission_id, number) do
    head = Ledger.ensure_head(organization_id, mission_id)

    with {:ok, revision} <- Ledger.fetch_revision(mission_id, number) do
      entries = Enum.map(Ledger.entries(revision.revision_id), &entry_view/1)

      {:ok,
       revision
       |> revision_view(head.revision_number)
       |> Map.put(:entries, entries)
       |> ActorNames.named(mission_id)}
    end
  end

  @doc "Combined change from revision `from` to revision `to` (`from < to`), per entity."
  @spec compare(String.t(), pos_integer(), pos_integer()) :: {:ok, [map()]} | {:error, term()}
  def compare(mission_id, from, to) when is_integer(from) and is_integer(to) and from < to do
    with {:ok, _} <- Ledger.fetch_revision(mission_id, from),
         {:ok, _} <- Ledger.fetch_revision(mission_id, to) do
      {:ok,
       mission_id
       |> Ledger.entries_between(from, to)
       |> fold_entries()
       |> ActorNames.named(mission_id)}
    end
  end

  def compare(_mission_id, _from, _to), do: {:error, :invalid_range}

  @spec entity_history(String.t(), String.t(), String.t()) :: [map()]
  def entity_history(mission_id, kind, entity_id) do
    mission_id
    |> Ledger.entity_entries(kind, entity_id)
    |> Enum.map(&entry_view/1)
    |> ActorNames.named(mission_id)
  end

  defp fold_entries(entries) do
    entries
    |> Enum.group_by(&{&1.kind, &1.entity_id})
    |> Enum.map(fn {{kind, entity_id}, group} ->
      first = List.first(group)
      last = List.last(group)

      %{
        kind: kind,
        entity_id: entity_id,
        revisions: group |> Enum.map(& &1.revision_number) |> Enum.uniq(),
        op: fold_op(first.before, last.after),
        fields: Document.diff(first.before, last.after)
      }
    end)
    |> Enum.reject(&(&1.fields == [] and &1.op == :update))
    |> Enum.sort_by(&{&1.kind, &1.entity_id})
  end

  defp fold_op(nil, nil), do: :none
  defp fold_op(nil, _after), do: :create
  defp fold_op(_before, nil), do: :delete
  defp fold_op(_before, _after), do: :update

  defp change_set_view(nil), do: nil

  defp change_set_view(set) do
    changes = ChangeSetStore.changes(set.change_set_id)
    withdrawn = ChangeSetStore.changes(set.change_set_id, ["withdrawn"])

    %{
      id: set.change_set_id,
      version: set.version,
      state: known(set.state),
      base_revision: set.base_revision_number,
      opened_at: set.opened_at,
      opened_by: actor(set.opened_by),
      staged_count: length(changes),
      changes: Enum.map(changes, &change_view/1),
      withdrawn: Enum.map(withdrawn, &change_view/1),
      authors: changes |> Enum.map(& &1.author) |> Enum.uniq() |> Enum.map(&actor/1),
      submitted_by: actor(set.submitted_by),
      submitted_at: set.submitted_at,
      reason: set.reason,
      approval_required: approval_required?(set.policy_document),
      # A reviewer's decisions only: a direct apply's not_required record (#117 step 2) is no review;
      # it's in the four-eyes record (ReviewRecord.decisions/2) and the audit (#239).
      reviews:
        set.change_set_id
        |> ChangeSetStore.reviews()
        |> Enum.reject(&(&1.decision == "not_required"))
        |> Enum.map(&review_view/1),
      failure: set.failure_document,
      applied_revision: set.applied_revision_number
    }
  end

  defp change_view(change) do
    ops = ChangeSetStore.ops_for_change(change.change_id)

    %{
      id: change.change_id,
      summary: change.summary,
      author: actor(change.author),
      staged_at: change.staged_at,
      source: change.source,
      state: known(change.state),
      ops:
        Enum.map(ops, fn op ->
          %{
            id: op.op_id,
            kind: op.kind,
            entity_id: op.entity_id,
            action: known(op.action),
            paths: op.touched_paths,
            payload: op.payload
          }
        end)
    }
  end

  defp review_view(review) do
    %{
      decision: known(review.decision),
      actor: actor(review.actor),
      comment: review.comment,
      decided_at: review.decided_at
    }
  end

  defp revision_view(revision, head_number) do
    %{
      revision: revision.revision_number,
      kind: known(revision.kind),
      live: revision.revision_number == head_number,
      applied_at: revision.applied_at,
      applied_by: actor(revision.applied_by),
      reason: revision.reason,
      summary: revision.summary,
      entry_count: revision.entry_count,
      change_set_id: revision.change_set_id,
      rolls_back_to: revision.rolls_back_to,
      approvals:
        Enum.map(revision.approvals, fn approval ->
          %{
            actor: actor(approval["actor"]),
            comment: approval["comment"],
            decided_at: parse_time(approval["decided_at"])
          }
        end),
      activation_id: revision.activation_id,
      generation: revision.generation
    }
  end

  defp entry_view(entry) do
    %{
      revision: entry.revision_number,
      kind: entry.kind,
      entity_id: entry.entity_id,
      op: known(entry.op),
      paths: entry.paths,
      fields: Document.diff(entry.before, entry.after),
      before: entry.before,
      after: entry.after
    }
  end

  @known Map.new(
           ~w(open in_review applied discarded staged withdrawn create update delete
              approved sent_back baseline change_set rollback legacy_activation),
           &{&1, String.to_atom(&1)}
         )

  defp known(value), do: Map.fetch!(@known, value)

  defp approval_required?(%{"approval_required" => required}), do: required
  defp approval_required?(_policy), do: nil

  defp actor(nil), do: nil
  defp actor(%{"kind" => kind, "id" => id} = doc), do: %{kind: kind, id: id, name: doc["name"]}

  defp parse_time(nil), do: nil

  defp parse_time(value) do
    case DateTime.from_iso8601(value) do
      {:ok, time, _offset} -> time
      _ -> nil
    end
  end
end
