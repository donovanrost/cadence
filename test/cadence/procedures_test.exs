defmodule Cadence.ProceduresTest do
  use Cadence.DataCase, async: true

  alias Cadence.Procedures
  alias Cadence.Settings

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

  describe "tags" do
    test "list_tags/2 returns unique tags across procedures" do
      org = organization_fixture()
      mission = mission_fixture(organization: org)
      procedure_fixture(organization: org, mission: mission, tags: ["safety", "recovery"])
      procedure_fixture(organization: org, mission: mission, tags: ["safety", "commissioning"])

      tags = Procedures.list_tags(org.id, mission_id: mission.id)
      assert tags == ["commissioning", "recovery", "safety"]
    end

    test "list_tags/2 returns empty list when no tags" do
      org = organization_fixture()
      mission = mission_fixture(organization: org)
      procedure_fixture(organization: org, mission: mission)

      tags = Procedures.list_tags(org.id, mission_id: mission.id)
      assert tags == []
    end

    test "list_procedures/2 filters by tags with AND logic" do
      org = organization_fixture()
      mission = mission_fixture(organization: org)
      p1 = procedure_fixture(organization: org, mission: mission, tags: ["safety", "recovery"])
      p2 = procedure_fixture(organization: org, mission: mission, tags: ["safety"])

      # Filter by single tag
      results = Procedures.list_procedures(org.id, mission_id: mission.id, tags: ["safety"])
      assert length(results) == 2

      # Filter by multiple tags (AND)
      results =
        Procedures.list_procedures(org.id, mission_id: mission.id, tags: ["safety", "recovery"])

      assert length(results) == 1
      assert hd(results).id == p1.id

      # No procedures with non-existent tag
      results = Procedures.list_procedures(org.id, mission_id: mission.id, tags: ["nonexistent"])
      assert results == []

      # Empty tags list returns all
      results = Procedures.list_procedures(org.id, mission_id: mission.id, tags: [])
      assert length(results) == 2

      # Verify p2 excluded from multi-tag query
      results = Procedures.list_procedures(org.id, mission_id: mission.id, tags: ["recovery"])
      assert length(results) == 1
      assert hd(results).id == p1.id
      refute Enum.any?(results, &(&1.id == p2.id))
    end

    test "tags are normalized to lowercase and deduped" do
      org = organization_fixture()
      mission = mission_fixture(organization: org)
      user = user_fixture()

      {:ok, proc} =
        Procedures.create_procedure(
          %{
            organization_id: org.id,
            mission_id: mission.id,
            name: "Tag Test",
            tags: ["safety", "recovery", "safety"]
          },
          user_id: user.id
        )

      # Tags should be deduped
      assert proc.tags == ["safety", "recovery"]
    end

    test "tags are normalized via changeset" do
      # Test normalization via changeset directly
      changeset =
        Procedures.change_procedure(%Cadence.Procedures.Procedure{}, %{
          name: "Tag Test",
          organization_id: Ecto.UUID.generate(),
          tags: ["Safety", "RECOVERY", "safety"]
        })

      assert changeset.valid?
      assert Ecto.Changeset.get_field(changeset, :tags) == ["safety", "recovery"]
    end

    test "invalid tags are rejected" do
      org = organization_fixture()
      mission = mission_fixture(organization: org)

      # Test validation via changeset directly since create_procedure uses insert!
      changeset =
        Procedures.change_procedure(%Cadence.Procedures.Procedure{}, %{
          organization_id: org.id,
          mission_id: mission.id,
          name: "Tag Test",
          tags: ["invalid tag with spaces"]
        })

      refute changeset.valid?
      errors = errors_on(changeset)

      assert "tags must contain only lowercase letters, numbers, and hyphens (max 50 chars)" in errors.tags
    end

    test "tags starting with hyphen are rejected" do
      org = organization_fixture()
      mission = mission_fixture(organization: org)

      # Test validation via changeset directly since create_procedure uses insert!
      changeset =
        Procedures.change_procedure(%Cadence.Procedures.Procedure{}, %{
          organization_id: org.id,
          mission_id: mission.id,
          name: "Tag Test",
          tags: ["-invalid"]
        })

      refute changeset.valid?
      errors = errors_on(changeset)

      assert "tags must contain only lowercase letters, numbers, and hyphens (max 50 chars)" in errors.tags
    end

    test "valid tags with hyphens and numbers are accepted" do
      org = organization_fixture()
      mission = mission_fixture(organization: org)
      user = user_fixture()

      {:ok, proc} =
        Procedures.create_procedure(
          %{
            organization_id: org.id,
            mission_id: mission.id,
            name: "Tag Test",
            tags: ["phase-1", "v2-release", "test123"]
          },
          user_id: user.id
        )

      assert proc.tags == ["phase-1", "v2-release", "test123"]
    end

    test "update_procedure/2 can update tags" do
      procedure = procedure_fixture(tags: ["old-tag"])
      {:ok, updated} = Procedures.update_procedure(procedure, %{tags: ["new-tag", "another"]})
      assert updated.tags == ["new-tag", "another"]
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

  describe "approval workflow" do
    setup do
      org = organization_fixture()
      mission = mission_fixture(organization: org)
      author = user_fixture()
      approver = user_fixture()
      approver2 = user_fixture()
      procedure = procedure_fixture(organization: org, mission: mission, user: author)
      version = Procedures.get_version!(procedure.current_version_id)

      %{
        org: org,
        mission: mission,
        author: author,
        approver: approver,
        approver2: approver2,
        procedure: procedure,
        version: version
      }
    end

    test "submit_for_review transitions draft to in_review", ctx do
      {:ok, version} = Procedures.submit_for_review(ctx.version, ctx.author.id)

      assert version.status == :in_review
      assert version.submitted_at != nil
      assert version.submitted_by_id == ctx.author.id

      events = Procedures.list_version_events(version.id)
      assert length(events) == 1
      assert hd(events).event_type == :submitted
    end

    test "submit_for_review fails if not in draft status", ctx do
      {:ok, version} = Procedures.submit_for_review(ctx.version, ctx.author.id)

      assert {:error, :invalid_status} = Procedures.submit_for_review(version, ctx.author.id)
    end

    test "withdraw_submission returns to draft and clears approvals", ctx do
      {:ok, version} = Procedures.submit_for_review(ctx.version, ctx.author.id)
      {:ok, _} = Procedures.add_approval(version, ctx.approver.id, :approved)

      {:ok, withdrawn} = Procedures.withdraw_submission(version, ctx.author.id)

      assert withdrawn.status == :draft
      assert withdrawn.submitted_at == nil
      assert withdrawn.submitted_by_id == nil
      assert Procedures.list_approvals(version.id) == []

      events = Procedures.list_version_events(version.id)
      assert Enum.any?(events, &(&1.event_type == :withdrawn))
    end

    test "withdraw_submission fails if not author", ctx do
      {:ok, version} = Procedures.submit_for_review(ctx.version, ctx.author.id)

      assert {:error, :not_author} = Procedures.withdraw_submission(version, ctx.approver.id)
    end

    test "withdraw_submission fails if withdrawal disabled", ctx do
      {:ok, _} = Settings.set_org(ctx.org, :procedures, :allow_withdrawal, false)
      {:ok, version} = Procedures.submit_for_review(ctx.version, ctx.author.id)

      assert {:error, :withdrawal_not_allowed} =
               Procedures.withdraw_submission(version, ctx.author.id)
    end

    test "add_approval with required=1 immediately approves", ctx do
      {:ok, _} = Settings.set_org(ctx.org, :procedures, :required_approvals, 1)

      {:ok, version} = Procedures.submit_for_review(ctx.version, ctx.author.id)
      {:ok, %{version: version}} = Procedures.add_approval(version, ctx.approver.id, :approved)

      assert version.status == :approved
      assert version.approved_at != nil
      assert version.approved_by_id == ctx.approver.id
    end

    test "add_approval with required=2 needs two approvals", ctx do
      {:ok, _} = Settings.set_org(ctx.org, :procedures, :required_approvals, 2)

      {:ok, version} = Procedures.submit_for_review(ctx.version, ctx.author.id)
      {:ok, %{version: version}} = Procedures.add_approval(version, ctx.approver.id, :approved)

      # Still in review - need one more approval
      assert version.status == :in_review

      {:ok, %{version: version}} = Procedures.add_approval(version, ctx.approver2.id, :approved)

      assert version.status == :approved
    end

    test "rejection returns version to draft", ctx do
      {:ok, version} = Procedures.submit_for_review(ctx.version, ctx.author.id)

      {:ok, %{version: version}} =
        Procedures.add_approval(version, ctx.approver.id, :rejected, comment: "Needs work")

      assert version.status == :draft
      assert version.rejected_at != nil
      assert version.rejected_by_id == ctx.approver.id
      assert version.rejection_reason == "Needs work"
    end

    test "cannot approve own work when setting is false", ctx do
      {:ok, _} = Settings.set_org(ctx.org, :procedures, :allow_self_approval, false)

      {:ok, version} = Procedures.submit_for_review(ctx.version, ctx.author.id)

      # Version was created by author, so they can't approve
      assert {:error, :cannot_approve_own_work} =
               Procedures.add_approval(version, ctx.author.id, :approved)
    end

    test "can approve own work when setting is true", ctx do
      # Default is true, but let's be explicit
      {:ok, _} = Settings.set_org(ctx.org, :procedures, :allow_self_approval, true)
      {:ok, _} = Settings.set_org(ctx.org, :procedures, :required_approvals, 1)

      {:ok, version} = Procedures.submit_for_review(ctx.version, ctx.author.id)

      {:ok, %{version: version}} = Procedures.add_approval(version, ctx.author.id, :approved)
      assert version.status == :approved
    end

    test "cannot submit decision twice", ctx do
      {:ok, version} = Procedures.submit_for_review(ctx.version, ctx.author.id)
      {:ok, _} = Procedures.add_approval(version, ctx.approver.id, :approved)

      assert {:error, :already_submitted_decision} =
               Procedures.add_approval(version, ctx.approver.id, :approved)
    end

    test "get_approval_status returns correct summary", ctx do
      {:ok, _} = Settings.set_org(ctx.org, :procedures, :required_approvals, 2)

      {:ok, version} = Procedures.submit_for_review(ctx.version, ctx.author.id)
      {:ok, _} = Procedures.add_approval(version, ctx.approver.id, :approved)

      status = Procedures.get_approval_status(version)

      assert status.required == 2
      assert status.approved == 1
      assert status.rejected == 0
      assert status.pending == 1
      assert status.can_be_approved == false
      assert status.is_blocked == false
      assert length(status.approvals) == 1
    end

    test "get_approval_status shows blocked when pending rejection exists", ctx do
      {:ok, _} = Settings.set_org(ctx.org, :procedures, :required_approvals, 2)

      {:ok, version} = Procedures.submit_for_review(ctx.version, ctx.author.id)
      {:ok, _} = Procedures.add_approval(version, ctx.approver.id, :approved)

      {:ok, _} =
        Procedures.add_approval(version, ctx.approver2.id, :rejected, comment: "Needs work")

      # Rejection returns to draft
      version = Procedures.get_version!(ctx.version.id)
      assert version.status == :draft
      assert version.rejection_reason == "Needs work"
    end

    test "list_approvals returns approvals for version", ctx do
      {:ok, version} = Procedures.submit_for_review(ctx.version, ctx.author.id)
      {:ok, _} = Procedures.add_approval(version, ctx.approver.id, :approved, comment: "LGTM")

      approvals = Procedures.list_approvals(version.id)
      assert length(approvals) == 1

      approval = hd(approvals)
      assert approval.decision == :approved
      assert approval.comment == "LGTM"
      assert approval.user.id == ctx.approver.id
    end

    test "list_version_events returns audit trail", ctx do
      {:ok, version} = Procedures.submit_for_review(ctx.version, ctx.author.id)
      {:ok, _} = Procedures.add_approval(version, ctx.approver.id, :approved)

      events = Procedures.list_version_events(version.id)

      assert length(events) >= 2
      event_types = Enum.map(events, & &1.event_type)
      assert :submitted in event_types
      assert :approval_added in event_types
    end

    test "approval updates procedure current_version_id", ctx do
      {:ok, _} = Settings.set_org(ctx.org, :procedures, :required_approvals, 1)

      {:ok, version} = Procedures.submit_for_review(ctx.version, ctx.author.id)
      {:ok, _} = Procedures.add_approval(version, ctx.approver.id, :approved)

      procedure = Procedures.get_procedure!(ctx.procedure.id)
      assert procedure.current_version_id == version.id
    end
  end

  describe "export_procedure/1" do
    test "exports procedure with current version" do
      org = organization_fixture()
      mission = mission_fixture(organization: org)
      user = user_fixture()

      {:ok, procedure} =
        Procedures.create_procedure(
          %{
            organization_id: org.id,
            mission_id: mission.id,
            name: "Export Test",
            description: "A procedure to export",
            type: :dag,
            tags: ["safety", "recovery"]
          },
          user_id: user.id,
          source: %{"steps" => %{"step_1" => %{"type" => "log", "message" => "Hello"}}},
          parameters_schema: %{"param1" => %{"type" => "string"}}
        )

      export = Procedures.export_procedure(procedure)

      assert export["export_version"] == "1.0.0"
      assert export["exported_at"] != nil
      assert export["source_procedure_id"] == procedure.id
      assert export["source_mission_id"] == mission.id
      assert export["procedure"]["name"] == "Export Test"
      assert export["procedure"]["description"] == "A procedure to export"
      assert export["procedure"]["type"] == "dag"
      assert export["procedure"]["tags"] == ["safety", "recovery"]
      assert export["procedure"]["version"]["version_number"] == 1
      assert export["procedure"]["version"]["source"] == %{"steps" => %{"step_1" => %{"type" => "log", "message" => "Hello"}}}
      assert export["procedure"]["version"]["parameters_schema"] == %{"param1" => %{"type" => "string"}}
    end

    test "exports procedure without version when none exists" do
      org = organization_fixture()
      mission = mission_fixture(organization: org)

      # Directly create a procedure without version (simulating edge case)
      {:ok, procedure} =
        Cadence.Repo.insert(%Cadence.Procedures.Procedure{
          organization_id: org.id,
          mission_id: mission.id,
          name: "No Version Procedure",
          type: :dag,
          tags: []
        })

      export = Procedures.export_procedure(procedure)

      assert export["export_version"] == "1.0.0"
      assert export["procedure"]["name"] == "No Version Procedure"
      assert export["procedure"]["version"] == nil
    end

    test "exports approved version data" do
      procedure = approved_procedure_fixture(tags: ["approved-tag"])

      export = Procedures.export_procedure(procedure)

      assert export["procedure"]["tags"] == ["approved-tag"]
      assert export["procedure"]["version"]["version_number"] == 1
    end
  end

  describe "import_procedure/4" do
    test "creates new procedure in draft status" do
      org = organization_fixture()
      mission = mission_fixture(organization: org)
      user = user_fixture()

      export_data = %{
        "export_version" => "1.0.0",
        "exported_at" => "2025-01-15T14:30:00Z",
        "source_procedure_id" => Ecto.UUID.generate(),
        "source_mission_id" => Ecto.UUID.generate(),
        "procedure" => %{
          "name" => "Imported Procedure",
          "description" => "A test import",
          "type" => "dag",
          "tags" => ["imported", "test"],
          "version" => %{
            "version_number" => 3,
            "source" => %{"steps" => %{"step_1" => %{"type" => "log", "message" => "Imported"}}},
            "parameters_schema" => %{"temp" => %{"type" => "number"}},
            "allow_hazardous_commands" => false
          }
        }
      }

      {:ok, procedure} =
        Procedures.import_procedure(org.id, mission.id, export_data, user_id: user.id)

      assert procedure.name == "Imported Procedure"
      assert procedure.description == "A test import"
      assert procedure.type == :dag
      assert procedure.tags == ["imported", "test"]

      version = Procedures.get_version!(procedure.current_version_id)
      assert version.status == :draft
      assert version.version_number == 1
      assert version.source == %{"steps" => %{"step_1" => %{"type" => "log", "message" => "Imported"}}}
      assert version.parameters_schema == %{"temp" => %{"type" => "number"}}
    end

    test "returns error for duplicate name" do
      org = organization_fixture()
      mission = mission_fixture(organization: org)
      user = user_fixture()

      # Create existing procedure
      procedure_fixture(organization: org, mission: mission, name: "Existing Procedure")

      export_data = %{
        "export_version" => "1.0.0",
        "procedure" => %{
          "name" => "Existing Procedure",
          "type" => "dag",
          "version" => %{
            "source" => %{"steps" => %{}},
            "parameters_schema" => %{}
          }
        }
      }

      assert {:error, :name_already_exists} =
               Procedures.import_procedure(org.id, mission.id, export_data, user_id: user.id)
    end

    test "allows name override" do
      org = organization_fixture()
      mission = mission_fixture(organization: org)
      user = user_fixture()

      # Create existing procedure with original name
      procedure_fixture(organization: org, mission: mission, name: "Original Name")

      export_data = %{
        "export_version" => "1.0.0",
        "procedure" => %{
          "name" => "Original Name",
          "type" => "dag",
          "version" => %{
            "source" => %{"steps" => %{}},
            "parameters_schema" => %{}
          }
        }
      }

      {:ok, procedure} =
        Procedures.import_procedure(org.id, mission.id, export_data,
          user_id: user.id,
          name: "Renamed Import"
        )

      assert procedure.name == "Renamed Import"
    end

    test "returns error for invalid export format" do
      org = organization_fixture()
      mission = mission_fixture(organization: org)
      user = user_fixture()

      # Missing export_version
      assert {:error, :invalid_export_format} =
               Procedures.import_procedure(org.id, mission.id, %{"procedure" => %{}},
                 user_id: user.id
               )

      # Wrong export_version
      assert {:error, :invalid_export_format} =
               Procedures.import_procedure(
                 org.id,
                 mission.id,
                 %{"export_version" => "2.0.0", "procedure" => %{"name" => "Test", "type" => "dag"}},
                 user_id: user.id
               )

      # Missing procedure name
      assert {:error, :invalid_export_format} =
               Procedures.import_procedure(
                 org.id,
                 mission.id,
                 %{"export_version" => "1.0.0", "procedure" => %{"type" => "dag"}},
                 user_id: user.id
               )
    end

    test "returns error for missing version data" do
      org = organization_fixture()
      mission = mission_fixture(organization: org)
      user = user_fixture()

      export_data = %{
        "export_version" => "1.0.0",
        "procedure" => %{
          "name" => "No Version",
          "type" => "dag",
          "version" => nil
        }
      }

      assert {:error, :missing_version_data} =
               Procedures.import_procedure(org.id, mission.id, export_data, user_id: user.id)
    end

    test "imports script type procedures" do
      org = organization_fixture()
      mission = mission_fixture(organization: org)
      user = user_fixture()

      export_data = %{
        "export_version" => "1.0.0",
        "procedure" => %{
          "name" => "Script Procedure",
          "type" => "script",
          "tags" => [],
          "version" => %{
            "source" => %{"code" => "cadence.log('Hello')"},
            "parameters_schema" => %{}
          }
        }
      }

      {:ok, procedure} =
        Procedures.import_procedure(org.id, mission.id, export_data, user_id: user.id)

      assert procedure.type == :script

      version = Procedures.get_version!(procedure.current_version_id)
      assert version.source == %{"code" => "cadence.log('Hello')"}
    end

    test "imports allow_hazardous_commands flag" do
      org = organization_fixture()
      mission = mission_fixture(organization: org)
      user = user_fixture()

      export_data = %{
        "export_version" => "1.0.0",
        "procedure" => %{
          "name" => "Hazardous Procedure",
          "type" => "dag",
          "version" => %{
            "source" => %{"steps" => %{}},
            "parameters_schema" => %{},
            "allow_hazardous_commands" => true
          }
        }
      }

      {:ok, procedure} =
        Procedures.import_procedure(org.id, mission.id, export_data, user_id: user.id)

      version = Procedures.get_version!(procedure.current_version_id)
      assert version.allow_hazardous_commands == true
    end
  end
end
