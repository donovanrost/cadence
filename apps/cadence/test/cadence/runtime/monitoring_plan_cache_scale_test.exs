defmodule Cadence.Runtime.MonitoringPlanCacheScaleTest do
  @moduledoc """
  What the plan cache saves a partition per batch (#451 T1), on a 5,000-parameter plan (0.5 to 1 MB
  of plans): the old path decoded the whole plan for every batch and scanned every monitoring plan
  and algorithm for every update; the cached path is one index lookup per update. Excluded by
  default; `mix test --include scale`.
  """
  use ExUnit.Case, async: false

  @moduletag :scale

  alias Cadence.Catalog.MissionModel.{Canonical, Expression, RuntimePlan}
  alias Cadence.Runtime.MonitoringPlanCache
  alias Cadence.SemanticRuntime
  alias Cadence.SemanticRuntime.{PlanDecoder, State, Update}

  @parameters 5_000
  @batch 20
  @batches 50

  defp runtime_plan(target, plan_id, content) do
    %RuntimePlan{
      plan_id: plan_id,
      target: target,
      target_contract_version: "2",
      mission_model_revision_id: "rev",
      mission_model_content_sha256: "sha",
      layer_ids: [],
      compiler_version: "test",
      status: :ready,
      content_sha256: "content-#{plan_id}",
      plan: content
    }
  end

  defp plans do
    %{
      monitoring:
        runtime_plan(:monitoring, "mon-scale", %{
          policies:
            for i <- 0..(@parameters - 1) do
              %{
                policy_id: "policy:p#{i}",
                parameter_id: "p#{i}",
                minimum_violations: 2,
                default_rules: [
                  %{kind: :comparison, operator: :>, value: 10, severity: :critical},
                  %{kind: :comparison, operator: :>, value: 5, severity: :warning}
                ]
              }
            end
        }),
      algorithm:
        runtime_plan(:algorithm, "alg-scale", %{
          algorithms:
            for i <- 0..(div(@parameters, 10) - 1) do
              %{
                algorithm_id: "algorithm:#{i}",
                input_parameter_ids: ["p#{i * 10}", "p#{i * 10 + 1}"],
                outputs: [
                  %{
                    parameter_id: "d#{i}",
                    qualified_name: "/d#{i}",
                    expression:
                      Expression.new(%{
                        node: {:+, {:parameter, "p#{i * 10}"}, {:parameter, "p#{i * 10 + 1}"}},
                        result_type: :number
                      })
                  }
                ]
              }
            end
        })
    }
  end

  defp update(id, parameter, value, at) do
    Update.new(%{
      update_id: id,
      parameter_id: parameter,
      qualified_name: "/" <> parameter,
      value: value,
      raw_value: value,
      quality: :good,
      receipt_time: at,
      generation_time: at,
      producer_kind: :container,
      producer_id: "container:hk"
    })
  end

  defp batch(n) do
    at = DateTime.add(~U[2026-11-28 12:00:00.000000Z], n, :second)

    for k <- 0..(@batch - 1) do
      # A spread of parameters, some with algorithms, some past a limit.
      parameter = "p#{rem(n * 397 + k * 211, @parameters)}"
      update("u-#{n}-#{k}", parameter, rem(n + k, 20), at)
    end
  end

  test "per-batch cost of the semantic runtime on a 5,000-parameter plan, decode and scan vs the cache" do
    plans = plans()
    {:ok, cache} = MonitoringPlanCache.start_link()
    {:ok, index} = MonitoringPlanCache.acquire(cache, plans)

    old = fn n ->
      decoded = PlanDecoder.decode(plans)
      SemanticRuntime.process(%State{}, batch(n), decoded)
    end

    new = fn n -> SemanticRuntime.process(%State{}, batch(n), index) end

    # The same results either way, on every batch measured.
    for n <- 0..(@batches - 1), do: assert(old.(n) == new.(n))

    time = fn fun ->
      times = for n <- 0..(@batches - 1), do: elem(:timer.tc(fn -> fun.(n) end), 0) / 1_000
      sorted = Enum.sort(times)
      {Enum.at(sorted, div(@batches, 2)), Enum.at(sorted, @batches - 2)}
    end

    {old_p50, old_p99} = time.(old)
    {new_p50, new_p99} = time.(new)

    IO.puts(
      "SEMANTIC BATCH of #{@batch} updates, #{@parameters}-parameter plan: " <>
        "decode and scan p50 #{Float.round(old_p50, 2)} ms / p99 #{Float.round(old_p99, 2)} ms; " <>
        "cached index p50 #{Float.round(new_p50, 2)} ms / p99 #{Float.round(new_p99, 2)} ms"
    )

    {load_us, _} = :timer.tc(fn -> MonitoringPlanCache.acquire(self_cache(), plans) end)
    IO.puts("SEMANTIC PLAN LOAD (once per plan per node): #{Float.round(load_us / 1_000, 1)} ms")

    assert new_p99 < old_p50
  end

  # A fresh cache, so the load is a miss.
  defp self_cache do
    {:ok, cache} = MonitoringPlanCache.start_link()
    cache
  end

  # Rule rows (#451 T2b): every parameter has a mission rule and a spacecraft rule that replaces it
  # for sc-1, so each update resolves the effective rules (filter, replace, digest) before it
  # evaluates. Compared with the plain plan's per-batch cost above.
  defp rule_plans do
    rules =
      for i <- 0..(@parameters - 1), row <- [mission_rule(i), craft_rule(i)], do: row

    %{
      monitoring:
        runtime_plan(:monitoring, "mon-rules-scale", %{
          policies:
            for(
              i <- 0..(@parameters - 1),
              do: %{policy_id: "policy:p#{i}", parameter_id: "p#{i}"}
            ),
          rules: rules
        })
    }
  end

  defp mission_rule(i), do: rule_row(i, "mission", nil, 10)
  defp craft_rule(i), do: rule_row(i, "spacecraft", "sc-1", 15)

  defp rule_row(i, scope, craft, above) do
    row = %{
      rule_id: "limit:p#{i}",
      scope: scope,
      spacecraft_id: craft,
      parameter_id: "p#{i}",
      kind: "limit",
      severity: :critical,
      enabled: true,
      definition: %{kind: :comparison, operator: :>, value: above}
    }

    Map.put(row, :rule_digest, Canonical.sha256(row))
  end

  defp craft_batch(n) do
    for update <- batch(n),
        do: %{update | metadata: %{mission_id: "m", spacecraft_id: "sc-1"}}
  end

  test "per-batch cost with rule rows: each update resolves its spacecraft's effective rules" do
    plans = rule_plans()
    {:ok, cache} = MonitoringPlanCache.start_link()
    {:ok, index} = MonitoringPlanCache.acquire(cache, plans)
    listed = plans |> PlanDecoder.decode()

    run = fn plan, n -> SemanticRuntime.process(%State{}, craft_batch(n), plan) end

    for n <- 0..(@batches - 1), do: assert(run.(index, n) == run.(listed, n))

    times = for n <- 0..(@batches - 1), do: elem(:timer.tc(fn -> run.(index, n) end), 0) / 1_000
    sorted = Enum.sort(times)

    IO.puts(
      "SEMANTIC BATCH WITH RULE ROWS of #{@batch} updates, #{@parameters} parameters x " <>
        "(1 mission rule + 1 craft rule): cached index p50 " <>
        "#{Float.round(Enum.at(sorted, div(@batches, 2)), 3)} ms / p99 " <>
        "#{Float.round(Enum.at(sorted, @batches - 2), 3)} ms"
    )
  end
end
