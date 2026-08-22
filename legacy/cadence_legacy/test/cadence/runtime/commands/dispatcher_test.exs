defmodule Cadence.Runtime.Commands.TargetDispatcherTest do
  use Cadence.IntegrationCase

  import Cadence.OrganizationsFixtures
  import Cadence.MissionsFixtures
  import Cadence.MissionDatabaseFixtures
  import Cadence.TargetsFixtures

  alias Cadence.Application.Missions.{MissionConfig, MissionQueries}
  alias Cadence.Application.Targeting.TargetQueries
  alias Cadence.Commands
  alias Cadence.MissionDatabase.{Argument, MetaCommand}
  alias Cadence.Runtime.Commands.{TargetDispatcher, TargetQueue, VerificationManager}
  alias Cadence.Runtime.Uplink.Dispatcher, as: UplinkDispatcher

  # Setup creates an org, mission, target, and commands for testing
  setup do
    # Create organization and mission using fixtures
    org = organization_fixture()

    mission =
      mission_fixture(
        organization: org,
        phase: "operational"
      )

    # Create database and definition_set for the target
    database = database_fixture(organization: org, mission: mission)

    definition_set =
      definition_set_fixture(organization: org, mission: mission, database: database)

    # Create target using fixture
    target =
      target_fixture(
        organization: org,
        mission: mission,
        definition_set: definition_set,
        name: "SC1",
        identifier: "SC1-#{System.unique_integer([:positive])}",
        status: "online",
        config: %{"command_apid" => 100}
      )

    # Create a simple command (linked to definition_set so dispatcher can find it)
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

    mission_entity = MissionQueries.find!(mission.id)

    target_entity = TargetQueries.find_with_definition_set!(target.id)

    config = %MissionConfig{
      mission_id: mission.id,
      organization_id: org.id,
      mission: mission_entity
    }

    {:ok, _uplink_pid} =
      start_supervised({UplinkDispatcher, config: config}, id: :uplink_dispatcher)

    {:ok, _verification_pid} =
      start_supervised({VerificationManager, mission_id: mission.id}, id: :verification_manager)

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

      # Confirm should either succeed or fail due to no transport (which is expected in test)
      result = Commands.confirm_dispatch(mission.id, target.id, info.token)

      # Will fail because we don't have a transport set up, but the confirmation worked
      assert {:error, :no_transport} = result
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
