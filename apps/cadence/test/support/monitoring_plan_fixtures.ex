defmodule Cadence.MonitoringPlanFixtures do
  @moduledoc """
  A STAND-IN for the compiled monitoring plan of ADR-020 P3 (#451, PR #1081's `MonitoringLowering`
  output), for the evaluation tests. Test support only: once #1081 is on develop a fixture that
  compiles a revision through the real compiler replaces these builders, and nothing in `lib/`
  changes.

  An entry is one policy for one parameter at one scope, string-keyed as the compiler stores it:
  the policy's own definition (`default_rules`, `contexts`, persistence counts, `disabled`) and
  `policy_id`, `rule_id` (`"policy:" <> semantic id`, fixed across edits), `rule_digest`
  (`"monitoring_rule:v1:" <> sha256` of what is evaluated), `origin`, `declaration_id`, `scope`
  (`"mission"` or `"spacecraft"`) and `spacecraft_id`. A per-craft override takes the overridden
  policy's `policy_id` and `rule_id` and keeps its own `declaration_id`, so the craft's state and
  episode continue across it.
  """

  alias Cadence.Catalog.MissionModel.{Canonical, RuntimePlan}

  @identity ~w(rule_id rule_digest origin declaration_id scope spacecraft_id policy_id)

  @doc "A mission-scoped policy entry (`above:` is its comparison threshold)."
  @spec entry(binary(), keyword()) :: map()
  def entry(semantic_id, opts \\ []) do
    build(semantic_id, semantic_id, "mission", nil, opts)
  end

  @doc """
  A spacecraft-scoped override of the policy `target_id` for `spacecraft_id`: the target's
  `policy_id` and `rule_id`, its own `declaration_id`.
  """
  @spec override(binary(), binary(), binary(), keyword()) :: map()
  def override(target_id, declaration_id, spacecraft_id, opts \\ []) do
    build(target_id, declaration_id, "spacecraft", spacecraft_id, opts)
  end

  @doc "A policy authored for one spacecraft only (no mission entry has its `rule_id`)."
  @spec craft_only(binary(), binary(), keyword()) :: map()
  def craft_only(semantic_id, spacecraft_id, opts \\ []),
    do: build(semantic_id, semantic_id, "spacecraft", spacecraft_id, opts)

  defp build(policy_id, declaration_id, scope, spacecraft_id, opts) do
    entry = %{
      "policy_id" => policy_id,
      "parameter_id" => Keyword.get(opts, :parameter_id, "p"),
      "default_rules" => [
        %{
          "kind" => "comparison",
          "operator" => ">",
          "value" => Keyword.get(opts, :above, 10),
          "severity" => Keyword.get(opts, :severity, "critical")
        }
      ],
      "minimum_violations" => Keyword.get(opts, :violations, 1),
      "minimum_conformance" => Keyword.get(opts, :conformance, 1),
      "disabled" => Keyword.get(opts, :disabled, false),
      "declaration_id" => declaration_id,
      "origin" => Keyword.get(opts, :origin, "catalog"),
      "rule_id" => "policy:" <> policy_id,
      "scope" => scope,
      "spacecraft_id" => spacecraft_id
    }

    Map.put(entry, "rule_digest", digest(entry))
  end

  @doc "The digest of what the evaluator reads from an entry, as the compiler computes it."
  @spec digest(map()) :: binary()
  def digest(entry),
    do: "monitoring_rule:v1:" <> Canonical.sha256({1, Map.drop(entry, @identity)})

  @doc "The runtime plans of a revision holding `entries`."
  @spec plans([map()], binary() | nil) :: %{monitoring: RuntimePlan.t()}
  def plans(entries, plan_id \\ nil) do
    id = plan_id || "monitoring-" <> Canonical.sha256(entries)

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
        plan: %{"policies" => entries}
      }
    }
  end
end
