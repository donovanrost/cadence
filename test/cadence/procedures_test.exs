defmodule Cadence.ProceduresTest do
  use Cadence.DataCase, async: true

  alias Cadence.Procedures

  import Cadence.OrganizationsFixtures
  import Cadence.MissionsFixtures
  import Cadence.AccountsFixtures
  import Cadence.ProceduresFixtures

  describe "procedures" do
    test "list_procedures/2 returns procedures for organization" do
      org = organization_fixture()
      mission = mission_fixture(organization: org)
      procedure = procedure_fixture(organization: org, mission: mission)

      procedures = Procedures.list_procedures(org.id)
      assert length(procedures) == 1
      assert hd(procedures).id == procedure.id
    end

    test "list_procedures/2 filters by mission" do
      org = organization_fixture()
      mission1 = mission_fixture(organization: org)
      mission2 = mission_fixture(organization: org)

      proc1 = procedure_fixture(organization: org, mission: mission1)
      _proc2 = procedure_fixture(organization: org, mission: mission2)

      procedures = Procedures.list_procedures(org.id, mission_id: mission1.id)
      assert length(procedures) == 1
      assert hd(procedures).id == proc1.id
    end

    test "get_procedure/1 returns procedure" do
      procedure = procedure_fixture()
      assert Procedures.get_procedure(procedure.id).id == procedure.id
    end

    test "get_procedure_by_name/3 finds procedure" do
      org = organization_fixture()
      mission = mission_fixture(organization: org)
      procedure = procedure_fixture(organization: org, mission: mission, name: "MyProcedure")

      found = Procedures.get_procedure_by_name(org.id, mission.id, "MyProcedure")
      assert found.id == procedure.id
    end

    test "create_procedure/2 creates procedure with initial version" do
      org = organization_fixture()
      mission = mission_fixture(organization: org)
      user = user_fixture()

      {:ok, procedure} =
        Procedures.create_procedure(
          %{
            organization_id: org.id,
            mission_id: mission.id,
            name: "New Procedure",
            type: :dag
          },
          user_id: user.id,
          source: %{"steps" => %{}}
        )

      assert procedure.name == "New Procedure"
      assert procedure.current_version_id != nil

      version = Procedures.get_version!(procedure.current_version_id)
      assert version.version_number == 1
      assert version.status == :draft
      assert version.created_by_id == user.id
    end

    test "create_procedure/2 persists source steps" do
      org = organization_fixture()
      mission = mission_fixture(organization: org)
      user = user_fixture()

      steps = %{
        "step_1" => %{"type" => "log", "message" => "Hello", "depends_on" => []},
        "step_2" => %{"type" => "wait", "duration" => 1000, "depends_on" => ["step_1"]},
        "step_3" => %{
          "type" => "command",
          "name" => "TEST_CMD",
          "args" => %{"value" => 42},
          "depends_on" => ["step_2"]
        }
      }

      {:ok, procedure} =
        Procedures.create_procedure(
          %{
            organization_id: org.id,
            mission_id: mission.id,
            name: "Steps Test",
            type: :dag
          },
          user_id: user.id,
          source: %{"steps" => steps}
        )

      version = Procedures.get_version!(procedure.current_version_id)
      assert version.source == %{"steps" => steps}
      assert map_size(version.source["steps"]) == 3
      assert version.source["steps"]["step_1"]["type"] == "log"
    end

    test "update_procedure/2 updates procedure metadata" do
      procedure = procedure_fixture()
      {:ok, updated} = Procedures.update_procedure(procedure, %{description: "Updated"})
      assert updated.description == "Updated"
    end

    test "delete_procedure/1 deletes procedure" do
      procedure = procedure_fixture()
      {:ok, _} = Procedures.delete_procedure(procedure)
      assert Procedures.get_procedure(procedure.id) == nil
    end
  end

  describe "versions" do
    test "list_versions/1 returns versions for procedure" do
      procedure = procedure_fixture()
      versions = Procedures.list_versions(procedure.id)
      assert length(versions) == 1
    end

    test "create_version/3 creates new version" do
      procedure = procedure_fixture()
      user = user_fixture()

      {:ok, version} =
        Procedures.create_version(
          procedure.id,
          %{source: %{"steps" => [%{"type" => "log", "message" => "v2"}]}},
          user_id: user.id
        )

      assert version.version_number == 2
      assert version.status == :draft
    end

    test "approve_version/2 approves version" do
      procedure = procedure_fixture()
      user = user_fixture()
      version = Procedures.get_version!(procedure.current_version_id)

      {:ok, approved} = Procedures.approve_version(version, user.id)

      assert approved.status == :approved
      assert approved.approved_by_id == user.id
      assert approved.approved_at != nil
    end

    test "deprecate_version/1 deprecates version" do
      procedure = approved_procedure_fixture()
      version = Procedures.get_version!(procedure.current_version_id)

      {:ok, deprecated} = Procedures.deprecate_version(version)
      assert deprecated.status == :deprecated
    end

    test "get_approved_version/1 returns latest approved version" do
      procedure = procedure_fixture()
      user = user_fixture()

      # Initially no approved version
      assert Procedures.get_approved_version(procedure.id) == nil

      # Approve version 1
      v1 = Procedures.get_version!(procedure.current_version_id)
      {:ok, _} = Procedures.approve_version(v1, user.id)

      # Create and approve version 2
      {:ok, v2} =
        Procedures.create_version(
          procedure.id,
          %{source: %{"steps" => []}},
          user_id: user.id
        )

      {:ok, approved_v2} = Procedures.approve_version(v2, user.id)

      # Should return version 2
      latest = Procedures.get_approved_version(procedure.id)
      assert latest.id == approved_v2.id
      assert latest.version_number == 2
    end
  end

  describe "executions" do
    test "create_execution/1 creates execution record" do
      procedure = procedure_fixture()
      user = user_fixture()

      {:ok, execution} =
        Procedures.create_execution(%{
          procedure_id: procedure.id,
          procedure_version_id: procedure.current_version_id,
          organization_id: procedure.organization_id,
          mission_id: procedure.mission_id,
          parameters: %{"key" => "value"},
          triggered_by: :manual,
          triggered_by_user_id: user.id
        })

      assert execution.status == :pending
      assert execution.parameters == %{"key" => "value"}
      assert execution.triggered_by == :manual
    end

    test "list_executions/1 returns executions" do
      execution = execution_fixture()
      executions = Procedures.list_executions(organization_id: execution.organization_id)
      assert length(executions) == 1
    end

    test "list_executions/1 filters by status" do
      execution = execution_fixture()

      # Update to running (requires started_at per state machine validation)
      {:ok, _} =
        Procedures.update_execution_status(execution, %{
          status: :running,
          started_at: DateTime.utc_now()
        })

      pending = Procedures.list_executions(status: :pending)
      running = Procedures.list_executions(status: :running)

      assert length(pending) == 0
      assert length(running) == 1
    end

    test "update_execution_status/2 updates status" do
      execution = execution_fixture()

      {:ok, updated} =
        Procedures.update_execution_status(execution, %{
          status: :running,
          started_at: DateTime.utc_now()
        })

      assert updated.status == :running
      assert updated.started_at != nil
    end

    test "update_execution_status/2 validates transitions" do
      execution = execution_fixture()

      # Can't go from pending to completed
      {:error, changeset} =
        Procedures.update_execution_status(execution, %{status: :completed})

      assert errors_on(changeset).status != nil
    end
  end

  describe "logs" do
    test "create_log/1 creates log entry" do
      execution = execution_fixture()

      {:ok, log} =
        Procedures.create_log(%{
          execution_id: execution.id,
          timestamp: DateTime.utc_now(),
          level: :info,
          message: "Test message",
          step_index: 0
        })

      assert log.message == "Test message"
      assert log.level == :info
    end

    test "list_logs/2 returns logs for execution" do
      execution = execution_fixture()

      {:ok, _} =
        Procedures.create_log(%{
          execution_id: execution.id,
          timestamp: DateTime.utc_now(),
          level: :info,
          message: "Log 1"
        })

      {:ok, _} =
        Procedures.create_log(%{
          execution_id: execution.id,
          timestamp: DateTime.utc_now(),
          level: :error,
          message: "Log 2"
        })

      all_logs = Procedures.list_logs(execution.id)
      assert length(all_logs) == 2

      error_logs = Procedures.list_logs(execution.id, level: :error)
      assert length(error_logs) == 1
    end
  end
end
