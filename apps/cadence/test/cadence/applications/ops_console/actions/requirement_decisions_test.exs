defmodule Cadence.Applications.OpsConsole.Actions.RequirementDecisionsTest do
  use Cadence.DataCase, async: false

  alias Cadence.Accounts.{OrganizationMembership, User}
  alias Cadence.Applications.{ActionRequest, HostContext}
  alias Cadence.Applications.OpsConsole.Actions.ContactPlanning, as: Actions
  alias Cadence.Auth.Scope
  alias Cadence.ContactPlanning.{ContactPlans, ContactRequirements, Planner}
  alias Cadence.Spacecraft

  @org "org-requirement-decisions"
  @mission "mission-requirement-decisions"
  @craft "craft-requirement-decisions"
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
    Map.put(context, :planning, planning(context))
  end

  test "a new search never silently substitutes a newer requirement version", context do
    params = decision(context)

    assert {:ok, _, next} =
             ContactRequirements.version(
               context.scope,
               @mission,
               context.requirement.contact_requirement_id,
               1,
               %{minimum_duration_seconds: 61}
             )

    assert {:error, :stale_contact_requirement_evidence} = execute(context.scope, "plan", params)
    assert length(runs(context)) == 1

    # This fresh mission has no configured provider routes: no provider request
    # can occur, but the actual host action still persists its reviewed version.
    assert {:ok, %{"planningRunId" => id} = result} =
             execute(context.scope, "plan", decision(%{context | version: next}))

    assert {:ok, run} = Planner.fetch_run(@org, @mission, id)
    assert run.contact_requirement_version == 2
    assert run.contact_requirement_id == context.requirement.contact_requirement_id

    assert result["navigation"]["href"] ==
             "/missions/#{@mission}/ops/requirements/#{context.requirement.contact_requirement_id}?" <>
               URI.encode_query(%{"planning_run_id" => id, "version" => 2})
  end

  test "plan creation uses the explicitly reviewed run even when a newer run exists", context do
    first = context.planning
    second = planning(context, 60)
    refute first.run.contact_planning_run_id == second.run.contact_planning_run_id
    assert hd(runs(context)).contact_planning_run_id == second.run.contact_planning_run_id
    params = selection(context, first)

    assert {:ok, %{"contactPlanId" => plan_id, "version" => 1} = result} =
             execute(context.scope, "create-plan", params)

    assert {:ok, _, version} = ContactPlans.fetch(@org, @mission, plan_id)
    assert version.selected_snapshot_ids == params["selected_snapshot_ids"]
    assert [run_id] = version.planning_run_refs_document["runs"]
    assert run_id == first.run.contact_planning_run_id
    assert result["requirementEvidence"] == params["requirement_evidence"]
    assert result["planningRunId"] == first.run.contact_planning_run_id
    assert result["actorId"] == context.scope.user.user_id
    assert result["navigation"]["href"] == "/missions/#{@mission}/ops/plans/#{plan_id}"
  end

  test "a current requirement reference cannot authorize an older-version run", context do
    assert {:ok, _, next} =
             ContactRequirements.version(
               context.scope,
               @mission,
               context.requirement.contact_requirement_id,
               1,
               %{minimum_duration_seconds: 61}
             )

    params = selection(%{context | version: next}, context.planning)

    assert {:error, :planning_run_requirement_version_mismatch} =
             execute(context.scope, "create-plan", params)

    assert ContactPlans.list(@org, @mission) == []
  end

  test "selected snapshots must belong to the reviewed run and exact requirement", context do
    second = planning(context)
    params = selection(context, context.planning)

    wrong =
      Map.put(
        params,
        "selected_snapshot_ids",
        Enum.map(second.snapshots, & &1.contact_opportunity_snapshot_id)
      )

    assert {:error, :opportunity_scope_mismatch} = execute(context.scope, "create-plan", wrong)
    assert ContactPlans.list(@org, @mission) == []
  end

  test "closed requirements reject both new searches and proposals", context do
    assert {:ok, _} =
             ContactRequirements.close(
               context.scope,
               @mission,
               context.requirement.contact_requirement_id,
               1,
               "Closed after review"
             )

    assert {:error, :contact_requirement_inactive} =
             execute(context.scope, "plan", decision(context))

    assert {:error, :contact_requirement_inactive} =
             execute(context.scope, "create-plan", selection(context, context.planning))

    assert length(runs(context)) == 1
    assert ContactPlans.list(@org, @mission) == []
  end

  test "missing protocols, changed hashes, substituted scope and unknown keys have no effects",
       context do
    params = decision(context)

    for bad <- [
          Map.delete(params, "requirement_evidence"),
          put_in(params, ["requirement_evidence", "contract_version"], 2),
          put_in(params, ["requirement_evidence", "requirement_version"], 1.0),
          put_in(params, ["requirement_evidence", "content_sha256"], String.duplicate("0", 64)),
          put_in(
            params,
            ["requirement_evidence", "content_sha256"],
            context.version.content_sha256 <> "\n"
          ),
          put_in(params, ["requirement_evidence", "mission_id"], "foreign-mission"),
          put_in(params, ["requirement_evidence", "organization_id"], "foreign-org"),
          put_in(params, ["requirement_evidence", "requirement_id"], "foreign-requirement"),
          put_in(params, ["requirement_evidence", "extra"], "not supported"),
          Map.put(params, "extra", true)
        ] do
      assert {:error, _} = execute(context.scope, "plan", bad)

      selected =
        Map.take(selection(context, context.planning), ~w(planning_run_id selected_snapshot_ids))

      assert {:error, _} = execute(context.scope, "create-plan", Map.merge(bad, selected))
    end

    assert {:error, :scope_mismatch} =
             execute(%{context.scope | mission_id: "foreign"}, "plan", params)

    assert length(runs(context)) == 1
    assert ContactPlans.list(@org, @mission) == []
  end

  test "missing mission authority rejects decisions before effects", context do
    denied = %{context.scope | organization_membership: nil}
    assert {:error, :forbidden} = execute(denied, "plan", decision(context))

    assert {:error, :forbidden} =
             execute(denied, "create-plan", selection(context, context.planning))

    assert length(runs(context)) == 1
    assert ContactPlans.list(@org, @mission) == []
  end

  test "legacy, duplicate and oversized selections never create a proposal", context do
    params = selection(context, context.planning)
    [id] = params["selected_snapshot_ids"]

    for ids <- [
          [],
          [id, id],
          Enum.map(1..201, &"snapshot-#{&1}"),
          [nil],
          [String.duplicate("x", 257)]
        ] do
      assert {:error, _} =
               execute(
                 context.scope,
                 "create-plan",
                 Map.put(params, "selected_snapshot_ids", ids)
               )
    end

    assert {:error, _} =
             execute(context.scope, "create-plan", Map.delete(params, "planning_run_id"))

    assert {:error, _} =
             execute(context.scope, "create-plan", Map.delete(params, "requirement_evidence"))

    assert ContactPlans.list(@org, @mission) == []
  end

  defp decision(context),
    do: %{
      "contact_requirement_id" => context.requirement.contact_requirement_id,
      "requirement_evidence" => %{
        "contract_version" => 1,
        "organization_id" => @org,
        "mission_id" => @mission,
        "requirement_id" => context.requirement.contact_requirement_id,
        "requirement_version" => context.version.version,
        "content_sha256" => context.version.content_sha256
      }
    }

  defp selection(context, planning),
    do:
      Map.merge(decision(context), %{
        "planning_run_id" => planning.run.contact_planning_run_id,
        "selected_snapshot_ids" =>
          Enum.map(planning.snapshots, & &1.contact_opportunity_snapshot_id)
      })

  defp execute(scope, action, params),
    do:
      Actions.execute(
        scope,
        HostContext.mission(@mission),
        "contact_requirement_show",
        %ActionRequest{
          application_key: "ops_console",
          application_version: 1,
          action_id: action,
          params: params
        }
      )

  defp runs(context),
    do: Planner.list_runs(@org, @mission, context.requirement.contact_requirement_id)

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
