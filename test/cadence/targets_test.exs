defmodule Cadence.TargetsTest do
  use Cadence.DataCase, async: true

  import Cadence.OrganizationsFixtures

  alias Cadence.{Targets, Missions}
  alias Cadence.Targets.Target

  setup do
    org = organization_fixture()

    {:ok, mission} =
      Missions.create_mission(%{
        organization_id: org.id,
        name: "Test Mission",
        slug: "test-mission",
        status: "active"
      })

    %{mission: mission, organization: org}
  end

  describe "targets" do
    test "list_targets/1 returns all targets for a mission", %{mission: mission} do
      {:ok, target} =
        Targets.create_target(%{
          mission_id: mission.id,
          name: "Satellite 1",
          identifier: "SAT-001",
          type: "spacecraft"
        })

      targets = Targets.list_targets(mission)
      assert length(targets) == 1
      assert hd(targets).id == target.id
    end

    test "get_target!/1 returns the target with given id", %{mission: mission} do
      {:ok, target} =
        Targets.create_target(%{
          mission_id: mission.id,
          name: "Satellite 1",
          identifier: "SAT-001",
          type: "spacecraft"
        })

      assert Targets.get_target!(target.id).id == target.id
    end

    test "get_target_by_identifier/2 returns target by identifier", %{mission: mission} do
      {:ok, target} =
        Targets.create_target(%{
          mission_id: mission.id,
          name: "Satellite 1",
          identifier: "SAT-001",
          type: "spacecraft"
        })

      found = Targets.get_target_by_identifier(mission, "SAT-001")
      assert found.id == target.id
    end

    test "create_target/1 with valid data creates a target", %{mission: mission} do
      valid_attrs = %{
        mission_id: mission.id,
        name: "Satellite 1",
        identifier: "SAT-001",
        type: "spacecraft",
        status: "offline"
      }

      assert {:ok, %Target{} = target} = Targets.create_target(valid_attrs)
      assert target.name == "Satellite 1"
      assert target.identifier == "SAT-001"
      assert target.type == "spacecraft"
    end

    test "create_target/1 enforces unique identifier per mission", %{mission: mission} do
      attrs = %{
        mission_id: mission.id,
        name: "Satellite 1",
        identifier: "SAT-001",
        type: "spacecraft"
      }

      assert {:ok, _} = Targets.create_target(attrs)
      assert {:error, changeset} = Targets.create_target(attrs)
      # The unique constraint is on [:mission_id, :identifier]
      assert %{mission_id: ["has already been taken"]} = errors_on(changeset)
    end

    test "update_target/2 updates the target", %{mission: mission} do
      {:ok, target} =
        Targets.create_target(%{
          mission_id: mission.id,
          name: "Satellite 1",
          identifier: "SAT-001",
          type: "spacecraft"
        })

      assert {:ok, %Target{} = target} = Targets.update_target(target, %{name: "Updated Name"})
      assert target.name == "Updated Name"
    end

    test "delete_target/1 deletes the target", %{mission: mission} do
      {:ok, target} =
        Targets.create_target(%{
          mission_id: mission.id,
          name: "Satellite 1",
          identifier: "SAT-001",
          type: "spacecraft"
        })

      assert {:ok, %Target{}} = Targets.delete_target(target)
      assert_raise Ecto.NoResultsError, fn -> Targets.get_target!(target.id) end
    end
  end

  describe "circuit breaker" do
    setup %{mission: mission} do
      {:ok, target} =
        Targets.create_target(%{
          mission_id: mission.id,
          name: "Satellite 1",
          identifier: "SAT-001",
          type: "spacecraft"
        })

      %{target: target}
    end

    test "open_circuit_breaker/1 opens the circuit breaker", %{target: target} do
      assert {:ok, updated} = Targets.open_circuit_breaker(target)
      assert updated.circuit_breaker_status == "open"
      assert updated.circuit_breaker_opened_at != nil
    end

    test "close_circuit_breaker/1 closes and resets", %{target: target} do
      {:ok, target} = Targets.open_circuit_breaker(target)
      {:ok, updated} = Targets.close_circuit_breaker(target)

      assert updated.circuit_breaker_status == "closed"
      assert updated.circuit_breaker_failures == 0
      assert updated.circuit_breaker_opened_at == nil
    end

    test "increment_circuit_breaker_failures/1 increments count", %{target: target} do
      {:ok, updated} = Targets.increment_circuit_breaker_failures(target)
      assert updated.circuit_breaker_failures == 1
      assert updated.circuit_breaker_status == "closed"
    end

    test "increment_circuit_breaker_failures/1 opens after threshold", %{target: target} do
      {:ok, target} = Targets.increment_circuit_breaker_failures(target, 2)
      assert target.circuit_breaker_failures == 1

      {:ok, target} = Targets.increment_circuit_breaker_failures(target, 2)
      assert target.circuit_breaker_failures == 2
      assert target.circuit_breaker_status == "open"
    end

    test "circuit_breaker_open?/1 checks status", %{target: target} do
      refute Targets.circuit_breaker_open?(target)

      {:ok, target} = Targets.open_circuit_breaker(target)
      assert Targets.circuit_breaker_open?(target)
    end
  end

  describe "target groups" do
    test "create_target_group/1 creates a group", %{mission: mission} do
      attrs = %{
        mission_id: mission.id,
        name: "Shell 1",
        slug: "shell-1",
        group_type: "shell"
      }

      assert {:ok, group} = Targets.create_target_group(attrs)
      assert group.name == "Shell 1"
      assert group.group_type == "shell"
    end

    test "list_target_groups/1 returns all groups for mission", %{mission: mission} do
      {:ok, _} =
        Targets.create_target_group(%{
          mission_id: mission.id,
          name: "Shell 1",
          slug: "shell-1",
          group_type: "shell"
        })

      groups = Targets.list_target_groups(mission)
      assert length(groups) == 1
    end

    test "add_target_to_group/2 adds target to group", %{mission: mission} do
      {:ok, target} =
        Targets.create_target(%{
          mission_id: mission.id,
          name: "SAT-001",
          identifier: "SAT-001",
          type: "spacecraft"
        })

      {:ok, group} =
        Targets.create_target_group(%{
          mission_id: mission.id,
          name: "Shell 1",
          slug: "shell-1",
          group_type: "shell"
        })

      assert {:ok, updated_group} = Targets.add_target_to_group(target, group)
      assert length(updated_group.targets) == 1
    end

    test "add_target_to_group/2 rejects mismatched missions", %{mission: mission, organization: org} do
      {:ok, other_mission} =
        Missions.create_mission(%{
          organization_id: org.id,
          name: "Other Mission",
          slug: "other-mission",
          status: "active"
        })

      {:ok, target} =
        Targets.create_target(%{
          mission_id: mission.id,
          name: "SAT-001",
          identifier: "SAT-001",
          type: "spacecraft"
        })

      {:ok, group} =
        Targets.create_target_group(%{
          mission_id: other_mission.id,
          name: "Shell 1",
          slug: "shell-1",
          group_type: "shell"
        })

      assert {:error, :mission_mismatch} = Targets.add_target_to_group(target, group)
    end
  end
end
