defmodule Cadence.Procedures.Engine.ExecutionCoordinatorTest do
  use Cadence.IntegrationCase

  alias Cadence.Procedures.Engine.ExecutionCoordinator
  alias Cadence.Repo
  alias Ecto.Adapters.SQL.Sandbox

  import Cadence.OrganizationsFixtures
  import Cadence.MissionsFixtures
  import Cadence.ProceduresFixtures

  # Note: Full execution integration tests would need special handling for
  # async database access. These tests focus on coordinator logic.

  setup do
    # Allow spawned processes to use the test database connection
    Sandbox.mode(Repo, {:shared, self()})
    on_exit(fn -> Cadence.ProceduresHelpers.stop_execution_processes() end)
    :ok
  end

  describe "start_link/1" do
    test "starts the coordinator for a mission" do
      org = organization_fixture()
      mission = mission_fixture(organization: org)

      {:ok, pid} =
        ExecutionCoordinator.start_link(
          mission_id: mission.id,
          organization_id: org.id
        )

      assert Process.alive?(pid)

      GenServer.stop(pid)
    end

    test "registers in the MissionRegistry" do
      org = organization_fixture()
      mission = mission_fixture(organization: org)

      {:ok, pid} =
        ExecutionCoordinator.start_link(
          mission_id: mission.id,
          organization_id: org.id
        )

      assert ExecutionCoordinator.whereis(mission.id) == pid

      GenServer.stop(pid)
    end
  end

  describe "start_execution/3" do
    setup do
      org = organization_fixture()
      mission = mission_fixture(organization: org)
      procedure = procedure_fixture(organization: org, mission: mission)

      {:ok, pid} =
        ExecutionCoordinator.start_link(
          mission_id: mission.id,
          organization_id: org.id
        )

      on_exit(fn ->
        if Process.alive?(pid), do: GenServer.stop(pid)
      end)

      %{org: org, mission: mission, procedure: procedure}
    end

    test "returns error for non-existent procedure", %{mission: mission} do
      {:error, :procedure_not_found} =
        ExecutionCoordinator.start_execution(mission.id, Ecto.UUID.generate())
    end

    test "enforces concurrency limit", %{mission: mission, procedure: procedure, org: org} do
      # Stop existing coordinator
      GenServer.stop(ExecutionCoordinator.whereis(mission.id))

      # Start with max_concurrent = 1
      {:ok, _pid} =
        ExecutionCoordinator.start_link(
          mission_id: mission.id,
          organization_id: org.id,
          max_concurrent: 1
        )

      # First execution should succeed
      {:ok, _execution1} = ExecutionCoordinator.start_execution(mission.id, procedure.id)

      # Give it a moment to register
      Process.sleep(50)

      # Second should fail
      {:error, :at_concurrency_limit} =
        ExecutionCoordinator.start_execution(mission.id, procedure.id)
    end

    test "creates execution record", %{mission: mission, procedure: procedure} do
      {:ok, execution} = ExecutionCoordinator.start_execution(mission.id, procedure.id)

      assert execution.procedure_id == procedure.id
      assert execution.mission_id == mission.id
      assert execution.status in [:pending, :running]
    end

    test "accepts parameters", %{mission: mission, procedure: procedure} do
      params = %{"key" => "value", "number" => 42}

      {:ok, execution} =
        ExecutionCoordinator.start_execution(mission.id, procedure.id, parameters: params)

      assert execution.parameters == params
    end

    test "accepts user_id for audit", %{mission: mission, procedure: procedure} do
      user = Cadence.AccountsFixtures.user_fixture()

      {:ok, execution} =
        ExecutionCoordinator.start_execution(mission.id, procedure.id, user_id: user.id)

      assert execution.triggered_by_user_id == user.id
    end
  end

  describe "list_active/1" do
    setup do
      org = organization_fixture()
      mission = mission_fixture(organization: org)
      procedure = procedure_fixture(organization: org, mission: mission)

      {:ok, pid} =
        ExecutionCoordinator.start_link(
          mission_id: mission.id,
          organization_id: org.id
        )

      on_exit(fn ->
        if Process.alive?(pid), do: GenServer.stop(pid)
      end)

      %{org: org, mission: mission, procedure: procedure}
    end

    test "returns empty list when no executions", %{mission: mission} do
      assert ExecutionCoordinator.list_active(mission.id) == []
    end

    test "returns active executions", %{mission: mission, procedure: procedure} do
      {:ok, execution} = ExecutionCoordinator.start_execution(mission.id, procedure.id)

      # Wait for registration
      Process.sleep(50)

      active = ExecutionCoordinator.list_active(mission.id)
      assert length(active) == 1
      assert hd(active).id == execution.id
    end
  end

  describe "get_counts/1" do
    setup do
      org = organization_fixture()
      mission = mission_fixture(organization: org)

      {:ok, pid} =
        ExecutionCoordinator.start_link(
          mission_id: mission.id,
          organization_id: org.id
        )

      on_exit(fn ->
        if Process.alive?(pid), do: GenServer.stop(pid)
      end)

      %{org: org, mission: mission}
    end

    test "returns zero counts when no executions", %{mission: mission} do
      counts = ExecutionCoordinator.get_counts(mission.id)

      assert counts.running == 0
      assert counts.paused == 0
      assert counts.pending == 0
    end
  end

  describe "control operations" do
    setup do
      org = organization_fixture()
      mission = mission_fixture(organization: org)

      {:ok, pid} =
        ExecutionCoordinator.start_link(
          mission_id: mission.id,
          organization_id: org.id
        )

      on_exit(fn ->
        if Process.alive?(pid), do: GenServer.stop(pid)
      end)

      %{org: org, mission: mission}
    end

    test "returns error for non-existent execution", %{mission: mission} do
      {:error, :not_found} =
        ExecutionCoordinator.pause(mission.id, Ecto.UUID.generate())
    end
  end

  describe "whereis/1" do
    test "returns nil for non-existent mission" do
      assert ExecutionCoordinator.whereis(Ecto.UUID.generate()) == nil
    end
  end
end
