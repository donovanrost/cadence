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
    |> Enum.reduce_while(initial, fn op, acc ->
      case step(organization_id, mission_id, base_revision, op, acc) do
        {:halt, acc} -> {:halt, %{acc | halted?: true}}
        acc -> {:cont, acc}
      end
    end)
    |> finalize(organization_id, mission_id)
    |> holds(organization_id, mission_id)
    |> Map.update!(:entries, &Enum.reverse/1)
    |> Map.update!(:conflicts, &Enum.reverse/1)
    |> Map.update!(:errors, &Enum.reverse/1)
    |> Map.update!(:effects, &Enum.reverse/1)
    |> Map.update!(:diffs, &Enum.reverse/1)
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
    action = action_atom(op.action)
    current = load_current(kind, organization_id, mission_id, op.entity_id)

    with {:ok, proposed} <- propose(op.action, current, op.payload),
         [] <- value_conflicts(mission_id, base_revision, op, current) do
      acc
      |> Map.update!(:diffs, &[diff(op, current, proposed) | &1])
      |> add_effect(kind, organization_id, mission_id, action, op, current, proposed)
      |> validate_and_write(kind, organization_id, mission_id, action, op, current, proposed)
    else
      {:conflict, reason} ->
        Map.update!(acc, :conflicts, &[conflict(op, reason, []) | &1])

      conflicts when is_list(conflicts) ->
        Map.update!(acc, :conflicts, &[conflict(op, :value_changed, conflicts) | &1])
    end
  end

  defp validate_and_write(acc, kind, org, mission_id, action, op, current, proposed) do
    case kind.validate(org, mission_id, action, op.entity_id, current, proposed) do
      :ok ->
        write(acc, kind, org, mission_id, action, op, current, proposed)

      {:error, field_errors} ->
        Map.update!(acc, :errors, &[error(op, field_errors) | &1])
    end
  end

  defp write(acc, kind, org, mission_id, action, op, current, proposed) do
    case kind.write(org, mission_id, action, op.entity_id, current, proposed, options(op)) do
      {:ok, stored, extra} ->
        entry = %{
          kind: op.kind,
          entity_id: op.entity_id,
          op: action,
          previous: current,
          proposed: Document.normalize(stored)
        }

        acc
        |> Map.update!(:entries, &(Enum.reverse(extra, [entry]) ++ &1))
        |> Map.update!(:impacts, &MapSet.put(&1, kind.runtime_impact(action, current, proposed)))

      # A store refusal the kind can word as field errors (e.g. a listen port another mission
      # holds) reads like validation, on the field.
      {:error, [%{path: _, message: _} | _] = field_errors} ->
        {:halt, Map.update!(acc, :errors, &[error(op, field_errors) | &1])}

      {:error, reason} ->
        {:halt,
         Map.update!(
           acc,
           :errors,
           &[error(op, [%{path: "", message: "Could not save: " <> describe(reason)}]) | &1]
         )}
    end
  end

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
