defmodule Cadence.ContactPlanning.FleetOptimizerTest do
  use ExUnit.Case, async: true

  alias Cadence.ContactPlanning.{
    ContactOpportunitySnapshot,
    ContactRequirementVersion,
    FleetOptimizer,
    FleetPlanningPolicyVersion
  }

  @organization_id "org-fleet-optimizer"
  @mission_id "mission-fleet-optimizer"
  @now ~U[2026-07-17 06:00:00.000000Z]

  test "identical normalized inputs produce identical selections with stable ID tie breaks" do
    requirement = requirement("stable")

    later_id =
      snapshot(requirement, "zulu", 3_600, 4_500,
        provider: "provider-a",
        station: "station-a"
      )

    earlier_id =
      snapshot(requirement, "alpha", 3_600, 4_500,
        provider: "provider-a",
        station: "station-a"
      )

    policy = policy()

    assert {:ok, first} =
             FleetOptimizer.optimize(
               [requirement],
               [later_id, earlier_id],
               policy,
               now: @now
             )

    assert {:ok, second} =
             FleetOptimizer.optimize(
               [requirement],
               [earlier_id, later_id],
               policy,
               now: @now
             )

    assert first.selected_snapshot_ids == ["snapshot-alpha"]
    assert second.selected_snapshot_ids == first.selected_snapshot_ids
    assert second.decisions == first.decisions
    assert second.coverage_by_requirement == first.coverage_by_requirement

    assert decision(first, "snapshot-alpha").disposition == :selected
    assert decision(first, "snapshot-zulu").disposition == :displaced

    assert decision(first, "snapshot-zulu").explanation_document["code"] ==
             "requirement_already_satisfied"
  end

  test "earlier demand wins and same-spacecraft overlap is a hard fleet constraint" do
    early =
      requirement("early",
        spacecraft_id: "spacecraft-shared",
        latest_end: DateTime.add(@now, 7_200, :second),
        priority: :routine
      )

    later =
      requirement("later",
        spacecraft_id: "spacecraft-shared",
        latest_end: DateTime.add(@now, 10_800, :second),
        priority: :critical
      )

    early_snapshot =
      snapshot(early, "early", 3_600, 5_400,
        provider: "provider-a",
        station: "station-a"
      )

    later_snapshot =
      snapshot(later, "later", 4_500, 6_300,
        provider: "provider-b",
        station: "station-b"
      )

    assert {:ok, result} =
             FleetOptimizer.optimize(
               [later, early],
               [later_snapshot, early_snapshot],
               policy(),
               now: @now
             )

    assert result.selected_snapshot_ids == ["snapshot-early"]

    assert failure_codes(decision(result, "snapshot-later")) == [
             "same_spacecraft_overlap"
           ]

    assert result.coverage_by_requirement[early.contact_requirement_id]["state"] ==
             "satisfied"

    assert result.coverage_by_requirement[later.contact_requirement_id]["state"] ==
             "unsatisfied"
  end

  test "declared exclusive resource capacity controls overlapping spacecraft contacts" do
    requirement_a = requirement("resource-a", spacecraft_id: "spacecraft-a")
    requirement_b = requirement("resource-b", spacecraft_id: "spacecraft-b")

    snapshot_a =
      snapshot(requirement_a, "resource-a", 3_600, 5_400,
        provider: "provider-shared",
        station: "station-shared",
        service_pool: "pool-shared"
      )

    snapshot_b =
      snapshot(requirement_b, "resource-b", 3_600, 5_400,
        provider: "provider-shared",
        station: "station-shared",
        service_pool: "pool-shared"
      )

    assert {:ok, constrained} =
             FleetOptimizer.optimize(
               [requirement_a, requirement_b],
               [snapshot_b, snapshot_a],
               policy(),
               now: @now
             )

    assert constrained.selected_snapshot_ids == ["snapshot-resource-a"]

    assert failure_codes(decision(constrained, "snapshot-resource-b")) == [
             "exclusive_resource_capacity_exhausted"
           ]

    capacity_two =
      policy(
        resources: %{
          "default_exclusive_capacity" => 1,
          "capacities" => %{"provider-shared:station-shared:pool-shared" => 2}
        }
      )

    assert {:ok, unconstrained} =
             FleetOptimizer.optimize(
               [requirement_a, requirement_b],
               [snapshot_b, snapshot_a],
               capacity_two,
               now: @now
             )

    assert unconstrained.selected_snapshot_ids == [
             "snapshot-resource-a",
             "snapshot-resource-b"
           ]

    assert get_in(
             unconstrained.resource_summary,
             ["resources", "provider-shared:station-shared:pool-shared", "peak_parallel"]
           ) == 2
  end

  test "lower-priority work cannot consume the critical contact reserve" do
    routine_a =
      requirement("routine-a",
        spacecraft_id: "spacecraft-routine-a",
        latest_end: DateTime.add(@now, 7_200, :second)
      )

    routine_b =
      requirement("routine-b",
        spacecraft_id: "spacecraft-routine-b",
        latest_end: DateTime.add(@now, 8_100, :second)
      )

    critical =
      requirement("critical",
        spacecraft_id: "spacecraft-critical",
        latest_end: DateTime.add(@now, 10_800, :second),
        priority: :critical
      )

    snapshots = [
      snapshot(routine_a, "routine-a", 3_600, 4_200,
        provider: "provider-a",
        station: "station-a"
      ),
      snapshot(routine_b, "routine-b", 4_200, 4_800,
        provider: "provider-b",
        station: "station-b"
      ),
      snapshot(critical, "critical", 4_800, 5_400,
        provider: "provider-c",
        station: "station-c"
      )
    ]

    reserve_policy =
      policy(
        budgets: %{
          "max_contacts" => 2,
          "max_estimated_cost_micros" => nil,
          "currency" => nil,
          "per_provider" => %{},
          "critical_contact_reserve" => 1,
          "critical_cost_reserve_micros" => 0
        }
      )

    assert {:ok, result} =
             FleetOptimizer.optimize(
               [routine_a, routine_b, critical],
               Enum.reverse(snapshots),
               reserve_policy,
               now: @now
             )

    assert result.selected_snapshot_ids == [
             "snapshot-routine-a",
             "snapshot-critical"
           ]

    assert failure_codes(decision(result, "snapshot-routine-b")) == [
             "critical_contact_reserve_protected"
           ]
  end

  test "hard cost ceilings reject unknown currency evidence and enforce aggregate budget" do
    unknown_requirement = requirement("unknown-cost", spacecraft_id: "spacecraft-unknown")

    unknown =
      snapshot(unknown_requirement, "unknown-cost", 3_600, 4_200,
        provider: "provider-unknown",
        station: "station-unknown"
      )

    wrong_currency_requirement =
      requirement("wrong-currency", spacecraft_id: "spacecraft-currency")

    wrong_currency =
      snapshot(wrong_currency_requirement, "wrong-currency", 4_200, 4_800,
        provider: "provider-currency",
        station: "station-currency",
        cost: {50, "EUR"}
      )

    first = requirement("budget-a", spacecraft_id: "spacecraft-budget-a")
    second = requirement("budget-b", spacecraft_id: "spacecraft-budget-b")

    first_snapshot =
      snapshot(first, "budget-a", 4_800, 5_400,
        provider: "provider-a",
        station: "station-a",
        cost: {100, "USD"}
      )

    second_snapshot =
      snapshot(second, "budget-b", 5_400, 6_000,
        provider: "provider-b",
        station: "station-b",
        cost: {100, "USD"}
      )

    cost_policy =
      policy(
        budgets: %{
          "max_contacts" => 10,
          "max_estimated_cost_micros" => 150,
          "currency" => "USD",
          "per_provider" => %{},
          "critical_contact_reserve" => 0,
          "critical_cost_reserve_micros" => 0
        }
      )

    assert {:ok, result} =
             FleetOptimizer.optimize(
               [unknown_requirement, wrong_currency_requirement, first, second],
               [second_snapshot, wrong_currency, unknown, first_snapshot],
               cost_policy,
               now: @now
             )

    assert decision(result, "snapshot-unknown-cost").disposition == :ineligible

    assert failure_codes(decision(result, "snapshot-unknown-cost")) == [
             "estimated_cost_unknown"
           ]

    assert failure_codes(decision(result, "snapshot-wrong-currency")) == [
             "estimated_cost_currency_mismatch"
           ]

    assert result.selected_snapshot_ids == ["snapshot-budget-a"]

    assert failure_codes(decision(result, "snapshot-budget-b")) == [
             "global_cost_budget_exhausted"
           ]

    assert result.budget_summary["known_cost_micros"] == 100
    assert result.budget_summary["currency"] == "USD"
  end

  test "minimum volume may select several contacts and redundancy requires distinct providers" do
    volume_requirement =
      requirement("volume",
        spacecraft_id: "spacecraft-volume",
        success_measure: :minimum_data_volume,
        minimum_data_volume_bytes: 150,
        contact_count: 1,
        latest_end: DateTime.add(@now, 14_400, :second)
      )

    first_volume =
      snapshot(volume_requirement, "volume-a", 3_600, 4_200,
        provider: "provider-a",
        station: "station-a",
        volume: 100
      )

    second_volume =
      snapshot(volume_requirement, "volume-b", 5_400, 6_000,
        provider: "provider-b",
        station: "station-b",
        volume: 100
      )

    assert {:ok, volume_result} =
             FleetOptimizer.optimize(
               [volume_requirement],
               [second_volume, first_volume],
               policy(),
               now: @now
             )

    assert volume_result.selected_snapshot_ids == [
             "snapshot-volume-a",
             "snapshot-volume-b"
           ]

    assert volume_result.coverage_by_requirement[volume_requirement.contact_requirement_id][
             "state"
           ] == "satisfied"

    redundant_requirement =
      requirement("redundant",
        spacecraft_id: "spacecraft-redundant",
        contact_count: 2,
        latest_end: DateTime.add(@now, 18_000, :second)
      )

    provider_a_one =
      snapshot(redundant_requirement, "provider-a-one", 3_600, 4_200,
        provider: "provider-a",
        station: "station-a-one"
      )

    provider_a_two =
      snapshot(redundant_requirement, "provider-a-two", 5_400, 6_000,
        provider: "provider-a",
        station: "station-a-two"
      )

    provider_b =
      snapshot(redundant_requirement, "provider-b", 7_200, 7_800,
        provider: "provider-b",
        station: "station-b"
      )

    redundancy_policy =
      policy(
        redundancy: %{
          "distinct_provider_required" => true,
          "distinct_station_required" => false,
          "distinct_service_pool_required" => false
        },
        scoring: %{"diversity_weight" => 0}
      )

    assert {:ok, redundancy_result} =
             FleetOptimizer.optimize(
               [redundant_requirement],
               [provider_a_two, provider_b, provider_a_one],
               redundancy_policy,
               now: @now
             )

    assert redundancy_result.selected_snapshot_ids == [
             "snapshot-provider-a-one",
             "snapshot-provider-b"
           ]

    assert failure_codes(decision(redundancy_result, "snapshot-provider-a-two")) == [
             "redundancy_not_distinct"
           ]

    assert get_in(
             redundancy_result.coverage_by_requirement,
             [
               redundant_requirement.contact_requirement_id,
               "redundancy",
               "dimensions",
               "provider",
               "distinct_count"
             ]
           ) == 2
  end

  test "locked commitments remain selected and block conflicting new work" do
    locked_requirement =
      requirement("locked",
        spacecraft_id: "spacecraft-locked",
        latest_end: DateTime.add(@now, 10_800, :second)
      )

    candidate_requirement =
      requirement("candidate",
        spacecraft_id: "spacecraft-locked",
        latest_end: DateTime.add(@now, 11_700, :second)
      )

    locked =
      snapshot(locked_requirement, "locked", 3_600, 5_400,
        provider: "provider-locked",
        station: "station-locked",
        expires_at: DateTime.add(@now, -60, :second)
      )

    candidate =
      snapshot(candidate_requirement, "candidate", 4_500, 6_300,
        provider: "provider-new",
        station: "station-new"
      )

    assert {:ok, result} =
             FleetOptimizer.optimize(
               [candidate_requirement, locked_requirement],
               [candidate],
               policy(),
               now: @now,
               locked_commitments: [locked]
             )

    assert result.selected_snapshot_ids == ["snapshot-locked"]
    assert decision(result, "snapshot-locked").disposition == :locked
    assert decision(result, "snapshot-locked").rank == 1

    assert failure_codes(decision(result, "snapshot-candidate")) == [
             "same_spacecraft_overlap"
           ]

    assert result.termination_document["locked_snapshot_count"] == 1
  end

  test "local improvement work is bounded by the approved policy" do
    requirement = requirement("bounded")

    snapshots =
      for suffix <- ~w(a b c d) do
        snapshot(requirement, suffix, 3_600, 4_500,
          provider: "provider-a",
          station: "station-a"
        )
      end

    bounded_policy =
      policy(
        scoring: %{
          "priority_weight" => 1_000,
          "deadline_weight" => 800,
          "scarcity_weight" => 600,
          "preferred_duration_weight" => 300,
          "volume_weight" => 300,
          "confidence_weight" => 200,
          "cost_efficiency_weight" => 100,
          "diversity_weight" => 200,
          "fragmentation_penalty" => 100,
          "expiry_risk_penalty" => 200,
          "local_improvement_limit" => 1,
          "local_improvement_width" => 2
        }
      )

    assert {:ok, result} =
             FleetOptimizer.optimize(
               [requirement],
               Enum.reverse(snapshots),
               bounded_policy,
               now: @now
             )

    assert result.termination_document["local_improvement_evaluations"] == 1
    assert result.termination_document["local_improvement_limit"] == 1
    assert result.termination_document["configured_local_improvement_width"] == 2
    assert result.termination_document["effective_local_improvement_width"] == 1
  end

  test "reserve values cannot exceed or float free of their policy ceilings" do
    assert {:error, {:invalid_fleet_planning_policy_field, :budgets, "critical_contact_reserve"}} =
             FleetPlanningPolicyVersion.new(
               policy_attrs(
                 budgets: %{
                   "max_contacts" => 1,
                   "max_estimated_cost_micros" => nil,
                   "currency" => nil,
                   "per_provider" => %{},
                   "critical_contact_reserve" => 2,
                   "critical_cost_reserve_micros" => 0
                 }
               )
             )

    assert {:error,
            {:invalid_fleet_planning_policy_field, :budgets, "critical_cost_reserve_micros"}} =
             FleetPlanningPolicyVersion.new(
               policy_attrs(
                 budgets: %{
                   "max_contacts" => 10,
                   "max_estimated_cost_micros" => nil,
                   "currency" => nil,
                   "per_provider" => %{},
                   "critical_contact_reserve" => 0,
                   "critical_cost_reserve_micros" => 1
                 }
               )
             )
  end

  defp decision(result, snapshot_id) do
    Enum.find(result.decisions, &(&1.contact_opportunity_snapshot_id == snapshot_id))
  end

  defp failure_codes(decision) do
    Enum.map(decision.hard_constraint_document["failures"], & &1["code"])
  end

  defp requirement(suffix, overrides \\ []) do
    defaults = %{
      contact_requirement_id: "requirement-#{suffix}",
      organization_id: @organization_id,
      mission_id: @mission_id,
      version: 1,
      spacecraft_id: "spacecraft-#{suffix}",
      service_direction: :downlink,
      contact_intent: "payload_downlink",
      earliest_start: DateTime.add(@now, 3_600, :second),
      latest_end: DateTime.add(@now, 10_800, :second),
      success_measure: :minimum_duration,
      minimum_duration_seconds: 600,
      preferred_duration_seconds: 900,
      minimum_data_volume_bytes: nil,
      contact_count: 1,
      minimum_separation_seconds: 0,
      priority: :routine,
      provider_constraints_document: %{"allowed" => [], "excluded" => []},
      station_constraints_document: %{"allowed" => [], "excluded" => []},
      policy_constraints_document: %{},
      approval_policy_document: %{"mode" => "manual"},
      rationale: "Fleet optimizer test",
      metadata: %{},
      created_by: "fleet-optimizer-test",
      created_at: @now
    }

    overrides
    |> Enum.into(defaults)
    |> ContactRequirementVersion.new()
  end

  defp snapshot(requirement, suffix, starts_offset, ends_offset, opts) do
    provider = Keyword.fetch!(opts, :provider)
    station = Keyword.fetch!(opts, :station)
    service_pool = Keyword.get(opts, :service_pool, "pool-#{suffix}")
    volume = Keyword.get(opts, :volume, 1_000)
    expires_at = Keyword.get(opts, :expires_at, DateTime.add(@now, 86_400, :second))

    extensions =
      case Keyword.get(opts, :cost) do
        {micros, currency} ->
          %{"estimated_cost" => %{"amount_micros" => micros, "currency" => currency}}

        nil ->
          %{}
      end

    ContactOpportunitySnapshot.new(%{
      contact_opportunity_snapshot_id: "snapshot-#{suffix}",
      contact_planning_run_id: "planning-run-#{suffix}",
      contact_planning_search_id: "planning-search-#{suffix}",
      organization_id: @organization_id,
      mission_id: @mission_id,
      contact_requirement_id: requirement.contact_requirement_id,
      contact_requirement_version: requirement.version,
      provider_opportunity_ref: "provider-opportunity-#{suffix}",
      starts_at: DateTime.add(@now, starts_offset, :second),
      ends_at: DateTime.add(@now, ends_offset, :second),
      expires_at: expires_at,
      availability: Keyword.get(opts, :availability, :available),
      estimated_capacity_document: %{"bytes" => volume},
      synthetic: Keyword.get(opts, :synthetic, false),
      route_binding_document: %{
        "route_key" => "route-#{suffix}",
        "spacecraft_id" => requirement.spacecraft_id,
        "provider_id" => provider,
        "provider_account_id" => "account-#{provider}",
        "provider_account_grant_id" => "grant-#{provider}",
        "provider_account_grant_version" => 1
      },
      normalized_opportunity_document: %{
        "id" => "provider-opportunity-#{suffix}",
        "ground_station_ref" => station,
        "antenna_or_service_pool_ref" => service_pool,
        "extensions" => extensions
      },
      provider_evidence_document: %{},
      evaluation_document: %{"eligible" => Keyword.get(opts, :eligible, true)},
      eligible: Keyword.get(opts, :eligible, true),
      content_sha256: String.pad_trailing("hash-#{suffix}", 64, "0"),
      captured_at: @now
    })
  end

  defp policy(overrides \\ []) do
    overrides
    |> policy_attrs()
    |> FleetPlanningPolicyVersion.new!()
  end

  defp policy_attrs(overrides) do
    defaults = %{
      fleet_planning_policy_id: "fleet-policy",
      organization_id: @organization_id,
      mission_id: @mission_id,
      version: 1,
      horizon_document: %{},
      scoring_document: %{},
      resource_policy_document: %{},
      budget_quota_document: %{},
      redundancy_document: %{},
      automation_repair_document: %{},
      created_by: "fleet-optimizer-test",
      created_at: @now
    }

    overrides =
      overrides
      |> Enum.map(fn
        {:resources, value} -> {:resource_policy_document, value}
        {:budgets, value} -> {:budget_quota_document, value}
        {:redundancy, value} -> {:redundancy_document, value}
        {:scoring, value} -> {:scoring_document, value}
        item -> item
      end)

    Enum.into(overrides, defaults)
  end
end
