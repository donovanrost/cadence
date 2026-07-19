defmodule Cadence.ContactPlanning.ContactPlansTest do
  use Cadence.DataCase, async: false

  alias Cadence.Accounts.{OrganizationMembership, User}
  alias Cadence.Auth.Scope
  alias Cadence.ContactPlanning.{ContactPlans, ContactRequirements, Planner}
  alias Cadence.Persistence.Schemas.ContactPlanRow
  alias Cadence.Repo
  alias Cadence.Spacecraft

  @organization_id "org-contact-plans"
  @mission_id "mission-contact-plans"
  @spacecraft_id "spacecraft-contact-plans"
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
               list_routes: fn _organization_id, _mission_id, _spacecraft_id ->
                 {:ok, %{routes: [route()], findings: []}}
               end,
               search_opportunities: fn _organization_id,
                                        _mission_id,
                                        _route_key,
                                        _window,
                                        _opts ->
                 {:ok,
                  %{
                    opportunities: [
                      opportunity("one", 3_600, 4_500),
                      opportunity("two", 7_200, 8_100)
                    ]
                  }}
               end
             )

    %{
      organization: organization,
      member_scope: member_scope,
      requirement: requirement,
      requirement_version: requirement_version,
      planning: planning
    }
  end

  test "creates an immutable draft from exact runs, requirements, and opportunity snapshots",
       context do
    [selected, rejected] = context.planning.snapshots

    assert {:ok, plan, version} =
             ContactPlans.create(
               context.member_scope,
               @mission_id,
               %{
                 planning_run_ids: [context.planning.run.contact_planning_run_id],
                 selected_snapshot_ids: [selected.contact_opportunity_snapshot_id],
                 rationale: "Prefer the earlier pass"
               },
               now: @now
             )

    assert plan.lifecycle_state == :draft
    assert plan.current_version == 1
    assert version.selected_snapshot_ids == [selected.contact_opportunity_snapshot_id]
    assert version.rejected_snapshot_ids == [rejected.contact_opportunity_snapshot_id]

    assert version.requirement_refs_document == %{
             "requirements" => [
               %{
                 "id" => context.requirement.contact_requirement_id,
                 "version" => context.requirement_version.version
               }
             ]
           }

    assert version.planning_run_refs_document == %{
             "runs" => [context.planning.run.contact_planning_run_id]
           }

    assert version.coverage_document["satisfied"]
    assert version.conflict_document == %{"clear" => true, "items" => []}
    assert version.unsatisfied_document["clear"]
    assert version.content_sha256 =~ ~r/\A[0-9a-f]{64}\z/

    refute get_in(version.policy_snapshot_document, [
             "selections",
             Access.at(0),
             "route_binding",
             "client"
           ])

    assert {:ok, ^plan, ^version} =
             ContactPlans.fetch(@organization_id, @mission_id, plan.contact_plan_id)

    assert ContactPlans.selected_snapshots(
             @organization_id,
             @mission_id,
             plan.contact_plan_id,
             1
           ) == [selected]
  end

  test "versioning is deterministic, preserves history, and rejects stale edits", context do
    [first, second] = context.planning.snapshots

    assert {:ok, plan, version_one} = create_plan(context, [first])

    assert {:ok, plan_two, version_two} =
             ContactPlans.version(
               context.member_scope,
               @mission_id,
               plan.contact_plan_id,
               1,
               %{
                 selected_snapshot_ids: [second.contact_opportunity_snapshot_id],
                 rationale: "Use the later pass"
               },
               now: DateTime.add(@now, 1, :second)
             )

    assert plan_two.current_version == 2
    assert version_two.version == 2
    assert version_two.selected_snapshot_ids == [second.contact_opportunity_snapshot_id]
    refute version_two.content_sha256 == version_one.content_sha256

    assert [^version_two, ^version_one] =
             ContactPlans.list_versions(@organization_id, @mission_id, plan.contact_plan_id)

    assert {:error, :stale_contact_plan_version} =
             ContactPlans.version(
               context.member_scope,
               @mission_id,
               plan.contact_plan_id,
               1,
               %{rationale: "Stale editor"}
             )
  end

  test "a pending proposal can be revised back to draft but committed states cannot be edited",
       context do
    [selected | _rest] = context.planning.snapshots
    assert {:ok, plan, _version} = create_plan(context, [selected])

    assert {:ok, pending} =
             ContactPlans.submit(
               context.member_scope,
               @mission_id,
               plan.contact_plan_id,
               1,
               "Ready for review",
               now: @now
             )

    assert pending.lifecycle_state == :pending_approval

    assert {:ok, draft, version_two} =
             ContactPlans.version(
               context.member_scope,
               @mission_id,
               plan.contact_plan_id,
               1,
               %{rationale: "Addressed reviewer note"},
               now: DateTime.add(@now, 1, :second)
             )

    assert draft.lifecycle_state == :draft
    assert version_two.version == 2

    ContactPlanRow
    |> Repo.get!(plan.contact_plan_id)
    |> ContactPlanRow.projection_changeset(%{
      current_version: 2,
      lifecycle_state: "approved",
      lifecycle_changed_by: context.member_scope.user.user_id,
      lifecycle_changed_at: DateTime.add(@now, 2, :second),
      lifecycle_reason: "test commitment",
      approved_version: 2,
      approved_at: DateTime.add(@now, 2, :second),
      approved_by: context.member_scope.user.user_id
    })
    |> Repo.update!()

    assert {:error, :contact_plan_not_editable} =
             ContactPlans.version(
               context.member_scope,
               @mission_id,
               plan.contact_plan_id,
               2,
               %{rationale: "Mutation after commitment"}
             )
  end

  test "rejects selected snapshots that are outside the exact referenced runs", context do
    %{organization: foreign_organization, mission: foreign_mission} =
      persist_mission_scope("org-contact-plans-foreign", "mission-contact-plans-foreign")

    assert {:ok, _spacecraft} =
             Cadence.SpacecraftStore.persist_spacecraft(
               foreign_organization.organization_id,
               Spacecraft.new(%{
                 spacecraft_id: "spacecraft-contact-plans-foreign",
                 mission_id: foreign_mission.mission_id,
                 display_name: "Foreign"
               })
             )

    foreign_scope = scope(foreign_organization, :member)

    assert {:ok, foreign_requirement, foreign_version} =
             ContactRequirements.create(
               foreign_scope,
               foreign_mission.mission_id,
               requirement_attrs(%{spacecraft_id: "spacecraft-contact-plans-foreign"}),
               now: @now
             )

    assert {:ok, foreign_planning} =
             Planner.run(
               foreign_scope,
               foreign_mission.mission_id,
               foreign_requirement.contact_requirement_id,
               foreign_version.version,
               now: @now,
               list_routes: fn _organization_id, _mission_id, spacecraft_id ->
                 {:ok, %{routes: [route(%{spacecraft_id: spacecraft_id})], findings: []}}
               end,
               search_opportunities: fn _, _, _, _, _ ->
                 {:ok, %{opportunities: [opportunity("foreign", 3_600, 4_500)]}}
               end
             )

    [foreign_snapshot] = foreign_planning.snapshots

    assert {:error, :contact_plan_snapshot_not_in_referenced_runs} =
             ContactPlans.create(context.member_scope, @mission_id, %{
               planning_run_ids: [context.planning.run.contact_planning_run_id],
               selected_snapshot_ids: [foreign_snapshot.contact_opportunity_snapshot_id]
             })
  end

  test "allows an unsatisfied draft while making the shortfall explicit", context do
    assert {:ok, requirement, version} =
             ContactRequirements.version(
               context.member_scope,
               @mission_id,
               context.requirement.contact_requirement_id,
               1,
               %{contact_count: 2},
               now: DateTime.add(@now, 1, :second)
             )

    assert {:ok, planning} =
             Planner.run(
               context.member_scope,
               @mission_id,
               requirement.contact_requirement_id,
               version.version,
               now: @now,
               list_routes: fn _, _, _ -> {:ok, %{routes: [route()], findings: []}} end,
               search_opportunities: fn _, _, _, _, _ ->
                 {:ok, %{opportunities: [opportunity("only", 3_600, 4_500)]}}
               end
             )

    [selected] = planning.snapshots

    assert {:ok, _plan, proposal} =
             ContactPlans.create(context.member_scope, @mission_id, %{
               planning_run_ids: [planning.run.contact_planning_run_id],
               selected_snapshot_ids: [selected.contact_opportunity_snapshot_id],
               rationale: "Record the best currently available partial coverage"
             })

    refute proposal.coverage_document["satisfied"]
    refute proposal.unsatisfied_document["clear"]

    assert get_in(proposal.unsatisfied_document, [
             "requirements",
             Access.at(0),
             "hard_failures",
             Access.at(0),
             "code"
           ]) ==
             "contact_count_not_met"
  end

  defp create_plan(context, selected) do
    ContactPlans.create(
      context.member_scope,
      @mission_id,
      %{
        planning_run_ids: [context.planning.run.contact_planning_run_id],
        selected_snapshot_ids: Enum.map(selected, & &1.contact_opportunity_snapshot_id),
        rationale: "Plan proposal"
      },
      now: @now
    )
  end

  defp route(overrides \\ %{}) do
    Map.merge(
      %{
        route_key: "route-contact-plan",
        spacecraft_id: @spacecraft_id,
        provider_spacecraft_ref: "SC-plan",
        source_endpoint_id: "source-plan",
        routing_rule_id: "routing-plan",
        link_assignment_id: "link-plan",
        path_template_id: "path-plan",
        path_template_version: 1,
        transport_id: "transport-plan",
        transport_version: 2,
        provider_id: "provider-plan",
        provider_version: 3,
        provider_account_id: "account-plan",
        provider_account_version: 4,
        provider_account_grant_id: "grant-plan",
        provider_account_grant_version: 5,
        provider_profile_id: "runtime-plan",
        provider_profile_version: 6,
        service_profile_ref: %{"id" => "service-downlink", "version" => 7},
        delivery_profile_ref: %{"id" => "delivery-cadence", "version" => 8},
        delivery_policy_document: %{"mode" => "approval_required", "version" => 1},
        provider_display_name: "Plan Provider",
        service_display_name: "Realtime downlink",
        delivery_display_name: "Cadence primary",
        route_display_name: "Plan Route",
        client: ContactPlansTest.FakeClient
      },
      overrides
    )
  end

  defp opportunity(suffix, starts_offset, ends_offset) do
    %{
      "id" => "opportunity-#{suffix}",
      "spacecraft_ref" => "SC-plan",
      "ground_station_ref" => "station-plan",
      "antenna_or_service_pool_ref" => "pool-plan",
      "service_profile_ref" => "service-downlink",
      "starts_at" => iso(starts_offset),
      "ends_at" => iso(ends_offset),
      "expires_at" => iso(18_000),
      "availability" => "available",
      "estimated_capacity" => %{"bytes" => 2_000_000_000},
      "synthetic" => true,
      "extensions" => %{
        "orbit_readiness" => %{"status" => "current", "valid_until" => iso(28_800)}
      }
    }
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
        policy_constraints_document: %{},
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
        user_id: "contact-plans-user-#{role}-#{organization.organization_id}",
        email: "contact-plans-#{role}-#{organization.organization_id}@example.test",
        display_name: "Contact Planner #{role}"
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
