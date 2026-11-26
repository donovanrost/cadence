defmodule Cadence.Configuration.Pipeline do
  @moduledoc """
  Applies staged ops, in order, to the current database state. It is the shared core of
  `Preview` (inside a rolled-back transaction) and of an apply (inside the committing one).

  For each op it loads the live document, detects conflicts by value against the op's base,
  computes the proposed document, validates the transition through its kind and writes it.
  Validation problems are collected so a preview reports all of them. The first failed write
  stops the run, because Postgres aborts the transaction after any SQL error.

  Must run inside a transaction.
  """

  alias Cadence.Configuration.{ActorNames, Document, Kinds, Ledger}
  alias Cadence.SpacecraftTypeStore

  @type op :: %{
          required(:op_id) => String.t(),
          required(:change_id) => String.t(),
          required(:kind) => String.t(),
          required(:entity_id) => String.t(),
          required(:action) => String.t(),
          required(:payload) => map(),
          required(:base) => map(),
          required(:touched_paths) => [String.t()]
        }

  @type result :: %{
          entries: [map()],
          conflicts: [map()],
          errors: [map()],
          effects: [map()],
          diffs: [map()],
          impacts: MapSet.t(),
          halted?: boolean()
        }

  @doc """
  Runs `ops`. Option `:actor`: who applies them (the applier's `%{"kind", "id", ...}`), handed to
  each kind's `write/7` and `effect/7` as `options[:actor]`, so a write records who made it (a
  retire's `retired_by`, an archive's actor, the save trail). A preview passes none.
  """
  @spec run(String.t(), String.t(), integer(), [op()], keyword()) :: result()
  def run(organization_id, mission_id, base_revision, ops, opts \\ []) do
    ops = with_actor(ops, Keyword.get(opts, :actor))

    # Kinds re-read the same profile versions once per spacecraft; one read each for the run.
    SpacecraftTypeStore.with_version_memo(fn ->
      run_ops(organization_id, mission_id, base_revision, ops)
    end)
  end

  # In memory only: the staged payload keeps its own options.
  defp with_actor(ops, nil), do: ops

  defp with_actor(ops, %{} = actor) do
    Enum.map(ops, fn op ->
      options = op.payload |> Map.get("options", %{}) |> Map.put(:actor, actor)
      %{op | payload: Map.put(op.payload, "options", options)}
    end)
  end

  defp run_ops(organization_id, mission_id, base_revision, ops) do
    initial = %{
      entries: [],
      conflicts: [],
      errors: [],
      effects: [],
      diffs: [],
      impacts: MapSet.new(),
      halted?: false
    }

    ops
    |> Enum.chunk_by(&operation_group/1)
    |> Enum.reduce_while(initial, fn group, acc ->
      run_group(organization_id, mission_id, base_revision, group, acc)
    end)
    |> finalize(organization_id, mission_id)
    |> holds(organization_id, mission_id)
    |> Map.update!(:entries, &Enum.reverse/1)
    |> Map.update!(:conflicts, &Enum.reverse/1)
    |> Map.update!(:errors, &Enum.reverse/1)
    |> Map.update!(:effects, &Enum.reverse/1)
    |> Map.update!(:diffs, &Enum.reverse/1)
  end

  defp operation_group(op) do
    kind = Kinds.fetch!(op.kind)

    if function_exported?(kind, :batchable?, 1) and
         not function_exported?(kind, :effect, 7) and kind.batchable?(op),
       do: {:batch, kind},
       else: :single
  end

  defp run_group(org, mission, base, [first | _] = ops, acc) do
    case operation_group(first) do
      :single ->
        run_steps(ops, acc, &step(org, mission, base, &1, &2))

      {:batch, kind} ->
        run_steps(distinct_groups(ops), acc, &step_batch(kind, org, mission, base, &1, &2))
    end
  end

  defp run_steps(ops, acc, step) do
    result =
      Enum.reduce_while(ops, acc, fn op, acc ->
        case step.(op, acc) do
          {:halt, acc} -> {:halt, %{acc | halted?: true}}
          acc -> {:cont, acc}
        end
      end)

    if result.halted?, do: {:halt, result}, else: {:cont, result}
  end

  # Repeated edits to an entity must see the result of the previous edit.
  defp distinct_groups(ops) do
    Enum.chunk_while(
      ops,
      {[], MapSet.new()},
      fn op, {batch, ids} ->
        if MapSet.member?(ids, op.entity_id) do
          {:cont, Enum.reverse(batch), {[op], MapSet.new([op.entity_id])}}
        else
          {:cont, {[op | batch], MapSet.put(ids, op.entity_id)}}
        end
      end,
      fn {batch, _ids} -> {:cont, Enum.reverse(batch), nil} end
    )
  end

  defp step_batch(kind, org, mission, base, ops, acc) do
    {documents, context} = kind.load_batch(org, mission, Enum.map(ops, & &1.entity_id))

    {transitions, acc} =
      Enum.reduce(ops, {[], acc}, fn op, {transitions, acc} ->
        current = Document.normalize(Map.get(documents, op.entity_id))

        case transition(mission, base, op, current) do
          {:ok, change} ->
            acc = Map.update!(acc, :diffs, &[diff(op, current, change.proposed) | &1])
            {[change | transitions], acc}

          {:conflict, item} ->
            {transitions, Map.update!(acc, :conflicts, &[item | &1])}
        end
      end)

    write_batch(Enum.reverse(transitions), kind, org, mission, context, acc)
  end

  defp write_batch([], _kind, _org, _mission, _context, acc), do: acc

  defp write_batch(transitions, kind, org, mission, context, acc) do
    case kind.write_batch(org, mission, transitions, context) do
      {:ok, outcomes} ->
        Enum.zip(transitions, outcomes)
        |> Enum.reduce(acc, fn
          {change, {:ok, stored}}, acc ->
            record_entry(acc, kind, change, stored, [])

          {%{op: op}, {:invalid, fields}}, acc ->
            Map.update!(acc, :errors, &[error(op, fields) | &1])
        end)

      {:error, id, reason} ->
        %{op: op} = Enum.find(transitions, hd(transitions), &(&1.id == id))
        write_error(acc, op, reason)

      {:error, reason} ->
        %{op: op} = hd(transitions)
        write_error(acc, op, reason)
    end
  end

  # Derived kinds run only when every op applied cleanly; otherwise there's nothing coherent
  # to derive from.
  defp finalize(%{halted?: false, errors: [], conflicts: []} = acc, organization_id, mission_id) do
    Kinds.all()
    |> Enum.filter(&function_exported?(&1, :finalize, 3))
    |> Enum.reduce(acc, fn kind, acc ->
      case kind.finalize(organization_id, mission_id, Enum.reverse(acc.entries)) do
        {:ok, entries, impacts} ->
          %{
            acc
            | entries: Enum.reverse(entries, acc.entries),
              impacts: Enum.into(impacts, acc.impacts)
          }

        {:error, field_errors} ->
          error = %{
            op_id: nil,
            change_id: nil,
            kind: kind.kind(),
            entity_id: nil,
            errors: field_errors
          }

          Map.update!(acc, :errors, &[error | &1])
      end
    end)
  end

  defp finalize(acc, _organization_id, _mission_id), do: acc

  defp holds(%{halted?: false, errors: [], conflicts: []} = acc, organization_id, mission_id) do
    entries = Enum.reverse(acc.entries)

    holds =
      Kinds.all()
      |> Enum.filter(&function_exported?(&1, :holds, 3))
      |> Enum.flat_map(& &1.holds(organization_id, mission_id, entries))

    Map.put(acc, :holds, holds)
  end

  defp holds(acc, _organization_id, _mission_id), do: Map.put(acc, :holds, [])

  @doc "Computes the proposed document for an op from the live document."
  @spec propose(String.t(), Document.t() | nil, map()) ::
          {:ok, Document.t() | nil} | {:conflict, atom()}
  def propose("create", nil, %{"document" => document}), do: {:ok, document}
  def propose("create", _current, _payload), do: {:conflict, :entity_exists}
  def propose(_action, nil, _payload), do: {:conflict, :entity_gone}

  def propose("update", current, %{"changes" => changes}),
    do: {:ok, Document.patch(current, changes)}

  def propose("delete", _current, _payload), do: {:ok, nil}

  defp step(organization_id, mission_id, base_revision, op, acc) do
    kind = Kinds.fetch!(op.kind)
    current = load_current(kind, organization_id, mission_id, op.entity_id)

    case transition(mission_id, base_revision, op, current) do
      {:ok, change} ->
        acc
        |> Map.update!(:diffs, &[diff(op, current, change.proposed) | &1])
        |> add_effect(
          kind,
          organization_id,
          mission_id,
          change.action,
          op,
          current,
          change.proposed
        )
        |> validate_and_write(kind, organization_id, mission_id, change)

      {:conflict, item} ->
        Map.update!(acc, :conflicts, &[item | &1])
    end
  end

  defp transition(mission_id, base_revision, op, current) do
    with {:ok, proposed} <- propose(op.action, current, op.payload),
         [] <- value_conflicts(mission_id, base_revision, op, current) do
      {:ok,
       %{
         action: action_atom(op.action),
         id: op.entity_id,
         op: op,
         current: current,
         proposed: proposed
       }}
    else
      {:conflict, reason} ->
        {:conflict, conflict(op, reason, [])}

      conflicts when is_list(conflicts) ->
        {:conflict, conflict(op, :value_changed, conflicts)}
    end
  end

  defp validate_and_write(acc, kind, org, mission_id, change) do
    case kind.validate(org, mission_id, change.action, change.id, change.current, change.proposed) do
      :ok ->
        write(acc, kind, org, mission_id, change)

      {:error, field_errors} ->
        Map.update!(acc, :errors, &[error(change.op, field_errors) | &1])
    end
  end

  defp write(
         acc,
         kind,
         org,
         mission_id,
         %{action: action, id: id, op: op, current: current, proposed: proposed} = change
       ) do
    case kind.write(org, mission_id, action, id, current, proposed, options(op)) do
      {:ok, stored, extra} -> record_entry(acc, kind, change, stored, extra)
      {:error, reason} -> write_error(acc, op, reason)
    end
  end

  defp record_entry(acc, kind, change, stored, extra) do
    entry = %{
      kind: change.op.kind,
      entity_id: change.id,
      op: change.action,
      previous: change.current,
      proposed: Document.normalize(stored)
    }

    acc
    |> Map.update!(:entries, &(Enum.reverse(extra, [entry]) ++ &1))
    |> Map.update!(
      :impacts,
      &MapSet.put(&1, kind.runtime_impact(change.action, change.current, change.proposed))
    )
  end

  # A store refusal the kind can word (e.g. a claimed listen port) stays on the field.
  defp write_error(acc, op, [%{path: _, message: _} | _] = fields),
    do: {:halt, Map.update!(acc, :errors, &[error(op, fields) | &1])}

  defp write_error(acc, op, reason),
    do: write_error(acc, op, [%{path: "", message: "Could not save: " <> describe(reason)}])

  defp add_effect(acc, kind, org, mission_id, action, op, current, proposed) do
    if function_exported?(kind, :effect, 7) do
      case kind.effect(org, mission_id, action, op.entity_id, current, proposed, options(op)) do
        nil -> acc
        effect -> Map.update!(acc, :effects, &[Map.put(effect, :op_id, op.op_id) | &1])
      end
    else
      acc
    end
  end

  defp action_atom("create"), do: :create
  defp action_atom("update"), do: :update
  defp action_atom("delete"), do: :delete

  defp options(op), do: Map.get(op.payload, "options", %{})

  defp load_current(kind, organization_id, mission_id, entity_id) do
    organization_id
    |> kind.load(mission_id, [entity_id])
    |> Map.get(entity_id)
    |> Document.normalize()
  end

  defp value_conflicts(_mission_id, _base_revision, %{action: "create"}, _current), do: []

  defp value_conflicts(mission_id, base_revision, op, current) do
    values = Map.get(op.base, "values", %{})

    stale =
      for path <- op.touched_paths,
          Map.get(values, path) != Document.get(current, path),
          do: path

    stale = stale_document(op, current, stale)

    case stale do
      [] ->
        []

      paths ->
        changed_in = changed_in(mission_id, op, base_revision, paths)
        actors = mission_id |> changed_by(changed_in) |> ActorNames.named(mission_id)

        Enum.map(paths, fn path ->
          revision = Map.get(changed_in, path, :outside)

          %{
            path: path,
            base: Map.get(values, path),
            live: Document.get(current, path),
            staged: staged_value(op, path),
            changed_in: revision,
            # Who applied that revision (ux: "changed in r9 by Mira K."); nil when outside.
            changed_by: Map.get(actors, revision)
          }
        end)
    end
  end

  # A delete conflicts when anything about the entity changed since it was staged.
  defp stale_document(%{action: "delete", base: %{"sha256" => sha}}, current, stale) do
    if Document.sha256(current) == sha, do: stale, else: Enum.uniq(["" | stale])
  end

  defp stale_document(_op, _current, stale), do: stale

  defp changed_in(mission_id, op, base_revision, paths) do
    mission_id
    |> Ledger.entity_entries(op.kind, op.entity_id)
    |> Enum.filter(&(&1.revision_number > base_revision))
    |> Enum.reverse()
    |> Enum.reduce(%{}, &record_changed_in(&1, &2, paths))
  end

  defp changed_by(mission_id, changed_in) do
    changed_in
    |> Map.values()
    |> Enum.uniq()
    |> Map.new(fn number ->
      case Ledger.fetch_revision(mission_id, number) do
        {:ok, revision} -> {number, actor_name(revision.applied_by)}
        _missing -> {number, nil}
      end
    end)
  end

  defp actor_name(%{"name" => name} = actor),
    do: %{kind: actor["kind"], id: actor["id"], name: name}

  defp actor_name(_actor), do: nil

  defp record_changed_in(entry, acc, paths) do
    paths
    |> Enum.filter(&(&1 in entry.paths or &1 == ""))
    |> Enum.reduce(acc, &Map.put_new(&2, &1, entry.revision_number))
  end

  defp staged_value(%{payload: %{"changes" => changes}}, path) do
    changes
    |> Enum.find(%{}, &(&1["path"] == path))
    |> Map.get("value")
  end

  defp staged_value(_op, _path), do: nil

  defp diff(op, current, proposed) do
    %{
      op_id: op.op_id,
      change_id: op.change_id,
      kind: op.kind,
      entity_id: op.entity_id,
      action: op.action,
      fields: Document.diff(current, proposed)
    }
  end

  defp conflict(op, reason, paths) do
    %{
      op_id: op.op_id,
      change_id: op.change_id,
      kind: op.kind,
      entity_id: op.entity_id,
      reason: reason,
      paths: paths
    }
  end

  defp error(op, field_errors) do
    %{
      op_id: op.op_id,
      change_id: op.change_id,
      kind: op.kind,
      entity_id: op.entity_id,
      errors: field_errors
    }
  end

  defp describe(%Ecto.Changeset{} = changeset) do
    changeset
    |> Ecto.Changeset.traverse_errors(fn {message, _opts} -> message end)
    |> Enum.map_join("; ", fn {field, messages} -> "#{field} #{Enum.join(messages, ", ")}" end)
  end

  defp describe(reason) when is_atom(reason),
    do: reason |> Atom.to_string() |> String.replace("_", " ")

  defp describe(reason), do: inspect(reason)
end
