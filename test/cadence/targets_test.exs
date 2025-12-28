defmodule Cadence.TargetsTest do
  use Cadence.DataCase, async: true

  import Cadence.OrganizationsFixtures
  import Cadence.MissionDatabaseFixtures

  alias Cadence.Domain.Targeting.Entities.Target
  alias Cadence.{Missions, Targets}

  setup do
    org = organization_fixture()

    {:ok, mission} =
      Missions.create_mission(org.id, %{
        name: "Test Mission",
        slug: "test-mission",
        status: "active"
      })

    # Create a definition set for the mission (required for targets)
    definition_set = definition_set_fixture(organization: org, mission: mission)

    %{mission: mission, organization: org, definition_set: definition_set}
  end

  describe "targets" do
    test "list_targets/1 returns all targets for a mission", %{
      mission: mission,
      definition_set: ds
    } do
      {:ok, target} =
        Targets.create_target(%{
          mission_id: mission.id,
          definition_set_id: ds.id,
          name: "Satellite 1",
          identifier: "SAT-001",
          type: :spacecraft
        })

      targets = Targets.list_targets(mission)
      assert length(targets) == 1
      assert hd(targets).id == target.id
    end

    test "get_target!/2 returns the target with given id", %{mission: mission, definition_set: ds} do
      {:ok, target} =
        Targets.create_target(%{
          mission_id: mission.id,
          definition_set_id: ds.id,
          name: "Satellite 1",
          identifier: "SAT-001",
          type: :spacecraft
        })

      found = Targets.get_target!(target.id, mission.id)
      assert found.id == target.id
    end

    test "get_target/2 returns {:ok, target} or {:error, :not_found}", %{
      mission: mission,
      definition_set: ds
    } do
      {:ok, target} =
        Targets.create_target(%{
          mission_id: mission.id,
          definition_set_id: ds.id,
          name: "Satellite 1",
          identifier: "SAT-001",
          type: :spacecraft
        })

      assert {:ok, found} = Targets.get_target(target.id, mission.id)
      assert found.id == target.id

      assert {:error, :not_found} = Targets.get_target(Ecto.UUID.generate(), mission.id)
    end

    test "get_target_by_identifier/2 returns target by identifier", %{
      mission: mission,
      definition_set: ds
    } do
      {:ok, target} =
        Targets.create_target(%{
          mission_id: mission.id,
          definition_set_id: ds.id,
          name: "Satellite 1",
          identifier: "SAT-001",
          type: :spacecraft
        })

      assert {:ok, found} = Targets.get_target_by_identifier(mission, "SAT-001")
      assert found.id == target.id
    end

    test "create_target/1 with valid data creates a target", %{
      mission: mission,
      definition_set: ds
    } do
      valid_attrs = %{
        mission_id: mission.id,
        definition_set_id: ds.id,
        name: "Satellite 1",
        identifier: "SAT-001",
        type: :spacecraft,
        status: :offline
      }

      assert {:ok, %Target{} = target} = Targets.create_target(valid_attrs)
      assert target.name == "Satellite 1"
      assert target.identifier == "SAT-001"
      assert target.type == :spacecraft
    end

    test "create_target/1 enforces unique identifier per mission", %{
      mission: mission,
      definition_set: ds
    } do
      attrs = %{
        mission_id: mission.id,
        definition_set_id: ds.id,
        name: "Satellite 1",
        identifier: "SAT-001",
        type: :spacecraft
      }

      assert {:ok, _} = Targets.create_target(attrs)
      assert {:error, errors} = Targets.create_target(attrs)
      # The unique constraint error from the repository
      assert is_map(errors)
    end

    test "update_target/2 updates the target", %{mission: mission, definition_set: ds} do
      {:ok, target} =
        Targets.create_target(%{
          mission_id: mission.id,
          definition_set_id: ds.id,
          name: "Satellite 1",
          identifier: "SAT-001",
          type: :spacecraft
        })

      assert {:ok, %Target{} = updated} = Targets.update_target(target, %{name: "Updated Name"})
      assert updated.name == "Updated Name"
    end

    test "delete_target/1 deletes the target", %{mission: mission, definition_set: ds} do
      {:ok, target} =
        Targets.create_target(%{
          mission_id: mission.id,
          definition_set_id: ds.id,
          name: "Satellite 1",
          identifier: "SAT-001",
          type: :spacecraft
        })

      assert {:ok, %Target{}} = Targets.delete_target(target)
      assert {:error, :not_found} = Targets.get_target(target.id, mission.id)
    end
  end

  describe "circuit breaker" do
    setup %{mission: mission, definition_set: ds} do
      {:ok, target} =
        Targets.create_target(%{
          mission_id: mission.id,
          definition_set_id: ds.id,
          name: "Satellite 1",
          identifier: "SAT-001",
          type: :spacecraft
        })

      %{target: target}
    end

    test "open_circuit_breaker/1 opens the circuit breaker", %{target: target} do
      assert {:ok, updated} = Targets.open_circuit_breaker(target)
      assert updated.circuit_breaker_status == :open
      assert updated.circuit_breaker_opened_at != nil
    end

    test "close_circuit_breaker/1 closes and resets", %{target: target} do
      {:ok, target} = Targets.open_circuit_breaker(target)
      {:ok, updated} = Targets.close_circuit_breaker(target)

      assert updated.circuit_breaker_status == :closed
      assert updated.circuit_breaker_failures == 0
      assert updated.circuit_breaker_opened_at == nil
    end

    test "increment_circuit_breaker_failures/1 increments count", %{target: target} do
      {:ok, updated} = Targets.increment_circuit_breaker_failures(target)
      assert updated.circuit_breaker_failures == 1
      assert updated.circuit_breaker_status == :closed
    end

    test "increment_circuit_breaker_failures/1 opens after threshold", %{target: target} do
      {:ok, target} = Targets.increment_circuit_breaker_failures(target, 2)
      assert target.circuit_breaker_failures == 1

      {:ok, target} = Targets.increment_circuit_breaker_failures(target, 2)
      assert target.circuit_breaker_failures == 2
      assert target.circuit_breaker_status == :open
    end

    test "circuit_breaker_open?/1 checks status", %{target: target} do
      refute Targets.circuit_breaker_open?(target)

      {:ok, target} = Targets.open_circuit_breaker(target)
      assert Targets.circuit_breaker_open?(target)
    end
  end
end
