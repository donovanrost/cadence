defmodule Cadence.Repo.Migrations.CreateReviewWorkflowRecordables do
  @moduledoc """
  Creates recordable tables for the PR-style review workflow.

  These recordables track the complete audit trail of procedure version reviews:
  - Submission with reviewer requests
  - Individual review decisions (approve/request changes)
  - Threaded comments and resolution
  - Resubmission after addressing changes
  - Version closure
  """

  use Ecto.Migration

  def change do
    # ============================================
    # PROCEDURE REVIEW WORKFLOW RECORDABLES
    # ============================================

    # Review submitted (version submitted for review with optional reviewers)
    create table(:procedure_review_submitteds, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :note, :text
      add :reviewer_ids, {:array, :binary_id}, default: []
      timestamps(type: :utc_datetime_usec, updated_at: false)
    end

    # Review requested (specific reviewer requested)
    create table(:procedure_review_requesteds, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :reviewer_id, :binary_id, null: false
      add :message, :text
      timestamps(type: :utc_datetime_usec, updated_at: false)
    end

    # Review approved (reviewer approves the version)
    create table(:procedure_review_approveds, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :body, :text
      timestamps(type: :utc_datetime_usec, updated_at: false)
    end

    # Changes requested (reviewer requests changes, creates blocking review)
    create table(:procedure_changes_requesteds, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :body, :text, null: false
      add :thread_id, :binary_id
      timestamps(type: :utc_datetime_usec, updated_at: false)
    end

    # Comment added to review thread
    create table(:procedure_review_comment_addeds, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :thread_id, :binary_id, null: false
      add :body, :text, null: false
      timestamps(type: :utc_datetime_usec, updated_at: false)
    end

    # Thread resolved
    create table(:procedure_thread_resolveds, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :thread_id, :binary_id, null: false
      timestamps(type: :utc_datetime_usec, updated_at: false)
    end

    # Version resubmitted (after addressing changes)
    create table(:procedure_version_resubmitteds, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :note, :text
      timestamps(type: :utc_datetime_usec, updated_at: false)
    end

    # Version closed (abandoned, like closing a PR without merging)
    create table(:procedure_version_closeds, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :reason, :text
      timestamps(type: :utc_datetime_usec, updated_at: false)
    end
  end
end
