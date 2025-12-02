defmodule Cadence.Missions.MissionLifecycleTest do
  use Cadence.DataCase, async: false

  import Cadence.OrganizationsFixtures

  alias Cadence.Missions
  alias Cadence.Missions.MissionSupervisor
  alias Cadence.Telemetry.CurrentValueTable

  # Allow mission supervisor spawned processes to access the database
  setup do
    Ecto.Adapters.SQL.Sandbox.mode(Cadence.Repo, {:shared, self()})
    :ok
  end

  describe "mission supervision tree" do
    setup do
      org = organization_fixture()

      {:ok, mission} =
        Missions.create_mission(%{
          organization_id: org.id,
          name: "Test Mission",
          slug: "test-mission",
          status: "active",
          phase: "testing"
        })

      %{mission: mission, organization: org}
    end

    test "starts mission supervision tree", %{mission: mission} do
      {:ok, pid} = Missions.start_mission(mission)

      assert Process.alive?(pid)
      assert {:ok, ^pid} = MissionSupervisor.get_mission_pid(mission.id)
    end

    test "CVT process is started with mission", %{mission: mission} do
      {:ok, _pid} = Missions.start_mission(mission)

      # Verify CVT is running by trying to set a value
      :ok =
        CurrentValueTable.set(
          mission.id,
          "SAT-001",
          "STATUS",
          "voltage",
          28.5
        )

      # Verify we can retrieve it
      {:ok, value} = CurrentValueTable.get(mission.id, "SAT-001", "STATUS", "voltage")
      assert value.value == 28.5
      assert value.limits_state == :green
    end

    test "stops mission supervision tree", %{mission: mission} do
      {:ok, pid} = Missions.start_mission(mission)
      assert Process.alive?(pid)

      :ok = Missions.stop_mission(mission.id)

      # Give it a moment to terminate
      Process.sleep(50)

      refute Process.alive?(pid)
      assert {:error, :not_found} = MissionSupervisor.get_mission_pid(mission.id)
    end

    test "does not start mission with inactive status" do
      org = organization_fixture()

      {:ok, mission} =
        Missions.create_mission(%{
          organization_id: org.id,
          name: "Inactive Mission",
          slug: "inactive-mission",
          status: "inactive"
        })

      assert {:error, _} = Missions.start_mission(mission)
    end

    test "mission instances are isolated - different ETS tables", %{organization: org} do
      {:ok, mission1} =
        Missions.create_mission(%{
          organization_id: org.id,
          name: "Mission 1",
          slug: "mission-1",
          status: "active"
        })

      {:ok, mission2} =
        Missions.create_mission(%{
          organization_id: org.id,
          name: "Mission 2",
          slug: "mission-2",
          status: "active"
        })

      {:ok, _} = Missions.start_mission(mission1)
      {:ok, _} = Missions.start_mission(mission2)

      # Set different values in each mission's CVT
      :ok = CurrentValueTable.set(mission1.id, "SAT-A", "STATUS", "temp", 25.0)
      :ok = CurrentValueTable.set(mission2.id, "SAT-B", "STATUS", "temp", 30.0)

      # Verify isolation - mission1 should not see mission2's data
      {:ok, value1} = CurrentValueTable.get(mission1.id, "SAT-A", "STATUS", "temp")
      assert value1.value == 25.0

      {:ok, value2} = CurrentValueTable.get(mission2.id, "SAT-B", "STATUS", "temp")
      assert value2.value == 30.0

      # Mission1 should not have SAT-B data
      assert {:error, :not_found} = CurrentValueTable.get(mission1.id, "SAT-B", "STATUS", "temp")

      # Clean up
      Missions.stop_mission(mission1.id)
      Missions.stop_mission(mission2.id)
    end
  end

  describe "CVT operations" do
    setup do
      org = organization_fixture()

      {:ok, mission} =
        Missions.create_mission(%{
          organization_id: org.id,
          name: "CVT Test Mission",
          slug: "cvt-test",
          status: "active"
        })

      {:ok, _} = Missions.start_mission(mission)

      on_exit(fn ->
        Missions.stop_mission(mission.id)
      end)

      %{mission: mission}
    end

    test "stores and retrieves telemetry values", %{mission: mission} do
      :ok =
        CurrentValueTable.set(
          mission.id,
          "SAT-001",
          "POWER",
          "battery_voltage",
          28.5,
          limits_state: :green,
          metadata: %{unit: "volts"}
        )

      {:ok, value} = CurrentValueTable.get(mission.id, "SAT-001", "POWER", "battery_voltage")

      assert value.value == 28.5
      assert value.limits_state == :green
      assert value.metadata.unit == "volts"
      assert %DateTime{} = value.received_time
    end

    test "updates existing telemetry values", %{mission: mission} do
      :ok = CurrentValueTable.set(mission.id, "SAT-001", "POWER", "battery_voltage", 28.0)
      :ok = CurrentValueTable.set(mission.id, "SAT-001", "POWER", "battery_voltage", 29.5)

      {:ok, value} = CurrentValueTable.get(mission.id, "SAT-001", "POWER", "battery_voltage")
      assert value.value == 29.5
    end

    test "gets all telemetry for a target", %{mission: mission} do
      :ok = CurrentValueTable.set(mission.id, "SAT-001", "POWER", "voltage", 28.5)
      :ok = CurrentValueTable.set(mission.id, "SAT-001", "POWER", "current", 5.2)
      :ok = CurrentValueTable.set(mission.id, "SAT-001", "THERMAL", "temp_1", 22.0)
      :ok = CurrentValueTable.set(mission.id, "SAT-002", "POWER", "voltage", 27.8)

      telemetry = CurrentValueTable.get_target_telemetry(mission.id, "SAT-001")

      assert length(telemetry) == 3

      assert Enum.any?(telemetry, fn {{target, packet, item}, _} ->
               target == "SAT-001" && packet == "POWER" && item == "voltage"
             end)
    end

    test "gets all telemetry for a packet", %{mission: mission} do
      :ok = CurrentValueTable.set(mission.id, "SAT-001", "POWER", "voltage", 28.5)
      :ok = CurrentValueTable.set(mission.id, "SAT-002", "POWER", "voltage", 27.8)
      :ok = CurrentValueTable.set(mission.id, "SAT-001", "THERMAL", "temp", 22.0)

      telemetry = CurrentValueTable.get_packet_telemetry(mission.id, "POWER")

      assert length(telemetry) == 2

      assert Enum.all?(telemetry, fn {{_target, packet, _item}, _} ->
               packet == "POWER"
             end)
    end

    test "clears all telemetry for a target", %{mission: mission} do
      :ok = CurrentValueTable.set(mission.id, "SAT-001", "POWER", "voltage", 28.5)
      :ok = CurrentValueTable.set(mission.id, "SAT-001", "THERMAL", "temp", 22.0)
      :ok = CurrentValueTable.set(mission.id, "SAT-002", "POWER", "voltage", 27.8)

      :ok = CurrentValueTable.clear_target(mission.id, "SAT-001")

      # SAT-001 telemetry should be gone
      assert {:error, :not_found} =
               CurrentValueTable.get(mission.id, "SAT-001", "POWER", "voltage")

      assert {:error, :not_found} =
               CurrentValueTable.get(mission.id, "SAT-001", "THERMAL", "temp")

      # SAT-002 telemetry should still exist
      {:ok, _} = CurrentValueTable.get(mission.id, "SAT-002", "POWER", "voltage")
    end

    test "returns CVT statistics", %{mission: mission} do
      :ok = CurrentValueTable.set(mission.id, "SAT-001", "POWER", "voltage", 28.5)
      :ok = CurrentValueTable.set(mission.id, "SAT-001", "POWER", "current", 5.2)

      stats = CurrentValueTable.stats(mission.id)

      assert stats.total_entries == 2
      assert is_integer(stats.memory_words)
      assert is_integer(stats.memory_bytes)
    end
  end
end
