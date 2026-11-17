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

  alias Cadence.Governance.ActivationPolicy
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

  test "acknowledgements on a fully satisfied plan are rejected, not stored", context do
    assert {:error, {:contact_plan_exceptions_unknown, [id]}} =
             ContactPlanApprovals.approve(
               context.admin_scope,
               @mission_id,
               context.plan.contact_plan_id,
               context.plan.current_version,
               context.plan_version.content_sha256,
               "Reviewed provider, station, policy, and expiry",
               now: DateTime.add(@now, 2, :second),
               resolve_route: route_resolver(),
               acknowledged_exceptions: [
                 %{
                   requirement_id: context.requirement.contact_requirement_id,
                   reason: "Nothing is unmet here"
                 }
               ]
             )

    assert id == context.requirement.contact_requirement_id
  end

  describe "acknowledged exceptions (DECISIONS #28)" do
    setup context do
      # A second requirement whose window is searched but left unselected.
      assert {:ok, gap, gap_version} =
               ContactRequirements.create(
                 context.member_scope,
                 @mission_id,
                 requirement_attrs(),
                 now: @now
               )

      assert {:ok, gap_planning} =
               Planner.run(
                 context.member_scope,
                 @mission_id,
                 gap.contact_requirement_id,
                 gap_version.version,
                 now: @now,
                 list_routes: fn _, _, _ -> {:ok, %{routes: [route()], findings: []}} end,
                 search_opportunities: fn _, _, _, _, _ ->
                   {:ok, %{opportunities: [opportunity(%{"id" => "opportunity-gap"})]}}
                 end
               )

      assert {:ok, plan, plan_version} =
               ContactPlans.create(
                 context.member_scope,
                 @mission_id,
                 %{
                   planning_run_ids: [
                     context.snapshot.contact_planning_run_id,
                     gap_planning.run.contact_planning_run_id
                   ],
                   selected_snapshot_ids: [context.snapshot.contact_opportunity_snapshot_id],
                   rationale: "Accept the gap for the second requirement"
                 },
                 now: @now
               )

      assert {:ok, pending} =
               ContactPlans.submit(
                 context.member_scope,
                 @mission_id,
                 plan.contact_plan_id,
                 plan.current_version,
                 "Ready for administrator review",
                 now: DateTime.add(@now, 1, :second)
               )

      %{gap: gap, gap_plan: pending, gap_version: plan_version}
    end

    test "an unsatisfied plan is refused without acknowledgements", context do
      assert {:error, :contact_plan_not_satisfied} = approve_gap(context, nil)
    end

    test "every unsatisfied requirement must be acknowledged with a reason", context do
      assert {:error, {:contact_plan_exception_invalid, _}} =
               approve_gap(context, [
                 %{requirement_id: context.gap.contact_requirement_id, reason: "short"}
               ])

      assert {:error, {:contact_plan_exceptions_unknown, ["nope"]}} =
               approve_gap(context, [
                 %{
                   requirement_id: context.gap.contact_requirement_id,
                   reason: "Weather window next pass"
                 },
                 %{requirement_id: "nope", reason: "Not part of this plan at all"}
               ])
    end

    test "duplicate acknowledgements for one requirement are invalid", context do
      ack = %{
        requirement_id: context.gap.contact_requirement_id,
        reason: "Weather window next pass"
      }

      assert {:error, {:contact_plan_exception_invalid, id}} = approve_gap(context, [ack, ack])
      assert id == context.gap.contact_requirement_id
    end

    test "acknowledged gaps are approved and audited on the approval", context do
      reason = "Recorder margin allows one missed pass"

      assert {:ok, plan, _version, approval} =
               approve_gap(context, [
                 %{"requirement_id" => context.gap.contact_requirement_id, "reason" => reason}
               ])

      assert plan.lifecycle_state == :approved

      assert [
               %{
                 "contact_requirement_id" => gap_id,
                 "contact_requirement_version" => 1,
                 "reason" => ^reason
               }
             ] = approval.exceptions

      assert gap_id == context.gap.contact_requirement_id

      assert [%{exceptions: [_]}] =
               ContactPlanApprovals.list(@organization_id, @mission_id, plan.contact_plan_id)
    end
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

  describe "no self-approval under 'independent' approval (director 11-15)" do
    setup context do
      %{admin_plan: admin_plan(context)}
    end

    test "the administrator who wrote and submitted a version can't approve it", context do
      assert {:error, :contact_plan_self_approval_forbidden} =
               approve_as(context.admin_scope, context.admin_plan)

      assert {:ok, plan, _version} =
               ContactPlans.fetch(
                 @organization_id,
                 @mission_id,
                 context.admin_plan.plan.contact_plan_id
               )

      assert plan.lifecycle_state == :pending_approval
    end

    test "another administrator approves it", context do
      assert {:ok, plan, _version, _approval} =
               approve_as(other_admin_scope(context), context.admin_plan)

      assert plan.lifecycle_state == :approved
    end

    test "the requester may still send it back", context do
      assert {:ok, plan, _version, _decision} =
               ContactPlanApprovals.reject(
                 context.admin_scope,
                 @mission_id,
                 context.admin_plan.plan.contact_plan_id,
                 context.admin_plan.plan.current_version,
                 context.admin_plan.version.content_sha256,
                 "Not this window after all",
                 now: DateTime.add(@now, 2, :second)
               )

      # A send back returns it to draft for a new version.
      assert plan.lifecycle_state == :draft
    end

    test "under 'direct' approval the same administrator may approve", context do
      policy = ActivationPolicy.load(@organization_id, @mission_id)

      assert {:ok, _saved} =
               ActivationPolicy.save(context.admin_scope, @mission_id, policy.token, %{
                 "value" => %{"approval_requirement" => "direct"}
               })

      assert {:ok, plan, _version, _approval} =
               approve_as(context.admin_scope, context.admin_plan)

      assert plan.lifecycle_state == :approved
    end
  end

  test "approval records immutable route bindings without invoking Control", context do
    assert {:ok, _plan, _version, _approval} =
             ContactPlanApprovals.approve(
               context.admin_scope,
               @mission_id,
               context.plan.contact_plan_id,
               1,
               context.plan_version.content_sha256,
               "Route configuration reviewed",
               now: DateTime.add(@now, 2, :second),
               resolve_route: fn _, _, _, _ -> raise "Control resolver must not run" end
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

  # A plan an administrator wrote and submitted, from the same planning snapshot; the setup's own
  # plan (a member's) is sent back first, so only this one is pending.
  defp admin_plan(context) do
    assert {:ok, _rejected, _version, _decision} =
             ContactPlanApprovals.reject(
               context.admin_scope,
               @mission_id,
               context.plan.contact_plan_id,
               context.plan.current_version,
               context.plan_version.content_sha256,
               "Replaced by the administrator's own plan",
               now: DateTime.add(@now, 1, :second)
             )

    assert {:ok, plan, version} =
             ContactPlans.create(
               context.admin_scope,
               @mission_id,
               %{
                 planning_run_ids: [context.snapshot.contact_planning_run_id],
                 selected_snapshot_ids: [context.snapshot.contact_opportunity_snapshot_id],
                 rationale: "The administrator's own plan"
               },
               now: DateTime.add(@now, 1, :second)
             )

    assert {:ok, pending} =
             ContactPlans.submit(
               context.admin_scope,
               @mission_id,
               plan.contact_plan_id,
               plan.current_version,
               "Ready",
               now: DateTime.add(@now, 1, :second)
             )

    %{plan: pending, version: version}
  end

  defp approve_as(scope, %{plan: plan, version: version}) do
    ContactPlanApprovals.approve(
      scope,
      @mission_id,
      plan.contact_plan_id,
      plan.current_version,
      version.content_sha256,
      "Reviewed provider, station, policy, and expiry",
      now: DateTime.add(@now, 2, :second),
      resolve_route: route_resolver()
    )
  end

  defp other_admin_scope(context) do
    scope = context.admin_scope
    user = %{scope.user | user_id: "contact-plan-approval-second-admin"}
    membership = %{scope.organization_membership | user_id: user.user_id}
    %{scope | user: user, organization_membership: membership}
  end

  # U76 (lead 11-17; P3: blank is none): an approval's note is optional and recorded as NULL.
  for {label, note} <- [{"no note", nil}, {"a whitespace-only note", "   "}] do
    test "U76: an approval with #{label} records NULL, never a canned text", context do
      assert {:ok, _plan, _version, approval} = approve(context, unquote(note))
      assert approval.reason == nil

      assert [%{reason: nil}] =
               Cadence.Repo.all(
                 from(row in Cadence.Management.Contacts.Store.ContactPlanApprovalRow,
                   where: row.contact_plan_id == ^context.plan.contact_plan_id,
                   select: %{reason: row.reason}
                 )
               )
    end
  end

  test "U76: a rejection still needs its reason; a blank one records nothing", context do
    assert {:error, :contact_plan_decision_reason_required} =
             ContactPlanApprovals.reject(
               context.admin_scope,
               @mission_id,
               context.plan.contact_plan_id,
               1,
               context.plan_version.content_sha256,
               "   ",
               now: DateTime.add(@now, 2, :second)
             )

    assert ContactPlanApprovals.list(@organization_id, @mission_id, context.plan.contact_plan_id) ==
             []
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

  defp approve(context, note) do
    ContactPlanApprovals.approve(
      context.admin_scope,
      @mission_id,
      context.plan.contact_plan_id,
      context.plan.current_version,
      context.plan_version.content_sha256,
      note,
      now: DateTime.add(@now, 2, :second),
      resolve_route: route_resolver()
    )
  end

  defp approve_gap(context, acknowledged) do
    ContactPlanApprovals.approve(
      context.admin_scope,
      @mission_id,
      context.gap_plan.contact_plan_id,
      context.gap_plan.current_version,
      context.gap_version.content_sha256,
      "Reviewed provider, station, policy, and expiry",
      now: DateTime.add(@now, 2, :second),
      resolve_route: route_resolver(),
      acknowledged_exceptions: acknowledged
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
