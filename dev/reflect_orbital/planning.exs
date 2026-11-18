defmodule Cadence.Dev.ReflectOrbital.Planning do
  @moduledoc false
  # Contact planning for the Earendil demo: one approved, active fleet planning
  # policy and a recurring downlink requirement template for the first N
  # spacecraft (EARENDIL_PLANNING_SPACECRAFT, default 10: the ones with live
  # feeds), so the console can draft a day reproducibly. Idempotent.
  alias Cadence.Auth.Scope
  alias Cadence.ContactPlanning.{ContactRequirementTemplates, FleetPlanningPolicies}
  alias Cadence.Dev.ReflectOrbital.Fixture, as: F

  @anchor ~U[2026-01-01 00:00:00Z]
  @minimum_duration_s 300

  def run do
    unless Code.ensure_loaded?(Mix) and Mix.env() == :dev,
      do: raise("The Earendil planning seed requires development mode")

    Logger.configure(level: :warning)
    {:ok, _apps} = Application.ensure_all_started(:cadence)
    {:ok, organization} = Cadence.Organizations.fetch_organization(F.organization_id())
    {user, membership} = admin_member(System.get_env("EARENDIL_DEMO_EMAIL", "admin@example.com"))

    prepare(Scope.new(%{user: user, organization: organization, organization_membership: membership}))
  end

  # The given user when they are a Reflect Orbital member; otherwise the first
  # organization admin of Reflect Orbital (the env admin may not be a member).
  defp admin_member(email) do
    with {:ok, user} <- Cadence.Accounts.fetch_user_by_email(email),
         {:ok, membership} <- Cadence.Accounts.fetch_user_membership(user.user_id, F.organization_id()) do
      {user, membership}
    else
      _not_member ->
        case Enum.find(
               Cadence.Accounts.list_organization_members(F.organization_id()),
               &(&1.membership.role == :organization_admin)
             ) do
          %{user: user, membership: membership} -> {user, membership}
          nil -> raise "No Reflect Orbital organization admin to seed planning as (set EARENDIL_DEMO_EMAIL)"
        end
    end
  end

  def prepare(%Scope{} = scope) do
    policy = ensure_policy(scope)
    count = String.to_integer(System.get_env("EARENDIL_PLANNING_SPACECRAFT", "10"))
    templates = ensure_templates(scope, count)

    IO.puts("""
    Contact planning: fleet planning policy #{policy} active; #{templates} recurring downlink
    templates (one 5-minute contact every 6 h) for the first #{count} spacecraft.
    """)
  end

  defp ensure_policy(scope) do
    case FleetPlanningPolicies.fetch_active(F.organization_id(), F.mission_id()) do
      {:ok, policy, _version} ->
        policy.fleet_planning_policy_id

      {:error, _none} ->
        {:ok, policy, version} = FleetPlanningPolicies.create(scope, F.mission_id(), policy_attrs())

        {:ok, _, _, _} =
          FleetPlanningPolicies.approve(
            scope,
            F.mission_id(),
            policy.fleet_planning_policy_id,
            version.version,
            version.content_sha256,
            "Earendil demo planning boundary"
          )

        policy.fleet_planning_policy_id
    end
  end

  defp ensure_templates(scope, count) do
    templates = ContactRequirementTemplates.list(F.organization_id(), F.mission_id())
    existing = MapSet.new(templates, fn {_template, version} -> version.spacecraft_id end)

    # Bring templates seeded with an older rule up to date (new template version).
    Enum.each(templates, fn {template, version} ->
      if version.requirement_document["minimum_duration_seconds"] != @minimum_duration_s do
        {:ok, _template, _version} =
          ContactRequirementTemplates.version(
            scope,
            F.mission_id(),
            template.contact_requirement_template_id,
            version.version,
            template_attrs(version.spacecraft_id)
          )
      end
    end)

    F.spacecraft()
    |> Enum.take(count)
    |> Enum.reject(&MapSet.member?(existing, &1.spacecraft_id))
    |> Enum.each(fn craft ->
      # Templates are created active.
      {:ok, _template, _version} =
        ContactRequirementTemplates.create(scope, F.mission_id(), template_attrs(craft.spacecraft_id))
    end)

    F.organization_id()
    |> ContactRequirementTemplates.list(F.mission_id(), lifecycle_state: :active)
    |> length()
  end

  defp template_attrs(spacecraft_id) do
    %{
      spacecraft_id: spacecraft_id,
      schedule_document: %{
        "type" => "fixed_interval",
        "anchor_at" => DateTime.to_iso8601(@anchor),
        "interval_seconds" => 21_600,
        "window_offset_seconds" => 0,
        "window_duration_seconds" => 21_600
      },
      requirement_document: %{
        "service_direction" => "downlink",
        "contact_intent" => "recurring_payload_downlink",
        "success_measure" => "minimum_duration",
        # The simulator's visibility windows are 8 min; ask for 5.
        "minimum_duration_seconds" => @minimum_duration_s,
        "preferred_duration_seconds" => @minimum_duration_s,
        "minimum_data_volume_bytes" => nil,
        "contact_count" => 1,
        "minimum_separation_seconds" => 0,
        "priority" => "routine",
        "provider_constraints_document" => %{"allowed" => [], "excluded" => []},
        "station_constraints_document" => %{"allowed" => [], "excluded" => []},
        "policy_constraints_document" => %{},
        "approval_policy_document" => %{"mode" => "manual"},
        "rationale" => "Earendil demo: drain the payload recorder every 6 h",
        "metadata" => F.metadata()
      },
      catch_up_policy_document: %{
        "maximum_occurrences_per_run" => 8,
        "maximum_lookback_seconds" => 86_400
      }
    }
  end

  defp policy_attrs do
    %{
      horizon_document: %{
        "max_horizon_seconds" => 172_800,
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
        "max_contacts" => 1_000,
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
end
