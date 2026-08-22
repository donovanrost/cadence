defmodule Cadence.Dashboards.SourceReadinessTest do
  use Cadence.UnitCase, async: true

  alias Cadence.Dashboards.SourceReadiness

  test "normalizes policy attributes and classifies blocking source health" do
    policy =
      SourceReadiness.normalize_policy(%{
        "policy_id" => "strict-ops",
        "block_source_health" => ["unavailable", "degraded"],
        "block_freshness" => ["fresh"],
        "block_connection_test" => ["failed", "blocked"]
      })

    assert policy == %{
             policy_id: "strict_ops",
             block_source_health: [:unavailable, :degraded],
             block_freshness: [:fresh],
             block_connection_test: [:failed, :blocked]
           }

    assert %{
             blocked?: true,
             reasons: [:source_degraded],
             policy_id: "strict_ops"
           } =
             SourceReadiness.classify(
               %{source_health: :degraded, freshness: :fresh},
               policy
             )

    assert %{
             blocked?: false,
             reasons: []
           } =
             SourceReadiness.classify(
               %{source_health: :degraded, freshness: :stale},
               policy
             )
  end

  test "falls back to default policy when policy values are invalid" do
    assert SourceReadiness.normalize_policy(block_source_health: [:unsupported]) ==
             SourceReadiness.default_policy()
  end

  test "classifies blocked connection-test results independently of source health" do
    policy = SourceReadiness.default_policy()

    assert %{
             blocked?: true,
             reasons: [:connection_test_failed],
             connection_test_result: :failed
           } =
             SourceReadiness.classify(
               %{source_health: :healthy, freshness: :fresh, connection_test_result: "failed"},
               policy
             )

    assert %{
             blocked?: true,
             reasons: [:connection_test_blocked],
             connection_test_result: :blocked
           } =
             SourceReadiness.classify(
               %{
                 source_health: :healthy,
                 freshness: :fresh,
                 status: %{payload: %{"connection_test_result" => "blocked"}}
               },
               policy
             )

    assert %{
             blocked?: false,
             reasons: []
           } =
             SourceReadiness.classify(
               %{
                 source_health: :healthy,
                 freshness: :fresh,
                 status: %{payload: %{"connection_test_result" => "unsupported"}}
               },
               policy
             )
  end
end
