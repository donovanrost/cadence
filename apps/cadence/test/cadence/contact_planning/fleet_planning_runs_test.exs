defmodule Cadence.ContactPlanning.FleetPlanningRunsTest do
  use Cadence.DataCase, async: false

  alias Cadence.Accounts.{OrganizationMembership, User}
  alias Cadence.Auth.Scope

  alias Cadence.ContactPlanning.{
    ContactRequirements,
    FleetPlanningPolicies,
    FleetPlanningRuns
  }

  alias Cadence.Spacecraft

  @organization_id "org-fleet-planning-runs"
  @mission_id "mission-fleet-planning-runs"
  @spacecraft_id "spacecraft-fleet-planning-runs"
  @now ~U[2026-07-17 04:00:00.000000Z]

  setup do
    %{organization: organization, mission: mission} =
      persist_mission_scope(@organization_id, @mission_id)

    spacecraft =
      Spacecraft.new(%{
        spacecraft_id: @spacecraft_id,
        mission_id: mission.mission_id,
        display_name: "Aurora Fleet"
      })

    assert {:ok, _spacecraft} =
             Cadence.SpacecraftStore.persist_spacecraft(@organization_id, spacecraft)

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
               "Fleet planning enabled"
             )

    %{
      admin_scope: admin_scope,
      member_scope: member_scope,
      organization: organization,
      policy: policy,
      policy_version: policy_version
    }
  end

  test "a mission member snapshots the exact active policy and intersecting Requirements",
       context do
    assert {:ok, requirement, requirement_version} =
             ContactRequirements.create(
               context.member_scope,
               @mission_id,
               requirement_attrs()
             )

    assert {:ok, _outside, _outside_version} =
             ContactRequirements.create(
               context.member_scope,
               @mission_id,
               requirement_attrs(%{
                 earliest_start: DateTime.add(@now, 86_400, :second),
                 latest_end: DateTime.add(@now, 90_000, :second)
               })
             )

    assert {:ok, run, [input_ref]} =
             FleetPlanningRuns.create(
               context.member_scope,
               @mission_id,
               run_attrs()
             )

    assert run.lifecycle_state == :queued
    assert run.phase == :queued
    assert run.trigger_kind == :manual
    assert run.fleet_planning_policy_id == context.policy.fleet_planning_policy_id
    assert run.fleet_planning_policy_version == context.policy_version.version
    assert run.input_document["requirement_count"] == 1
    assert run.trigger_actor_document["id"] == context.member_scope.user.user_id

    assert input_ref.contact_requirement_id == requirement.contact_requirement_id
    assert input_ref.contact_requirement_version == requirement_version.version
    assert input_ref.input_state == :pending
    assert input_ref.result_state == :pending

    assert {:ok, ^run} =
             FleetPlanningRuns.fetch(
               @organization_id,
               @mission_id,
               run.fleet_planning_run_id
             )

    assert [^run] = FleetPlanningRuns.list(@organization_id, @mission_id)

    assert [^input_ref] =
             FleetPlanningRuns.list_requirement_refs(
               @organization_id,
               @mission_id,
               run.fleet_planning_run_id
             )
  end

  test "a run keeps immutable Requirement evidence after the Requirement changes", context do
    assert {:ok, requirement, version_one} =
             ContactRequirements.create(
               context.member_scope,
               @mission_id,
               requirement_attrs()
             )

    assert {:ok, run, [input_ref]} =
             FleetPlanningRuns.create(
               context.member_scope,
               @mission_id,
               run_attrs(%{
                 requirement_refs: [
                   %{
                     contact_requirement_id: requirement.contact_requirement_id,
                     version: version_one.version
                   }
                 ]
               })
             )

    assert {:ok, _requirement_two, version_two} =
             ContactRequirements.version(
               context.member_scope,
               @mission_id,
               requirement.contact_requirement_id,
               1,
               %{priority: :critical}
             )

    assert version_two.version == 2

    assert [persisted_ref] =
             FleetPlanningRuns.list_requirement_refs(
               @organization_id,
               @mission_id,
               run.fleet_planning_run_id
             )

    assert persisted_ref == input_ref
    assert persisted_ref.contact_requirement_version == 1

    assert {:error, :fleet_planning_requirement_version_changed} =
             FleetPlanningRuns.create(
               context.member_scope,
               @mission_id,
               run_attrs(%{
                 requirement_refs: [
                   %{
                     contact_requirement_id: requirement.contact_requirement_id,
                     version: version_one.version
                   }
                 ]
               })
             )
  end

  test "policy horizon, nonempty input, and mission membership fail closed", context do
    assert {:ok, requirement, version} =
             ContactRequirements.create(
               context.member_scope,
               @mission_id,
               requirement_attrs()
             )

    assert {:error, :fleet_planning_horizon_exceeds_policy} =
             FleetPlanningRuns.create(
               context.member_scope,
               @mission_id,
               run_attrs(%{horizon_end: DateTime.add(@now, 86_401, :second)})
             )

    assert {:error, :fleet_planning_run_has_no_requirements} =
             FleetPlanningRuns.create(
               context.member_scope,
               @mission_id,
               run_attrs(%{requirement_refs: []})
             )

    outsider_scope =
      Scope.new(%{
        user:
          User.new(%{
            email: "fleet-run-outsider@example.test",
            display_name: "Fleet Run Outsider"
          }),
        organization_id: context.organization.organization_id,
        organization: context.organization
      })

    assert {:error, :forbidden} =
             FleetPlanningRuns.create(
               outsider_scope,
               @mission_id,
               run_attrs(%{
                 requirement_refs: [
                   %{
                     contact_requirement_id: requirement.contact_requirement_id,
                     version: version.version
                   }
                 ]
               })
             )
  end

  test "phase advancement is ordered and retry-safe", context do
    run = create_run!(context)

    assert {:ok, materializing} =
             FleetPlanningRuns.advance_phase(
               context.member_scope,
               @mission_id,
               run.fleet_planning_run_id,
               :queued,
               :materializing
             )

    assert materializing.lifecycle_state == :running
    assert materializing.phase == :materializing
    assert %DateTime{} = materializing.started_at

    assert {:ok, ^materializing} =
             FleetPlanningRuns.advance_phase(
               context.member_scope,
               @mission_id,
               run.fleet_planning_run_id,
               :queued,
               :materializing
             )

    assert {:error, :stale_fleet_planning_run_phase} =
             FleetPlanningRuns.advance_phase(
               context.member_scope,
               @mission_id,
               run.fleet_planning_run_id,
               :searching,
               :optimizing
             )

    assert {:error, :invalid_fleet_planning_phase} =
             FleetPlanningRuns.advance_phase(
               context.member_scope,
               @mission_id,
               run.fleet_planning_run_id,
               :materializing,
               :optimizing
             )

    assert {:ok, searching} =
             FleetPlanningRuns.advance_phase(
               context.member_scope,
               @mission_id,
               run.fleet_planning_run_id,
               :materializing,
               :searching,
               %{progress_document: %{"requirements_total" => 1, "requirements_searched" => 0}}
             )

    assert searching.phase == :searching
    assert searching.progress_document["requirements_total"] == 1
  end

  test "per-Requirement checkpoints preserve prior evidence when fields are omitted", context do
    run = create_run!(context)

    [input_ref] =
      FleetPlanningRuns.list_requirement_refs(
        @organization_id,
        @mission_id,
        run.fleet_planning_run_id
      )

    assert {:ok, searching_ref} =
             FleetPlanningRuns.update_requirement_progress(
               context.member_scope,
               @mission_id,
               run.fleet_planning_run_id,
               input_ref.contact_requirement_id,
               :searching,
               :pending,
               %{
                 explanation_document: %{
                   "code" => "provider_search_started",
                   "attempt" => 1
                 }
               }
             )

    assert {:ok, searched_ref} =
             FleetPlanningRuns.update_requirement_progress(
               context.member_scope,
               @mission_id,
               run.fleet_planning_run_id,
               input_ref.contact_requirement_id,
               :searched,
               :partial
             )

    assert searched_ref.explanation_document == searching_ref.explanation_document
    assert searched_ref.contact_planning_run_id == nil
    assert searched_ref.input_state == :searched
    assert searched_ref.result_state == :partial
  end

  test "finished and canceled runs retain explicit terminal evidence", context do
    completed_run = create_run!(context)

    completed =
      [
        {:queued, :materializing, %{}},
        {:materializing, :searching, %{}},
        {:searching, :optimizing, %{}},
        {:optimizing, :materializing_plan, %{}},
        {:materializing_plan, :finished,
         %{
           outcome: :partial,
           result_summary_document: %{
             "requirements_satisfied" => 0,
             "requirements_partial" => 1
           }
         }}
      ]
      |> Enum.reduce(completed_run, fn {expected, next, attrs}, current ->
        assert {:ok, advanced} =
                 FleetPlanningRuns.advance_phase(
                   context.member_scope,
                   @mission_id,
                   current.fleet_planning_run_id,
                   expected,
                   next,
                   attrs
                 )

        advanced
      end)

    assert completed.lifecycle_state == :partial
    assert completed.phase == :finished
    assert %DateTime{} = completed.completed_at
    assert completed.result_summary_document["requirements_partial"] == 1

    canceled_run = create_run!(context)

    assert {:error, :fleet_planning_run_cancel_reason_required} =
             FleetPlanningRuns.cancel(
               context.member_scope,
               @mission_id,
               canceled_run.fleet_planning_run_id,
               ""
             )

    assert {:ok, canceled} =
             FleetPlanningRuns.cancel(
               context.member_scope,
               @mission_id,
               canceled_run.fleet_planning_run_id,
               "Operator superseded this run"
             )

    assert canceled.lifecycle_state == :canceled
    assert canceled.phase == :finished
    assert canceled.failure_document["code"] == "operator_canceled"

    assert {:error, :fleet_planning_run_terminal} =
             FleetPlanningRuns.cancel(
               context.member_scope,
               @mission_id,
               canceled_run.fleet_planning_run_id,
               "Cancel again"
             )
  end

  defp create_run!(context) do
    assert {:ok, requirement, version} =
             ContactRequirements.create(
               context.member_scope,
               @mission_id,
               requirement_attrs()
             )

    assert {:ok, run, [_input_ref]} =
             FleetPlanningRuns.create(
               context.member_scope,
               @mission_id,
               run_attrs(%{
                 requirement_refs: [
                   %{
                     contact_requirement_id: requirement.contact_requirement_id,
                     version: version.version
                   }
                 ]
               })
             )

    run
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

  defp requirement_attrs(overrides \\ %{}) do
    Map.merge(
      %{
        spacecraft_id: @spacecraft_id,
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
        rationale: "Protect recorder margin",
        metadata: %{"source" => "fleet-run-test"}
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

  defp scope(organization, role) do
    user =
      User.new(%{
        user_id: "fleet-run-user-#{role}",
        email: "fleet-run-#{role}@example.test",
        display_name: "Fleet Run #{role}"
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
