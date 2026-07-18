defmodule Cadence.ContactPlanning.FleetPlanningPoliciesTest do
  use Cadence.DataCase, async: false

  alias Cadence.Accounts.{OrganizationMembership, User}
  alias Cadence.Auth.Scope

  alias Cadence.ContactPlanning.{
    FleetPlanningPolicies,
    FleetPlanningPolicyDocument
  }

  @organization_id "org-fleet-planning-policy"
  @mission_id "mission-fleet-planning-policy"
  @now ~U[2026-07-17 02:00:00.000000Z]

  setup do
    %{organization: organization} =
      persist_mission_scope(@organization_id, @mission_id)

    %{
      admin_scope: scope(organization, :organization_admin),
      member_scope: scope(organization, :member)
    }
  end

  test "policy documents normalize defaults and reject ambiguous automation or cost" do
    assert {:ok, horizon} = FleetPlanningPolicyDocument.normalize_horizon(%{})
    assert horizon["max_horizon_seconds"] == 7 * 24 * 60 * 60
    assert horizon["requirement_concurrency"] == 8

    assert {:error, {:unknown_fleet_planning_policy_field, :horizon, "surprise"}} =
             FleetPlanningPolicyDocument.normalize_horizon(%{"surprise" => true})

    assert {:error, {:invalid_fleet_planning_policy_field, :budgets, "currency"}} =
             FleetPlanningPolicyDocument.normalize_budgets(%{
               "max_estimated_cost_micros" => 100
             })

    assert {:error, :advisory_policy_cannot_submit_automatically} =
             FleetPlanningPolicyDocument.normalize_automation(%{
               "mode" => "advisory",
               "automatic_submission" => true
             })
  end

  test "an administrator creates a normalized draft while members fail closed", context do
    assert {:error, :forbidden} =
             FleetPlanningPolicies.create(
               context.member_scope,
               @mission_id,
               policy_attrs()
             )

    assert {:ok, policy, version} =
             FleetPlanningPolicies.create(
               context.admin_scope,
               @mission_id,
               policy_attrs(),
               now: @now
             )

    assert policy.lifecycle_state == :draft
    assert policy.current_version == 1
    assert policy.active_version == nil
    assert version.horizon_document["requirement_concurrency"] == 12
    assert version.scoring_document["priority_weight"] == 2_000
    assert version.budget_quota_document["currency"] == "USD"
    assert version.content_sha256 =~ ~r/\A[0-9a-f]{64}\z/

    assert {:error, :active_fleet_planning_policy_not_found} =
             FleetPlanningPolicies.fetch_active(@organization_id, @mission_id)
  end

  test "approval activates one exact hash with named administrator evidence", context do
    assert {:ok, policy, version} =
             FleetPlanningPolicies.create(
               context.admin_scope,
               @mission_id,
               policy_attrs(),
               now: @now
             )

    assert {:error, :stale_fleet_planning_policy_hash} =
             FleetPlanningPolicies.approve(
               context.admin_scope,
               @mission_id,
               policy.fleet_planning_policy_id,
               1,
               String.duplicate("0", 64),
               "Wrong hash"
             )

    assert {:ok, active, ^version, approval} =
             FleetPlanningPolicies.approve(
               context.admin_scope,
               @mission_id,
               policy.fleet_planning_policy_id,
               1,
               version.content_sha256,
               "Approved for advisory fleet planning",
               now: DateTime.add(@now, 60, :second)
             )

    assert active.lifecycle_state == :active
    assert active.active_version == 1
    assert approval.decision == :approved
    assert approval.actor_user_id == context.admin_scope.user.user_id
    assert approval.actor_document["display_name"] == "Fleet Policy organization_admin"

    assert {:ok, ^active, ^version} =
             FleetPlanningPolicies.fetch_active(@organization_id, @mission_id)

    assert [^approval] =
             FleetPlanningPolicies.list_approvals(
               @organization_id,
               @mission_id,
               policy.fleet_planning_policy_id
             )
  end

  test "a new draft version leaves the approved version active until exact approval", context do
    assert {:ok, policy, version_one} =
             FleetPlanningPolicies.create(
               context.admin_scope,
               @mission_id,
               policy_attrs(),
               now: @now
             )

    assert {:ok, active_one, ^version_one, _approval} =
             FleetPlanningPolicies.approve(
               context.admin_scope,
               @mission_id,
               policy.fleet_planning_policy_id,
               1,
               version_one.content_sha256,
               "Initial policy"
             )

    assert {:ok, draft_two, version_two} =
             FleetPlanningPolicies.version(
               context.admin_scope,
               @mission_id,
               policy.fleet_planning_policy_id,
               1,
               %{
                 "horizon_document" => %{
                   "max_horizon_seconds" => 3 * 24 * 60 * 60,
                   "requirement_concurrency" => 16
                 }
               },
               now: DateTime.add(@now, 120, :second)
             )

    assert draft_two.current_version == 2
    assert draft_two.active_version == 1
    assert version_two.horizon_document["requirement_concurrency"] == 16

    assert {:ok, fetched, fetched_current} =
             FleetPlanningPolicies.fetch(@organization_id, @mission_id)

    assert fetched.current_version == 2
    assert fetched_current.version == 2

    assert {:ok, active_before, active_version_before} =
             FleetPlanningPolicies.fetch_active(@organization_id, @mission_id)

    assert active_before.active_version == 1
    assert active_version_before.version == 1

    assert {:error, :stale_fleet_planning_policy_version} =
             FleetPlanningPolicies.approve(
               context.admin_scope,
               @mission_id,
               policy.fleet_planning_policy_id,
               1,
               version_one.content_sha256,
               "Stale approval"
             )

    assert {:ok, active_two, ^version_two, _approval} =
             FleetPlanningPolicies.approve(
               context.admin_scope,
               @mission_id,
               policy.fleet_planning_policy_id,
               2,
               version_two.content_sha256,
               "Expanded concurrency approved"
             )

    assert active_two.active_version == 2
    assert active_one.fleet_planning_policy_id == active_two.fleet_planning_policy_id
  end

  test "concurrent decisions serialize and only one exact version wins", context do
    assert {:ok, policy, version} =
             FleetPlanningPolicies.create(
               context.admin_scope,
               @mission_id,
               policy_attrs(),
               now: @now
             )

    results =
      [:approved, :rejected]
      |> Task.async_stream(
        fn
          :approved ->
            FleetPlanningPolicies.approve(
              context.admin_scope,
              @mission_id,
              policy.fleet_planning_policy_id,
              1,
              version.content_sha256,
              "Approve"
            )

          :rejected ->
            FleetPlanningPolicies.reject(
              context.admin_scope,
              @mission_id,
              policy.fleet_planning_policy_id,
              1,
              version.content_sha256,
              "Reject"
            )
        end,
        ordered: false,
        timeout: :infinity
      )
      |> Enum.map(fn {:ok, result} -> result end)

    assert Enum.count(results, &match?({:ok, _policy, _version, _approval}, &1)) == 1

    assert Enum.count(
             results,
             &(&1 == {:error, :fleet_planning_policy_already_decided})
           ) == 1
  end

  test "retirement removes active policy and prevents further versions", context do
    assert {:ok, policy, version} =
             FleetPlanningPolicies.create(
               context.admin_scope,
               @mission_id,
               policy_attrs(),
               now: @now
             )

    assert {:ok, _active, ^version, _approval} =
             FleetPlanningPolicies.approve(
               context.admin_scope,
               @mission_id,
               policy.fleet_planning_policy_id,
               1,
               version.content_sha256,
               "Activate"
             )

    assert {:ok, retired} =
             FleetPlanningPolicies.retire(
               context.admin_scope,
               @mission_id,
               policy.fleet_planning_policy_id,
               1,
               "Replaced by new mission policy"
             )

    assert retired.lifecycle_state == :retired
    assert retired.active_version == nil

    assert {:error, :active_fleet_planning_policy_not_found} =
             FleetPlanningPolicies.fetch_active(@organization_id, @mission_id)

    assert {:error, :fleet_planning_policy_retired} =
             FleetPlanningPolicies.version(
               context.admin_scope,
               @mission_id,
               policy.fleet_planning_policy_id,
               1,
               %{}
             )
  end

  defp policy_attrs do
    %{
      horizon_document: %{
        "max_horizon_seconds" => 7 * 24 * 60 * 60,
        "requirement_concurrency" => 12,
        "provider_search_concurrency" => 4,
        "reuse_freshness_seconds" => 300
      },
      scoring_document: %{
        "priority_weight" => 2_000,
        "deadline_weight" => 1_000,
        "scarcity_weight" => 800,
        "local_improvement_limit" => 200,
        "local_improvement_width" => 3
      },
      resource_policy_document: %{
        "default_exclusive_capacity" => 1,
        "capacities" => %{"provider-a:station-1:antenna-1" => 2}
      },
      budget_quota_document: %{
        "max_contacts" => 1_000,
        "max_estimated_cost_micros" => 10_000_000_000,
        "currency" => "usd",
        "per_provider" => %{
          "provider-a" => %{
            "max_contacts" => 600,
            "max_estimated_cost_micros" => 8_000_000_000
          }
        },
        "critical_contact_reserve" => 100,
        "critical_cost_reserve_micros" => 1_000_000_000
      },
      redundancy_document: %{
        "distinct_provider_required" => true,
        "distinct_station_required" => false,
        "distinct_service_pool_required" => false
      },
      automation_repair_document: %{
        "mode" => "approval_required",
        "execution_concurrency" => 4,
        "max_repair_attempts" => 3,
        "repair_horizon_seconds" => 86_400,
        "automatic_submission" => true
      }
    }
  end

  defp scope(organization, role) do
    user =
      User.new(%{
        user_id: "fleet-policy-user-#{role}",
        email: "fleet-policy-#{role}@example.test",
        display_name: "Fleet Policy #{role}"
      })

    membership =
      OrganizationMembership.new(%{
        user_id: user.user_id,
        organization_id: organization.organization_id,
        role: role
      })

    Scope.new(%{
      user: user,
      organization_id: organization.organization_id,
      organization: organization,
      organization_membership: membership
    })
  end
end
