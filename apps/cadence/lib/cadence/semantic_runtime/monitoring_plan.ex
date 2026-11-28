defmodule Cadence.SemanticRuntime.MonitoringPlan do
  @moduledoc """
  Executable monitoring policy for one semantic parameter, at one scope.

  The compiled plan's identity fields (ADR-020 P3, #451, from `MonitoringLowering`):
  `rule_id` stays fixed across edits, `rule_digest` changes with what is evaluated, and `origin`
  (`:catalog | :mission_layer`) with `declaration_id` says where the policy came from. `scope` is
  `:mission` (`spacecraft_id: nil`, every craft on the revision) or `:spacecraft` (that craft
  only). A partition takes, per `rule_id`, its craft's spacecraft entry when there is one, else the
  mission entry. Plans compiled before P3 carry nil for all of these.
  """

  @type t :: %__MODULE__{
          policy_id: binary(),
          parameter_id: binary(),
          contexts: [map()],
          default_rules: [map()],
          minimum_violations: pos_integer(),
          minimum_conformance: pos_integer(),
          missing_state: atom(),
          invalid_state: atom(),
          disabled: boolean(),
          rule_digest: binary() | nil,
          rule_id: binary() | nil,
          origin: :catalog | :mission_layer | nil,
          declaration_id: binary() | nil,
          scope: :mission | :spacecraft | nil,
          spacecraft_id: binary() | nil,
          space_system_id: binary() | nil,
          runtime_name: binary() | nil
        }

  @enforce_keys [:policy_id, :parameter_id]
  defstruct @enforce_keys ++
              [
                contexts: [],
                default_rules: [],
                minimum_violations: 1,
                minimum_conformance: 1,
                missing_state: :unknown,
                invalid_state: :unknown,
                disabled: false,
                # The digest of the rules in force for this parameter (#451 T2): when it changes the
                # persistence counters reset and the result says so. nil (a plan without digests)
                # never resets anything.
                rule_digest: nil,
                rule_id: nil,
                origin: nil,
                declaration_id: nil,
                scope: nil,
                spacecraft_id: nil,
                # The owning SpaceSystem and qualified runtime name (ADR-020 P5); nil before them.
                space_system_id: nil,
                runtime_name: nil
              ]

  @origins %{"catalog" => :catalog, "mission_layer" => :mission_layer}
  @scopes %{"mission" => :mission, "spacecraft" => :spacecraft}

  @doc """
  The identity a partition resolves and carries a plan by: `{rule_id, scope, spacecraft_id}`.
  One policy can be several entries (its mission entry and per-craft overrides share `policy_id`
  and `rule_id`), so `policy_id` alone is not unique in a plan.
  """
  @spec key(t()) :: {binary() | nil, :mission | :spacecraft | nil, binary() | nil}
  def key(%__MODULE__{rule_id: rule_id, scope: scope, spacecraft_id: spacecraft_id}),
    do: {rule_id, scope, spacecraft_id}

  @doc """
  The entries of a parameter as `spacecraft_id` runs them (#451 T2): per `rule_id`, that craft's
  spacecraft entry when there is one, else the mission entry; another craft's entries are dropped;
  a spacecraft entry with a `rule_id` no mission entry has (a policy for one craft only) is that
  craft's own. An entry with no `rule_id` and no scope (a plan compiled before P3) is kept for every
  craft; a spacecraft-scoped entry with no `rule_id` is dropped (P3's compiler never produces one,
  and without a `rule_id` there is nothing for it to replace or be added under). A policy
  turned off for a craft is its entry with `disabled: true`, which the evaluator reports as
  `disabled`. Order is the plan's, with an override in the place of the entry it replaces.
  """
  @spec resolve([t()], binary() | nil) :: [t()]
  def resolve(entries, spacecraft_id) when is_list(entries) do
    {craft, mission} =
      entries
      |> Enum.filter(&applies?(&1, spacecraft_id))
      |> Enum.split_with(&(&1.scope == :spacecraft))

    overrides = craft |> Enum.reject(&is_nil(&1.rule_id)) |> Map.new(&{&1.rule_id, &1})
    mission_ids = MapSet.new(mission, & &1.rule_id)

    replaced = Enum.map(mission, &Map.get(overrides, &1.rule_id, &1))
    added = Enum.reject(craft, &(is_nil(&1.rule_id) or MapSet.member?(mission_ids, &1.rule_id)))

    replaced ++ added
  end

  defp applies?(%__MODULE__{scope: :spacecraft, spacecraft_id: id}, spacecraft_id),
    do: not is_nil(spacecraft_id) and id == spacecraft_id

  defp applies?(%__MODULE__{}, _spacecraft_id), do: true

  @spec new(map()) :: t()
  def new(attrs) when is_map(attrs) do
    %__MODULE__{
      policy_id: value(attrs, :policy_id),
      parameter_id: value(attrs, :parameter_id),
      contexts: value(attrs, :contexts, []),
      default_rules: value(attrs, :default_rules, []),
      minimum_violations: value(attrs, :minimum_violations, 1),
      minimum_conformance: value(attrs, :minimum_conformance, 1),
      missing_state: attrs |> value(:missing_state, :unknown) |> normalize_atom(),
      invalid_state: attrs |> value(:invalid_state, :unknown) |> normalize_atom(),
      disabled: value(attrs, :disabled, false),
      rule_digest: value(attrs, :rule_digest),
      rule_id: value(attrs, :rule_id),
      origin: attrs |> value(:origin) |> known(@origins),
      declaration_id: value(attrs, :declaration_id),
      scope: attrs |> value(:scope) |> known(@scopes),
      spacecraft_id: value(attrs, :spacecraft_id),
      space_system_id: value(attrs, :space_system_id),
      runtime_name: value(attrs, :runtime_name)
    }
  end

  # A closed vocabulary: anything else (including nil, a pre-P3 plan) is nil, never a new atom.
  defp known(value, vocabulary) when is_atom(value) and not is_nil(value),
    do: if(value in Map.values(vocabulary), do: value)

  defp known(value, vocabulary) when is_binary(value), do: Map.get(vocabulary, value)
  defp known(_value, _vocabulary), do: nil

  defp normalize_atom(value) when is_atom(value), do: value
  defp normalize_atom(value) when is_binary(value), do: String.to_existing_atom(value)

  defp value(attrs, key, default \\ nil),
    do: Map.get(attrs, key, Map.get(attrs, Atom.to_string(key), default))
end
