defmodule Cadence.Applications.OpsConsole.Actions.PlanDecisionsTest do
  use Cadence.DataCase, async: false

  alias Cadence.Accounts.{OrganizationMembership, User}
  alias Cadence.Applications.{ActionRequest, HostContext}
  alias Cadence.Applications.OpsConsole.Actions.ContactPlanning, as: Actions
  alias Cadence.Auth.Scope
  alias Cadence.ContactPlanning.{ContactPlanApprovals, ContactPlans, ContactRequirements, Planner}
  alias Cadence.Control.Contacts, as: ControlContacts
  alias Cadence.Management.Contacts, as: ManagementContacts
  alias Cadence.Spacecraft

  @org "org-plan-decisions"
  @mission "mission-plan-decisions"
  @craft "craft-plan-decisions"
  @now ~U[2027-01-01 00:00:00Z]

  setup do
    %{organization: organization} = persist_mission_scope(@org, @mission)

    user =
      User.new(%{
        user_id: "requirement-reviewer",
        email: "reviewer@example.test",
        display_name: "Reviewer"
      })

    membership =
      OrganizationMembership.new(%{user_id: user.user_id, organization_id: @org, role: :member})

    scope =
      Scope.new(%{
        user: user,
        organization_id: @org,
        organization: organization,
        organization_membership: membership
      })

    assert {:ok, _} =
             Cadence.SpacecraftStore.persist_spacecraft(
               @org,
               Spacecraft.new(%{
                 spacecraft_id: @craft,
                 mission_id: @mission,
                 display_name: "Review spacecraft"
               })
             )

    assert {:ok, requirement, version} =
             ContactRequirements.create(scope, @mission, %{
               spacecraft_id: @craft,
               service_direction: :downlink,
               contact_intent: "payload_downlink",
               earliest_start: DateTime.add(@now, 3600),
               latest_end: DateTime.add(@now, 28_800),
               success_measure: :minimum_duration,
               minimum_duration_seconds: 60,
               priority: :high,
               rationale: "Reviewed requirement"
             })

    context = %{scope: scope, requirement: requirement, version: version}
    planning = planning(context)

    assert {:ok, plan, plan_version} =
             ContactPlans.create(scope, @mission, %{
               planning_run_ids: [planning.run.contact_planning_run_id],
               selected_snapshot_ids:
                 Enum.map(planning.snapshots, & &1.contact_opportunity_snapshot_id),
               rationale: "Reviewed plan"
             })

    admin_user =
      User.new(%{
        user_id: "plan-review-admin",
        email: "plan-review-admin@example.test",
        display_name: "Plan administrator"
      })

    admin =
      Scope.new(%{
        user: admin_user,
        organization_id: @org,
        organization: organization,
        organization_membership:
          OrganizationMembership.new(%{
            user_id: admin_user.user_id,
            organization_id: @org,
            role: :organization_admin
          })
      })

    Map.merge(context, %{planning: planning, plan: plan, plan_version: plan_version, admin: admin})
  end

  test "submission persists only the reviewed version", context do
    assert {:ok, result} = execute(context.scope, "submit-plan", params(context, "submission"))
    assert result["contactPlanId"] == context.plan.contact_plan_id
    assert result["contentSha256"] == context.plan_version.content_sha256
    assert {:ok, plan, version} = ContactPlans.fetch(@org, @mission, context.plan.contact_plan_id)
    assert plan.lifecycle_state == :pending_approval
    assert version.version == 1
    assert plan.lifecycle_reason == "Reviewed exact plan"
  end

  test "no action substitutes a newer version for stale reviewed content", context do
    assert {:ok, _, newer} =
             ContactPlans.version(context.scope, @mission, context.plan.contact_plan_id, 1, %{
               rationale: "Changed proposal"
             })

    for {action, wrapper} <- actions() do
      assert {:error, :stale_contact_plan_evidence} =
               execute(context.admin, action, params(context, wrapper))
    end

    assert {:ok, plan, ^newer} = ContactPlans.fetch(@org, @mission, context.plan.contact_plan_id)
    assert plan.lifecycle_state == :draft
    assert approvals(context) == []
    assert items(context) == []
  end

  test "approval returns the exact approved fact identity and accepts its execution items",
       context do
    submit(context)
    assert {:ok, result} = execute(context.admin, "approve-plan", params(context, "decision"))
    assert result["contactPlanId"] == context.plan.contact_plan_id
    assert result["version"] == 1
    assert result["contentSha256"] == context.plan_version.content_sha256
    assert [approval] = approvals(context)
    assert approval.content_sha256 == context.plan_version.content_sha256
    assert approval.reason == "Reviewed exact plan"
    assert approval.actor_id == context.admin.user.user_id
    assert [item] = items(context)
    assert item.contact_plan_version == 1
    assert item.lifecycle_state == :pending
    assert item.attempt_count == 0
  end

  test "rejection records the exact reviewed version without execution items", context do
    submit(context)
    assert {:ok, result} = execute(context.admin, "reject-plan", params(context, "decision"))
    assert result["version"] == 1
    assert [approval] = approvals(context)
    assert approval.decision == :rejected
    assert approval.content_sha256 == context.plan_version.content_sha256
    assert items(context) == []
  end

  test "scope, malformed evidence, unknown keys and wrong hashes cause no effects", context do
    for {action, wrapper} <- actions(),
        bad <- [
          Map.delete(params(context, wrapper), "plan_evidence"),
          Map.put(params(context, wrapper), "extra", "untrusted"),
          put_in(params(context, wrapper), ["plan_evidence", "contract_version"], 2),
          put_in(params(context, wrapper), ["plan_evidence", "plan_version"], "1"),
          put_in(
            params(context, wrapper),
            ["plan_evidence", "content_sha256"],
            String.duplicate("0", 64)
          ),
          put_in(params(context, wrapper), ["plan_evidence", "mission_id"], "foreign"),
          put_in(params(context, wrapper), ["plan_evidence", "organization_id"], "foreign"),
          put_in(params(context, wrapper), ["plan_evidence", "plan_id"], "foreign"),
          put_in(params(context, wrapper), ["plan_evidence", "extra"], true)
        ] do
      assert {:error, _} = execute(context.admin, action, bad)
    end

    assert {:ok, %{lifecycle_state: :draft}, _} =
             ContactPlans.fetch(@org, @mission, context.plan.contact_plan_id)

    assert approvals(context) == []
    assert items(context) == []
  end

  test "reasons are bounded and membership and admin decisions remain authorized", context do
    for reason <- ["", "   ", 42, String.duplicate("x", 4097)] do
      bad = put_in(params(context, "submission"), ["submission", "reason"], reason)
      assert {:error, _} = execute(context.scope, "submit-plan", bad)
    end

    denied = %{context.scope | organization_membership: nil}

    for {action, wrapper} <- actions() do
      assert {:error, _} = execute(denied, action, params(context, wrapper))
    end

    submit(context)

    for action <- ["approve-plan", "reject-plan"] do
      assert {:error, _} = execute(context.scope, action, params(context, "decision"))
    end

    assert approvals(context) == []
    assert items(context) == []
  end

  test "execution rejects mismatched approval evidence before inserting execution work",
       context do
    submit(context)

    assert {:ok, _approved} =
             ManagementContacts.approve_plan(
               context.admin,
               @mission,
               context.plan.contact_plan_id,
               1,
               context.plan_version.content_sha256,
               "Approve exact plan"
             )

    assert items(context) == []

    for opts <- [
          [expected_plan_version: 2, expected_plan_hash: context.plan_version.content_sha256],
          [expected_plan_version: 1.0, expected_plan_hash: context.plan_version.content_sha256],
          [expected_plan_version: 1, expected_plan_hash: String.duplicate("0", 64)],
          [expected_plan_version: 1]
        ] do
      assert {:error, :stale_contact_plan_evidence} =
               ControlContacts.execute_approved_plan(
                 context.scope,
                 @mission,
                 context.plan.contact_plan_id,
                 opts
               )
    end

    assert items(context) == []

    assert {:ok, %{lifecycle_state: :approved}, _} =
             ContactPlans.fetch(@org, @mission, context.plan.contact_plan_id)

    # No provider routes are configured in this test mission. Execution records
    # the route-not-ready failure without making a provider reservation request.
    assert {:ok, result} = execute(context.scope, "execute-plan", params(context, nil))
    assert result["contactPlanId"] == context.plan.contact_plan_id
    assert [item] = items(context)
    assert item.contact_plan_version == 1
    assert item.lifecycle_state == :failed
    assert item.last_error_document["code"] == "contact_plan_execution_route_not_ready"
  end

  defp actions,
    do: [
      {"submit-plan", "submission"},
      {"approve-plan", "decision"},
      {"reject-plan", "decision"},
      {"execute-plan", nil}
    ]

  defp params(context, wrapper) do
    params = %{
      "contact_plan_id" => context.plan.contact_plan_id,
      "plan_evidence" => %{
        "contract_version" => 1,
        "organization_id" => @org,
        "mission_id" => @mission,
        "plan_id" => context.plan.contact_plan_id,
        "plan_version" => context.plan_version.version,
        "content_sha256" => context.plan_version.content_sha256
      }
    }

    if wrapper, do: Map.put(params, wrapper, %{"reason" => "Reviewed exact plan"}), else: params
  end

  defp submit(context) do
    assert {:ok, _} = execute(context.scope, "submit-plan", params(context, "submission"))
  end

  defp approvals(context),
    do: ContactPlanApprovals.list(@org, @mission, context.plan.contact_plan_id)

  defp items(context),
    do: ControlContacts.list_plan_execution(@org, @mission, context.plan.contact_plan_id, 1)

  defp execute(scope, action, params),
    do:
      Actions.execute(scope, HostContext.mission(@mission), "contact_plan_show", %ActionRequest{
        application_key: "ops_console",
        application_version: 1,
        action_id: action,
        params: params
      })

  defp planning(context, offset \\ 0) do
    assert {:ok, result} =
             Planner.run(
               context.scope,
               @mission,
               context.requirement.contact_requirement_id,
               context.version.version,
               now: DateTime.add(@now, offset),
               list_routes: fn _, _, _ -> {:ok, %{routes: [route()], findings: []}} end,
               search_opportunities: fn _, _, _, _, _ ->
                 {:ok, %{opportunities: [opportunity()]}}
               end
             )

    assert [snapshot] = result.snapshots
    assert snapshot.eligible
    result
  end

  defp route,
    do: %{
      route_key: "review-route",
      spacecraft_id: @craft,
      provider_spacecraft_ref: "SC-review",
      source_endpoint_id: "source-review",
      routing_rule_id: "routing-review",
      link_assignment_id: "link-review",
      path_template_id: "path-review",
      path_template_version: 1,
      transport_id: "transport-review",
      transport_version: 1,
      provider_id: "provider-review",
      provider_version: 1,
      provider_account_id: "account-review",
      provider_account_version: 1,
      provider_account_grant_id: "grant-review",
      provider_account_grant_version: 1,
      provider_profile_id: "runtime-review",
      provider_profile_version: 1,
      service_profile_ref: %{"id" => "service-review", "version" => 1},
      delivery_profile_ref: %{"id" => "delivery-review", "version" => 1},
      delivery_policy_document: %{"mode" => "approval_required", "version" => 1},
      provider_display_name: "Review Provider",
      service_display_name: "Downlink",
      delivery_display_name: "Primary",
      route_display_name: "Review route"
    }

  defp opportunity,
    do: %{
      "id" => "opportunity-review",
      "spacecraft_ref" => "SC-review",
      "ground_station_ref" => "station-review",
      "antenna_or_service_pool_ref" => "pool-review",
      "service_profile_ref" => "service-review",
      "starts_at" => iso(3600),
      "ends_at" => iso(4500),
      "expires_at" => iso(18_000),
      "availability" => "available",
      "estimated_capacity" => %{"bytes" => 2_000_000_000},
      "synthetic" => true,
      "extensions" => %{
        "orbit_readiness" => %{"status" => "current", "valid_until" => iso(28_800)}
      }
    }

  defp iso(seconds), do: @now |> DateTime.add(seconds) |> DateTime.to_iso8601()
end
