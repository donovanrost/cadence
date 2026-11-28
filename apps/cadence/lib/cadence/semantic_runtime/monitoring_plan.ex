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
          spacecraft_id: binary() | nil
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
                spacecraft_id: nil
              ]

  @origins %{"catalog" => :catalog, "mission_layer" => :mission_layer}
  @scopes %{"mission" => :mission, "spacecraft" => :spacecraft}

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
      spacecraft_id: value(attrs, :spacecraft_id)
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
