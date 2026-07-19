defmodule Cadence.ContactPlanning.ContactPlanApprovalsTest do
  use Cadence.DataCase, async: false

  alias Cadence.Accounts.{OrganizationMembership, User}
  alias Cadence.Auth.Scope

  alias Cadence.ContactPlanning.{
    ContactPlanApprovals,
    ContactPlans,
    ContactRequirements,
    Planner
  }

  alias Cadence.Spacecraft

  @organization_id "org-contact-plan-approvals"
  @mission_id "mission-contact-plan-approvals"
  @spacecraft_id "spacecraft-contact-plan-approvals"
  @now ~U[2026-07-16 20:00:00.000000Z]

  setup do
    %{organization: organization, mission: mission} =
      persist_mission_scope(@organization_id, @mission_id)

    assert {:ok, _spacecraft} =
             Cadence.SpacecraftStore.persist_spacecraft(
               @organization_id,
               Spacecraft.new(%{
                 spacecraft_id: @spacecraft_id,
                 mission_id: mission.mission_id,
                 display_name: "Asteria"
               })
             )

    member_scope = scope(organization, :member)
    admin_scope = scope(organization, :organization_admin)

    assert {:ok, requirement, requirement_version} =
             ContactRequirements.create(
               member_scope,
               @mission_id,
               requirement_attrs(),
               now: @now
             )

    assert {:ok, planning} =
             Planner.run(
               member_scope,
               @mission_id,
               requirement.contact_requirement_id,
               requirement_version.version,
               now: @now,
               list_routes: fn _, _, _ -> {:ok, %{routes: [route()], findings: []}} end,
               search_opportunities: fn _, _, _, _, _ ->
                 {:ok, %{opportunities: [opportunity()]}}
               end
             )

    [snapshot] = planning.snapshots

    assert {:ok, plan, plan_version} =
             ContactPlans.create(
               member_scope,
               @mission_id,
               %{
                 planning_run_ids: [planning.run.contact_planning_run_id],
                 selected_snapshot_ids: [snapshot.contact_opportunity_snapshot_id],
                 rationale: "Commit the primary provider window"
               },
               now: @now
             )

    assert {:ok, pending_plan} =
             ContactPlans.submit(
               member_scope,
               @mission_id,
               plan.contact_plan_id,
               plan.current_version,
               "Ready for administrator review",
               now: DateTime.add(@now, 1, :second)
             )

    %{
      member_scope: member_scope,
      admin_scope: admin_scope,
      requirement: requirement,
      plan: pending_plan,
      plan_version: plan_version,
      snapshot: snapshot
    }
  end

  test "an organization administrator approves one exact proposal with named evidence", context do
    assert {:ok, plan, version, approval} = approve(context)

    assert plan.lifecycle_state == :approved
    assert plan.approved_version == version.version
    assert plan.approved_by == context.admin_scope.user.user_id
    assert approval.decision == :approved
    assert approval.content_sha256 == version.content_sha256

    assert approval.actor_document == %{
             "kind" => "user",
             "id" => context.admin_scope.user.user_id,
             "user_id" => context.admin_scope.user.user_id,
             "display_name" => context.admin_scope.user.display_name,
             "email" => context.admin_scope.user.email
           }

    assert approval.actor_kind == :user
    assert approval.actor_id == context.admin_scope.user.user_id

    assert ContactPlanApprovals.list(
             @organization_id,
             @mission_id,
             plan.contact_plan_id
           ) == [approval]

    assert {:error, :contact_plan_not_pending_approval} = approve(context)
  end

  test "concurrent approval attempts serialize to one exact decision", context do
    results =
      1..2
      |> Task.async_stream(
        fn _attempt -> approve(context) end,
        ordered: false,
        max_concurrency: 2,
        timeout: :infinity
      )
      |> Enum.map(fn {:ok, result} -> result end)

    assert Enum.count(results, &match?({:ok, _plan, _version, _approval}, &1)) == 1
    assert Enum.count(results, &(&1 == {:error, :contact_plan_not_pending_approval})) == 1

    assert [_approval] =
             ContactPlanApprovals.list(
               @organization_id,
               @mission_id,
               context.plan.contact_plan_id
             )
  end

  test "mission members cannot approve plans", context do
    assert {:error, :forbidden} =
             ContactPlanApprovals.approve(
               context.member_scope,
               @mission_id,
               context.plan.contact_plan_id,
               context.plan.current_version,
               context.plan_version.content_sha256,
               "I should not be able to approve",
               now: DateTime.add(@now, 2, :second),
               resolve_route: route_resolver()
             )
  end

  test "stale version and content hashes fail before provider route validation", context do
    assert {:error, :stale_contact_plan_version} =
             ContactPlanApprovals.approve(
               context.admin_scope,
               @mission_id,
               context.plan.contact_plan_id,
               2,
               context.plan_version.content_sha256,
               "Reviewed",
               resolve_route: route_resolver()
             )

    assert {:error, :stale_contact_plan_content} =
             ContactPlanApprovals.approve(
               context.admin_scope,
               @mission_id,
               context.plan.contact_plan_id,
               1,
               String.duplicate("0", 64),
               "Reviewed",
               resolve_route: route_resolver()
             )
  end

  test "approval detects changed Requirements", context do
    assert {:ok, _requirement, _version} =
             ContactRequirements.version(
               context.member_scope,
               @mission_id,
               context.requirement.contact_requirement_id,
               1,
               %{priority: :critical},
               now: DateTime.add(@now, 2, :second)
             )

    assert {:error, :contact_plan_requirement_changed} = approve(context)
  end

  test "approval detects expired provider opportunities", context do
    assert {:error, :contact_plan_opportunity_expired} =
             ContactPlanApprovals.approve(
               context.admin_scope,
               @mission_id,
               context.plan.contact_plan_id,
               context.plan.current_version,
               context.plan_version.content_sha256,
               "Reviewed after expiry",
               now: DateTime.add(@now, 18_001, :second),
               resolve_route: route_resolver()
             )
  end

  test "approval requires the exact ready route and catches changed bindings", context do
    assert {:error, :contact_plan_route_not_ready} =
             ContactPlanApprovals.approve(
               context.admin_scope,
               @mission_id,
               context.plan.contact_plan_id,
               1,
               context.plan_version.content_sha256,
               "Route reviewed",
               now: DateTime.add(@now, 2, :second),
               resolve_route: fn _, _, _, _ -> {:error, :grant_revoked} end
             )

    changed_route = route(%{transport_version: 99})

    assert {:error, :contact_plan_route_binding_changed} =
             ContactPlanApprovals.approve(
               context.admin_scope,
               @mission_id,
               context.plan.contact_plan_id,
               1,
               context.plan_version.content_sha256,
               "Route reviewed",
               now: DateTime.add(@now, 2, :second),
               resolve_route: fn _, _, _, _ -> {:ok, changed_route} end
             )
  end

  test "an unsatisfied plan remains reviewable but cannot be approved", context do
    assert {:ok, requirement, requirement_version} =
             ContactRequirements.create(
               context.member_scope,
               @mission_id,
               requirement_attrs(%{contact_count: 2, rationale: "Need redundant passes"}),
               now: @now
             )

    assert {:ok, planning} =
             Planner.run(
               context.member_scope,
               @mission_id,
               requirement.contact_requirement_id,
               requirement_version.version,
               now: @now,
               list_routes: fn _, _, _ -> {:ok, %{routes: [route()], findings: []}} end,
               search_opportunities: fn _, _, _, _, _ ->
                 {:ok, %{opportunities: [opportunity(%{"id" => "opportunity-partial"})]}}
               end
             )

    [snapshot] = planning.snapshots

    assert {:ok, plan, version} =
             ContactPlans.create(context.member_scope, @mission_id, %{
               planning_run_ids: [planning.run.contact_planning_run_id],
               selected_snapshot_ids: [snapshot.contact_opportunity_snapshot_id],
               rationale: "Preserve partial option for review"
             })

    assert {:ok, _pending} =
             ContactPlans.submit(
               context.member_scope,
               @mission_id,
               plan.contact_plan_id,
               1,
               "Review partial coverage"
             )

    assert {:error, :contact_plan_not_satisfied} =
             ContactPlanApprovals.approve(
               context.admin_scope,
               @mission_id,
               plan.contact_plan_id,
               1,
               version.content_sha256,
               "Cannot accept shortfall",
               now: DateTime.add(@now, 2, :second),
               resolve_route: route_resolver()
             )
  end

  test "rejection records a required reason and forces a new version before resubmission",
       context do
    assert {:ok, plan, version, approval} =
             ContactPlanApprovals.reject(
               context.admin_scope,
               @mission_id,
               context.plan.contact_plan_id,
               1,
               context.plan_version.content_sha256,
               "Use the later station window",
               now: DateTime.add(@now, 2, :second)
             )

    assert plan.lifecycle_state == :draft
    assert version.version == 1
    assert approval.decision == :rejected
    assert approval.reason == "Use the later station window"

    assert {:error, :contact_plan_version_already_decided} =
             ContactPlans.submit(
               context.member_scope,
               @mission_id,
               plan.contact_plan_id,
               1,
               "Resubmit unchanged"
             )

    assert {:ok, revised, version_two} =
             ContactPlans.version(
               context.member_scope,
               @mission_id,
               plan.contact_plan_id,
               1,
               %{rationale: "Address the station-window concern"}
             )

    assert revised.current_version == 2
    assert version_two.content_sha256 != version.content_sha256
  end

  defp approve(context) do
    ContactPlanApprovals.approve(
      context.admin_scope,
      @mission_id,
      context.plan.contact_plan_id,
      context.plan.current_version,
      context.plan_version.content_sha256,
      "Reviewed provider, station, policy, and expiry",
      now: DateTime.add(@now, 2, :second),
      resolve_route: route_resolver()
    )
  end

  defp route_resolver do
    fn _organization_id, _mission_id, _spacecraft_id, _route_key -> {:ok, route()} end
  end

  defp route(overrides \\ %{}) do
    Map.merge(
      %{
        route_key: "route-contact-plan-approval",
        spacecraft_id: @spacecraft_id,
        provider_spacecraft_ref: "SC-approval",
        source_endpoint_id: "source-approval",
        routing_rule_id: "routing-approval",
        link_assignment_id: "link-approval",
        path_template_id: "path-approval",
        path_template_version: 1,
        transport_id: "transport-approval",
        transport_version: 2,
        provider_id: "provider-approval",
        provider_version: 3,
        provider_account_id: "account-approval",
        provider_account_version: 4,
        provider_account_grant_id: "grant-approval",
        provider_account_grant_version: 5,
        provider_profile_id: "runtime-approval",
        provider_profile_version: 6,
        service_profile_ref: %{"id" => "service-downlink", "version" => 7},
        delivery_profile_ref: %{"id" => "delivery-cadence", "version" => 8},
        delivery_policy_document: %{
          "version" => 1,
          "mode" => "bounded_automatic",
          "maximum_later_start_shift_seconds" => 120,
          "approved_station_substitutions" => ["station-backup"]
        },
        provider_display_name: "Approval Provider",
        service_display_name: "Realtime downlink",
        delivery_display_name: "Cadence primary",
        route_display_name: "Approval Route",
        client: ContactPlanApprovalsTest.FakeClient
      },
      overrides
    )
  end

  defp opportunity(overrides \\ %{}) do
    Map.merge(
      %{
        "id" => "opportunity-approval",
        "spacecraft_ref" => "SC-approval",
        "ground_station_ref" => "station-primary",
        "antenna_or_service_pool_ref" => "pool-primary",
        "service_profile_ref" => "service-downlink",
        "starts_at" => iso(3_600),
        "ends_at" => iso(4_500),
        "expires_at" => iso(18_000),
        "availability" => "available",
        "estimated_capacity" => %{"bytes" => 2_000_000_000},
        "synthetic" => true,
        "extensions" => %{
          "orbit_readiness" => %{"status" => "current", "valid_until" => iso(28_800)}
        }
      },
      overrides
    )
  end

  defp requirement_attrs(overrides \\ %{}) do
    Map.merge(
      %{
        spacecraft_id: @spacecraft_id,
        service_direction: :downlink,
        contact_intent: "payload_downlink",
        earliest_start: DateTime.add(@now, 3_600, :second),
        latest_end: DateTime.add(@now, 28_800, :second),
        success_measure: :minimum_data_volume,
        minimum_duration_seconds: 600,
        preferred_duration_seconds: 900,
        minimum_data_volume_bytes: 1_500_000_000,
        contact_count: 1,
        minimum_separation_seconds: 0,
        priority: :high,
        provider_constraints_document: %{"allowed" => [], "excluded" => []},
        station_constraints_document: %{"allowed" => [], "excluded" => []},
        policy_constraints_document: %{
          "maximum_later_start_shift_seconds" => 60,
          "approved_station_substitutions" => []
        },
        approval_policy_document: %{"mode" => "manual"},
        rationale: "Downlink recorder",
        metadata: %{}
      },
      overrides
    )
  end

  defp scope(organization, role) do
    user =
      User.new(%{
        user_id: "contact-plan-approval-user-#{role}",
        email: "contact-plan-approval-#{role}@example.test",
        display_name: "Contact Plan #{role}"
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

  defp iso(offset), do: DateTime.add(@now, offset, :second) |> DateTime.to_iso8601()
end
