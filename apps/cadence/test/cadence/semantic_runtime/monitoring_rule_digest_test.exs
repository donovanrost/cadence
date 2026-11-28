defmodule Cadence.SemanticRuntime.MonitoringRuleDigestTest do
  @moduledoc """
  A change of the rules in force resets a policy's persistence counters, keeps an open alarm, and
  says `rule_changed` in the result's metadata (#451 T2, contract 6); a plan with no digest changes
  nothing.
  """
  use Cadence.UnitCase, async: true

  alias Cadence.SemanticRuntime.{MonitoringEvaluator, MonitoringPlan, Update}

  @at ~U[2026-11-28 12:00:00.000000Z]

  defp plan(digest, threshold, opts \\ []) do
    MonitoringPlan.new(%{
      policy_id: "policy:p",
      parameter_id: "p",
      minimum_violations: Keyword.get(opts, :violations, 3),
      minimum_conformance: Keyword.get(opts, :conformance, 2),
      rule_digest: digest,
      default_rules: [%{kind: :comparison, operator: :>, value: threshold, severity: :critical}]
    })
  end

  defp update(n, value) do
    Update.new(%{
      update_id: "u#{n}",
      parameter_id: "p",
      qualified_name: "/p",
      value: value,
      raw_value: value,
      quality: :good,
      receipt_time: DateTime.add(@at, n),
      generation_time: DateTime.add(@at, n),
      producer_kind: :container,
      producer_id: "c"
    })
  end

  defp run(plan, n, value, prior) do
    MonitoringEvaluator.evaluate(plan, update(n, value), %{}, prior)
  end

  test "an edit resets the counters: the violations counted under the old rule do not count" do
    old = plan("digest-1", 10)
    new = plan("digest-2", 10)

    {r1, s1} = run(old, 1, 50, %{})
    {r2, s2} = run(old, 2, 50, s1)
    assert {r1.violation_count, r2.violation_count} == {1, 2}
    assert r2.metadata == %{}

    # The rules change after two of the three violations: the count starts again.
    {r3, s3} = run(new, 3, 50, s2)
    assert r3.violation_count == 1
    assert r3.transition == nil
    assert r3.effective_state == :normal
    assert r3.metadata == %{rule_changed: %{from: "digest-1", to: "digest-2", rule_ids: []}}
    assert s3.rule_digest == "digest-2"

    # Two more under the new rules reach the three, and the alarm opens.
    {r4, s4} = run(new, 4, 50, s3)
    {r5, _s5} = run(new, 5, 50, s4)
    assert {r4.violation_count, r4.metadata} == {2, %{}}
    assert r5.transition == %{from: :normal, to: :critical}
  end

  test "an open alarm survives an edit and is judged anew: it clears only after the conformance count" do
    old = plan("digest-1", 10, violations: 1)
    new = plan("digest-2", 100, violations: 1)

    {_r, open} = run(old, 1, 50, %{})
    assert open.effective_state == :critical

    # 50 is within the new threshold (100): a normal sample, but the count starts at 1 of 2.
    {r2, s2} = run(new, 2, 50, open)
    assert r2.effective_state == :critical
    assert r2.transition == nil
    assert r2.conformance_count == 1
    assert r2.metadata == %{rule_changed: %{from: "digest-1", to: "digest-2", rule_ids: []}}

    {r3, _s3} = run(new, 3, 50, s2)
    assert r3.transition == %{from: :critical, to: :normal}
  end

  test "an unchanged digest, a first evaluation and a state with no digest never say rule_changed" do
    same = plan("digest-1", 10)

    {first, s1} = run(same, 1, 50, %{})
    assert first.metadata == %{}
    assert s1.rule_digest == "digest-1"

    {again, _s2} = run(same, 2, 50, s1)
    assert again.metadata == %{}

    # State written before plans carried digests: the plan's digest is adopted, counts kept.
    legacy_state = %{
      effective_state: :normal,
      candidate_state: :critical,
      violation_count: 2,
      conformance_count: 0
    }

    {adopted, s3} = run(same, 3, 50, legacy_state)
    assert adopted.metadata == %{}
    assert adopted.transition == %{from: :normal, to: :critical}
    assert s3.rule_digest == "digest-1"
  end

  test "a plan with no digest leaves results and state exactly as before" do
    legacy = plan(nil, 10)

    {r1, s1} = run(legacy, 1, 50, %{})
    {r2, s2} = run(legacy, 2, 50, s1)
    assert r1.metadata == %{} and r2.metadata == %{}
    refute Map.has_key?(s2, :rule_digest)
    assert r2.violation_count == 2

    # Even after a state that carries a digest (a plan rolled back to one without digests): no
    # reset, no event, and the state goes back to what a digest-less plan writes.
    {r3, s3} = run(legacy, 3, 50, Map.put(s2, :rule_digest, "digest-1"))
    assert r3.metadata == %{}
    assert r3.violation_count == 3
    refute Map.has_key?(s3, :rule_digest)
  end
end
