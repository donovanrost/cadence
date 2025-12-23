defmodule Cadence.Application.Procedures.ApprovalWorkflow do
  @moduledoc """
  Use case module for procedure version approval workflow.

  Manages the lifecycle of procedure versions through the approval process:
  draft → submitted → approved/rejected

  ## Workflow

  1. Author creates a version in `:draft` status
  2. Author submits for review (`:submitted`)
  3. Reviewers can approve or reject
  4. Approved versions can be executed
  5. When a new version is approved, old versions are deprecated

  ## Usage

      # Submit for review
      {:ok, version} = ApprovalWorkflow.submit(version_id, user_id)

      # Add approval
      {:ok, version} = ApprovalWorkflow.approve(version_id, user_id, "LGTM")

      # Or reject
      {:ok, version} = ApprovalWorkflow.reject(version_id, user_id, "Needs more detail")

      # Withdraw submission
      {:ok, version} = ApprovalWorkflow.withdraw(version_id)
  """

  alias Cadence.Application.Procedures.ProcedureQueries
  alias Cadence.Domain.Procedures.Entities.ProcedureVersion
  alias Cadence.Ports.Messaging.EventPublisher
  alias Cadence.Ports.Recordings.EventRecorder

  @type version_id :: String.t()
  @type user_id :: String.t()

  # Get configured repository
  defp repo do
    Application.get_env(
      :cadence,
      :procedure_repository,
      Cadence.Adapters.Persistence.Ecto.Procedures.EctoProcedureRepository
    )
  end

  # Get configured event recorder
  defp recorder do
    EventRecorder.impl()
  end

  @doc """
  Submits a version for review.

  Transitions from `:draft` to `:submitted` status.

  ## Parameters

  - `version_id` - UUID of the version to submit
  - `user_id` - UUID of the user submitting

  ## Returns

  - `{:ok, version}` - Successfully submitted
  - `{:error, :not_found}` - Version not found
  - `{:error, {:invalid_transition, from, to}}` - Not in draft status
  """
  @spec submit(version_id(), user_id()) :: {:ok, ProcedureVersion.t()} | {:error, term()}
  def submit(version_id, _user_id) do
    with {:ok, version} <- ProcedureQueries.find_version(version_id),
         {:ok, updated} <- ProcedureVersion.submit(version),
         {:ok, saved} <- repo().save_version(updated) do
      broadcast_status_change(saved, :submitted)
      {:ok, saved}
    end
  end

  @doc """
  Adds an approval to a submitted version.

  If enough approvals are collected (based on `required_approvals`),
  the version automatically transitions to `:approved` status.

  ## Parameters

  - `version_id` - UUID of the version to approve
  - `user_id` - UUID of the approving user
  - `comment` - Optional approval comment

  ## Returns

  - `{:ok, version}` - Approval added (may be approved if threshold reached)
  - `{:error, :not_found}` - Version not found
  - `{:error, :already_approved}` - User already approved this version
  - `{:error, {:cannot_approve, status}}` - Not in submitted status
  """
  @spec approve(version_id(), user_id(), String.t() | nil) ::
          {:ok, ProcedureVersion.t()} | {:error, term()}
  def approve(version_id, user_id, comment \\ nil) do
    with {:ok, version} <- ProcedureQueries.find_version(version_id),
         {:ok, updated} <- ProcedureVersion.add_approval(version, user_id, comment),
         {:ok, saved} <- repo().save_version(updated) do
      if saved.status == :approved do
        # Deprecate other approved versions
        deprecate_other_versions(saved)
        broadcast_status_change(saved, :approved)
      else
        broadcast_approval_added(saved, user_id)
      end

      {:ok, saved}
    end
  end

  @doc """
  Force-approves a version immediately.

  Bypasses the approval count requirement. Use when an authorized
  approver can approve regardless of required_approvals setting.

  ## Parameters

  - `version_id` - UUID of the version to approve
  - `user_id` - UUID of the approving user

  ## Returns

  - `{:ok, version}` - Successfully approved
  - `{:error, :not_found}` - Version not found
  - `{:error, {:invalid_transition, from, to}}` - Not in submitted status
  """
  @spec force_approve(version_id(), user_id()) ::
          {:ok, ProcedureVersion.t()} | {:error, term()}
  def force_approve(version_id, _user_id) do
    with {:ok, version} <- ProcedureQueries.find_version(version_id),
         {:ok, updated} <- ProcedureVersion.approve(version),
         {:ok, saved} <- repo().save_version(updated) do
      deprecate_other_versions(saved)
      broadcast_status_change(saved, :approved)
      {:ok, saved}
    end
  end

  @doc """
  Rejects a submitted version.

  Records the rejection reason and returns to draft-like state
  (in the domain model, transitions to `:rejected`).

  ## Parameters

  - `version_id` - UUID of the version to reject
  - `user_id` - UUID of the rejecting user
  - `reason` - Reason for rejection

  ## Returns

  - `{:ok, version}` - Successfully rejected
  - `{:error, :not_found}` - Version not found
  - `{:error, {:invalid_transition, from, to}}` - Not in submitted status
  """
  @spec reject(version_id(), user_id(), String.t() | nil) ::
          {:ok, ProcedureVersion.t()} | {:error, term()}
  def reject(version_id, user_id, reason \\ nil) do
    with {:ok, version} <- ProcedureQueries.find_version(version_id),
         {:ok, updated} <- ProcedureVersion.reject(version, user_id, reason),
         {:ok, saved} <- repo().save_version(updated) do
      broadcast_status_change(saved, :rejected)
      {:ok, saved}
    end
  end

  @doc """
  Withdraws a submitted version.

  Author can withdraw their submission to make further edits.

  ## Parameters

  - `version_id` - UUID of the version to withdraw

  ## Returns

  - `{:ok, version}` - Successfully withdrawn
  - `{:error, :not_found}` - Version not found
  - `{:error, {:invalid_transition, from, to}}` - Not in submitted status
  """
  @spec withdraw(version_id()) :: {:ok, ProcedureVersion.t()} | {:error, term()}
  def withdraw(version_id) do
    with {:ok, version} <- ProcedureQueries.find_version(version_id),
         {:ok, updated} <- ProcedureVersion.withdraw(version),
         {:ok, saved} <- repo().save_version(updated) do
      broadcast_status_change(saved, :withdrawn)
      {:ok, saved}
    end
  end

  @doc """
  Deprecates an approved version.

  Used when a newer version is approved or when a version
  should no longer be used.

  ## Parameters

  - `version_id` - UUID of the version to deprecate

  ## Returns

  - `{:ok, version}` - Successfully deprecated
  - `{:error, :not_found}` - Version not found
  - `{:error, {:invalid_transition, from, to}}` - Not in approved status
  """
  @spec deprecate(version_id()) :: {:ok, ProcedureVersion.t()} | {:error, term()}
  def deprecate(version_id) do
    with {:ok, version} <- ProcedureQueries.find_version(version_id),
         {:ok, updated} <- ProcedureVersion.deprecate(version),
         {:ok, saved} <- repo().save_version(updated) do
      broadcast_status_change(saved, :deprecated)
      {:ok, saved}
    end
  end

  @doc """
  Gets the number of approvals still needed.

  ## Returns

  - `{:ok, count}` - Number of approvals needed
  - `{:error, :not_found}` - Version not found
  """
  @spec approvals_needed(version_id()) :: {:ok, non_neg_integer()} | {:error, :not_found}
  def approvals_needed(version_id) do
    case ProcedureQueries.find_version(version_id) do
      {:ok, version} -> {:ok, ProcedureVersion.approvals_needed(version)}
      error -> error
    end
  end

  # ===========================================================================
  # Private Helpers
  # ===========================================================================

  defp deprecate_other_versions(%ProcedureVersion{procedure_id: procedure_id, id: except_id}) do
    repo().deprecate_other_versions(procedure_id, except_id)
  end

  defp event_publisher, do: EventPublisher.impl()

  defp broadcast_status_change(%ProcedureVersion{procedure_id: procedure_id} = version, event) do
    event_publisher().publish(
      "procedure:#{procedure_id}:versions",
      {:version_status_changed, event, version}
    )

    # Record the event
    record_status_change(version, event)
  rescue
    _ -> :ok
  end

  defp broadcast_approval_added(%ProcedureVersion{procedure_id: procedure_id} = version, user_id) do
    event_publisher().publish(
      "procedure:#{procedure_id}:versions",
      {:approval_added, version, user_id}
    )

    # Record the approval event
    recorder().record(:procedure_approval_added, version, user_id, %{})
  rescue
    _ -> :ok
  end

  defp record_status_change(version, :submitted) do
    recorder().record(:procedure_version_submitted, version, version.author_id, %{})
  end

  defp record_status_change(version, :approved) do
    recorder().record(:procedure_version_approved, version, nil, %{})
  end

  defp record_status_change(version, :rejected) do
    recorder().record(:procedure_version_rejected, version, version.rejected_by_id, %{})
  end

  defp record_status_change(version, :withdrawn) do
    recorder().record(:procedure_version_withdrawn, version, version.author_id, %{})
  end

  defp record_status_change(version, :deprecated) do
    recorder().record(:procedure_version_deprecated, version, nil, %{})
  end

  defp record_status_change(_version, _event), do: :ok
end
