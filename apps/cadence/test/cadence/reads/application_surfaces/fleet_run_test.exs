defmodule Cadence.Reads.ApplicationSurfaces.FleetRunTest do
  use Cadence.DataCase, async: false
  alias Cadence.Applications.{ActionRequest, HostContext, SurfaceQueryRequest}
  alias Cadence.Applications.OpsConsole.ActionProvider
  alias Cadence.ContactPlanning.{ContactRequirements, FleetPlanningRuns}
  alias Cadence.FleetRunFixtures, as: Fixtures
  alias Cadence.FleetStartFixtures
  alias Cadence.Reads.ApplicationSurfaces.OpsConsole
  alias Cadence.Reads.ApplicationSurfaces.Planning.FleetRun

  @checker Path.expand(
             "../../../../../../frontend/modules/planning-and-contacts/src/features/fleet-planning/run-producer-check.mjs",
             __DIR__
           )
  setup do: Fixtures.setup_run()

  test "authoritative queued and completed run models render through the public Vue entry", c do
    model = model(c)
    assert model["phase"] == "queued"
    assert model["requirements"]["total"] == 1
    assert model["can_continue"]
    native(%{model: model, action: "render"})
    completed = Fixtures.complete(c)
    result = model(completed)
    assert result["phase"] == "finished"
    assert [%{"disposition" => "selected"}] = result["decisions"]["entries"]
    assert result["candidate"]["version"] == 1
    refute result["repair"]["available"]
    native(%{model: result, action: "render"})
    assert byte_size(Jason.encode!(result)) < 60_000
  end

  test "native continuation input reaches the public scoped action without substitution", c do
    observed = model(c)
    input = native(%{model: observed, action: "continue"})

    assert input == %{
             "fleet_planning_run_id" => c.run.fleet_planning_run_id,
             "evidence" => observed["evidence"]
           }

    assert {:ok, result} = action(c, "refresh-fleet-run", input)
    assert result["evidence"] == observed["evidence"]
    assert result["phase"] == "finished"
    assert {:error, :fleet_run_review_changed} = action(c, "refresh-fleet-run", input)
  end

  test "native repair submits the exact reviewed Plan and locked commitment evidence", c do
    c = Fixtures.repairable(c)
    observed = model(c)
    assert observed["repair"]["available"]

    window = %{
      "horizon_start" => "2026-07-17T04:00:00.000Z",
      "horizon_end" => "2026-07-17T08:00:00.000Z"
    }

    input = native(%{model: observed, action: "repair", window: window})
    assert input["evidence"] == observed["repair"]["evidence"]
    assert input["repair"] == window
    assert {:ok, receipt} = action(c, "repair-fleet-run", input)
    assert receipt["lifecycleState"] == "queued"

    assert {:ok, run} =
             FleetPlanningRuns.fetch(
               c.organization_id,
               c.mission_id,
               receipt["fleetPlanningRunId"]
             )

    assert run.source_fleet_planning_run_id == c.run.fleet_planning_run_id
    assert run.input_document["creation_review"] == input["evidence"]
  end

  test "input paging stays bounded and keeps exact versions after newer requirement edits", c do
    for _ <- 1..11,
        do:
          ContactRequirements.create(
            c.scope,
            c.mission_id,
            FleetStartFixtures.requirement_attrs()
          )

    {:ok, run, _} =
      FleetPlanningRuns.create(c.scope, c.mission_id, %{
        horizon_start: c.run.horizon_start,
        horizon_end: c.run.horizon_end
      })

    c = %{c | run: run}
    first = model(c)
    assert length(first["requirements"]["entries"]) == 10
    assert first["requirements"]["more"]
    second = model(c, %{"requirements_page" => "2"})
    assert length(second["requirements"]["entries"]) == 2
    refute second["requirements"]["more"]
    assert first["evidence"] == second["evidence"]
    native(%{model: second, action: "render"})

    assert {:ok, _, _} =
             ContactRequirements.version(
               c.scope,
               c.mission_id,
               c.requirement.contact_requirement_id,
               1,
               %{priority: :critical}
             )

    assert first["evidence"] == model(c)["evidence"]
  end

  test "scope and query admission fail closed without mutating the run", c do
    for params <- [
          %{"requirements_page" => "0"},
          %{"decisions_page" => "01"},
          %{"automation_page" => 1},
          %{"extra" => "x"}
        ] do
      assert {:error, :invalid_fleet_run_query} =
               FleetRun.admit_query(
                 Map.put(params, "fleet_planning_run_id", c.run.fleet_planning_run_id)
               )
    end

    assert {:error, :unsupported_application_surface_query} =
             OpsConsole.load(
               %{c.scope | organization_membership: nil},
               HostContext.mission(c.mission_id),
               request(c, %{})
             )

    assert {:error, :unsupported_application_surface_query} =
             OpsConsole.load(
               c.scope,
               HostContext.mission(c.mission_id),
               request(c, %{"mission_id" => "foreign"})
             )

    assert {:ok, run} =
             FleetPlanningRuns.fetch(c.organization_id, c.mission_id, c.run.fleet_planning_run_id)

    assert run.phase == :queued
  end

  test "optimizer decisions page through every persisted ranked opportunity", c do
    search = fn org, mission, route, window, opts ->
      {:ok, %{opportunities: [opportunity]}} =
        Fixtures.search_opportunities(org, mission, route, window, opts)

      {:ok, %{opportunities: Enum.map(1..12, &Map.put(opportunity, "id", "opportunity-#{&1}"))}}
    end

    c = Fixtures.complete(c, search_opportunities: search)
    first = model(c)
    second = model(c, %{"decisions_page" => "2"})
    assert length(first["decisions"]["entries"]) == 10
    assert first["decisions"]["more"]
    assert length(second["decisions"]["entries"]) == 2
    refute second["decisions"]["more"]

    actual =
      Enum.map(
        first["decisions"]["entries"] ++ second["decisions"]["entries"],
        & &1["snapshot_id"]
      )

    expected =
      FleetPlanningRuns.list_decisions(
        c.organization_id,
        c.mission_id,
        c.run.fleet_planning_run_id
      )

    assert actual == Enum.map(expected, & &1.contact_opportunity_snapshot_id)
    assert length(Enum.uniq(actual)) == 12
    native(%{model: second, action: "render"})
  end

  defp model(c, params \\ %{}) do
    assert {:ok, _} =
             FleetRun.load(
               c.scope,
               c.mission,
               Map.put(params, "fleet_planning_run_id", c.run.fleet_planning_run_id)
             )

    assert {:ok,
            %{
              "data" => %{
                "presentation" => %{
                  "component" => "OpsFleetPlanningRun",
                  "props" => %{"run" => model}
                }
              }
            }} = OpsConsole.load(c.scope, HostContext.mission(c.mission_id), request(c, params))

    model
  end

  defp request(c, params),
    do: %SurfaceQueryRequest{
      application_key: "ops_console",
      application_version: 1,
      surface_id: "fleet_planning_run",
      surface_version: 1,
      query_id: "cadence.ops.fleet_planning_run",
      query_version: 1,
      params: Map.put(params, "fleet_planning_run_id", c.run.fleet_planning_run_id)
    }

  defp action(c, id, input),
    do:
      ActionProvider.execute(c.scope, HostContext.mission(c.mission_id), %ActionRequest{
        application_key: "ops_console",
        application_version: 1,
        surface_id: "fleet_planning_run",
        surface_version: 1,
        action_id: id,
        params: input
      })

  defp native(supplied) do
    {output, status} =
      System.cmd("node", [@checker, Jason.encode!(supplied)], stderr_to_stdout: true)

    assert status == 0, output

    if supplied.action == "render",
      do: :ok,
      else:
        output
        |> then(&Regex.run(~r/FLEET_RUN_PAYLOAD=([^\n]+)/, &1))
        |> Enum.at(1)
        |> Jason.decode!()
  end
end
