defmodule Cadence.Configuration.Staging do
  @moduledoc """
  Stages changes into the mission's one shared change set.

  Staging validates each op's shape and fields through its kind (no cross-entity checks; those
  run in the preview), records the live values of the paths it touches as its base, and refuses
  a path another author already staged. A re-stage by the same author replaces that author's
  earlier value; the same author staging a delete they already staged adds nothing (fe-setup, qa:
  a double-submitted Archive made two changes), and a stage of only such deletes answers with the
  change that holds them.
  """

  import Ecto.Query

  alias Cadence.Configuration.{ChangeRow, ChangeSetStore, Document, Kinds, OpRow, Translation}
  alias Cadence.Ids
  alias Cadence.Repo

  @actions ~w(create update delete)
  @max_ops 1_000

  @type op_input :: %{
          required(:kind) => String.t(),
          required(:action) => String.t() | atom(),
          optional(:entity_id) => String.t(),
          optional(:document) => map(),
          optional(:changes) => [%{path: String.t(), value: term()}]
        }

  @spec stage(String.t(), String.t(), integer(), map(), map(), [op_input()]) ::
          {:ok, map()} | {:error, term()}
  def stage(organization_id, mission_id, head_revision, actor, attrs, ops)
      when is_list(ops) and length(ops) in 1..@max_ops do
    with {:ok, summary} <- summary(attrs),
         {:ok, prepared} <- prepare_all(organization_id, mission_id, ops) do
      Repo.transaction(fn ->
        organization_id
        |> ChangeSetStore.lock_or_open(mission_id, head_revision, actor)
        |> stage_locked(actor, summary, Map.get(attrs, :source, %{}), prepared)
      end)
    end
  end

  def stage(_organization_id, _mission_id, _head, _actor, _attrs, _ops),
    do: {:error, {:invalid_op, 0, [%{path: "", message: "Stage between 1 and #{@max_ops} ops"}]}}

  defp stage_locked(set, actor, summary, source, prepared) do
    with :ok <- not_frozen(set),
         :ok <- rollback_alone(set, source),
         :ok <- resolve_overlaps(set, actor, prepared),
         :ok <- stage_conflicts(set, prepared) do
      write(set, actor, summary, source, prepared)
    else
      {:error, reason} -> Repo.rollback(reason)
    end
  end

  defp write(set, actor, summary, source, prepared) do
    entity_ids = Enum.map(prepared, & &1.entity_id)
    held = Enum.map(prepared, &staged_delete(&1, set, actor))

    case for {op, nil} <- Enum.zip(prepared, held), do: op do
      [] -> result(set, set.version, hd(held), entity_ids)
      fresh -> insert_change(set, actor, summary, source, fresh, entity_ids)
    end
  end

  # A rollback is its set's only change (DECISIONS #49 review 3/4), decided under the set lock: it
  # stages only into an empty set, and nothing else joins a set that holds one.
  defp rollback_alone(set, source) do
    staged = ChangeSetStore.changes(set.change_set_id)

    cond do
      rollback?(source) and staged != [] -> {:error, :change_set_open}
      Enum.any?(staged, &rollback?(&1.source)) -> {:error, :rollback_in_progress}
      true -> :ok
    end
  end

  defp rollback?(%{"rollback" => %{}}), do: true
  defp rollback?(_source), do: false

  @doc "Prepares unstaged ops for a preview, in pipeline form."
  @spec prepare_ops(String.t(), String.t(), [op_input()]) :: {:ok, [map()]} | {:error, term()}
  def prepare_ops(organization_id, mission_id, ops)
      when is_list(ops) and length(ops) in 1..@max_ops do
    with {:ok, prepared} <- prepare_all(organization_id, mission_id, ops) do
      {:ok,
       prepared
       |> Enum.with_index()
       |> Enum.map(fn {op, index} ->
         Map.merge(op, %{op_id: "unstaged:#{index}", change_id: "unstaged"})
       end)}
    end
  end

  def prepare_ops(_organization_id, _mission_id, _ops),
    do:
      {:error, {:invalid_op, 0, [%{path: "", message: "Preview between 1 and #{@max_ops} ops"}]}}

  defp summary(%{summary: summary}) when is_binary(summary) do
    case String.trim(summary) do
      trimmed when byte_size(trimmed) in 1..500 -> {:ok, trimmed}
      _ -> {:error, {:invalid_op, 0, [%{path: "summary", message: "Enter a short summary"}]}}
    end
  end

  defp summary(_attrs),
    do: {:error, {:invalid_op, 0, [%{path: "summary", message: "Enter a short summary"}]}}

  defp prepare_all(organization_id, mission_id, ops) do
    deleting = deleting(mission_id, ops)
    documents = prefetch_documents(organization_id, mission_id, ops)

    ops
    |> Enum.with_index()
    |> Enum.reduce_while({:ok, []}, fn {op, index}, {:ok, acc} ->
      case prepare(organization_id, mission_id, op, deleting, documents) do
        {:ok, prepared} -> {:cont, {:ok, [prepared | acc]}}
        {:error, errors} when is_list(errors) -> {:halt, {:error, {:invalid_op, index, errors}}}
        # A kind's own refusal with details (e.g. {:in_use, uses}, ux U82) passes through as is.
        {:error, refusal} -> {:halt, {:error, refusal}}
      end
    end)
    |> case do
      {:ok, prepared} -> {:ok, Enum.reverse(prepared)}
      error -> error
    end
  end

  defp prefetch_documents(org, mission, ops) do
    edits =
      for op <- ops,
          {:ok, action} <- [action(op)],
          action in ["update", "delete"],
          is_binary(Map.get(op, :entity_id)),
          {:ok, kind} <- [kind(op)],
          function_exported?(kind, :load_batch, 3),
          do: {kind, op.entity_id}

    edits
    |> Enum.group_by(&elem(&1, 0), &elem(&1, 1))
    |> Map.new(fn {kind, ids} -> {kind, kind.load(org, mission, ids)} end)
  end

  defp prepare(organization_id, mission_id, op, deleting, documents) do
    with {:ok, kind} <- kind(op),
         {:ok, action} <- action(op),
         {:ok, options} <- options(kind, action, Map.get(op, :options)),
         {:ok, prepared} <-
           prepare(kind, action, organization_id, mission_id, op, deleting, documents) do
      {:ok, put_options(prepared, options)}
    end
  end

  defp options(_kind, _action, nil), do: {:ok, %{}}
  defp options(_kind, _action, options) when options == %{}, do: {:ok, %{}}

  defp options(kind, action, %{} = options) do
    if function_exported?(kind, :normalize_options, 2),
      do: kind.normalize_options(action_atom(action), Document.normalize(options)),
      else: {:error, [%{path: "options", message: "This change takes no options"}]}
  end

  defp options(_kind, _action, _options),
    do: {:error, [%{path: "options", message: "Options must be an object"}]}

  defp put_options(prepared, options) when options == %{}, do: prepared

  defp put_options(prepared, options),
    do: %{prepared | payload: Map.put(prepared.payload, "options", options)}

  defp prepare(kind, "create", organization_id, mission_id, op, _deleting, _documents) do
    entity_id = Map.get(op, :entity_id) || Ids.new(kind.id_prefix())

    with {:ok, document} <-
           Translation.document(
             kind,
             organization_id,
             mission_id,
             Document.normalize(op[:document])
           ),
         {:ok, document} <- kind.normalize(:create, entity_id, document),
         entity_id = Map.get(op, :entity_id) || create_entity_id(kind, document, entity_id),
         :ok <- not_live(kind, organization_id, mission_id, entity_id, document) do
      {:ok, op_attrs(kind, "create", entity_id, %{"document" => document}, %{}, [])}
    end
  end

  defp prepare(kind, action, organization_id, mission_id, op, deleting, documents) do
    entity_id = Map.get(op, :entity_id)

    with {:ok, current} <- current(kind, organization_id, mission_id, entity_id, documents),
         :ok <- stage_check(kind, organization_id, mission_id, action, entity_id, deleting) do
      prepare_existing(kind, action, {organization_id, mission_id}, entity_id, current, op)
    end
  end

  # A kind whose ids follow from the document can be asked to create what's already live: its
  # validate/6 sees the live document as `previous` and words the refusal.
  defp not_live(kind, organization_id, mission_id, entity_id, document) do
    with true <- function_exported?(kind, :create_entity_id, 1),
         %{} = live <- Map.get(kind.load(organization_id, mission_id, [entity_id]), entity_id),
         {:error, errors} <-
           kind.validate(organization_id, mission_id, :create, entity_id, live, document) do
      {:error, errors}
    else
      :ok -> {:error, [%{path: "entity_id", message: "This already exists"}]}
      _not_live -> :ok
    end
  end

  # A kind whose ids follow from the document (a limit definition's point and set) names it.
  defp create_entity_id(kind, document, minted) do
    if function_exported?(kind, :create_entity_id, 1),
      do: kind.create_entity_id(document),
      else: minted
  end

  defp prepare_existing(kind, "delete", _tenant, entity_id, current, _op) do
    with {:ok, _} <- kind.normalize(:delete, entity_id, nil) do
      {:ok, op_attrs(kind, "delete", entity_id, %{}, %{"sha256" => Document.sha256(current)}, [])}
    end
  end

  defp prepare_existing(kind, "update", {organization_id, mission_id}, entity_id, current, op) do
    with {:ok, changes} <- changes(op, current),
         {:ok, changes} <-
           Translation.changes(kind, organization_id, mission_id, current, changes),
         {:ok, proposed} <- kind.normalize(:update, entity_id, Document.patch(current, changes)) do
      changes = Enum.map(changes, &%{&1 | "value" => Document.get(proposed, &1["path"])})
      paths = Enum.map(changes, & &1["path"])
      base = %{"values" => Map.new(paths, &{&1, Document.get(current, &1)})}

      {:ok, op_attrs(kind, "update", entity_id, %{"changes" => changes}, base, paths)}
    end
  end

  defp changes(op, current) do
    changes =
      op
      |> Map.get(:changes, [])
      |> Enum.map(&%{"path" => to_string(&1[:path] || &1["path"]), "value" => change_value(&1)})
      |> Enum.reject(&(Document.get(current, &1["path"]) == Document.normalize(&1["value"])))

    case changes do
      [] -> {:error, [%{path: "", message: "Nothing to change"}]}
      changes -> {:ok, changes}
    end
  end

  defp change_value(change), do: Map.get(change, :value, Map.get(change, "value"))

  defp current(_kind, _organization_id, _mission_id, nil, _documents),
    do: {:error, [%{path: "entity_id", message: "Choose what to change"}]}

  defp current(kind, organization_id, mission_id, entity_id, documents) do
    live =
      Map.get_lazy(documents, kind, fn -> kind.load(organization_id, mission_id, [entity_id]) end)

    case Map.get(live, entity_id) do
      nil -> {:error, absent(kind, organization_id, mission_id, entity_id)}
      document -> {:ok, Document.normalize(document)}
    end
  end

  # A kind can refuse an update or delete at stage, before anything is staged
  # (ConfigKind.stage_check/4): e.g. archiving a transport something still uses.
  defp stage_check(kind, organization_id, mission_id, action, entity_id, deleting) do
    if function_exported?(kind, :stage_check, 5),
      do: kind.stage_check(organization_id, mission_id, action_atom(action), entity_id, deleting),
      else: :ok
  end

  # What's being deleted beside an op: this stage's deletes and those already staged in the open
  # set, as {kind, entity_id}. A delete whose only users are going too isn't refused at stage
  # (e.g. a station with its transports); apply checks again against live state, op by op.
  defp deleting(mission_id, ops) do
    staged =
      case ChangeSetStore.active(mission_id) do
        nil -> []
        set -> ChangeSetStore.staged_ops(set.change_set_id)
      end

    for op <- ops ++ staged,
        to_string(Map.get(op, :action)) == "delete",
        is_binary(Map.get(op, :entity_id)),
        into: MapSet.new(),
        do: {to_string(op.kind), op.entity_id}
  end

  # A kind can say why an entity it won't load can't be changed (ConfigKind.absent_errors/3),
  # so the refusal reads right where it was tried instead of "This no longer exists".
  defp absent(kind, organization_id, mission_id, entity_id) do
    if function_exported?(kind, :absent_errors, 3),
      do: kind.absent_errors(organization_id, mission_id, entity_id),
      else: [%{path: "entity_id", message: "This no longer exists"}]
  end

  defp kind(%{kind: kind}) do
    case Kinds.fetch(to_string(kind)) do
      {:ok, module} -> {:ok, module}
      {:error, :unknown_kind} -> {:error, [%{path: "kind", message: "Unknown kind"}]}
    end
  end

  defp kind(_op), do: {:error, [%{path: "kind", message: "Unknown kind"}]}

  defp action(%{action: action}) do
    action = to_string(action)

    if action in @actions,
      do: {:ok, action},
      else: {:error, [%{path: "action", message: "Unknown action"}]}
  end

  defp action(_op), do: {:error, [%{path: "action", message: "Unknown action"}]}

  defp action_atom("create"), do: :create
  defp action_atom("update"), do: :update
  defp action_atom("delete"), do: :delete

  defp op_attrs(kind, action, entity_id, payload, base, paths) do
    %{
      kind: kind.kind(),
      action: action,
      entity_id: entity_id,
      payload: payload,
      base: base,
      touched_paths: paths
    }
  end

  # ConfigKind.stage_conflicts/4 for the kinds this request stages (e.g. a SCID another staged
  # spacecraft holds, S9), against what the set has staged once this author's overlaps are replaced.
  defp stage_conflicts(set, prepared) do
    kinds = prepared |> Enum.map(& &1.kind) |> Enum.uniq() |> Enum.map(&Kinds.fetch!/1)

    case Enum.filter(kinds, &function_exported?(&1, :stage_conflicts, 4)) do
      [] ->
        :ok

      checking ->
        staged = ChangeSetStore.staged_ops(set.change_set_id)
        Enum.find_value(checking, :ok, &kind_conflicts(&1, set, staged, prepared))
    end
  end

  defp kind_conflicts(kind, set, staged, prepared) do
    case kind.stage_conflicts(set.organization_id, set.mission_id, staged, prepared) do
      :ok -> nil
      {:error, _} = error -> error
    end
  end

  defp not_frozen(%{state: "in_review"}), do: {:error, :frozen_in_review}
  defp not_frozen(_set), do: :ok

  # Another author's staged op on the same entity and path blocks the stage. The same author's
  # earlier value for a path is replaced by the new one.
  defp resolve_overlaps(set, actor, prepared) do
    actor_key = actor_key(actor)
    staged = ChangeSetStore.staged_ops(set.change_set_id)

    case Enum.find_value(prepared, &foreign_overlap(&1, staged, actor_key)) do
      nil ->
        Enum.each(prepared, &replace_own(&1, staged, actor_key))
        withdraw_emptied(set, actor_key)
        :ok

      overlap ->
        {:error, {:path_already_staged, overlap}}
    end
  end

  defp foreign_overlap(op, staged, actor_key) do
    Enum.find_value(staged, fn other ->
      with true <- other.author_key != actor_key,
           true <- same_entity?(op, other),
           [path | _] <- overlapping_paths(op, other) do
        %{
          change_id: other.change_id,
          author: other.author,
          kind: op.kind,
          entity_id: op.entity_id,
          path: path,
          value: staged_value(other, path)
        }
      else
        _ -> nil
      end
    end)
  end

  defp replace_own(op, staged, actor_key) do
    for other <- staged,
        other.author_key == actor_key,
        same_entity?(op, other),
        other.action == "update",
        overlapping_paths(op, other) != [] do
      remaining = other.touched_paths -- op.touched_paths
      shrink_op(other, remaining)
    end
  end

  defp shrink_op(%{op_id: op_id}, []), do: Repo.delete_all(op_query(op_id))

  defp shrink_op(other, remaining) do
    changes = Enum.filter(other.payload["changes"], &(&1["path"] in remaining))
    values = Map.take(other.base["values"], remaining)

    Repo.update_all(op_query(other.op_id),
      set: [
        touched_paths: remaining,
        payload: Map.put(other.payload, "changes", changes),
        base: %{"values" => values}
      ]
    )
  end

  defp op_query(op_id), do: where(OpRow, [op], op.op_id == ^op_id)

  defp withdraw_emptied(set, actor_key) do
    ids =
      from(change in ChangeRow,
        as: :change,
        where:
          change.change_set_id == ^set.change_set_id and change.state == "staged" and
            change.author_key == ^actor_key,
        where: not exists(from(op in OpRow, where: op.change_id == parent_as(:change).change_id)),
        select: change.change_id
      )
      |> Repo.all()

    ChangeSetStore.set_change_states(set.change_set_id, ids, "withdrawn")
  end

  defp same_entity?(op, other), do: op.kind == other.kind and op.entity_id == other.entity_id

  defp overlapping_paths(%{action: action}, _other) when action in ["create", "delete"], do: [""]
  defp overlapping_paths(_op, %{action: action}) when action in ["create", "delete"], do: [""]

  defp overlapping_paths(op, other),
    do: Enum.filter(op.touched_paths, &(&1 in other.touched_paths))

  defp staged_value(%{payload: %{"changes" => changes}}, path),
    do: changes |> Enum.find(%{}, &(&1["path"] == path)) |> Map.get("value")

  defp staged_value(_other, _path), do: nil

  # The change holding this author's identical staged delete, if any.
  defp staged_delete(%{action: "delete"} = op, set, actor) do
    key = actor_key(actor)

    set.change_set_id
    |> ChangeSetStore.staged_ops()
    |> Enum.find_value(fn other ->
      if other.author_key == key and other.action == "delete" and same_entity?(op, other),
        do: other.change_id
    end)
  end

  defp staged_delete(_op, _set, _actor), do: nil

  defp result(set, version, change_id, entity_ids),
    do: %{
      change_set_id: set.change_set_id,
      change_id: change_id,
      version: version,
      staged_count: length(ChangeSetStore.changes(set.change_set_id)),
      base_revision: set.base_revision_number,
      entity_ids: entity_ids
    }

  defp insert_change(set, actor, summary, source, prepared, entity_ids) do
    now = DateTime.utc_now()
    change_id = Ids.new("config_change")

    Repo.insert!(%ChangeRow{
      change_id: change_id,
      change_set_id: set.change_set_id,
      organization_id: set.organization_id,
      mission_id: set.mission_id,
      author: actor,
      author_key: actor_key(actor),
      staged_at: now,
      summary: summary,
      source: Document.normalize(source),
      state: "staged",
      position: ChangeSetStore.next_change_position(set.change_set_id)
    })

    rows =
      prepared
      |> Enum.with_index()
      |> Enum.map(fn {op, index} ->
        Map.merge(op, %{
          op_id: Ids.new("config_op"),
          change_id: change_id,
          change_set_id: set.change_set_id,
          organization_id: set.organization_id,
          mission_id: set.mission_id,
          position: index
        })
      end)

    rows |> Enum.chunk_every(500) |> Enum.each(&Repo.insert_all(OpRow, &1))
    updated = ChangeSetStore.update_set(set, [])
    result(set, updated.version, change_id, entity_ids)
  end

  defp actor_key(%{"kind" => kind, "id" => id}), do: kind <> ":" <> id
end
