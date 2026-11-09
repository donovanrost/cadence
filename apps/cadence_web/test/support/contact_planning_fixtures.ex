defmodule CadenceWeb.ContactPlanningFixtures do
  @moduledoc false

  import ExUnit.Assertions

  alias Cadence.Auth.Scope
  alias Cadence.ContactPlanning.{ContactPlans, ContactRequirements, Planner}

  @now ~U[2027-01-01 00:00:00Z]

  def now, do: @now

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
        spacecraft_id: Cadence.Ids.new("spacecraft"),
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
        rationale: "Reviewed contact need"
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
