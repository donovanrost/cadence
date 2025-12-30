defmodule Cadence.Runtime.Commands.TargetDispatcherTest do
  use Cadence.DataCase, async: false

  alias Cadence.Commands
  alias Cadence.MissionDatabase.{Argument, Database, DefinitionSet, MetaCommand}
  alias Cadence.Missions.Mission
  alias Cadence.Organizations.Organization
  alias Cadence.Runtime.Commands.{TargetDispatcher, TargetQueue}
  alias Cadence.Targets.Target

  # Setup creates an org, mission, target, and commands for testing
  setup do
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

    # Create target
    target =
      %Target{}
      |> Target.changeset(%{
        mission_id: mission.id,
        definition_set_id: definition_set.id,
        name: "SC1",
        type: "spacecraft",
        identifier: "SC1_#{System.unique_integer([:positive])}",
        status: "online"
      })
      |> Repo.insert!()

    # Create a simple MetaCommand (linked to definition_set for lookup)
    simple_command =
      %MetaCommand{}
      |> MetaCommand.changeset(%{
        organization_id: org.id,
        mission_id: mission.id,
        definition_set_id: definition_set.id,
        name: "SET_MODE",
        opcode: 0x10,
        is_hazardous: false,
        requires_confirmation: false
      })
      |> Repo.insert!()

    # Add argument to simple command
    %Argument{}
    |> Argument.changeset(%{
      meta_command_id: simple_command.id,
      name: "mode",
      data_type_ref: "uint",
      bit_offset: 0,
      bit_length: 8,
      required: true
    })
    |> Repo.insert!()

    # Create a hazardous command
    hazardous_command =
      %MetaCommand{}
      |> MetaCommand.changeset(%{
        organization_id: org.id,
        mission_id: mission.id,
        definition_set_id: definition_set.id,
        name: "SAFE_MODE",
        opcode: 0x20,
        is_hazardous: true,
        hazard_description: "This will put spacecraft in safe mode",
        requires_confirmation: true
      })
      |> Repo.insert!()

    # Create command with phase restriction
    phase_restricted_command =
      %MetaCommand{}
      |> MetaCommand.changeset(%{
        organization_id: org.id,
        mission_id: mission.id,
        definition_set_id: definition_set.id,
        name: "COMMISSIONING_CMD",
        opcode: 0x30,
        is_hazardous: false,
        allowed_phases: ["commissioning", "testing"]
      })
      |> Repo.insert!()

    mission_entity = Cadence.Application.Missions.MissionQueries.find!(mission.id)

    target_entity =
      Cadence.Application.Targeting.TargetQueries.find_with_definition_set!(target.id)

    # Start the target queue and dispatcher for this target
    {:ok, _queue_pid} =
      start_supervised(
        {TargetQueue, mission: mission_entity, target: target_entity},
        id: :target_queue
      )

    {:ok, _dispatcher_pid} =
      start_supervised(
        {TargetDispatcher, mission: mission_entity, target: target_entity},
        id: :target_dispatcher
      )

    %{
      org: org,
      mission: mission,
      target: target,
      simple_command: simple_command,
      hazardous_command: hazardous_command,
      phase_restricted_command: phase_restricted_command
    }
  end

  describe "dispatch/4" do
    test "returns error for unknown command", %{mission: mission, target: target} do
      result = Commands.dispatch(mission.id, "NONEXISTENT", %{}, target: target.id)
      assert {:error, :unknown_command} = result
    end

    test "raises when target not provided", %{mission: mission} do
      assert_raise ArgumentError, ~r/target or target_id is required/, fn ->
        Commands.dispatch(mission.id, "SET_MODE", %{mode: 1}, [])
      end
    end

    test "returns error for unknown target", %{mission: mission} do
      # Dispatch to non-existent target should exit because no dispatcher process
      fake_target_id = Ecto.UUID.generate()

      assert {:error, :dispatcher_not_running} =
               Commands.dispatch(mission.id, "SET_MODE", %{mode: 1}, target: fake_target_id)
    end

    test "returns error when required argument is missing", %{mission: mission, target: target} do
      result = Commands.dispatch(mission.id, "SET_MODE", %{}, target: target.id)
      assert {:error, :validation_failed, errors} = result
      assert {"mode", "is required"} in errors
    end

    test "returns requires_confirmation for hazardous command", %{
      mission: mission,
      target: target
    } do
      result = Commands.dispatch(mission.id, "SAFE_MODE", %{}, target: target.id)

      assert {:error, :requires_confirmation, info} = result
      assert info.token
      assert info.command_name == "SAFE_MODE"
      assert info.hazard_description == "This will put spacecraft in safe mode"
      assert info.expires_at
    end

    test "returns error for phase-restricted command in wrong phase", %{
      mission: mission,
      target: target
    } do
      # Mission is in "operational" phase, but command only allowed in "commissioning" or "testing"
      result = Commands.dispatch(mission.id, "COMMISSIONING_CMD", %{}, target: target.id)

      # Phase can be string or atom depending on whether Ecto schema or domain entity is used
      assert {:error, :not_allowed_in_phase, phase} = result
      assert phase in ["operational", :operational]
    end
  end

  describe "confirm_dispatch/3" do
    test "returns error for invalid token", %{mission: mission, target: target} do
      result = Commands.confirm_dispatch(mission.id, target.id, "invalid-token")
      assert {:error, :invalid_token} = result
    end

    test "dispatches command after confirmation", %{mission: mission, target: target} do
      # First dispatch returns confirmation request
      {:error, :requires_confirmation, info} =
        Commands.dispatch(mission.id, "SAFE_MODE", %{}, target: target.id)

      # Confirm should either succeed or fail due to no interface (which is expected in test)
      result = Commands.confirm_dispatch(mission.id, target.id, info.token)

      # Will fail because we don't have an interface set up, but the confirmation worked
      assert {:error, :no_interface} = result
    end

    test "token expires after timeout", %{mission: mission, target: target} do
      # Get the token
      {:error, :requires_confirmation, info} =
        Commands.dispatch(mission.id, "SAFE_MODE", %{}, target: target.id)

      # Verify the token was created correctly with a reasonable expiry
      assert DateTime.diff(info.expires_at, DateTime.utc_now(), :second) > 0
      assert DateTime.diff(info.expires_at, DateTime.utc_now(), :second) <= 60
    end
  end

  describe "status/2" do
    test "returns dispatcher statistics for target", %{mission: mission, target: target} do
      status = TargetDispatcher.status(mission.id, target.id)

      assert status.mission_id == mission.id
      assert status.target_id == target.id
      assert status.pending_confirmations >= 0
      assert status.pending_verifications >= 0
      assert status.paused == false
    end
  end

  describe "pause/resume" do
    test "pauses and resumes dispatcher for target", %{mission: mission, target: target} do
      # Initially not paused
      status = TargetDispatcher.status(mission.id, target.id)
      refute status.paused

      # Pause
      :ok = TargetDispatcher.pause(mission.id, target.id)
      status = TargetDispatcher.status(mission.id, target.id)
      assert status.paused

      # Resume
      :ok = TargetDispatcher.resume(mission.id, target.id)
      status = TargetDispatcher.status(mission.id, target.id)
      refute status.paused
    end
  end
end
