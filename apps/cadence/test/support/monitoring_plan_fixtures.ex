defmodule Cadence.MonitoringPlanFixtures do
  @moduledoc """
  A STAND-IN for mission-model's compiled monitoring plan (#451, the fifth runtime plan kind), built
  to the contract agreed on the issue, for the evaluation tests. Test support only: when the real
  compile output (the 12-01 plan) is available, a fixture that returns it replaces this module's
  builders and nothing in `lib/` changes.

  A rule row is `%{rule_id, rule_digest, scope, spacecraft_id, parameter_id, kind, severity,
  enabled, definition}`: `scope` is `"mission"` (spacecraft_id nil) or `"spacecraft"`, `kind` is
  `"limit"` or `"alarm_rule"`, `definition` is the rule body the evaluator reads, `rule_digest` is
  the sha256 of the canonical row's content (so it changes with any edit and `rule_id` does not).
  The plan content is `%{policies: [...], rules: [...]}`: per-parameter settings and every rule of
  the revision once.
  """

  alias Cadence.Catalog.MissionModel.{Canonical, RuntimePlan}

  @doc "One rule row; `digest` follows the content unless given."
  @spec rule(binary(), keyword()) :: map()
  def rule(rule_id, opts \\ []) do
    row = %{
      rule_id: rule_id,
      scope: Keyword.get(opts, :scope, "mission"),
      spacecraft_id: Keyword.get(opts, :spacecraft_id),
      parameter_id: Keyword.get(opts, :parameter_id, "p"),
      kind: Keyword.get(opts, :kind, "limit"),
      severity: Keyword.get(opts, :severity, :critical),
      enabled: Keyword.get(opts, :enabled, true),
      definition:
        Keyword.get(opts, :definition, %{
          kind: :comparison,
          operator: :>,
          value: Keyword.get(opts, :above, 10)
        })
    }

    Map.put(row, :rule_digest, Keyword.get_lazy(opts, :digest, fn -> digest(row) end))
  end

  @doc "A spacecraft-scoped rule: the same `rule_id` replaces the mission rule for that spacecraft."
  @spec craft_rule(binary(), binary(), keyword()) :: map()
  def craft_rule(rule_id, spacecraft_id, opts \\ []),
    do: rule(rule_id, [scope: "spacecraft", spacecraft_id: spacecraft_id] ++ opts)

  @doc "A per-parameter policy (persistence counts and states) for the rules of `parameter_id`."
  @spec policy(binary(), keyword()) :: map()
  def policy(parameter_id, opts \\ []) do
    %{
      policy_id: Keyword.get(opts, :policy_id, "policy:" <> parameter_id),
      parameter_id: parameter_id,
      minimum_violations: Keyword.get(opts, :violations, 1),
      minimum_conformance: Keyword.get(opts, :conformance, 1)
    }
  end

  @doc "The runtime plans of a revision holding `rules` (and `policies`)."
  @spec plans([map()], [map()], binary()) :: %{monitoring: RuntimePlan.t()}
  def plans(rules, policies \\ [], plan_id \\ nil) do
    id = plan_id || "monitoring-" <> Canonical.sha256({rules, policies})

    %{
      monitoring: %RuntimePlan{
        plan_id: id,
        target: :monitoring,
        target_contract_version: "2",
        mission_model_revision_id: "rev-" <> id,
        mission_model_content_sha256: "sha",
        layer_ids: [],
        compiler_version: "test-stub",
        status: :ready,
        content_sha256: "content-" <> id,
        plan: %{policies: policies, rules: rules}
      }
    }
  end

  defp digest(row), do: Canonical.sha256(Map.delete(row, :rule_digest))
end
