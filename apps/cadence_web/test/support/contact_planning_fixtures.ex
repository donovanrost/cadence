defmodule CadenceWeb.ContactPlanningFixtures do
  @moduledoc false

  import ExUnit.Assertions

  alias Cadence.Auth.Scope
  alias Cadence.Governance.ActivationPolicy

  alias Cadence.ContactPlanning.{
    ContactPlans,
    ContactRequirements,
    FleetPlanningPolicies,
    Planner
  }

  @now ~U[2027-01-01 00:00:00Z]

  def now, do: @now

  @doc """
  Sets the mission's approval to 'direct', so an administrator's own submit also approves.
  'independent' (the default) needs a second person (director 11-15).
  """
  def approve_directly!(org, user, membership, mission) do
    scope =
      Scope.new(%{
        user: user,
        organization_id: org.organization_id,
        organization_membership: membership
      })

    policy = ActivationPolicy.load(org.organization_id, mission.mission_id)

    {:ok, _saved} =
      ActivationPolicy.save(scope, mission.mission_id, policy.token, %{
        "value" => %{"approval_requirement" => "direct"}
      })

    :ok
  end

  @doc """
  A spacecraft with one minimum-duration downlink requirement, a planning run
  that found one synthetic opportunity, and a draft plan selecting it.
  Options: `:select?` (default true) to leave the plan without the pass.
  """
  def plan_fixture(org, user, membership, mission, opts \\ []) do
    scope =
      Scope.new(%{
        user: user,
        organization_id: org.organization_id,
        organization_membership: membership
      })

    craft =
      Cadence.Spacecraft.new(%{
        spacecraft_id:
          Keyword.get_lazy(opts, :spacecraft_id, fn -> Cadence.Ids.new("spacecraft") end),
        mission_id: mission.mission_id,
        display_name: Keyword.get(opts, :display_name, "Plan craft")
      })

    {:ok, _} = Cadence.SpacecraftStore.persist_spacecraft(org.organization_id, craft)

    {:ok, requirement, version} =
      ContactRequirements.create(scope, mission.mission_id, %{
        spacecraft_id: craft.spacecraft_id,
        service_direction: :downlink,
        contact_intent: "payload_downlink",
        earliest_start: DateTime.add(@now, 3600),
        latest_end: DateTime.add(@now, 28_800),
        success_measure: :minimum_duration,
        minimum_duration_seconds: 60,
        priority: :high,
        rationale: "Reviewed contact need",
        metadata: Keyword.get(opts, :metadata, %{})
      })

    {:ok, planning} =
      Planner.run(scope, mission.mission_id, requirement.contact_requirement_id, version.version,
        now: @now,
        list_routes: fn _, _, _ ->
          {:ok, %{routes: [route(craft.spacecraft_id)], findings: []}}
        end,
        search_opportunities: fn _, _, _, _, _ -> {:ok, %{opportunities: [opportunity()]}} end
      )

    selected =
      if Keyword.get(opts, :select?, true),
        do: Enum.map(planning.snapshots, & &1.contact_opportunity_snapshot_id),
        else: []

    assert {:ok, plan, plan_version} =
             ContactPlans.create(scope, mission.mission_id, %{
               planning_run_ids: [planning.run.contact_planning_run_id],
               selected_snapshot_ids: selected,
               rationale: "Reviewed plan for the console"
             })

    %{
      scope: scope,
      craft: craft,
      requirement: requirement,
      requirement_version: version,
      planning: planning,
      plan: plan,
      plan_version: plan_version
    }
  end

  @doc "An approved, active fleet planning policy (admin scope required)."
  def active_policy!(admin_scope, mission_id) do
    assert {:ok, policy, version} =
             FleetPlanningPolicies.create(admin_scope, mission_id, policy_attrs())

    assert {:ok, _, _, _} =
             FleetPlanningPolicies.approve(
               admin_scope,
               mission_id,
               policy.fleet_planning_policy_id,
               version.version,
               version.content_sha256,
               "Reviewed fleet boundary"
             )

    policy
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
      resource_policy_document: %{"default_exclusive_capacity" => 1, "capacities" => %{}},
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

  def route(craft),
    do: %{
      route_key: "review-route",
      spacecraft_id: craft,
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

  def opportunity,
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
