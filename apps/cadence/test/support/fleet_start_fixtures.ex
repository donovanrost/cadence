defmodule Cadence.FleetStartFixtures do
  @moduledoc false
  alias Cadence.Accounts.{OrganizationMembership, User}
  alias Cadence.Auth.Scope
  alias Cadence.ContactPlanning.{ContactRequirements, FleetPlanningPolicies}
  alias Cadence.Spacecraft
  @organization_id "org-fleet-start"
  @mission_id "mission-fleet-start"
  @spacecraft_id "craft-fleet-start"
  @now ~U[2026-07-17 04:00:00.000000Z]

  def setup_start do
    %{organization: org, mission: mission} =
      Cadence.DataCase.persist_mission_scope(@organization_id, @mission_id)

    craft =
      Spacecraft.new(%{
        spacecraft_id: @spacecraft_id,
        mission_id: @mission_id,
        display_name: "Fleet craft"
      })

    {:ok, _} = Cadence.SpacecraftStore.persist_spacecraft(@organization_id, craft)
    admin = scope(org, :organization_admin)
    member = scope(org, :member)
    {:ok, policy, version} = FleetPlanningPolicies.create(admin, @mission_id, policy_attrs())

    {:ok, _, _, _} =
      FleetPlanningPolicies.approve(
        admin,
        @mission_id,
        policy.fleet_planning_policy_id,
        version.version,
        version.content_sha256,
        "Reviewed fleet boundary"
      )

    {:ok, requirement, requirement_version} =
      ContactRequirements.create(member, @mission_id, requirement_attrs())

    %{
      scope: member,
      admin: admin,
      organization: org,
      mission: mission,
      mission_id: @mission_id,
      organization_id: @organization_id,
      craft: craft,
      policy: policy,
      policy_version: version,
      requirement: requirement,
      requirement_version: requirement_version
    }
  end

  def params(recurring \\ false),
    do: %{
      "fleet_run" => %{
        "horizon_start" => DateTime.to_iso8601(@now),
        "horizon_end" => @now |> DateTime.add(14_400, :second) |> DateTime.to_iso8601(),
        "include_recurring" => recurring
      }
    }

  def requirement_attrs(overrides \\ %{}) do
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

  def policy_attrs do
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

  def template_attrs(overrides \\ %{}) do
    Map.merge(
      %{
        spacecraft_id: @spacecraft_id,
        schedule_document: %{
          "type" => "fixed_interval",
          "anchor_at" => DateTime.to_iso8601(@now),
          "interval_seconds" => 3_600,
          "window_offset_seconds" => 600,
          "window_duration_seconds" => 1_800
        },
        requirement_document: requirement_document(),
        catch_up_policy_document: %{
          "maximum_occurrences_per_run" => 10,
          "maximum_lookback_seconds" => 86_400
        }
      },
      overrides
    )
  end

  defp requirement_document(overrides \\ %{}) do
    Map.merge(
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
        "rationale" => "Keep payload recorder below mission threshold",
        "metadata" => %{"source" => "recurring-policy"}
      },
      overrides
    )
  end

  def scope(organization, role) do
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
