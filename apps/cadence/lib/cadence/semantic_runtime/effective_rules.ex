defmodule Cadence.SemanticRuntime.EffectiveRules do
  @moduledoc """
  The rules in force for one spacecraft, from every rule row of a parameter (#451 T2).

  The compiled monitoring plan holds every rule of a revision, once: mission-scoped rows
  (`scope: "mission"`, `spacecraft_id: nil`) and spacecraft-scoped rows (`scope: "spacecraft"`, a
  `spacecraft_id`). A spacecraft's effective rules (the contract mission-model gave on #451):

  - a spacecraft-scoped rule whose `rule_id` equals a mission-scoped rule's **replaces** it, for
    that spacecraft only;
  - a spacecraft-scoped rule with a new `rule_id` **adds** to that spacecraft's rules;
  - `enabled: false` on the replacing rule turns the mission rule off for that spacecraft (there is
    no implicit removal);
  - rows of another spacecraft are ignored; a disabled mission rule is off for everyone.

  A rule row is `%{rule_id, rule_digest, scope, spacecraft_id, parameter_id, kind, severity,
  enabled, definition}` with atom or string keys; `definition` is the rule body the monitoring
  evaluator understands (`kind: comparison | range | enumerated | boolean | string`, ...). Order is
  the plan's own, with a replacing rule in the place of the rule it replaces, and added rules after.
  """

  alias Cadence.Catalog.MissionModel.Canonical

  @type rule :: map()

  @doc "The effective rules of `spacecraft_id` (nil: the mission-wide set only)."
  @spec for_spacecraft([rule()], binary() | nil) :: [rule()]
  def for_spacecraft(rules, spacecraft_id) when is_list(rules) do
    {mission, craft} =
      rules
      |> Enum.filter(&applies?(&1, spacecraft_id))
      |> Enum.split_with(&(scope(&1) == "mission"))

    overrides = Map.new(craft, &{value(&1, :rule_id), &1})
    mission_ids = MapSet.new(mission, &value(&1, :rule_id))

    replaced = Enum.map(mission, &Map.get(overrides, value(&1, :rule_id), &1))
    added = Enum.reject(craft, &MapSet.member?(mission_ids, value(&1, :rule_id)))

    Enum.filter(replaced ++ added, &enabled?/1)
  end

  @doc "The rule as the monitoring evaluator takes it: the definition, with the rule's own identity."
  @spec evaluator_rule(rule()) :: map()
  def evaluator_rule(rule) do
    rule
    |> value(:definition, %{})
    |> Map.put(:severity, value(rule, :severity, :warning))
    |> Map.put(:rule_id, value(rule, :rule_id))
    |> Map.put(:rule_digest, value(rule, :rule_digest))
  end

  @doc """
  The digest of the rules in force: the policy's own (its settings and legacy rules) with the
  digests of the effective rules. It changes when any of them does, and only then.
  """
  @spec digest([rule()], binary() | nil) :: binary() | nil
  def digest([], base), do: base

  def digest(effective, base) do
    digests = effective |> Enum.map(&value(&1, :rule_digest)) |> Enum.sort()
    Canonical.sha256([base, digests])
  end

  defp applies?(rule, spacecraft_id) do
    case scope(rule) do
      "mission" -> true
      "spacecraft" -> not is_nil(spacecraft_id) and value(rule, :spacecraft_id) == spacecraft_id
      _unknown -> false
    end
  end

  defp scope(rule), do: rule |> value(:scope) |> to_string()
  defp enabled?(rule), do: value(rule, :enabled, true) != false

  defp value(attrs, key, default \\ nil),
    do: Map.get(attrs, key, Map.get(attrs, Atom.to_string(key), default))
end
