defmodule Cadence.Configuration.Rollback do
  @moduledoc """
  Rollback planning (docs/apogee/domain/change-sets.md §8, draft-2 note 5): the
  ops that return a mission's governed configuration to revision `target`.

  For every entity with ledger entries in `(target, head]`, the state at the
  target is the `before` of its earliest entry after the target. Each op is the
  kind's own inverse against the **current** state, so it goes through the same
  checks, holds, review, apply and runtime impact as any change, including a
  framing change's generation (#45):

  - created after the target → `delete` (the kind archives it where it can);
  - deleted after the target → `create` with the target document;
  - changed → `update` to the target document;
  - unchanged → no op.

  Refusals: the target must be `r1` or later and before the head (there is no
  ledger before `r1`), and the range must not contain a `legacy_activation`
  revision (its entries are snapshot diffs, not ledger inverses). The error
  names the newest one, which you can roll back to but not past.

  Entities whose current document differs from the ledger's latest `after`
  were changed outside a change set; they're listed in `outside` and become a
  HOLD (`rollback_overwrites_outside_change`) that must be acknowledged.
  """

  alias Cadence.Configuration.{Kinds, Ledger}

  @type plan :: %{
          target: pos_integer(),
          head: non_neg_integer(),
          reverts: [pos_integer()],
          ops: [map()],
          outside: [%{kind: String.t(), entity_id: String.t()}],
          summary: String.t()
        }

  @spec plan(String.t(), String.t(), integer()) :: {:ok, plan()} | {:error, term()}
  def plan(organization_id, mission_id, target) when is_integer(target) do
    head = Ledger.ensure_head(organization_id, mission_id).revision_number

    with :ok <- target_in_range(target, head),
         reverted = revisions_after(mission_id, target, head),
         :ok <- no_legacy(reverted),
         entries = Ledger.entries_between(mission_id, target, head),
         {:ok, ops, outside} <- inverse_ops(organization_id, mission_id, entries) do
      ops = ops |> without_rollout_pins() |> order()

      numbers = reverted |> Enum.map(& &1.revision_number) |> Enum.sort()

      {:ok,
       %{
         target: target,
         head: head,
         reverts: numbers,
         ops: ops,
         outside: outside,
         summary: "Roll back to r#{target} (reverts #{Enum.map_join(numbers, ", ", &"r#{&1}")})"
       }}
    end
  end

  def plan(_organization_id, _mission_id, _target), do: {:error, :invalid_rollback_target}

  @doc "Hold items for staged rollback ops whose entity changed outside a change set."
  @spec holds([map()]) :: [map()]
  def holds(ops) do
    for op <- ops,
        outside = get_in(op, [:source, "rollback", "outside"]) || [],
        %{"kind" => op.kind, "entity_id" => op.entity_id} in outside do
      %{
        code: "rollback_overwrites_outside_change",
        kind: op.kind,
        entity_id: op.entity_id,
        message: "Changed outside a change set since then; rolling back overwrites that change."
      }
    end
  end

  # A profile update rolls its pinned spacecraft to the new profile version (finalize), so when
  # the rollback reverts a profile, a craft's change of just its pin *version* to that same
  # profile is the rollout's to make; staging it too conflicts with the rollout.
  defp without_rollout_pins(ops) do
    profiles =
      for %{kind: "spacecraft_profile", action: "update", entity_id: id} <- ops,
          into: MapSet.new(),
          do: id

    Enum.flat_map(ops, fn
      %{kind: "spacecraft", action: "update", changes: changes} = op ->
        rest =
          Enum.reject(changes, fn change ->
            change.path == "spacecraft_type_version" and
              MapSet.member?(profiles, pinned_profile(op, changes))
          end)

        if rest == [], do: [], else: [%{op | changes: rest}]

      op ->
        [op]
    end)
  end

  # The profile the craft stays pinned to (its id isn't among the changes).
  defp pinned_profile(%{current_profile: id}, changes) do
    if Enum.any?(changes, &(&1.path == "spacecraft_type_id")), do: nil, else: id
  end

  defp pinned_profile(_op, _changes), do: nil

  # Kinds re-derived by finalize from their source (routes from profile routing rules); they
  # refuse staging, and reverting the source reverts them.
  @derived ~w(spacecraft_routes)

  # Dependency order (parents first). The `configuration_kinds` registry isn't one.
  @dependency ~w(ground_station transport spacecraft_profile spacecraft spacecraft_override)

  # Creates parents-first, then updates parents-first, then deletes children-first: a re-created
  # transport follows its station, a re-pin lands before the profile it left is removed.
  defp order(ops) do
    Enum.sort_by(ops, fn op ->
      rank = Enum.find_index(@dependency, &(&1 == op.kind)) || length(@dependency)

      case op.action do
        "create" -> {0, rank}
        "update" -> {1, rank}
        "delete" -> {2, -rank}
      end
    end)
  end

  defp target_in_range(target, head) when target >= 1 and target < head, do: :ok
  defp target_in_range(_target, _head), do: {:error, :invalid_rollback_target}

  defp no_legacy(revisions) do
    case Enum.filter(revisions, &(&1.kind == "legacy_activation")) do
      [] ->
        :ok

      legacy ->
        {:error,
         {:rollback_crosses_legacy, legacy |> Enum.map(& &1.revision_number) |> Enum.max()}}
    end
  end

  defp inverse_ops(organization_id, mission_id, entries) do
    by_entity =
      entries
      |> Enum.reject(&(&1.kind in @derived))
      |> Enum.group_by(&{&1.kind, &1.entity_id})

    by_entity
    |> Enum.group_by(fn {{kind, _id}, _entries} -> kind end)
    |> Enum.reduce_while({:ok, [], []}, fn {kind, entities}, {:ok, ops, outside} ->
      case kind_ops(organization_id, mission_id, kind, entities) do
        {:ok, kind_ops, kind_outside} -> {:cont, {:ok, ops ++ kind_ops, outside ++ kind_outside}}
        {:error, _reason} = error -> {:halt, error}
      end
    end)
  end

  defp kind_ops(organization_id, mission_id, kind, entities) do
    with {:ok, module} <- unknown_kind(Kinds.fetch(kind), kind) do
      ids = Enum.map(entities, fn {{_kind, id}, _entries} -> id end)
      {ops, outside} = kind_inverse(kind, entities, module.load(organization_id, mission_id, ids))
      {:ok, ops, outside}
    end
  end

  defp unknown_kind({:ok, module}, _kind), do: {:ok, module}
  defp unknown_kind({:error, :unknown_kind}, kind), do: {:error, {:rollback_unknown_kind, kind}}

  defp kind_inverse(kind, entities, current) do
    Enum.reduce(entities, {[], []}, fn {{_kind, id}, entity_entries}, {ops, outside} ->
      sorted = Enum.sort_by(entity_entries, &{&1.revision_number, &1.position})
      target_doc = List.first(sorted).before
      ledger_doc = List.last(sorted).after
      now = Map.get(current, id)

      ops = ops ++ op(kind, id, target_doc, now)
      outside = if now != ledger_doc, do: outside ++ [%{kind: kind, entity_id: id}], else: outside
      {ops, outside}
    end)
  end

  defp op(_kind, _id, same, same), do: []
  defp op(_kind, _id, nil, nil), do: []
  defp op(kind, id, nil, _current), do: [%{kind: kind, action: "delete", entity_id: id}]

  defp op(kind, id, target, nil),
    do: [%{kind: kind, action: "create", entity_id: id, document: target}]

  defp op(kind, id, target, current) do
    changes =
      (Map.keys(target) ++ Map.keys(current))
      |> Enum.uniq()
      |> Enum.reject(&(Map.get(target, &1) == Map.get(current, &1)))
      |> Enum.sort()
      |> Enum.map(&%{path: &1, value: Map.get(target, &1)})

    [
      %{kind: kind, action: "update", entity_id: id, changes: changes}
      |> maybe_profile(kind, current)
    ]
  end

  defp maybe_profile(op, "spacecraft", current),
    do: Map.put(op, :current_profile, current["spacecraft_type_id"])

  defp maybe_profile(op, _kind, _current), do: op

  # Every revision in (target, head], paging the ledger (200 per page).
  defp revisions_after(mission_id, target, head) do
    Stream.unfold(head + 1, fn
      before when before <= target + 1 ->
        nil

      before ->
        page =
          mission_id
          |> Ledger.list_revisions(limit: 200, before: before)
          |> Enum.filter(&(&1.revision_number > target))

        case page do
          [] -> nil
          rows -> {rows, rows |> Enum.map(& &1.revision_number) |> Enum.min()}
        end
    end)
    |> Enum.flat_map(& &1)
  end
end
