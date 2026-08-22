defmodule Cadence.ContactPlanning.AutomationGrantsTest do
  use Cadence.DataCase, async: false

  alias Cadence.Accounts.{OrganizationMembership, User}
  alias Cadence.Auth
  alias Cadence.Auth.{Scope, ServiceIdentity}

  alias Cadence.ContactPlanning.{
    AutomationGrants,
    FleetPlanningPolicies
  }

  @organization_id "org-automation-grants"
  @mission_id "mission-automation-grants"
  @now ~U[2026-07-17 10:00:00.000000Z]

  setup do
    %{organization: organization} =
      persist_mission_scope(@organization_id, @mission_id)

    admin_scope = scope(organization, :organization_admin)
    member_scope = scope(organization, :member)

    assert {:ok, policy, policy_version} =
             FleetPlanningPolicies.create(admin_scope, @mission_id, policy_attrs())

    assert {:ok, _active, ^policy_version, _approval} =
             FleetPlanningPolicies.approve(
               admin_scope,
               @mission_id,
               policy.fleet_planning_policy_id,
               policy_version.version,
               policy_version.content_sha256,
               "Enable bounded automation"
             )

    service_identity =
      ServiceIdentity.new(%{
        service_identity_id: "svc-fleet-automation",
        organization_id: @organization_id,
        mission_id: @mission_id,
        display_name: "Fleet automation",
        capabilities: [:mission_admin]
      })

    assert {:ok, issued} = Auth.issue_service_identity(service_identity)
    assert {:ok, service_scope} = Auth.authenticate_api_token(issued.api_token)

    %{
      admin_scope: admin_scope,
      member_scope: member_scope,
      service_scope: service_scope,
      service_identity: issued.service_identity,
      policy: policy,
      policy_version: policy_version
    }
  end

  test "an administrator issues an exact bounded grant and members cannot", context do
    assert {:error, :forbidden} =
             AutomationGrants.issue(
               context.member_scope,
               @mission_id,
               grant_attrs(context.service_identity)
             )

    assert {:ok, grant} =
             AutomationGrants.issue(
               context.admin_scope,
               @mission_id,
               grant_attrs(context.service_identity),
               now: @now
             )

    assert grant.lifecycle_state == :active
    assert grant.service_identity_id == context.service_identity.service_identity_id
    assert grant.fleet_planning_policy_id == context.policy.fleet_planning_policy_id
    assert grant.fleet_planning_policy_version == context.policy_version.version
    assert grant.allowed_actions == [:approve, :execute, :plan, :repair, :submit]
    assert grant.maximum_horizon_seconds == 3_600
    assert grant.maximum_contacts == 5
    assert grant.maximum_estimated_cost_micros == 500
    assert grant.currency == "USD"
    assert grant.maximum_execution_concurrency == 2
    assert grant.approved_by == context.admin_scope.user.user_id
    assert grant.content_sha256 =~ ~r/\A[0-9a-f]{64}\z/

    assert {:ok, ^grant} =
             AutomationGrants.fetch(
               @organization_id,
               @mission_id,
               grant.automation_grant_id
             )

    assert [^grant] =
             AutomationGrants.list(
               @organization_id,
               @mission_id,
               lifecycle_state: :active
             )
  end

  test "grant bounds and policy action ceilings fail closed", context do
    assert {:error, :automation_grant_horizon_exceeds_policy} =
             AutomationGrants.issue(
               context.admin_scope,
               @mission_id,
               grant_attrs(context.service_identity, %{maximum_horizon_seconds: 86_401}),
               now: @now
             )

    assert {:error, :automation_grant_contacts_exceed_policy} =
             AutomationGrants.issue(
               context.admin_scope,
               @mission_id,
               grant_attrs(context.service_identity, %{maximum_contacts: 11}),
               now: @now
             )

    assert {:error, :automation_grant_cost_exceeds_policy} =
             AutomationGrants.issue(
               context.admin_scope,
               @mission_id,
               grant_attrs(context.service_identity, %{
                 maximum_estimated_cost_micros: 1_001
               }),
               now: @now
             )

    assert {:error, :automation_grant_concurrency_exceeds_policy} =
             AutomationGrants.issue(
               context.admin_scope,
               @mission_id,
               grant_attrs(context.service_identity, %{
                 maximum_execution_concurrency: 5
               }),
               now: @now
             )
  end

  test "service authorization requires exact action, evidence, time, actor, and policy",
       context do
    assert {:ok, grant} =
             AutomationGrants.issue(
               context.admin_scope,
               @mission_id,
               grant_attrs(context.service_identity),
               now: @now
             )

    assert {:ok, ^grant} =
             AutomationGrants.authorize(
               context.service_scope,
               @mission_id,
               grant.automation_grant_id,
               :plan,
               %{horizon_seconds: 3_600},
               now: @now
             )

    assert {:error, :automation_grant_horizon_exceeded} =
             AutomationGrants.authorize(
               context.service_scope,
               @mission_id,
               grant.automation_grant_id,
               :plan,
               %{horizon_seconds: 3_601},
               now: @now
             )

    assert {:error, :automation_grant_contact_evidence_required} =
             AutomationGrants.authorize(
               context.service_scope,
               @mission_id,
               grant.automation_grant_id,
               :execute,
               %{execution_concurrency: 2},
               now: @now
             )

    assert {:error, :automation_grant_cost_evidence_required} =
             AutomationGrants.authorize(
               context.service_scope,
               @mission_id,
               grant.automation_grant_id,
               :execute,
               %{contact_count: 2, execution_concurrency: 2},
               now: @now
             )

    assert {:ok, ^grant} =
             AutomationGrants.authorize(
               context.service_scope,
               @mission_id,
               grant.automation_grant_id,
               :execute,
               %{
                 contact_count: 2,
                 estimated_cost_micros: 400,
                 currency: "usd",
                 execution_concurrency: 2
               },
               now: @now
             )

    assert {:error, :automation_grant_cost_limit_exceeded} =
             AutomationGrants.authorize(
               context.service_scope,
               @mission_id,
               grant.automation_grant_id,
               :execute,
               %{
                 contact_count: 2,
                 estimated_cost_micros: 501,
                 currency: "USD",
                 execution_concurrency: 2
               },
               now: @now
             )

    assert {:error, :automation_grant_expired} =
             AutomationGrants.authorize(
               context.service_scope,
               @mission_id,
               grant.automation_grant_id,
               :plan,
               %{horizon_seconds: 3_600},
               now: DateTime.add(@now, 86_400, :second)
             )
  end

  test "revocation is exact, durable, and immediately stops the service", context do
    assert {:ok, grant} =
             AutomationGrants.issue(
               context.admin_scope,
               @mission_id,
               grant_attrs(context.service_identity),
               now: @now
             )

    assert {:error, :stale_automation_grant_hash} =
             AutomationGrants.revoke(
               context.admin_scope,
               @mission_id,
               grant.automation_grant_id,
               String.duplicate("0", 64),
               "Wrong hash",
               now: @now
             )

    assert {:ok, revoked} =
             AutomationGrants.revoke(
               context.admin_scope,
               @mission_id,
               grant.automation_grant_id,
               grant.content_sha256,
               "Pause unattended scheduling",
               now: DateTime.add(@now, 60, :second)
             )

    assert revoked.lifecycle_state == :revoked
    assert revoked.revoked_by == context.admin_scope.user.user_id
    assert revoked.revocation_reason == "Pause unattended scheduling"

    assert {:error, :automation_grant_revoked} =
             AutomationGrants.authorize(
               context.service_scope,
               @mission_id,
               grant.automation_grant_id,
               :plan,
               %{horizon_seconds: 3_600},
               now: DateTime.add(@now, 120, :second)
             )
  end

  test "policy drift invalidates a previously active grant", context do
    assert {:ok, grant} =
             AutomationGrants.issue(
               context.admin_scope,
               @mission_id,
               grant_attrs(context.service_identity),
               now: @now
             )

    assert {:ok, _draft, version_two} =
             FleetPlanningPolicies.version(
               context.admin_scope,
               @mission_id,
               context.policy.fleet_planning_policy_id,
               1,
               %{
                 horizon_document: %{
                   "max_horizon_seconds" => 43_200,
                   "requirement_concurrency" => 4,
                   "provider_search_concurrency" => 2,
                   "reuse_freshness_seconds" => 300
                 }
               },
               now: DateTime.add(@now, 60, :second)
             )

    assert {:ok, _active, ^version_two, _approval} =
             FleetPlanningPolicies.approve(
               context.admin_scope,
               @mission_id,
               context.policy.fleet_planning_policy_id,
               version_two.version,
               version_two.content_sha256,
               "Reduce planning horizon",
               now: DateTime.add(@now, 120, :second)
             )

    assert {:error, :automation_grant_policy_drift} =
             AutomationGrants.authorize(
               context.service_scope,
               @mission_id,
               grant.automation_grant_id,
               :plan,
               %{horizon_seconds: 3_600},
               now: DateTime.add(@now, 180, :second)
             )
  end

  defp grant_attrs(service_identity, overrides \\ %{}) do
    Map.merge(
      %{
        service_identity_id: service_identity.service_identity_id,
        allowed_actions: [:plan, :repair, :submit, :approve, :execute],
        maximum_horizon_seconds: 3_600,
        maximum_contacts: 5,
        maximum_estimated_cost_micros: 500,
        currency: "USD",
        maximum_execution_concurrency: 2,
        valid_from: @now,
        valid_until: DateTime.add(@now, 86_400, :second),
        approval_reason: "Bound unattended fleet scheduling"
      },
      overrides
    )
  end

  defp policy_attrs do
    %{
      horizon_document: %{
        "max_horizon_seconds" => 86_400,
        "requirement_concurrency" => 4,
        "provider_search_concurrency" => 2,
        "reuse_freshness_seconds" => 300
      },
      scoring_document: %{},
      resource_policy_document: %{},
      budget_quota_document: %{
        "max_contacts" => 10,
        "max_estimated_cost_micros" => 1_000,
        "currency" => "USD",
        "per_provider" => %{},
        "critical_contact_reserve" => 0,
        "critical_cost_reserve_micros" => 0
      },
      redundancy_document: %{},
      automation_repair_document: %{
        "mode" => "bounded_automatic",
        "execution_concurrency" => 4,
        "max_repair_attempts" => 3,
        "repair_horizon_seconds" => 43_200,
        "automatic_submission" => true
      }
    }
  end

  defp scope(organization, role) do
    user =
      User.new(%{
        user_id: "automation-grant-user-#{role}",
        email: "automation-grant-#{role}@example.test",
        display_name: "Automation Grant #{role}"
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
