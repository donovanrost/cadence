defmodule Cadence.Reads.CatalogDiff do
  @moduledoc """
  What a catalog revision changes against the one before it (Catalog C3, DECISIONS #9 v1:
  added / changed / removed / breaking from the two revisions alone, no impact on queued
  commands, limits or dashboards).

  Declarations are matched by `{kind, qualified_name}` (their ids are content hashes). Changes
  roll up to what operators know: a **command** includes its arguments, argument types,
  encoding and verifiers; a **telemetry** item is a parameter with its type and calibrator
  (anything it references, or that's named under it, that isn't itself a command or
  parameter). Declarations no command
  or parameter references (containers, units, monitoring policies, …) are listed as `other`.

  Breaking (v1):
  - a command or parameter removed;
  - a command whose argument, argument type or encoding changed (requests built against the
    old shape stop encoding);
  - a parameter whose type changed (its decoding changes).

  Additions, descriptions, display names, verifiers, calibrators and units aren't breaking.
  """

  alias Cadence.Repo

  @items ~w(command parameter)
  @breaking_command_parts ~w(command_argument command_argument_type command_encoding)
  @breaking_parameter_parts ~w(parameter_type)
  @ignored ~w(provenance semantic_id expected_fingerprint extensions)
  @max_changes 500
  @max_depth 4

  @query """
  SELECT d.value
  FROM mission_model_revisions AS r,
       jsonb_each(r.revision_document->'value'->'declarations') AS d
  WHERE r.organization_id = $1 AND r.mission_id = $2 AND r.revision_id = $3
  """

  @doc "`{command_count, telemetry_count}` of a mission-model revision, or `{nil, nil}`."
  @spec counts(binary(), binary(), binary() | nil) :: {integer() | nil, integer() | nil}
  def counts(_organization_id, _mission_id, nil), do: {nil, nil}

  def counts(organization_id, mission_id, revision_id) do
    case declarations(organization_id, mission_id, revision_id) do
      {:ok, decls} -> {count(decls, "command"), count(decls, "parameter")}
      _unavailable -> {nil, nil}
    end
  end

  @doc "The C3 diff between two mission-model revisions, or nil when either can't be read."
  @spec diff(binary(), binary(), binary() | nil, binary() | nil) :: map() | nil
  def diff(_organization_id, _mission_id, nil, _after), do: nil
  def diff(_organization_id, _mission_id, _before, nil), do: nil

  def diff(organization_id, mission_id, before_id, after_id) do
    with {:ok, before} <- declarations(organization_id, mission_id, before_id),
         {:ok, after_decls} <- declarations(organization_id, mission_id, after_id) do
      compare(before, after_decls)
    else
      _unavailable -> nil
    end
  end

  @doc "Pure comparison of two declaration maps (`%{{kind, qualified_name} => decl}`)."
  @spec compare(map(), map()) :: map()
  def compare(before, after_decls) do
    item_changes =
      for key <- items(before, after_decls),
          change = item_change(key, before, after_decls),
          change != nil,
          do: change

    owned = owned(before) |> MapSet.union(owned(after_decls))

    other_changes =
      for key <- Enum.uniq(Map.keys(before) ++ Map.keys(after_decls)),
          not item?(key) and not MapSet.member?(owned, key),
          change = other_change(key, before, after_decls),
          change != nil,
          do: change

    changes = item_changes ++ other_changes

    %{
      summary: %{
        commands: kind_summary("command", before, after_decls, item_changes),
        telemetry: kind_summary("telemetry", before, after_decls, item_changes),
        unchanged:
          count(before, "command") + count(before, "parameter") -
            Enum.count(item_changes, &(&1.op != "added")),
        total_before: count(before, "command") + count(before, "parameter"),
        breaking: Enum.count(changes, & &1.breaking)
      },
      changes:
        changes |> Enum.sort_by(&{!&1.breaking, &1.kind, &1.name}) |> Enum.take(@max_changes),
      truncated: length(changes) > @max_changes
    }
  end

  defp declarations(organization_id, mission_id, revision_id) do
    case Repo.query(@query, [organization_id, mission_id, revision_id]) do
      {:ok, %{rows: rows}} ->
        {:ok,
         for(
           [decl] <- rows,
           is_map(decl),
           into: %{},
           do: {{decl["kind"], decl["qualified_name"]}, decl}
         )}

      {:error, _reason} ->
        {:error, :declarations_unavailable}
    end
  end

  defp count(decls, kind), do: Enum.count(decls, fn {{k, _name}, _decl} -> k == kind end)

  defp item?({kind, _name}), do: kind in @items

  defp items(before, after_decls),
    do: (Map.keys(before) ++ Map.keys(after_decls)) |> Enum.filter(&item?/1) |> Enum.uniq()

  defp item_change({kind, name} = key, before, after_decls) do
    case {Map.fetch(before, key), Map.fetch(after_decls, key)} do
      {:error, {:ok, _decl}} ->
        change("added", kind, name, nil, false)

      {{:ok, _decl}, :error} ->
        change("removed", kind, name, nil, true)

      {{:ok, _old}, {:ok, _new}} ->
        old = closure(key, before)
        new = closure(key, after_decls)

        if old == new do
          nil
        else
          parts = changed_parts(old, new)

          change(
            "changed",
            kind,
            name,
            describe(name, parts, old, new),
            breaking?(kind, parts)
          )
        end
    end
  end

  defp other_change({kind, name} = key, before, after_decls) do
    case {Map.get(before, key), Map.get(after_decls, key)} do
      {nil, _new} -> %{op: "added", kind: "other", name: name, change: kind, breaking: false}
      {_old, nil} -> %{op: "removed", kind: "other", name: name, change: kind, breaking: false}
      {old, new} -> other_changed(kind, name, normalize(old), normalize(new))
    end
  end

  defp other_changed(_kind, _name, same, same), do: nil

  defp other_changed(kind, name, old, new),
    do: %{
      op: "changed",
      kind: "other",
      name: name,
      change: "#{kind} " <> leaf_diff(old, new),
      breaking: false
    }

  defp change(op, kind, name, text, breaking),
    do: %{
      op: op,
      kind: if(kind == "command", do: "command", else: "telemetry"),
      name: name,
      change: text,
      breaking: breaking
    }

  defp kind_summary(label, before, after_decls, changes) do
    kind = if label == "command", do: "command", else: "parameter"
    mine = Enum.filter(changes, &(&1.kind == label))

    %{
      before: count(before, kind),
      after: count(after_decls, kind),
      added: Enum.count(mine, &(&1.op == "added")),
      changed: Enum.count(mine, &(&1.op == "changed")),
      removed: Enum.count(mine, &(&1.op == "removed"))
    }
  end

  # The item, what it references (not other items) and what's named under it (verifiers,
  # arguments: `/commands/X/...`), normalized: `%{key => decl}`.
  defp closure({_kind, name} = key, decls) do
    nested =
      for {{_k, part_name} = part, _decl} <- decls,
          not item?(part),
          is_binary(part_name) and is_binary(name),
          String.starts_with?(part_name, name <> "/"),
          do: part

    walk([key | nested], decls, %{}, @max_depth)
  end

  defp walk(_keys, _decls, acc, 0), do: acc

  defp walk(keys, decls, acc, depth) do
    found =
      for key <- keys,
          not Map.has_key?(acc, key),
          decl = Map.get(decls, key),
          decl != nil,
          into: %{},
          do: {key, normalize(decl)}

    next =
      for {_key, decl} <- found,
          ref <- decl["references"] || [],
          ref_key = {ref["expected_kind"], ref["resolved_qualified_name"]},
          not item?(ref_key),
          do: ref_key

    acc = Map.merge(acc, found)
    if next == [], do: acc, else: walk(next, decls, acc, depth - 1)
  end

  defp owned(decls) do
    for {key, _decl} <- decls,
        item?(key),
        {part, _decl} <- closure(key, decls),
        part != key,
        into: MapSet.new(),
        do: part
  end

  defp normalize(decl) do
    decl
    |> Map.drop(@ignored)
    |> Map.update("references", [], fn refs ->
      Enum.map(refs || [], &Map.drop(&1, ["resolved_id", "provenance"]))
    end)
  end

  defp changed_parts(old, new) do
    (Map.keys(old) ++ Map.keys(new))
    |> Enum.uniq()
    |> Enum.reject(&(Map.get(old, &1) == Map.get(new, &1)))
  end

  defp breaking?("command", parts),
    do: Enum.any?(parts, fn {kind, _name} -> kind in @breaking_command_parts end)

  defp breaking?("parameter", parts),
    do: Enum.any?(parts, fn {kind, _name} -> kind in @breaking_parameter_parts end)

  # "arguments/duration: definition.size_in_bits 16 → 32" for the first changed part.
  defp describe(item_name, [{_kind, part_name} = part | rest], old, new) do
    label =
      case String.replace_prefix(part_name || "", item_name <> "/", "") do
        ^part_name -> ""
        relative -> relative <> ": "
      end

    text =
      case {Map.get(old, part), Map.get(new, part)} do
        {nil, _added} -> "added"
        {_removed, nil} -> "removed"
        {before, after_decl} -> leaf_diff(before, after_decl)
      end

    more = if rest == [], do: "", else: " (+#{length(rest)} more)"
    label <> text <> more
  end

  defp describe(_item_name, [], _old, _new), do: nil

  defp leaf_diff(old, new) do
    a = flatten(old, "")
    b = flatten(new, "")

    case (Map.keys(a) ++ Map.keys(b))
         |> Enum.uniq()
         |> Enum.sort()
         |> Enum.reject(&(a[&1] == b[&1])) do
      [] ->
        "changed"

      [path | _rest] ->
        "#{String.replace_prefix(path, "definition.", "")} #{show(a[path])} → #{show(b[path])}"
    end
  end

  defp flatten(%{} = map, prefix) do
    Enum.reduce(map, %{}, fn {key, value}, acc ->
      Map.merge(acc, flatten(value, if(prefix == "", do: key, else: prefix <> "." <> key)))
    end)
  end

  defp flatten(value, prefix), do: %{prefix => value}

  defp show(nil), do: "none"
  defp show(value) when is_binary(value), do: value
  defp show(value), do: Jason.encode!(value)
end
