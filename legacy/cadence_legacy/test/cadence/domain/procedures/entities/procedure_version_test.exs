defmodule Cadence.Domain.Procedures.Entities.ProcedureVersionTest do
  @moduledoc """
  Pure unit tests for the ProcedureVersion domain entity.

  These tests run without database access, demonstrating that
  the domain logic is independent of persistence.
  """
  use Cadence.PureCase

  alias Cadence.Domain.Procedures.Entities.ProcedureVersion

  # ===========================================================================
  # Test Helpers
  # ===========================================================================

  defp valid_attrs(overrides \\ %{}) do
    Map.merge(
      %{
        id: random_id(),
        procedure_id: random_id(),
        version_number: 1,
        author_id: random_id(),
        steps: %{
          "step_1" => %{"type" => "command", "command" => "POWER_ON"},
          "step_2" => %{"type" => "wait", "duration" => 5}
        }
      },
      overrides
    )
  end

  defp create_version(overrides \\ %{}) do
    {:ok, version} = ProcedureVersion.new(valid_attrs(overrides))
    version
  end

  # ===========================================================================
  # Construction Tests
  # ===========================================================================

  describe "new/1" do
    test "creates a version with valid attributes" do
      attrs = valid_attrs()

      assert {:ok, version} = ProcedureVersion.new(attrs)
      assert version.procedure_id == attrs.procedure_id
      assert version.version_number == 1
      assert version.author_id == attrs.author_id
      assert version.steps == attrs.steps
    end

    test "sets initial status to :draft" do
      {:ok, version} = ProcedureVersion.new(valid_attrs())
      assert version.status == :draft
    end

    test "defaults parameters to empty map" do
      {:ok, version} = ProcedureVersion.new(valid_attrs())
      assert version.parameters == %{}
    end

    test "defaults required_approvals to 1" do
      {:ok, version} = ProcedureVersion.new(valid_attrs())
      assert version.required_approvals == 1
    end

    test "initializes approvals to empty list" do
      {:ok, version} = ProcedureVersion.new(valid_attrs())
      assert version.approvals == []
    end

    test "fails with missing required fields" do
      assert {:error, {:missing_required, missing}} = ProcedureVersion.new(%{})
      assert :procedure_id in missing
      assert :version_number in missing
      assert :author_id in missing
      assert :steps in missing
    end

    test "fails with invalid version number" do
      attrs = valid_attrs(%{version_number: 0})
      assert {:error, :invalid_version_number} = ProcedureVersion.new(attrs)

      attrs = valid_attrs(%{version_number: -1})
      assert {:error, :invalid_version_number} = ProcedureVersion.new(attrs)
    end

    test "fails with empty steps" do
      attrs = valid_attrs(%{steps: %{}})
      assert {:error, :invalid_steps} = ProcedureVersion.new(attrs)
    end

    test "accepts optional fields" do
      attrs =
        valid_attrs(%{
          description: "Initial version",
          change_summary: "Created procedure",
          parameters: %{"target" => "string"},
          required_approvals: 2
        })

      {:ok, version} = ProcedureVersion.new(attrs)
      assert version.description == "Initial version"
      assert version.change_summary == "Created procedure"
      assert version.parameters == %{"target" => "string"}
      assert version.required_approvals == 2
    end
  end

  # ===========================================================================
  # Workflow Transition Tests
  # ===========================================================================

  describe "submit/1" do
    test "transitions from draft to submitted" do
      version = create_version()

      assert {:ok, submitted} = ProcedureVersion.submit(version)
      assert submitted.status == :submitted
      assert submitted.submitted_at != nil
    end

    test "fails when already submitted" do
      version = create_version()
      {:ok, submitted} = ProcedureVersion.submit(version)

      assert {:error, {:invalid_transition, :submitted, :submitted}} =
               ProcedureVersion.submit(submitted)
    end

    test "fails when already approved" do
      version = create_version()
      {:ok, submitted} = ProcedureVersion.submit(version)
      {:ok, approved} = ProcedureVersion.approve(submitted)

      assert {:error, {:invalid_transition, :approved, :submitted}} =
               ProcedureVersion.submit(approved)
    end
  end

  describe "add_approval/3" do
    test "adds approval to submitted version" do
      version = create_version(%{required_approvals: 2})
      {:ok, submitted} = ProcedureVersion.submit(version)
      user_id = random_id()

      assert {:ok, with_approval} = ProcedureVersion.add_approval(submitted, user_id, "LGTM")
      assert length(with_approval.approvals) == 1
      assert hd(with_approval.approvals).user_id == user_id
      assert hd(with_approval.approvals).comment == "LGTM"
      # Still submitted (need 2 approvals)
      assert with_approval.status == :submitted
    end

    test "auto-approves when enough approvals collected" do
      version = create_version(%{required_approvals: 1})
      {:ok, submitted} = ProcedureVersion.submit(version)

      assert {:ok, approved} = ProcedureVersion.add_approval(submitted, random_id())
      assert approved.status == :approved
      assert approved.approved_at != nil
    end

    test "fails if user already approved" do
      version = create_version(%{required_approvals: 2})
      {:ok, submitted} = ProcedureVersion.submit(version)
      user_id = random_id()

      {:ok, with_approval} = ProcedureVersion.add_approval(submitted, user_id)

      assert {:error, :already_approved} =
               ProcedureVersion.add_approval(with_approval, user_id)
    end

    test "fails when not in submitted status" do
      version = create_version()

      assert {:error, {:cannot_approve, :draft}} =
               ProcedureVersion.add_approval(version, random_id())
    end
  end

  describe "approve/1" do
    test "directly approves submitted version" do
      version = create_version()
      {:ok, submitted} = ProcedureVersion.submit(version)

      assert {:ok, approved} = ProcedureVersion.approve(submitted)
      assert approved.status == :approved
      assert approved.approved_at != nil
    end

    test "fails when in draft" do
      version = create_version()

      assert {:error, {:invalid_transition, :draft, :approved}} =
               ProcedureVersion.approve(version)
    end
  end

  describe "reject/3" do
    test "rejects submitted version with reason" do
      version = create_version()
      {:ok, submitted} = ProcedureVersion.submit(version)
      reviewer_id = random_id()

      assert {:ok, rejected} =
               ProcedureVersion.reject(submitted, reviewer_id, "Missing safety checks")

      assert rejected.status == :rejected
      assert rejected.rejected_at != nil
      assert rejected.rejected_by_id == reviewer_id
      assert rejected.rejection_reason == "Missing safety checks"
    end

    test "fails when in draft" do
      version = create_version()

      assert {:error, {:invalid_transition, :draft, :rejected}} =
               ProcedureVersion.reject(version, random_id())
    end
  end

  describe "withdraw/1" do
    test "withdraws submitted version" do
      version = create_version()
      {:ok, submitted} = ProcedureVersion.submit(version)

      assert {:ok, withdrawn} = ProcedureVersion.withdraw(submitted)
      assert withdrawn.status == :withdrawn
    end

    test "fails when in draft" do
      version = create_version()

      assert {:error, {:invalid_transition, :draft, :withdrawn}} =
               ProcedureVersion.withdraw(version)
    end
  end

  describe "deprecate/1" do
    test "deprecates approved version" do
      version = create_version()
      {:ok, submitted} = ProcedureVersion.submit(version)
      {:ok, approved} = ProcedureVersion.approve(submitted)

      assert {:ok, deprecated} = ProcedureVersion.deprecate(approved)
      assert deprecated.status == :deprecated
      assert deprecated.deprecated_at != nil
    end

    test "fails when not approved" do
      version = create_version()

      assert {:error, {:invalid_transition, :draft, :deprecated}} =
               ProcedureVersion.deprecate(version)
    end
  end

  # ===========================================================================
  # Draft Editing Tests
  # ===========================================================================

  describe "update_steps/2" do
    test "updates steps of draft version" do
      version = create_version()

      new_steps = %{
        "step_1" => %{"type" => "wait", "duration" => 10}
      }

      assert {:ok, updated} = ProcedureVersion.update_steps(version, new_steps)
      assert updated.steps == new_steps
    end

    test "fails with empty steps" do
      version = create_version()

      assert {:error, :invalid_steps} = ProcedureVersion.update_steps(version, %{})
    end

    test "fails when not in draft" do
      version = create_version()
      {:ok, submitted} = ProcedureVersion.submit(version)

      assert {:error, {:not_editable, :submitted}} =
               ProcedureVersion.update_steps(submitted, %{"step" => %{}})
    end
  end

  describe "update_parameters/2" do
    test "updates parameters of draft version" do
      version = create_version()

      params = %{"target" => "string", "value" => "number"}

      assert {:ok, updated} = ProcedureVersion.update_parameters(version, params)
      assert updated.parameters == params
    end

    test "fails when not in draft" do
      version = create_version()
      {:ok, submitted} = ProcedureVersion.submit(version)

      assert {:error, {:not_editable, :submitted}} =
               ProcedureVersion.update_parameters(submitted, %{})
    end
  end

  describe "update_description/2" do
    test "updates description of draft version" do
      version = create_version()

      assert {:ok, updated} = ProcedureVersion.update_description(version, "New description")
      assert updated.description == "New description"
    end

    test "fails when not in draft" do
      version = create_version()
      {:ok, submitted} = ProcedureVersion.submit(version)

      assert {:error, {:not_editable, :submitted}} =
               ProcedureVersion.update_description(submitted, "desc")
    end
  end

  # ===========================================================================
  # Query Tests
  # ===========================================================================

  describe "executable?/1" do
    test "returns false for draft" do
      version = create_version()
      assert ProcedureVersion.executable?(version) == false
    end

    test "returns false for submitted" do
      version = create_version()
      {:ok, submitted} = ProcedureVersion.submit(version)
      assert ProcedureVersion.executable?(submitted) == false
    end

    test "returns true for approved" do
      version = create_version()
      {:ok, submitted} = ProcedureVersion.submit(version)
      {:ok, approved} = ProcedureVersion.approve(submitted)
      assert ProcedureVersion.executable?(approved) == true
    end

    test "returns false for rejected" do
      version = create_version()
      {:ok, submitted} = ProcedureVersion.submit(version)
      {:ok, rejected} = ProcedureVersion.reject(submitted, random_id())
      assert ProcedureVersion.executable?(rejected) == false
    end

    test "returns false for deprecated" do
      version = create_version()
      {:ok, submitted} = ProcedureVersion.submit(version)
      {:ok, approved} = ProcedureVersion.approve(submitted)
      {:ok, deprecated} = ProcedureVersion.deprecate(approved)
      assert ProcedureVersion.executable?(deprecated) == false
    end
  end

  describe "editable?/1" do
    test "returns true for draft" do
      version = create_version()
      assert ProcedureVersion.editable?(version) == true
    end

    test "returns false for submitted" do
      version = create_version()
      {:ok, submitted} = ProcedureVersion.submit(version)
      assert ProcedureVersion.editable?(submitted) == false
    end

    test "returns false for approved" do
      version = create_version()
      {:ok, submitted} = ProcedureVersion.submit(version)
      {:ok, approved} = ProcedureVersion.approve(submitted)
      assert ProcedureVersion.editable?(approved) == false
    end
  end

  describe "pending_review?/1" do
    test "returns false for draft" do
      version = create_version()
      assert ProcedureVersion.pending_review?(version) == false
    end

    test "returns true for submitted" do
      version = create_version()
      {:ok, submitted} = ProcedureVersion.submit(version)
      assert ProcedureVersion.pending_review?(submitted) == true
    end

    test "returns false for approved" do
      version = create_version()
      {:ok, submitted} = ProcedureVersion.submit(version)
      {:ok, approved} = ProcedureVersion.approve(submitted)
      assert ProcedureVersion.pending_review?(approved) == false
    end
  end

  describe "approvals_needed/1" do
    test "returns required_approvals when no approvals" do
      version = create_version(%{required_approvals: 3})
      {:ok, submitted} = ProcedureVersion.submit(version)

      assert ProcedureVersion.approvals_needed(submitted) == 3
    end

    test "returns remaining after some approvals" do
      version = create_version(%{required_approvals: 3})
      {:ok, submitted} = ProcedureVersion.submit(version)
      {:ok, with_one} = ProcedureVersion.add_approval(submitted, random_id())

      assert ProcedureVersion.approvals_needed(with_one) == 2
    end

    test "returns 0 when all approvals collected" do
      version = create_version(%{required_approvals: 1})
      {:ok, submitted} = ProcedureVersion.submit(version)
      {:ok, approved} = ProcedureVersion.add_approval(submitted, random_id())

      assert ProcedureVersion.approvals_needed(approved) == 0
    end
  end

  describe "already_approved_by?/2" do
    test "returns false when user has not approved" do
      version = create_version()
      {:ok, submitted} = ProcedureVersion.submit(version)

      assert ProcedureVersion.already_approved_by?(submitted, random_id()) == false
    end

    test "returns true when user has approved" do
      version = create_version(%{required_approvals: 2})
      {:ok, submitted} = ProcedureVersion.submit(version)
      user_id = random_id()
      {:ok, with_approval} = ProcedureVersion.add_approval(submitted, user_id)

      assert ProcedureVersion.already_approved_by?(with_approval, user_id) == true
    end
  end

  describe "authored_by?/2" do
    test "returns true for author" do
      author_id = random_id()
      version = create_version(%{author_id: author_id})

      assert ProcedureVersion.authored_by?(version, author_id) == true
    end

    test "returns false for non-author" do
      version = create_version()

      assert ProcedureVersion.authored_by?(version, random_id()) == false
    end
  end
end
