defmodule Cadence.ContactPlanning.FleetPlannerTest do
  use Cadence.DataCase, async: false

  alias Cadence.Accounts.{OrganizationMembership, User}
  alias Cadence.Auth.Scope

  alias Cadence.ContactPlanning.{
    ContactPlanExecutions,
    ContactPlans,
    ContactRequirements,
    ContactRequirementTemplates,
    FleetPlanner,
    FleetPlanningPolicies,
    FleetPlanningRuns,
    FleetRepairs
  }

  alias Cadence.Control.Contacts, as: ControlContacts
  alias Cadence.Management.Contacts, as: ManagementContacts

  alias Cadence.GroundNetworks.ProviderError

  alias Cadence.Control.Contacts.Store.ContactPlanExecutionItemRow
  alias Cadence.Management.Contacts.Store.ContactPlanRow

  alias Cadence.Repo
  alias Cadence.Spacecraft

  @organization_id "org-fleet-planner"
  @mission_id "mission-fleet-planner"
  @now ~U[2026-07-17 08:00:00.000000Z]

  setup do
    %{organization: organization, mission: mission} =
      persist_mission_scope(@organization_id, @mission_id)

    for suffix <- ~w(alpha beta gamma) do
      assert {:ok, _spacecraft} =
               Cadence.SpacecraftStore.persist_spacecraft(
                 @organization_id,
                 Spacecraft.new(%{
                   spacecraft_id: spacecraft_id(suffix),
                   mission_id: mission.mission_id,
                   display_name: "Fleet #{String.capitalize(suffix)}"
                 })
               )
    end

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
               "Enable fleet planner"
             )

    %{
      admin_scope: admin_scope,
      member_scope: member_scope,
      policy: policy,
      policy_version: policy_version
    }
  end

  test "composes Stage 4 searches into one deterministic ordinary candidate Plan", context do
    requirement_alpha = create_requirement!(context.member_scope, "alpha")
    requirement_beta = create_requirement!(context.member_scope, "beta")
    test_pid = self()

    assert {:ok, result} =
             FleetPlanner.plan(
               context.member_scope,
               @mission_id,
               run_attrs(),
               materialize_templates: false,
               now: @now,
               list_routes: &list_routes/3,
               search_opportunities: fn organization_id, mission_id, route_key, window, opts ->
                 send(test_pid, {:fleet_searched, route_key})
                 search_opportunities(organization_id, mission_id, route_key, window, opts)
               end
             )

    assert result.run.lifecycle_state == :completed
    assert result.run.phase == :finished
    assert result.run.fleet_planning_policy_id == context.policy.fleet_planning_policy_id
    assert result.run.fleet_planning_policy_version == context.policy_version.version
    assert result.plan.lifecycle_state == :draft
    assert result.plan_version.version == 1
    assert result.run.candidate_contact_plan_id == result.plan.contact_plan_id
    assert result.run.candidate_contact_plan_version == result.plan_version.version

    assert_received {:fleet_searched, "route-alpha"}
    assert_received {:fleet_searched, "route-beta"}

    assert Enum.map(result.requirement_refs, & &1.contact_requirement_id) ==
             Enum.sort([
               requirement_alpha.contact_requirement_id,
               requirement_beta.contact_requirement_id
             ])

    assert Enum.all?(result.requirement_refs, &(&1.input_state == :searched))
    assert Enum.all?(result.requirement_refs, &(&1.result_state == :satisfied))
    assert Enum.all?(result.requirement_refs, &is_binary(&1.contact_planning_run_id))

    assert Enum.map(result.decisions, & &1.disposition) == [:selected, :selected]
    assert Enum.map(result.decisions, & &1.rank) == [1, 2]

    assert length(result.plan_version.planning_run_refs_document["runs"]) == 2
    assert length(result.plan_version.selected_snapshot_ids) == 2
    assert result.plan_version.coverage_document["satisfied"]
    assert result.plan_version.conflict_document["clear"]

    assert ContactPlans.selected_snapshots(
             @organization_id,
             @mission_id,
             result.plan.contact_plan_id,
             1
           )
           |> length() == 2

    assert {:ok, repeated} =
             FleetPlanner.run(
               context.member_scope,
               @mission_id,
               result.run.fleet_planning_run_id,
               list_routes: fn _, _, _ ->
                 send(test_pid, :unexpected_route_search)
                 {:error, :must_not_run}
               end
             )

    assert repeated.run == result.run
    assert repeated.plan == result.plan
    assert repeated.plan_version == result.plan_version
    refute_received :unexpected_route_search
  end

  test "one failed provider search yields a partial fleet run and explainable Plan", context do
    requirement_alpha = create_requirement!(context.member_scope, "alpha")
    requirement_beta = create_requirement!(context.member_scope, "beta")

    assert {:ok, result} =
             FleetPlanner.plan(
               context.member_scope,
               @mission_id,
               run_attrs(),
               materialize_templates: false,
               now: @now,
               list_routes: &list_routes/3,
               search_opportunities: fn _organization_id, _mission_id, route_key, window, _opts ->
                 if route_key == "route-beta" do
                   {:error, ProviderError.unavailable("provider unavailable")}
                 else
                   {:ok, %{opportunities: [opportunity("alpha", window)]}}
                 end
               end
             )

    assert result.run.lifecycle_state == :partial
    assert result.plan.lifecycle_state == :draft
    assert length(result.plan_version.selected_snapshot_ids) == 1
    refute result.plan_version.coverage_document["satisfied"]

    refs = Map.new(result.requirement_refs, &{&1.contact_requirement_id, &1})

    assert refs[requirement_alpha.contact_requirement_id].result_state == :satisfied
    assert refs[requirement_beta.contact_requirement_id].input_state == :failed
    assert refs[requirement_beta.contact_requirement_id].result_state == :failed

    assert get_in(
             result.run.result_summary_document,
             ["coverage", requirement_beta.contact_requirement_id, "state"]
           ) == "unsatisfied"
  end

  test "Requirement drift stops closed before provider search and leaves durable failure",
       context do
    requirement = create_requirement!(context.member_scope, "alpha")
    test_pid = self()

    assert {:ok, run, [_ref]} =
             FleetPlanner.start(
               context.member_scope,
               @mission_id,
               run_attrs(),
               materialize_templates: false,
               now: @now
             )

    assert {:ok, _updated, version_two} =
             ContactRequirements.version(
               context.member_scope,
               @mission_id,
               requirement.contact_requirement_id,
               1,
               %{priority: :critical},
               now: DateTime.add(@now, 1, :second)
             )

    assert version_two.version == 2

    assert {:ok, result} =
             FleetPlanner.run(
               context.member_scope,
               @mission_id,
               run.fleet_planning_run_id,
               now: @now,
               list_routes: fn _, _, _ ->
                 send(test_pid, :unexpected_drift_search)
                 list_routes(@organization_id, @mission_id, spacecraft_id("alpha"))
               end
             )

    assert result.run.lifecycle_state == :failed
    assert result.run.phase == :finished
    assert result.run.failure_document["code"] == "fleet_inputs_stale"
    assert result.run.failure_document["reason_code"] == "fleet_planning_input_drift"
    assert result.plan == nil
    assert result.decisions == []
    refute_received :unexpected_drift_search
  end

  test "mission members materialize active templates as run-start operations", context do
    assert {:ok, template, _version} =
             ContactRequirementTemplates.create(
               context.admin_scope,
               @mission_id,
               %{
                 spacecraft_id: spacecraft_id("gamma"),
                 schedule_document: %{
                   "type" => "fixed_interval",
                   "anchor_at" => DateTime.to_iso8601(@now),
                   "interval_seconds" => 3_600,
                   "window_offset_seconds" => 600,
                   "window_duration_seconds" => 1_800
                 },
                 requirement_document: template_requirement_document(),
                 catch_up_policy_document: %{
                   "maximum_occurrences_per_run" => 2,
                   "maximum_lookback_seconds" => 86_400
                 }
               },
               now: @now
             )

    assert {:ok, run, refs} =
             FleetPlanner.start(
               context.member_scope,
               @mission_id,
               run_attrs(%{horizon_end: DateTime.add(@now, 7_200, :second)}),
               now: @now
             )

    assert run.input_document["template_materialization"] == %{
             "template_count" => 1,
             "occurrence_count" => 2,
             "created_count" => 2,
             "existing_count" => 0
           }

    assert length(refs) == 2

    assert Enum.all?(refs, fn ref ->
             {:ok, version} =
               ContactRequirements.fetch_version(
                 @organization_id,
                 @mission_id,
                 ref.contact_requirement_id,
                 ref.contact_requirement_version
               )

             get_in(version.metadata, [
               "generation",
               "contact_requirement_template_id"
             ]) == template.contact_requirement_template_id
           end)

    assert {:ok, repeated_run, repeated_refs} =
             FleetPlanner.start(
               context.member_scope,
               @mission_id,
               run_attrs(%{horizon_end: DateTime.add(@now, 7_200, :second)}),
               now: DateTime.add(@now, 30, :second)
             )

    assert repeated_run.input_document["template_materialization"]["existing_count"] == 2
    assert length(repeated_refs) == 2
  end

  test "the durable fail transition is phase-checked and idempotent", context do
    _requirement = create_requirement!(context.member_scope, "alpha")

    assert {:ok, run, [_ref]} =
             FleetPlanner.start(
               context.member_scope,
               @mission_id,
               run_attrs(),
               materialize_templates: false
             )

    assert {:error, :stale_fleet_planning_run_phase} =
             FleetPlanningRuns.fail(
               context.member_scope,
               @mission_id,
               run.fleet_planning_run_id,
               :searching,
               %{"code" => "wrong_phase"}
             )

    assert {:ok, failed} =
             FleetPlanningRuns.fail(
               context.member_scope,
               @mission_id,
               run.fleet_planning_run_id,
               :queued,
               %{"code" => "test_failure"},
               now: @now
             )

    assert failed.lifecycle_state == :failed
    assert failed.phase == :finished

    assert {:ok, ^failed} =
             FleetPlanningRuns.fail(
               context.member_scope,
               @mission_id,
               run.fleet_planning_run_id,
               :queued,
               %{"code" => "ignored_retry"},
               now: DateTime.add(@now, 30, :second)
             )
  end

  test "repair locks successful commitments and only books replacement selections", context do
    _requirement_alpha = create_requirement!(context.member_scope, "alpha")
    _requirement_beta = create_requirement!(context.member_scope, "beta")

    assert {:ok, source} =
             FleetPlanner.plan(
               context.member_scope,
               @mission_id,
               run_attrs(),
               materialize_templates: false,
               now: @now,
               list_routes: &list_routes/3,
               search_opportunities: &search_opportunities/5
             )

    assert {:ok, _pending} =
             ContactPlans.submit(
               context.member_scope,
               @mission_id,
               source.plan.contact_plan_id,
               source.plan_version.version,
               "Exercise partial execution repair",
               now: @now
             )

    resolve_route = fn _organization_id, _mission_id, spacecraft_id, _route_key ->
      suffix = String.replace_prefix(spacecraft_id, "spacecraft-", "")
      {:ok, route(suffix)}
    end

    assert {:ok, approved_handoff} =
             ManagementContacts.approve_plan(
               context.admin_scope,
               @mission_id,
               source.plan.contact_plan_id,
               source.plan_version.version,
               source.plan_version.content_sha256,
               "Approve repair source",
               now: DateTime.add(@now, 1, :second),
               resolve_route: resolve_route
             )

    assert :ok = ControlContacts.accept_approved_plan(approved_handoff)

    assert {:ok, approved, _version} =
             ManagementContacts.fetch_plan(
               @organization_id,
               @mission_id,
               source.plan.contact_plan_id
             )

    source_snapshots =
      ContactPlans.bookable_snapshots(
        @organization_id,
        @mission_id,
        source.plan.contact_plan_id,
        source.plan_version.version
      )

    locked_snapshot =
      Enum.find(source_snapshots, fn snapshot ->
        snapshot.route_binding_document["spacecraft_id"] == spacecraft_id("alpha")
      end)

    rejected_snapshot =
      Enum.find(source_snapshots, fn snapshot ->
        snapshot.route_binding_document["spacecraft_id"] == spacecraft_id("beta")
      end)

    mark_execution_item!(approved, locked_snapshot, :reserved)
    mark_execution_item!(approved, rejected_snapshot, :rejected)
    mark_plan_partially_reserved!(approved)

    assert {:ok, repaired} =
             FleetRepairs.repair(
               context.member_scope,
               @mission_id,
               source.run.fleet_planning_run_id,
               source.plan.contact_plan_id,
               source.plan_version.version,
               run_attrs(),
               now: DateTime.add(@now, 2, :second),
               list_routes: &list_routes/3,
               search_opportunities: &search_opportunities/5
             )

    assert repaired.run.trigger_kind == :repair
    assert repaired.run.source_fleet_planning_run_id == source.run.fleet_planning_run_id
    assert repaired.run.source_contact_plan_id == source.plan.contact_plan_id
    assert repaired.run.source_contact_plan_version == source.plan_version.version

    assert repaired.plan_version.locked_snapshot_ids == [
             locked_snapshot.contact_opportunity_snapshot_id
           ]

    assert length(repaired.plan_version.selected_snapshot_ids) == 1

    assert Enum.any?(repaired.decisions, fn decision ->
             decision.contact_opportunity_snapshot_id ==
               locked_snapshot.contact_opportunity_snapshot_id and
               decision.disposition == :locked
           end)

    assert {:ok, _pending_repair} =
             ContactPlans.submit(
               context.member_scope,
               @mission_id,
               repaired.plan.contact_plan_id,
               repaired.plan_version.version,
               "Approve only the replacement",
               now: DateTime.add(@now, 3, :second)
             )

    assert {:ok, repair_handoff} =
             ManagementContacts.approve_plan(
               context.admin_scope,
               @mission_id,
               repaired.plan.contact_plan_id,
               repaired.plan_version.version,
               repaired.plan_version.content_sha256,
               "Preserve the committed pass and book the replacement",
               now: DateTime.add(@now, 4, :second),
               resolve_route: resolve_route
             )

    assert :ok = ControlContacts.accept_approved_plan(repair_handoff)

    repair_items =
      ContactPlanExecutions.list(
        @organization_id,
        @mission_id,
        repaired.plan.contact_plan_id,
        repaired.plan_version.version
      )

    assert length(repair_items) == 1

    refute hd(repair_items).contact_opportunity_snapshot_id ==
             locked_snapshot.contact_opportunity_snapshot_id
  end

  defp create_requirement!(scope, suffix) do
    assert {:ok, requirement, _version} =
             ContactRequirements.create(
               scope,
               @mission_id,
               %{
                 spacecraft_id: spacecraft_id(suffix),
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
                 priority: :high,
                 provider_constraints_document: %{"allowed" => [], "excluded" => []},
                 station_constraints_document: %{"allowed" => [], "excluded" => []},
                 policy_constraints_document: %{},
                 approval_policy_document: %{"mode" => "manual"},
                 rationale: "Fleet planner integration test",
                 metadata: %{"suffix" => suffix}
               },
               now: @now
             )

    requirement
  end

  defp run_attrs(overrides \\ %{}) do
    Map.merge(
      %{
        horizon_start: @now,
        horizon_end: DateTime.add(@now, 14_400, :second),
        trigger_kind: :manual
      },
      overrides
    )
  end

  defp list_routes(_organization_id, _mission_id, spacecraft_id) do
    suffix = String.replace_prefix(spacecraft_id, "spacecraft-", "")
    {:ok, %{routes: [route(suffix)], findings: []}}
  end

  defp search_opportunities(_organization_id, _mission_id, route_key, window, _opts) do
    suffix = String.replace_prefix(route_key, "route-", "")
    {:ok, %{opportunities: [opportunity(suffix, window)]}}
  end

  defp route(suffix) do
    %{
      route_key: "route-#{suffix}",
      spacecraft_id: spacecraft_id(suffix),
      provider_spacecraft_ref: "SC-#{suffix}",
      source_endpoint_id: "source-#{suffix}",
      routing_rule_id: "routing-#{suffix}",
      link_assignment_id: "link-#{suffix}",
      path_template_id: "path-#{suffix}",
      path_template_version: 1,
      transport_id: "transport-#{suffix}",
      transport_version: 2,
      provider_id: "provider-#{suffix}",
      provider_version: 3,
      provider_account_id: "account-#{suffix}",
      provider_account_version: 4,
      provider_account_grant_id: "grant-#{suffix}",
      provider_account_grant_version: 5,
      provider_profile_id: "runtime-#{suffix}",
      provider_profile_version: 6,
      service_profile_ref: %{"id" => "service-downlink", "version" => 7},
      delivery_profile_ref: %{"id" => "delivery-cadence", "version" => 8},
      delivery_policy_document: %{"mode" => "approval_required", "version" => 1},
      provider_display_name: "Provider #{suffix}",
      service_display_name: "Realtime downlink",
      delivery_display_name: "Cadence primary",
      route_display_name: "Route #{suffix}",
      client: FleetPlannerTest.FakeClient
    }
  end

  defp opportunity(suffix, window) do
    starts_at = DateTime.add(@now, 3_600 + opportunity_offset(suffix), :second)
    ends_at = DateTime.add(starts_at, 900, :second)

    %{
      "id" => "opportunity-#{suffix}",
      "spacecraft_ref" => "SC-#{suffix}",
      "ground_station_ref" => "station-#{suffix}",
      "antenna_or_service_pool_ref" => "pool-#{suffix}",
      "service_profile_ref" => "service-downlink",
      "starts_at" => DateTime.to_iso8601(starts_at),
      "ends_at" => DateTime.to_iso8601(ends_at),
      "expires_at" => DateTime.to_iso8601(DateTime.add(@now, 1_800, :second)),
      "availability" => "available",
      "estimated_capacity" => %{"bytes" => 1_000_000_000},
      "synthetic" => true,
      "extensions" => %{
        "orbit_readiness" => %{
          "status" => "current",
          "valid_until" => window["ends_at"]
        }
      }
    }
  end

  defp opportunity_offset("alpha"), do: 0
  defp opportunity_offset("beta"), do: 1_800
  defp opportunity_offset(_suffix), do: 3_600

  defp mark_execution_item!(plan, snapshot, state) do
    row =
      Repo.get_by!(ContactPlanExecutionItemRow,
        organization_id: plan.organization_id,
        mission_id: plan.mission_id,
        contact_plan_id: plan.contact_plan_id,
        contact_plan_version: plan.approved_version,
        contact_opportunity_snapshot_id: snapshot.contact_opportunity_snapshot_id
      )

    assert {:ok, _updated} =
             row
             |> ContactPlanExecutionItemRow.transition_changeset(%{
               lifecycle_state: Atom.to_string(state),
               attempt_count: 1,
               last_error_document: %{},
               started_at: @now,
               completed_at: @now
             })
             |> Repo.update()
  end

  defp mark_plan_partially_reserved!(plan) do
    row = Repo.get!(ContactPlanRow, plan.contact_plan_id)

    assert {:ok, _updated} =
             row
             |> ContactPlanRow.projection_changeset(%{
               current_version: row.current_version,
               lifecycle_state: "partially_reserved",
               lifecycle_changed_by: row.approved_by,
               lifecycle_changed_at: DateTime.add(@now, 1, :second),
               lifecycle_reason: "one provider commitment failed",
               approved_version: row.approved_version,
               approved_at: row.approved_at,
               approved_by: row.approved_by
             })
             |> Repo.update()
  end

  defp template_requirement_document do
    %{
      "service_direction" => "downlink",
      "contact_intent" => "recurring_payload_downlink",
      "success_measure" => "minimum_duration",
      "minimum_duration_seconds" => 600,
      "preferred_duration_seconds" => 900,
      "minimum_data_volume_bytes" => nil,
      "contact_count" => 1,
      "minimum_separation_seconds" => 0,
      "priority" => "high",
      "provider_constraints_document" => %{"allowed" => [], "excluded" => []},
      "station_constraints_document" => %{"allowed" => [], "excluded" => []},
      "policy_constraints_document" => %{},
      "approval_policy_document" => %{"mode" => "manual"},
      "rationale" => "Recurring fleet test",
      "metadata" => %{"source" => "fleet-planner-test"}
    }
  end

  defp policy_attrs do
    %{
      horizon_document: %{
        "max_horizon_seconds" => 86_400,
        "requirement_concurrency" => 4,
        "provider_search_concurrency" => 2,
        "reuse_freshness_seconds" => 300
      },
      scoring_document: %{
        "priority_weight" => 2_000,
        "deadline_weight" => 1_000,
        "scarcity_weight" => 800,
        "local_improvement_limit" => 100,
        "local_improvement_width" => 2
      },
      resource_policy_document: %{
        "default_exclusive_capacity" => 1,
        "capacities" => %{}
      },
      budget_quota_document: %{
        "max_contacts" => 100,
        "max_estimated_cost_micros" => nil,
        "currency" => nil,
        "per_provider" => %{},
        "critical_contact_reserve" => 0,
        "critical_cost_reserve_micros" => 0
      },
      redundancy_document: %{
        "distinct_provider_required" => false,
        "distinct_station_required" => false,
        "distinct_service_pool_required" => false
      },
      automation_repair_document: %{
        "mode" => "advisory",
        "execution_concurrency" => 2,
        "max_repair_attempts" => 2,
        "repair_horizon_seconds" => 43_200,
        "automatic_submission" => false
      }
    }
  end

  defp spacecraft_id(suffix), do: "spacecraft-#{suffix}"

  defp scope(organization, role) do
    user =
      User.new(%{
        user_id: "fleet-planner-user-#{role}",
        email: "fleet-planner-#{role}@example.test",
        display_name: "Fleet Planner #{role}"
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
