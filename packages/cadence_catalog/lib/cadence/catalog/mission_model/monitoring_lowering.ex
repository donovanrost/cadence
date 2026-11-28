defmodule Cadence.Catalog.MissionModel.MonitoringLowering do
  @moduledoc """
  Lowers monitoring policies into the monitoring plan's entries (ADR-020 P3, #451; the contract
  agreed with telemetry there on 11-26 and 11-28).

  One entry is one policy for one parameter, at one scope. Each carries, beside the policy's own
  definition (`contexts`, `default_rules`, persistence counts, missing/invalid states, `disabled`):

    * `rule_id`: the policy's identity, `"policy:" <> semantic_id`. It stays the same when its
      thresholds change and when a mission layer replaces a catalog policy (the replace keeps the
      semantic id), so an open alarm episode keeps its `(subject, rule_id)` across an edit.
    * `rule_digest`: `"monitoring_rule:v1:" <> sha256` of what the evaluator reads (the parameter
      and the definition). It changes on any edit and on nothing else: the evaluator resets
      persistence counters and says `rule_changed` when it changes.
    * `origin`: `"catalog"` (an imported layer wrote it last) or `"mission_layer"` (an authored
      layer did), and `declaration_id`, the declaration that produced the entry.
    * `scope` and `spacecraft_id`: `"mission"` with `nil` applies to every craft on the revision;
      `"spacecraft"` with an id applies to that craft only. A policy scoped to several craft (its
      definition's `spacecraft_ids`) becomes one entry per craft.

  **Per-craft overrides.** A policy with an `:overrides` reference to another policy replaces that
  policy for its `spacecraft_ids` only: its entries take the overridden policy's `rule_id` and
  `policy_id` (partition state, the latest alarm state and episodes key on it), so the craft's
  episode continues across the override; `declaration_id` stays the override's own. An override
  must name a mission-wide policy (never another override, so no chain or cycle, and never a
  scoped policy) on the same parameter, and must list at least one craft (a mission-wide change is
  a `:replace`). Two entries for one `{rule_id, scope, spacecraft_id}` are refused. Each refusal
  is a blocking diagnostic on the monitoring target, so the change that causes it is a NO-GO. A partition resolves its craft's effective rules from the whole plan: the spacecraft
  entry for a `rule_id` when there is one, else the mission entry.

  The plan is compiled once per revision and holds every craft's entries, so a partition never
  reads per craft (the per-request rule, #1049).

  Each entry also carries the `SpaceSystem` that owns its policy: `space_system_id`,
  `space_system_path` and `runtime_name` (ADR-020 P5). Where a policy lives is not what it
  evaluates, so `rule_digest` (a whitelist) leaves them out.
  """

  alias Cadence.Catalog.MissionModel.{Canonical, Declaration, Diagnostic, SystemOwner}

  @digest_version 1

  @doc """
  The plan entries for `declarations` (the revision's monitoring policies, sorted) and the
  diagnostics their overrides raise. `origins` maps a declaration's semantic id to the kind of the
  layer that wrote it last (`:imported | :authored`).
  """
  @spec lower([Declaration.t()], %{optional(binary()) => atom()}, SystemOwner.index()) ::
          {[map()], [Diagnostic.t()]}
  def lower(declarations, origins, systems)
      when is_list(declarations) and is_map(origins) and is_map(systems) do
    by_id = Map.new(declarations, &{&1.semantic_id, &1})

    {lowered, diagnostics} =
      Enum.reduce(declarations, {[], []}, fn declaration, {lowered, diagnostics} ->
        case entries(declaration, by_id, origins, systems) do
          {:ok, new} -> {[{declaration, new} | lowered], diagnostics}
          {:error, diagnostic} -> {lowered, [diagnostic | diagnostics]}
        end
      end)

    lowered = Enum.reverse(lowered)
    entries = Enum.flat_map(lowered, &elem(&1, 1))
    {entries, Enum.reverse(diagnostics) ++ duplicates(lowered)}
  end

  @evaluated ~w(parameter_id contexts default_rules minimum_violations minimum_conformance
    missing_state invalid_state disabled)

  @doc "The identity a partition resolves and carries an entry by: `{rule_id, scope, spacecraft_id}`."
  @spec key(map()) :: {binary(), binary(), binary() | nil}
  def key(entry), do: {entry["rule_id"], entry["scope"], entry["spacecraft_id"]}

  @doc """
  The digest of what the evaluator reads from an entry: its parameter, contexts, default rules,
  persistence counts, missing/invalid states and `disabled` (what `MonitoringPlan.new/1` reads).
  A description or label edit leaves it alone, so it resets no persistence counter.
  """
  @spec rule_digest(map()) :: binary()
  def rule_digest(entry) when is_map(entry) do
    evaluated = Map.take(entry, @evaluated)
    "monitoring_rule:v#{@digest_version}:" <> Canonical.sha256({@digest_version, evaluated})
  end

  # Two entries for one `{rule_id, scope, spacecraft_id}` leave a partition no single rule to
  # run: refuse each repeat, naming both declarations.
  defp duplicates(lowered) do
    lowered
    |> Enum.flat_map(fn {declaration, entries} -> Enum.map(entries, &{key(&1), declaration}) end)
    |> Enum.group_by(&elem(&1, 0), &elem(&1, 1))
    |> Enum.flat_map(fn
      {_key, [_one]} ->
        []

      {{_rule, _scope, craft}, [first | repeats]} ->
        Enum.map(repeats, fn declaration ->
          diagnostic(
            declaration,
            "MM_MONITORING_OVERRIDE_DUPLICATE",
            "#{declaration.qualified_name} and #{first.qualified_name} both set this rule for #{craft}"
          )
        end)
    end)
  end

  defp entries(declaration, by_id, origins, systems) do
    base = base(declaration, origins, systems)
    spacecraft_ids = spacecraft_ids(declaration)

    case overridden(declaration) do
      nil ->
        {:ok, scoped(base, "policy:" <> declaration.semantic_id, spacecraft_ids)}

      target_id ->
        override(declaration, base, Map.get(by_id, target_id), spacecraft_ids, systems)
    end
  end

  defp override(declaration, _base, nil, _spacecraft_ids, _systems),
    do:
      {:error,
       diagnostic(
         declaration,
         "MM_MONITORING_OVERRIDE_TARGET",
         "an override must name a monitoring policy of this revision"
       )}

  defp override(declaration, _base, _target, [], _systems),
    do:
      {:error,
       diagnostic(
         declaration,
         "MM_MONITORING_OVERRIDE_SCOPE_REQUIRED",
         "an override applies to named spacecraft; a mission-wide change is a replace"
       )}

  defp override(declaration, base, target, spacecraft_ids, systems) do
    cond do
      not is_nil(overridden(target)) or spacecraft_ids(target) != [] ->
        {:error,
         diagnostic(
           declaration,
           "MM_MONITORING_OVERRIDE_CHAIN",
           "an override must name a mission-wide policy, never another override or a scoped policy"
         )}

      parameter_id(target) == base["parameter_id"] ->
        override_entries(base, target, spacecraft_ids, systems)

      true ->
        {:error,
         diagnostic(
           declaration,
           "MM_MONITORING_OVERRIDE_PARAMETER",
           "an override must be on the same parameter as the policy it overrides"
         )}
    end
  end

  # The craft's state, latest alarm state and episodes key on policy_id: an override is the
  # target policy for its craft, so it keeps that id as well as the rule_id, and lives where the
  # target does (its SpaceSystem and runtime name), whatever path it was authored under: a craft
  # that binds the target's system runs the override too (its own declaration_id stays).
  defp override_entries(base, target, spacecraft_ids, systems) do
    base =
      base
      |> Map.put("policy_id", target.semantic_id)
      |> Map.merge(SystemOwner.fields(target, systems))

    {:ok, scoped(base, "policy:" <> target.semantic_id, spacecraft_ids)}
  end

  defp base(declaration, origins, systems) do
    declaration.definition
    |> stringify_keys()
    |> Map.drop(["spacecraft_ids"])
    |> Map.merge(SystemOwner.fields(declaration, systems))
    |> Map.put("policy_id", declaration.semantic_id)
    |> Map.put("parameter_id", parameter_id(declaration))
    |> Map.put("declaration_id", declaration.semantic_id)
    |> Map.put("origin", origin(Map.get(origins, declaration.semantic_id)))
  end

  defp scoped(base, rule_id, []),
    do: [finish(base, rule_id, "mission", nil)]

  defp scoped(base, rule_id, spacecraft_ids),
    do: Enum.map(spacecraft_ids, &finish(base, rule_id, "spacecraft", &1))

  defp finish(base, rule_id, scope, spacecraft_id) do
    entry =
      base
      |> Map.put("rule_id", rule_id)
      |> Map.put("scope", scope)
      |> Map.put("spacecraft_id", spacecraft_id)

    Map.put(entry, "rule_digest", rule_digest(entry))
  end

  defp parameter_id(declaration), do: resolved(declaration, :parameter)
  defp overridden(declaration), do: resolved(declaration, :overrides)

  defp resolved(declaration, role) do
    Enum.find_value(declaration.references, fn reference ->
      if reference.role == role and is_binary(reference.resolved_id), do: reference.resolved_id
    end)
  end

  defp spacecraft_ids(declaration) do
    case value(declaration.definition, :spacecraft_ids) do
      ids when is_list(ids) ->
        ids |> Enum.filter(&(is_binary(&1) and &1 != "")) |> Enum.uniq() |> Enum.sort()

      _none ->
        []
    end
  end

  defp origin(:authored), do: "mission_layer"
  defp origin(_imported), do: "catalog"

  defp diagnostic(declaration, code, message) do
    Diagnostic.new(%{
      code: code,
      severity: :error,
      stage: :target_lowering,
      target: :monitoring,
      semantic_id: declaration.semantic_id,
      support: :invalid,
      message: message,
      provenance: declaration.provenance
    })
  end

  defp stringify_keys(map) when is_map(map),
    do: Map.new(map, fn {key, value} -> {to_string(key), value} end)

  defp value(map, key) when is_map(map), do: Map.get(map, key, Map.get(map, Atom.to_string(key)))
end
