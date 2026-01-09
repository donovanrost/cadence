defmodule Cadence.Commands.FleetTest do
  use Cadence.IntegrationCase

  alias Cadence.Application.Missions.MissionQueries
  alias Cadence.Application.Targeting.TargetQueries
  alias Cadence.Commands
  alias Cadence.MissionDatabase.{Argument, Database, DefinitionSet, MetaCommand}
  alias Cadence.Missions.Mission
  alias Cadence.Organizations.Organization
  alias Cadence.Runtime.Commands.{TargetDispatcher, TargetQueue}
  alias Cadence.Targets.Target

  defp base_fleet_setup do
    # Create organization
    org =
      %Organization{}
      |> Organization.changeset(%{
        name: "Test Org",
        slug: "test-org-#{System.unique_integer([:positive])}",
        status: "active",
        subscription_tier: "free"
      })
      |> Repo.insert!()

    # Create mission
    mission =
      %Mission{}
      |> Mission.changeset(%{
        organization_id: org.id,
        name: "Test Mission",
        slug: "test-mission-#{System.unique_integer([:positive])}",
        status: "active",
        phase: "operational"
      })
      |> Repo.insert!()

    # Create database for the mission
    database =
      %Database{}
      |> Database.changeset(%{
        mission_id: mission.id,
        name: "Test Database",
        slug: "test-database-#{System.unique_integer([:positive])}"
      })
      |> Repo.insert!()

    # Create definition set
    definition_set =
      %DefinitionSet{}
      |> DefinitionSet.changeset(%{
        organization_id: org.id,
        database_id: database.id,
        version: "1.0.0",
        source_format: :yaml
      })
      |> Repo.insert!()

    mission_entity = MissionQueries.find!(mission.id)

    # Create multiple targets for fleet operations
    targets =
      for i <- 1..5 do
        target =
          %Target{}
          |> Target.changeset(%{
            mission_id: mission.id,
            definition_set_id: definition_set.id,
            name: "SAT#{i}",
            type: "spacecraft",
            identifier: "SAT#{i}_#{System.unique_integer([:positive])}",
            status: "online"
          })
          |> Repo.insert!()

        target
      end

    # Create a simple command with arguments
    command =
      %MetaCommand{}
      |> MetaCommand.changeset(%{
        organization_id: org.id,
        mission_id: mission.id,
        definition_set_id: definition_set.id,
        name: "SET_ORBIT",
        opcode: 0x50,
        is_hazardous: false,
        requires_confirmation: false
      })
      |> Repo.insert!()

    # Add arguments to the command
    %Argument{}
    |> Argument.changeset(%{
      meta_command_id: command.id,
      name: "altitude",
      data_type_ref: "float",
      bit_offset: 0,
      bit_length: 32,
      required: true
    })
    |> Repo.insert!()

    %Argument{}
    |> Argument.changeset(%{
      meta_command_id: command.id,
      name: "inclination",
      data_type_ref: "float",
      bit_offset: 32,
      bit_length: 32,
      required: true
    })
    |> Repo.insert!()

    %{
      org: org,
      mission: mission,
      mission_entity: mission_entity,
      targets: targets,
      command: command
    }
  end

  defp start_target_pipelines(mission_entity, targets) do
    targets
    |> Enum.with_index(1)
    |> Enum.each(fn {target, i} ->
      target_entity = TargetQueries.find_with_definition_set!(target.id)

      {:ok, _queue_pid} =
        start_supervised(
          {TargetQueue, mission: mission_entity, target: target_entity},
          id: {:target_queue, i}
        )

      {:ok, _dispatcher_pid} =
        start_supervised(
          {TargetDispatcher, mission: mission_entity, target: target_entity},
          id: {:target_dispatcher, i}
        )
    end)
  end

  describe "fleet_dispatch_parameterized/4" do
    setup do
      setup = base_fleet_setup()
      start_target_pipelines(setup.mission_entity, setup.targets)
      setup
    end

    test "returns empty list for empty target_params", %{mission: mission} do
      result = Commands.fleet_dispatch_parameterized(mission.id, "SET_ORBIT", [])
      assert result == []
    end

    test "dispatches to multiple targets with per-target params", %{
      mission: mission,
      targets: targets
    } do
      target_params =
        targets
        |> Enum.with_index()
        |> Enum.map(fn {target, i} ->
          {target.id, %{altitude: 550.0 + i * 0.1, inclination: 53.0 + i * 0.01}}
        end)

      results = Commands.fleet_dispatch_parameterized(mission.id, "SET_ORBIT", target_params)

      assert length(results) == length(targets)

      # Each result should be {target_id, result}
      Enum.each(results, fn {target_id, result} ->
        assert is_binary(target_id)
        # Will fail with :no_interface since we don't have interfaces set up
        assert {:error, :no_interface} = result
      end)
    end

    test "returns validation errors for invalid params", %{mission: mission, targets: targets} do
      [target | _] = targets

      # Missing required argument
      target_params = [{target.id, %{altitude: 550.0}}]

      results = Commands.fleet_dispatch_parameterized(mission.id, "SET_ORBIT", target_params)

      assert [{_target_id, {:error, :validation_failed, errors}}] = results
      assert {"inclination", "is required"} in errors
    end

    test "handles unknown command for all targets", %{mission: mission, targets: targets} do
      target_params =
        Enum.map(targets, fn target ->
          {target.id, %{some: "param"}}
        end)

      results =
        Commands.fleet_dispatch_parameterized(mission.id, "NONEXISTENT_CMD", target_params)

      assert length(results) == length(targets)

      Enum.each(results, fn {_target_id, result} ->
        assert {:error, :unknown_command} = result
      end)
    end

    test "preserves order of results matching input order", %{mission: mission, targets: targets} do
      target_params =
        targets
        |> Enum.with_index()
        |> Enum.map(fn {target, i} ->
          {target.id, %{altitude: 550.0 + i, inclination: 53.0}}
        end)

      results = Commands.fleet_dispatch_parameterized(mission.id, "SET_ORBIT", target_params)

      result_target_ids = Enum.map(results, fn {target_id, _} -> target_id end)
      input_target_ids = Enum.map(target_params, fn {target_id, _} -> target_id end)

      assert result_target_ids == input_target_ids
    end

    test "parallel dispatch processes all targets", %{mission: mission, targets: targets} do
      target_params =
        targets
        |> Enum.with_index()
        |> Enum.map(fn {target, i} ->
          {target.id, %{altitude: 550.0 + i * 0.1, inclination: 53.0 + i * 0.01}}
        end)

      results =
        Commands.fleet_dispatch_parameterized(
          mission.id,
          "SET_ORBIT",
          target_params,
          parallel: true,
          max_concurrency: 10
        )

      assert length(results) == length(targets)

      Enum.each(results, fn {_target_id, result} ->
        # Will fail with :no_interface since we don't have interfaces set up
        assert {:error, :no_interface} = result
      end)
    end
  end

  describe "fleet_enqueue_parameterized/4" do
    setup do
      base_fleet_setup()
    end

    test "returns empty list for empty target_params", %{mission: mission} do
      result = Commands.fleet_enqueue_parameterized(mission.id, "SET_ORBIT", [])
      assert result == []
    end

    test "enqueues to multiple targets with per-target params", %{
      mission: mission,
      targets: targets
    } do
      target_params =
        targets
        |> Enum.with_index()
        |> Enum.map(fn {target, i} ->
          {target.id, %{altitude: 550.0 + i * 0.1, inclination: 53.0 + i * 0.01}}
        end)

      results = Commands.fleet_enqueue_parameterized(mission.id, "SET_ORBIT", target_params)

      assert length(results) == length(targets)

      # Each result should be {target_id, {:ok, queue_entry}}
      Enum.each(results, fn {target_id, result} ->
        assert is_binary(target_id)
        assert {:ok, entry} = result
        assert entry.command_name == "SET_ORBIT"
        assert entry.status == :pending
      end)
    end

    test "each target gets unique parameters in queue entry", %{
      mission: mission,
      targets: targets
    } do
      target_params =
        targets
        |> Enum.with_index()
        |> Enum.map(fn {target, i} ->
          {target.id, %{"altitude" => 550.0 + i, "inclination" => 53.0 + i * 0.1}}
        end)

      results = Commands.fleet_enqueue_parameterized(mission.id, "SET_ORBIT", target_params)

      # Verify each queue entry has unique parameters
      results
      |> Enum.with_index()
      |> Enum.each(fn {{_target_id, {:ok, entry}}, i} ->
        expected_altitude = 550.0 + i
        expected_inclination = 53.0 + i * 0.1

        assert entry.parameters["altitude"] == expected_altitude
        assert entry.parameters["inclination"] == expected_inclination
      end)
    end

    test "respects priority option for all targets", %{mission: mission, targets: targets} do
      target_params =
        Enum.map(targets, fn target ->
          {target.id, %{altitude: 550.0, inclination: 53.0}}
        end)

      results =
        Commands.fleet_enqueue_parameterized(
          mission.id,
          "SET_ORBIT",
          target_params,
          priority: 1
        )

      Enum.each(results, fn {_target_id, {:ok, entry}} ->
        assert entry.priority == 1
      end)
    end

    test "parallel enqueue processes all targets", %{mission: mission, targets: targets} do
      target_params =
        targets
        |> Enum.with_index()
        |> Enum.map(fn {target, i} ->
          {target.id, %{altitude: 550.0 + i * 0.1, inclination: 53.0 + i * 0.01}}
        end)

      results =
        Commands.fleet_enqueue_parameterized(
          mission.id,
          "SET_ORBIT",
          target_params,
          parallel: true,
          max_concurrency: 10
        )

      assert length(results) == length(targets)

      Enum.each(results, fn {_target_id, result} ->
        assert {:ok, entry} = result
        assert entry.command_name == "SET_ORBIT"
      end)
    end
  end

  describe "fleet operations with large fleet simulation" do
    setup do
      base_fleet_setup()
    end

    test "handles many targets efficiently with parallel option", %{
      mission: mission,
      targets: targets
    } do
      # Use the 5 targets we have, but simulate pattern for larger fleets
      target_params =
        targets
        |> Enum.with_index()
        |> Enum.map(fn {target, i} ->
          {target.id, %{altitude: 550.0 + i * 0.1, inclination: 53.0 + i * 0.01}}
        end)

      # Time sequential
      {sequential_time, _results} =
        :timer.tc(fn ->
          Commands.fleet_enqueue_parameterized(
            mission.id,
            "SET_ORBIT",
            target_params,
            parallel: false
          )
        end)

      # Time parallel
      {parallel_time, _results} =
        :timer.tc(fn ->
          Commands.fleet_enqueue_parameterized(
            mission.id,
            "SET_ORBIT",
            target_params,
            parallel: true,
            max_concurrency: 10
          )
        end)

      # Both should complete (we're not asserting parallel is faster with only 5 targets)
      assert sequential_time > 0
      assert parallel_time > 0
    end
  end
end
