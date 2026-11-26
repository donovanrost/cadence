defmodule Cadence.ContactPlanning.FleetSnapshotEvidenceTest do
  use Cadence.DataCase, async: false

  alias Cadence.ContactPlanning.{ContentHash, FleetPlanningRuns, Planner}
  alias Cadence.{ContactScheduleFixtures, FleetRunFixtures}

  test "fleet snapshots read back the pinned route and hashed provider evidence" do
    context = FleetRunFixtures.setup_run()
    run_id = context.run.fleet_planning_run_id

    assert {:ok, _} =
             FleetPlanningRuns.advance_phase(
               context.scope,
               context.mission_id,
               run_id,
               :queued,
               :materializing,
               %{}
             )

    assert {:ok, _} =
             FleetPlanningRuns.advance_phase(
               context.scope,
               context.mission_id,
               run_id,
               :materializing,
               :searching,
               %{}
             )

    route = FleetRunFixtures.route("alpha")
    orbit = %{"status" => "current", "ephemeris_ref" => "ephemeris-fixture"}

    opportunity =
      route
      |> ContactScheduleFixtures.opportunity(context.requirement_version.earliest_start)
      |> Map.merge(%{
        "route_key" => route.route_key,
        "delivery_profile_ref" => route.delivery_profile_ref["id"],
        "extensions" => %{"orbit_readiness" => orbit}
      })

    response =
      {:ok, %{opportunities: [opportunity], provider_evidence: %{"orbit_readiness" => orbit}}}

    now = DateTime.add(context.requirement_version.earliest_start, -60)

    entry =
      Planner.fleet_entry(
        context.requirement_version,
        context.scope.user.user_id,
        {:ok, %{routes: [route], findings: []}},
        %{route.route_key => response},
        %{},
        now: now,
        started_at: now
      )

    assert {:ok, :ok} =
             FleetPlanningRuns.checkpoint_search_batch(
               context.scope,
               context.mission_id,
               run_id,
               [entry]
             )

    stage4_id = entry.run.contact_planning_run_id

    assert [search] =
             Planner.list_searches(context.organization_id, context.mission_id, stage4_id)

    assert [snapshot] =
             Planner.list_snapshots(context.organization_id, context.mission_id, stage4_id)

    assert snapshot.route_binding_document == search.route_binding_document
    assert snapshot.normalized_opportunity_document == opportunity
    assert snapshot.provider_evidence_document == opportunity

    assert snapshot.content_sha256 ==
             ContentHash.sha256(%{
               "route" => search.route_binding_document,
               "opportunity" => opportunity
             })
  end
end
