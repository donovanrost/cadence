defmodule Cadence.Procedures.V2Test do
  use Cadence.DataCase, async: true

  alias Cadence.Procedures.StepSignoff
  alias Cadence.Procedures.V2

  import Cadence.OrganizationsFixtures
  import Cadence.AccountsFixtures
  import Cadence.ProceduresFixtures

  describe "sections" do
    setup do
      procedure = procedure_fixture()
      version = Cadence.Procedures.get_version!(procedure.current_version_id)
      %{version: version, procedure: procedure}
    end

    test "create_section/2 creates a section", %{version: version} do
      {:ok, section} =
        V2.create_section(version.id, %{
          name: "Pre-Flight Checks",
          description: "Verify all systems before launch",
          position: 0
        })

      assert section.name == "Pre-Flight Checks"
      assert section.description == "Verify all systems before launch"
      assert section.position == 0
      assert section.procedure_version_id == version.id
    end

    test "list_sections/1 returns sections in order", %{version: version} do
      {:ok, _} = V2.create_section(version.id, %{name: "Section B", position: 1})
      {:ok, _} = V2.create_section(version.id, %{name: "Section A", position: 0})
      {:ok, _} = V2.create_section(version.id, %{name: "Section C", position: 2})

      sections = V2.list_sections(version.id)
      assert length(sections) == 3
      assert Enum.map(sections, & &1.name) == ["Section A", "Section B", "Section C"]
    end

    test "update_section/2 updates a section", %{version: version} do
      {:ok, section} = V2.create_section(version.id, %{name: "Original", position: 0})
      {:ok, updated} = V2.update_section(section, %{name: "Updated"})

      assert updated.name == "Updated"
    end

    test "delete_section/1 removes section", %{version: version} do
      {:ok, section} = V2.create_section(version.id, %{name: "To Delete", position: 0})
      {:ok, _} = V2.delete_section(section)

      assert V2.get_section(section.id) == nil
    end

    test "reorder_sections/2 updates positions", %{version: version} do
      {:ok, s1} = V2.create_section(version.id, %{name: "First", position: 0})
      {:ok, s2} = V2.create_section(version.id, %{name: "Second", position: 1})
      {:ok, s3} = V2.create_section(version.id, %{name: "Third", position: 2})

      # Reorder: Third, First, Second
      {:ok, _} = V2.reorder_sections(version.id, [s3.id, s1.id, s2.id])

      sections = V2.list_sections(version.id)
      assert Enum.map(sections, & &1.name) == ["Third", "First", "Second"]
    end
  end

  describe "steps" do
    setup do
      procedure = procedure_fixture()
      version = Cadence.Procedures.get_version!(procedure.current_version_id)
      {:ok, section} = V2.create_section(version.id, %{name: "Test Section", position: 0})
      %{section: section, version: version}
    end

    test "create_step/2 creates a step", %{section: section} do
      {:ok, step} =
        V2.create_step(section.id, %{
          name: "check_power",
          title: "Verify Power Systems",
          position: 0,
          requires_signoff: true,
          required_roles: ["operator", "lead"],
          signoff_logic: :any
        })

      assert step.name == "check_power"
      assert step.title == "Verify Power Systems"
      assert step.requires_signoff == true
      assert step.required_roles == ["operator", "lead"]
      assert step.signoff_logic == :any
    end

    test "list_steps/1 returns steps in order", %{section: section} do
      {:ok, _} = V2.create_step(section.id, %{name: "step_b", position: 1})
      {:ok, _} = V2.create_step(section.id, %{name: "step_a", position: 0})

      steps = V2.list_steps(section.id)
      assert length(steps) == 2
      assert Enum.map(steps, & &1.name) == ["step_a", "step_b"]
    end

    test "get_step_with_blocks!/1 preloads blocks", %{section: section} do
      {:ok, step} = V2.create_step(section.id, %{name: "test_step", position: 0})

      {:ok, _block} =
        V2.create_block(step.id, %{
          block_type: :text,
          position: 0,
          content: %{"markdown" => "Hello"}
        })

      loaded = V2.get_step_with_blocks!(step.id)
      assert length(loaded.blocks) == 1
    end

    test "move_step/3 moves step to different section", %{section: section, version: version} do
      {:ok, section2} = V2.create_section(version.id, %{name: "Section 2", position: 1})
      {:ok, step} = V2.create_step(section.id, %{name: "movable_step", position: 0})

      {:ok, moved} = V2.move_step(step, section2.id, 0)
      assert moved.section_id == section2.id
    end
  end

  describe "blocks" do
    setup do
      procedure = procedure_fixture()
      version = Cadence.Procedures.get_version!(procedure.current_version_id)
      {:ok, section} = V2.create_section(version.id, %{name: "Test Section", position: 0})
      {:ok, step} = V2.create_step(section.id, %{name: "test_step", position: 0})
      %{step: step}
    end

    test "create_block/2 creates text block", %{step: step} do
      {:ok, block} =
        V2.create_block(step.id, %{
          block_type: :text,
          position: 0,
          content: %{"markdown" => "## Instructions\n\nFollow these steps carefully."}
        })

      assert block.block_type == :text
      assert block.content["markdown"] =~ "Instructions"
    end

    test "create_block/2 creates input block", %{step: step} do
      {:ok, block} =
        V2.create_block(step.id, %{
          block_type: :number_input,
          name: "voltage_reading",
          label: "Measured Voltage (V)",
          position: 0,
          required: true,
          content: %{"min" => 20.0, "max" => 30.0, "unit" => "V"}
        })

      assert block.block_type == :number_input
      assert block.name == "voltage_reading"
      assert block.label == "Measured Voltage (V)"
      assert block.required == true
    end

    test "create_block/2 creates telemetry_check block", %{step: step} do
      {:ok, block} =
        V2.create_block(step.id, %{
          block_type: :telemetry_check,
          name: "power_check",
          position: 0,
          content: %{
            "item" => "SC-001.EPS.voltage",
            "pass_criteria" => "Voltage must be above 24V"
          }
        })

      assert block.block_type == :telemetry_check
      assert block.content["item"] == "SC-001.EPS.voltage"
    end

    test "list_blocks/1 returns blocks in order", %{step: step} do
      {:ok, _} =
        V2.create_block(step.id, %{block_type: :text, position: 1, content: %{"markdown" => "B"}})

      {:ok, _} =
        V2.create_block(step.id, %{block_type: :text, position: 0, content: %{"markdown" => "A"}})

      blocks = V2.list_blocks(step.id)
      assert length(blocks) == 2
      assert Enum.at(blocks, 0).content["markdown"] == "A"
      assert Enum.at(blocks, 1).content["markdown"] == "B"
    end

    test "reorder_blocks/2 updates positions", %{step: step} do
      {:ok, b1} =
        V2.create_block(step.id, %{
          block_type: :text,
          position: 0,
          content: %{"markdown" => "First"}
        })

      {:ok, b2} =
        V2.create_block(step.id, %{
          block_type: :text,
          position: 1,
          content: %{"markdown" => "Second"}
        })

      {:ok, _} = V2.reorder_blocks(step.id, [b2.id, b1.id])

      blocks = V2.list_blocks(step.id)
      assert Enum.at(blocks, 0).content["markdown"] == "Second"
      assert Enum.at(blocks, 1).content["markdown"] == "First"
    end
  end

  describe "comments" do
    setup do
      procedure = procedure_fixture()
      version = Cadence.Procedures.get_version!(procedure.current_version_id)
      user = user_fixture()
      execution = execution_fixture(procedure: procedure, user: user)
      %{execution: execution, user: user, version: version}
    end

    test "create_comment/1 creates execution comment", %{execution: execution, user: user} do
      {:ok, comment} =
        V2.create_comment(%{
          procedure_execution_id: execution.id,
          user_id: user.id,
          content: "Noticed unusual telemetry readings",
          comment_type: :note
        })

      assert comment.content == "Noticed unusual telemetry readings"
      assert comment.comment_type == :note
      assert comment.user_id == user.id
    end

    test "reply_to_comment/2 creates threaded reply", %{execution: execution, user: user} do
      {:ok, parent} =
        V2.create_comment(%{
          procedure_execution_id: execution.id,
          user_id: user.id,
          content: "Question about step 3"
        })

      {:ok, reply} =
        V2.reply_to_comment(parent, %{
          user_id: user.id,
          content: "Answered your question"
        })

      assert reply.parent_comment_id == parent.id
      assert reply.procedure_execution_id == execution.id
    end

    test "list_comments/2 returns comments for execution", %{execution: execution, user: user} do
      {:ok, _} =
        V2.create_comment(%{
          procedure_execution_id: execution.id,
          user_id: user.id,
          content: "Comment 1"
        })

      {:ok, _} =
        V2.create_comment(%{
          procedure_execution_id: execution.id,
          user_id: user.id,
          content: "Comment 2"
        })

      comments = V2.list_comments(execution.id)
      assert length(comments) == 2
    end
  end

  describe "suggested edits (redlines)" do
    setup do
      procedure = procedure_fixture()
      version = Cadence.Procedures.get_version!(procedure.current_version_id)
      user = user_fixture()
      execution = execution_fixture(procedure: procedure, user: user)
      {:ok, section} = V2.create_section(version.id, %{name: "Test", position: 0})
      {:ok, step} = V2.create_step(section.id, %{name: "test_step", position: 0})
      %{execution: execution, user: user, step: step}
    end

    test "create_suggested_edit/1 creates a redline", %{
      execution: execution,
      user: user,
      step: step
    } do
      {:ok, edit} =
        V2.create_suggested_edit(%{
          procedure_execution_id: execution.id,
          target_step_id: step.id,
          suggested_by_id: user.id,
          edit_type: :modify_step,
          reason: "Need to add voltage verification",
          before_snapshot: %{"name" => step.name},
          after_snapshot: %{"name" => step.name, "verification" => "Check voltage > 24V"}
        })

      assert edit.edit_type == :modify_step
      assert edit.status == :pending
      assert edit.reason == "Need to add voltage verification"
    end

    test "accept_suggested_edit/3 accepts and records resolution", %{
      execution: execution,
      user: user,
      step: step
    } do
      reviewer = user_fixture()

      {:ok, edit} =
        V2.create_suggested_edit(%{
          procedure_execution_id: execution.id,
          target_step_id: step.id,
          suggested_by_id: user.id,
          edit_type: :modify_step,
          reason: "Add safety check",
          before_snapshot: %{"name" => step.name},
          after_snapshot: %{"name" => step.name, "safety" => true}
        })

      {:ok, accepted} = V2.accept_suggested_edit(edit, reviewer.id, "Good suggestion")

      assert accepted.status == :accepted
      assert accepted.resolved_by_id == reviewer.id
      assert accepted.resolution_note == "Good suggestion"
      assert accepted.resolved_at != nil
    end

    test "reject_suggested_edit/3 rejects with reason", %{
      execution: execution,
      user: user,
      step: step
    } do
      reviewer = user_fixture()

      {:ok, edit} =
        V2.create_suggested_edit(%{
          procedure_execution_id: execution.id,
          target_step_id: step.id,
          suggested_by_id: user.id,
          edit_type: :add_step,
          reason: "Add new step",
          after_snapshot: %{"name" => "new_step", "title" => "New Step"}
        })

      {:ok, rejected} =
        V2.reject_suggested_edit(edit, reviewer.id, "Not applicable to this procedure")

      assert rejected.status == :rejected
      assert rejected.resolution_note == "Not applicable to this procedure"
    end

    test "list_suggested_edits/2 filters by status", %{
      execution: execution,
      user: user,
      step: step
    } do
      reviewer = user_fixture()

      {:ok, pending} =
        V2.create_suggested_edit(%{
          procedure_execution_id: execution.id,
          target_step_id: step.id,
          suggested_by_id: user.id,
          edit_type: :modify_step,
          reason: "Pending edit",
          before_snapshot: %{"name" => step.name},
          after_snapshot: %{"name" => step.name, "modified" => true}
        })

      {:ok, accepted} =
        V2.create_suggested_edit(%{
          procedure_execution_id: execution.id,
          target_step_id: step.id,
          suggested_by_id: user.id,
          edit_type: :modify_step,
          reason: "Accepted edit",
          before_snapshot: %{"name" => step.name},
          after_snapshot: %{"name" => step.name, "accepted" => true}
        })

      V2.accept_suggested_edit(accepted, reviewer.id)

      pending_edits = V2.list_suggested_edits(execution.id, status: :pending)
      assert length(pending_edits) == 1
      assert hd(pending_edits).id == pending.id

      accepted_edits = V2.list_suggested_edits(execution.id, status: :accepted)
      assert length(accepted_edits) == 1
    end
  end

  describe "snippets" do
    setup do
      org = organization_fixture()
      user = user_fixture()
      %{org: org, user: user}
    end

    test "create_snippet/1 creates step snippet", %{org: org, user: user} do
      {:ok, snippet} =
        V2.create_snippet(%{
          organization_id: org.id,
          created_by_id: user.id,
          name: "Power Verification",
          description: "Standard power system check",
          snippet_type: :step,
          tags: ["power", "verification"],
          content: %{
            "name" => "power_check",
            "title" => "Verify Power Systems",
            "requires_signoff" => true,
            "blocks" => [
              %{"block_type" => "telemetry_check", "content" => %{"condition" => "voltage > 24"}}
            ]
          }
        })

      assert snippet.name == "Power Verification"
      assert snippet.snippet_type == :step
      assert "power" in snippet.tags
    end

    test "list_snippets/2 filters by type", %{org: org, user: user} do
      {:ok, _step} =
        V2.create_snippet(%{
          organization_id: org.id,
          created_by_id: user.id,
          name: "Step Snippet",
          snippet_type: :step,
          content: %{"name" => "test", "blocks" => []}
        })

      {:ok, _section} =
        V2.create_snippet(%{
          organization_id: org.id,
          created_by_id: user.id,
          name: "Section Snippet",
          snippet_type: :section,
          content: %{"name" => "Test Section", "steps" => []}
        })

      step_snippets = V2.list_snippets(org.id, type: :step)
      assert length(step_snippets) == 1
      assert hd(step_snippets).name == "Step Snippet"
    end

    test "list_snippets/2 filters by tags", %{org: org, user: user} do
      {:ok, _} =
        V2.create_snippet(%{
          organization_id: org.id,
          created_by_id: user.id,
          name: "Safety Check",
          snippet_type: :step,
          tags: ["safety", "critical"],
          content: %{"name" => "safety", "blocks" => []}
        })

      {:ok, _} =
        V2.create_snippet(%{
          organization_id: org.id,
          created_by_id: user.id,
          name: "Power Check",
          snippet_type: :step,
          tags: ["power"],
          content: %{"name" => "power", "blocks" => []}
        })

      safety_snippets = V2.list_snippets(org.id, tags: ["safety"])
      assert length(safety_snippets) == 1
      assert hd(safety_snippets).name == "Safety Check"
    end

    test "create_snippet_from_step/4 extracts step as snippet", %{org: org, user: user} do
      procedure = procedure_fixture(organization: org)
      version = Cadence.Procedures.get_version!(procedure.current_version_id)
      {:ok, section} = V2.create_section(version.id, %{name: "Test", position: 0})

      {:ok, step} =
        V2.create_step(section.id, %{
          name: "power_check",
          title: "Check Power",
          position: 0,
          requires_signoff: true,
          required_roles: ["operator"]
        })

      {:ok, _block} =
        V2.create_block(step.id, %{
          block_type: :telemetry_check,
          position: 0,
          name: "voltage_check",
          content: %{"item" => "SC-001.EPS.voltage", "pass_criteria" => "Voltage > 24V"}
        })

      {:ok, snippet} =
        V2.create_snippet_from_step(step, org.id, user.id, %{
          name: "Power Check Template",
          description: "Reusable power check step"
        })

      assert snippet.name == "Power Check Template"
      assert snippet.snippet_type == :step
      assert snippet.content["name"] == "power_check"
      assert snippet.content["required_roles"] == ["operator"]
      assert length(snippet.content["blocks"]) == 1
    end
  end

  describe "signoffs" do
    setup do
      procedure = procedure_fixture()
      version = Cadence.Procedures.get_version!(procedure.current_version_id)
      user = user_fixture()
      {:ok, section} = V2.create_section(version.id, %{name: "Test", position: 0})

      {:ok, step} =
        V2.create_step(section.id, %{
          name: "critical_step",
          position: 0,
          requires_signoff: true,
          required_roles: ["operator", "lead"],
          signoff_logic: :all
        })

      %{step: step, user: user}
    end

    test "StepSignoff.requirements_met?/3 checks all roles for :all logic", %{step: step} do
      signoffs = [
        %StepSignoff{role: "operator"},
        %StepSignoff{role: "lead"}
      ]

      assert StepSignoff.requirements_met?(signoffs, step.required_roles, :all) == true

      partial_signoffs = [%StepSignoff{role: "operator"}]
      assert StepSignoff.requirements_met?(partial_signoffs, step.required_roles, :all) == false
    end

    test "StepSignoff.requirements_met?/3 checks any role for :any logic", %{step: step} do
      signoffs = [%StepSignoff{role: "operator"}]

      assert StepSignoff.requirements_met?(signoffs, step.required_roles, :any) == true
    end

    test "StepSignoff.missing_roles/3 returns unfulfilled roles", %{step: step} do
      signoffs = [%StepSignoff{role: "operator"}]

      missing = StepSignoff.missing_roles(signoffs, step.required_roles, :all)
      assert missing == ["lead"]
    end
  end

  describe "version conversion" do
    test "convert_v1_to_v2/1 creates sections and steps from DAG source" do
      source = %{
        "steps" => %{
          "check_power" => %{
            "type" => "check",
            "condition" => "voltage > 24",
            "description" => "Verify voltage",
            "depends_on" => []
          },
          "send_command" => %{
            "type" => "command",
            "name" => "ENABLE_HEATER",
            "arguments" => %{"zone" => 1},
            "depends_on" => ["check_power"]
          }
        }
      }

      procedure = procedure_fixture(source: source)
      version = Cadence.Procedures.get_version!(procedure.current_version_id)

      {:ok, section} = V2.convert_v1_to_v2(version)

      assert section.name == "Main"

      steps = V2.list_steps(section.id)
      assert length(steps) == 2

      step_names = Enum.map(steps, & &1.name)
      assert "check_power" in step_names
      assert "send_command" in step_names
    end
  end
end
