defmodule Cadence.Governance.BindingSetStorage do
  @moduledoc """
  A binding-set version stored as content-addressed artifacts plus a membership list (#447,
  phase 4a; `config-materialization-model.md` §4 step 1), instead of the craft × packet rows.

  **Compress.** The instance and rule rows a version would store are grouped by their source
  endpoint. Within a group, the endpoint is replaced by `@placeholder` in exactly the four fields
  that carry it (api-ops): an instance's `capability_instance_id` and `source_endpoint_ref`, a
  rule's `binding_rule_id` and `capability_instance_id` (it names its instance), and the rule's
  `selector_scope` endpoint. What's left is the group's template. Its artifact is the canonical
  term hash of the template, so craft with the same configuration share one artifact. Mission-
  scoped instances (no endpoint) are one more group, stored as-is, with a null-endpoint member.

  **Refusals, never guesses.** Compression refuses when the endpoint still appears anywhere else in
  a group's rows, when `@placeholder` already appears anywhere, or when a rule names an unknown
  instance. The caller then stores today's rows, and says so (`Governance`).

  **Expand** is the exact inverse: each member's template with the placeholder put back in the
  same four fields gives the same row structs the rows form reads, which `Governance` hydrates
  through its one path. The template goes through the storage codec (`codec/1`) before it's
  compared, because jsonb is what a read gets back.
  """

  import Ecto.Query

  alias Cadence.Governance.{BindingRuleRow, BindingSetRow, CapabilityInstanceRow}
  alias Cadence.Platform.ContentHash
  alias Cadence.Repo

  @placeholder "$source_endpoint_ref$"

  @instance_fields ~w(capability_instance_id family_key target_scope source_endpoint_ref
    lifecycle_state capability_config_type capability_config_document)a
  @rule_fields ~w(binding_rule_id capability_instance_id handler_key selector_scope
    selector_match priority fanout_mode)a
  @map_fields ~w(capability_config_document selector_scope selector_match)a

  @type artifact :: %{sha: binary(), template: map()}
  @type member :: %{sha: binary(), source_endpoint_ref: binary() | nil}

  ## Pure: compress, expand, the codec

  @doc """
  The rows a version stores, as a read gets them back: map columns through the storage codec, and
  no row ids or timestamps. Both forms are compared in this shape.
  """
  @spec as_stored([CapabilityInstanceRow.t()], [BindingRuleRow.t()]) ::
          {[map()], [map()]}
  def as_stored(instances, rules) do
    {instances
     |> Enum.map(&fields(&1, @instance_fields))
     |> Enum.sort_by(& &1.capability_instance_id),
     rules |> Enum.map(&fields(&1, @rule_fields)) |> Enum.sort_by(& &1.binding_rule_id)}
  end

  @doc "`{:ok, artifacts, members}`, or `{:error, reason}` when the rows can't be compressed exactly."
  @spec compress([map()], [map()]) ::
          {:ok, [artifact()], [member()]} | {:error, term()}
  def compress(instances, rules) do
    endpoint_by_instance =
      Map.new(instances, &{&1.capability_instance_id, &1.source_endpoint_ref})

    with :ok <- placeholder_absent(instances ++ rules),
         {:ok, rule_groups} <- group_rules(rules, endpoint_by_instance),
         {:ok, artifacts, members} <- templates(instances, rule_groups) do
      {:ok, Enum.map(artifacts, fn {sha, template} -> %{sha: sha, template: template} end),
       Enum.reverse(members)}
    end
  end

  defp templates(instances, rule_groups) do
    instances
    |> Enum.group_by(& &1.source_endpoint_ref)
    |> Enum.sort_by(fn {endpoint, _rows} -> endpoint || "" end)
    |> Enum.reduce_while({:ok, %{}, []}, fn {endpoint, group}, {:ok, artifacts, members} ->
      case template(endpoint, group, Map.get(rule_groups, endpoint, [])) do
        {:ok, template} ->
          sha = ContentHash.term_sha256(template)
          member = %{sha: sha, source_endpoint_ref: endpoint}
          {:cont, {:ok, Map.put(artifacts, sha, template), [member | members]}}

        {:error, reason} ->
          {:halt, {:error, reason}}
      end
    end)
  end

  @doc "The rows `members` stand for, from their artifacts' templates (by sha)."
  @spec expand(%{binary() => map()}, [member()]) ::
          {:ok, {[CapabilityInstanceRow.t()], [BindingRuleRow.t()]}} | {:error, term()}
  def expand(templates, members) do
    Enum.reduce_while(members, {:ok, {[], []}}, fn member, {:ok, {instances, rules}} ->
      case Map.fetch(templates, member.sha) do
        {:ok, template} ->
          endpoint = member.source_endpoint_ref

          {:cont,
           {:ok,
            {Enum.map(template["instances"], &instance_row(&1, endpoint)) ++ instances,
             Enum.map(template["rules"], &rule_row(&1, endpoint)) ++ rules}}}

        :error ->
          {:halt, {:error, {:binding_artifact_missing, member.sha}}}
      end
    end)
  end

  @doc "What jsonb gives back for a template or a map column: the read's own codec."
  @spec codec(term()) :: term()
  def codec(term), do: term |> Jason.encode!() |> Jason.decode!()

  ## Storage

  @doc "Inserts a version's artifacts (shared, never updated) and members, in the caller's transaction."
  @spec insert(module(), BindingSetRow.t(), [artifact()], [member()]) :: {:ok, term()}
  def insert(repo, %BindingSetRow{} = row, artifacts, members) do
    now = DateTime.utc_now()
    scope = %{organization_id: row.organization_id, mission_id: row.mission_id}

    repo.insert_all(
      "governed_binding_artifacts",
      Enum.map(
        artifacts,
        &Map.merge(scope, %{artifact_sha256: &1.sha, template: &1.template, inserted_at: now})
      ),
      on_conflict: :nothing,
      conflict_target: [:organization_id, :mission_id, :artifact_sha256]
    )

    repo.insert_all(
      "governed_binding_set_members",
      Enum.map(members, fn member ->
        Map.merge(scope, %{
          binding_set_row_id: row.id,
          artifact_sha256: member.sha,
          source_endpoint_ref: member.source_endpoint_ref,
          inserted_at: now
        })
      end),
      on_conflict: :nothing
    )

    {:ok, length(members)}
  end

  @doc """
  The count and the hash of a version's members: the sorted `{endpoint | "", artifact_sha256}`
  pairs. Written on the version row with it and recomputed from the members read back (#450), so a
  member added or an artifact swapped after the version was written changes the hash.
  """
  @spec members_digest([%{sha: binary(), source_endpoint_ref: binary() | nil}]) :: %{
          member_count: non_neg_integer(),
          members_sha256: binary()
        }
  def members_digest(members) do
    pairs = members |> Enum.map(&{&1.source_endpoint_ref || "", &1.sha}) |> Enum.sort()
    %{member_count: length(pairs), members_sha256: ContentHash.term_sha256(pairs)}
  end

  @doc "`members_digest/1` of the members currently stored for a membership version (one query)."
  @spec stored_members_digest(BindingSetRow.t()) :: %{
          member_count: non_neg_integer(),
          members_sha256: binary()
        }
  def stored_members_digest(%BindingSetRow{} = row) do
    from(member in "governed_binding_set_members",
      where:
        member.binding_set_row_id == ^row.id and member.organization_id == ^row.organization_id and
          member.mission_id == ^row.mission_id,
      select: %{sha: member.artifact_sha256, source_endpoint_ref: member.source_endpoint_ref}
    )
    |> Repo.all()
    |> members_digest()
  end

  @doc """
  A membership version's parts, read in two queries and checked before anything is built from them
  (#450, mission-model's conditions): the members are exactly the version's (their count and hash
  equal what was written with it), every referenced artifact exists (`:binding_artifact_missing`)
  and still hashes to its key (`:binding_artifact_tampered`). `{:ok, %{members: [member], templates:
  %{sha => template}}}`; any failure is refused, never a fallback.
  """
  @spec load_parts(BindingSetRow.t()) ::
          {:ok, %{members: [member()], templates: %{binary() => map()}}} | {:error, term()}
  def load_parts(%BindingSetRow{} = row) do
    members = read_members(row)
    stored = %{member_count: row.member_count, members_sha256: row.members_sha256}

    with true <- members_digest(members) == stored || {:error, :binding_set_members_mismatch},
         {:ok, templates} <- read_templates(row, members) do
      {:ok, %{members: members, templates: templates}}
    end
  end

  defp read_members(%BindingSetRow{} = row) do
    from(member in "governed_binding_set_members",
      where:
        member.binding_set_row_id == ^row.id and member.organization_id == ^row.organization_id and
          member.mission_id == ^row.mission_id,
      select: %{sha: member.artifact_sha256, source_endpoint_ref: member.source_endpoint_ref}
    )
    |> Repo.all()
  end

  defp read_templates(%BindingSetRow{} = row, members) do
    shas = members |> Enum.map(& &1.sha) |> Enum.uniq()

    found =
      from(artifact in "governed_binding_artifacts",
        where:
          artifact.organization_id == ^row.organization_id and
            artifact.mission_id == ^row.mission_id and artifact.artifact_sha256 in ^shas,
        select: {artifact.artifact_sha256, artifact.template}
      )
      |> Repo.all()
      |> Map.new()

    Enum.reduce_while(shas, {:ok, found}, fn sha, {:ok, templates} ->
      case Map.fetch(templates, sha) do
        :error -> {:halt, {:error, {:binding_artifact_missing, sha}}}
        {:ok, template} -> artifact_intact(sha, template, templates)
      end
    end)
  end

  defp artifact_intact(sha, template, templates) do
    if ContentHash.term_sha256(template) == sha,
      do: {:cont, {:ok, templates}},
      else: {:halt, {:error, {:binding_artifact_tampered, sha}}}
  end

  @doc "A membership version's rows, read in two queries (members, then their artifacts)."
  @spec load(BindingSetRow.t()) ::
          {:ok, {[CapabilityInstanceRow.t()], [BindingRuleRow.t()]}} | {:error, term()}
  def load(%BindingSetRow{} = row) do
    with {:ok, %{members: members, templates: templates}} <- load_parts(row) do
      expand(templates, members)
    end
  end

  ## Templates

  defp template(nil, instances, rules), do: {:ok, document(instances, rules)}

  defp template(endpoint, instances, rules) when is_binary(endpoint) and endpoint != "" do
    template =
      document(
        Enum.map(instances, &parameterize_instance(&1, endpoint)),
        Enum.map(rules, &parameterize_rule(&1, endpoint))
      )

    if mentions?(template, endpoint),
      do: {:error, {:endpoint_outside_known_fields, endpoint}},
      else: {:ok, template}
  end

  defp template(endpoint, _instances, _rules), do: {:error, {:invalid_endpoint, endpoint}}

  # String keys and the codec's own values, so a template hashes the same before and after jsonb.
  defp document(instances, rules) do
    codec(%{
      "instances" =>
        instances |> Enum.map(&stringify/1) |> Enum.sort_by(& &1["capability_instance_id"]),
      "rules" => rules |> Enum.map(&stringify/1) |> Enum.sort_by(& &1["binding_rule_id"])
    })
  end

  defp parameterize_instance(instance, endpoint) do
    %{
      instance
      | capability_instance_id:
          String.replace(instance.capability_instance_id, endpoint, @placeholder),
        source_endpoint_ref: @placeholder
    }
  end

  defp parameterize_rule(rule, endpoint) do
    %{
      rule
      | binding_rule_id: String.replace(rule.binding_rule_id, endpoint, @placeholder),
        capability_instance_id:
          String.replace(rule.capability_instance_id, endpoint, @placeholder),
        selector_scope: swap_scope(rule.selector_scope, endpoint, @placeholder)
    }
  end

  defp instance_row(attrs, endpoint) do
    attrs = bind(attrs, endpoint, ["capability_instance_id"])
    attrs = if endpoint, do: Map.put(attrs, "source_endpoint_ref", endpoint), else: attrs
    struct(CapabilityInstanceRow, atomize(attrs, @instance_fields))
  end

  defp rule_row(attrs, endpoint) do
    attrs =
      attrs
      |> bind(endpoint, ["binding_rule_id", "capability_instance_id"])
      |> Map.update!("selector_scope", &swap_scope(&1, @placeholder, endpoint))

    struct(BindingRuleRow, atomize(attrs, @rule_fields))
  end

  defp bind(attrs, nil, _keys), do: attrs

  defp bind(attrs, endpoint, keys),
    do:
      Enum.reduce(
        keys,
        attrs,
        &Map.update!(&2, &1, fn id -> String.replace(id, @placeholder, endpoint) end)
      )

  # Only the scope's own endpoint value moves; nothing else in the selector does.
  defp swap_scope(%{"source_endpoint_ref" => from} = scope, from, to) when is_binary(to),
    do: Map.put(scope, "source_endpoint_ref", to)

  defp swap_scope(scope, _from, _to), do: scope

  ## Checks

  defp group_rules(rules, endpoint_by_instance) do
    Enum.reduce_while(rules, {:ok, %{}}, fn rule, {:ok, acc} ->
      case Map.fetch(endpoint_by_instance, rule.capability_instance_id) do
        {:ok, endpoint} -> {:cont, {:ok, Map.update(acc, endpoint, [rule], &[rule | &1])}}
        :error -> {:halt, {:error, {:rule_without_instance, rule.binding_rule_id}}}
      end
    end)
  end

  defp placeholder_absent(rows) do
    if Enum.any?(rows, &mentions?(&1, @placeholder)),
      do: {:error, :placeholder_in_content},
      else: :ok
  end

  defp mentions?(value, text) when is_binary(value), do: String.contains?(value, text)
  defp mentions?(%_{} = struct, text), do: struct |> Map.from_struct() |> mentions?(text)

  defp mentions?(map, text) when is_map(map),
    do:
      Enum.any?(map, fn {key, value} ->
        mentions?(to_string(key), text) or mentions?(value, text)
      end)

  defp mentions?(list, text) when is_list(list), do: Enum.any?(list, &mentions?(&1, text))
  defp mentions?(_value, _text), do: false

  ## Shapes

  defp fields(row, keys) do
    Map.new(keys, fn key ->
      value = Map.get(row, key)
      {key, if(key in @map_fields, do: codec(value || %{}), else: value)}
    end)
  end

  defp stringify(row), do: Map.new(row, fn {key, value} -> {Atom.to_string(key), value} end)

  defp atomize(attrs, keys), do: Map.new(keys, &{&1, Map.get(attrs, Atom.to_string(&1))})
end
