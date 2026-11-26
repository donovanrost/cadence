defmodule Cadence.AutomationGrantFixtures do
  @moduledoc """
  A mission with an active, bounded fleet planning policy, two org admins (a proposer and an
  approver), a member, and a service identity issued by a third person, for automation grant
  tests (#283).
  """
  import ExUnit.Assertions

  alias Cadence.Accounts.{OrganizationMembership, OrganizationMembershipRow, User, UserRow}
  alias Cadence.Auth
  alias Cadence.Auth.{Scope, ServiceIdentity}
  alias Cadence.ContactPlanning.FleetPlanningPolicies
  alias Cadence.PolicyReviewer
  alias Cadence.Repo

  @now ~U[2026-07-17 10:00:00.000000Z]

  def now, do: @now

  def setup!(prefix) do
    n = System.unique_integer([:positive])
    org = "org-#{prefix}-#{n}"
    mission = "mission-#{prefix}-#{n}"
    %{organization: organization} = Cadence.DataCase.persist_mission_scope(org, mission)

    proposer = person!(organization, :organization_admin, "proposer-#{n}")
    approver = person!(organization, :organization_admin, "approver-#{n}")
    third = person!(organization, :organization_admin, "third-#{n}")
    issuer = person!(organization, :organization_admin, "issuer-#{n}")
    member = person!(organization, :member, "member-#{n}")

    assert {:ok, policy, version} =
             FleetPlanningPolicies.create(proposer, mission, policy_attrs())

    assert {:ok, _active, ^version, _approval} =
             FleetPlanningPolicies.approve(
               PolicyReviewer.reviewer(proposer),
               mission,
               policy.fleet_planning_policy_id,
               version.version,
               version.content_sha256,
               "Enable bounded automation"
             )

    identity =
      ServiceIdentity.new(%{
        service_identity_id: "svc-#{prefix}-#{n}",
        organization_id: org,
        mission_id: mission,
        display_name: "Nightly planner",
        capabilities: [:mission_admin]
      })

    assert {:ok, issued} = Auth.issue_service_identity(identity, issuer)
    assert {:ok, service_scope} = Auth.authenticate_api_token(issued.api_token)

    %{
      org: org,
      mission: mission,
      organization: organization,
      proposer: proposer,
      approver: approver,
      third: third,
      issuer: issuer,
      member: member,
      service: issued.service_identity,
      service_scope: service_scope,
      policy: policy,
      policy_version: version
    }
  end

  def grant_attrs(service, overrides \\ %{}) do
    Map.merge(
      %{
        service_identity_id: service.service_identity_id,
        allowed_actions: [:plan, :repair, :submit, :approve, :execute],
        maximum_horizon_seconds: 3_600,
        maximum_contacts: 5,
        maximum_estimated_cost_micros: 500,
        currency: "USD",
        maximum_execution_concurrency: 2,
        validity_seconds: 86_400,
        approval_reason: "Bound unattended fleet scheduling"
      },
      overrides
    )
  end

  def policy_attrs do
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

  @doc "A persisted person (user and active membership) and their scope."
  def person!(organization, role, user_id) do
    user =
      User.new(%{
        user_id: user_id,
        email: "#{user_id}@example.test",
        display_name: user_id
      })

    membership =
      OrganizationMembership.new(%{
        user_id: user_id,
        organization_id: organization.organization_id,
        role: role
      })

    Repo.insert!(UserRow.changeset(user))
    Repo.insert!(OrganizationMembershipRow.changeset(membership))

    Scope.new(%{
      user: user,
      organization_id: organization.organization_id,
      organization: organization,
      organization_membership: membership
    })
  end
end
