defmodule Cadence.FleetRunFixtures do
  @moduledoc false
  alias Cadence.ContactPlanning.{ContactPlanExecutionItem, FleetPlanner, FleetPlanningRuns}
  alias Cadence.Control.Contacts.Store.ContactPlanExecutionItemRow
  alias Cadence.FleetStartFixtures
  alias Cadence.Management.Contacts.Store.ContactPlanRow
  alias Cadence.Repo
  @now ~U[2026-07-17 04:00:00.000000Z]
  def setup_run do
    c = FleetStartFixtures.setup_start()

    {:ok, run, refs} =
      FleetPlanningRuns.create(c.scope, c.mission_id, %{
        horizon_start: @now,
        horizon_end: DateTime.add(@now, 14_400, :second)
      })

    Map.merge(c, %{run: run, refs: refs})
  end

  def complete(c, opts \\ []) do
    options =
      Keyword.merge(
        [
          now: @now,
          list_routes: &list_routes/3,
          search_opportunities: &search_opportunities/5
        ],
        opts
      )

    {:ok, result} =
      FleetPlanner.run(c.scope, c.mission_id, c.run.fleet_planning_run_id, options)

    Map.merge(c, %{run: result.run, result: result})
  end

  def repairable(c) do
    c = complete(c)
    plan = c.result.plan
    row = Repo.get!(ContactPlanRow, plan.contact_plan_id)
    Repo.update!(Ecto.Changeset.change(row, lifecycle_state: "partially_reserved"))
    [snapshot_id] = c.result.plan_version.selected_snapshot_ids

    item =
      ContactPlanExecutionItem.new(%{
        organization_id: c.organization_id,
        mission_id: c.mission_id,
        contact_plan_id: plan.contact_plan_id,
        contact_plan_version: c.result.plan_version.version,
        contact_opportunity_snapshot_id: snapshot_id,
        idempotency_key: "fleet-run-reviewed-commitment",
        lifecycle_state: :uncertain,
        attempt_count: 1,
        last_error_document: %{}
      })

    execution = Repo.insert!(ContactPlanExecutionItemRow.changeset(item))
    Map.merge(c, %{execution: execution, snapshot_id: snapshot_id})
  end

  def list_routes(_organization_id, _mission_id, spacecraft_id) do
    suffix = if(spacecraft_id == "craft-fleet-start", do: "alpha", else: spacecraft_id)
    {:ok, %{routes: [route(suffix)], findings: []}}
  end

  def search_opportunities(_organization_id, _mission_id, route_key, window, _opts) do
    suffix = String.replace_prefix(route_key, "route-", "")
    {:ok, %{opportunities: [opportunity(suffix, window)]}}
  end

  def route(suffix) do
    %{
      route_key: "route-#{suffix}",
      spacecraft_id: "craft-fleet-start",
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
      client: __MODULE__
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
end
