defmodule Cadence.Repo.Migrations.CreateProceduresV2 do
  @moduledoc """
  Creates the normalized procedures v2 schema with Epsilon3-like block-based steps.

  This migration adds:
  - Sections, Steps, and Blocks (procedure definition)
  - StepExecutions, BlockExecutions, StepSignoffs (execution tracking)
  - ExecutionComments, SuggestedEdits (collaboration)
  - Snippets (reusable content library)
  - DataSourceConfigs (per-mission data source configuration)
  - New recordables for procedure events
  """

  use Ecto.Migration

  def change do
    # ─────────────────────────────────────────────────────────────
    # Procedure Definition Tables
    # ─────────────────────────────────────────────────────────────

    create table(:procedure_sections, primary_key: false) do
      add :id, :binary_id, primary_key: true

      add :procedure_version_id,
          references(:procedure_versions, type: :binary_id, on_delete: :delete_all),
          null: false

      add :name, :string, null: false
      add :description, :text
      add :position, :integer, null: false
      add :collapsed_by_default, :boolean, default: false

      timestamps(type: :utc_datetime)
    end

    create index(:procedure_sections, [:procedure_version_id])
    create index(:procedure_sections, [:procedure_version_id, :position])

    create table(:procedure_steps, primary_key: false) do
      add :id, :binary_id, primary_key: true

      add :section_id, references(:procedure_sections, type: :binary_id, on_delete: :delete_all),
        null: false

      add :name, :string, null: false
      add :title, :string
      add :position, :integer, null: false

      # Signoff requirements
      add :requires_signoff, :boolean, default: true
      add :required_roles, {:array, :string}, default: []
      add :signoff_logic, :string, default: "any"

      # Dependencies
      add :depends_on, {:array, :string}, default: []
      add :dependency_logic, :string, default: "all"

      # Conditional execution
      add :condition, :string
      add :on_fail, :string, default: "abort"

      # Duration estimate (for planning)
      add :estimated_duration_seconds, :integer

      timestamps(type: :utc_datetime)
    end

    create index(:procedure_steps, [:section_id])
    create index(:procedure_steps, [:section_id, :position])

    create unique_index(:procedure_steps, [:section_id, :name],
             name: :procedure_steps_section_id_name_index
           )

    create table(:procedure_blocks, primary_key: false) do
      add :id, :binary_id, primary_key: true

      add :step_id, references(:procedure_steps, type: :binary_id, on_delete: :delete_all),
        null: false

      add :block_type, :string, null: false
      add :position, :integer, null: false
      add :name, :string
      add :label, :string
      add :required, :boolean, default: false
      add :content, :map, default: %{}

      timestamps(type: :utc_datetime)
    end

    create index(:procedure_blocks, [:step_id])
    create index(:procedure_blocks, [:step_id, :position])

    # ─────────────────────────────────────────────────────────────
    # Execution Tracking Tables
    # ─────────────────────────────────────────────────────────────

    create table(:step_executions, primary_key: false) do
      add :id, :binary_id, primary_key: true

      add :procedure_execution_id,
          references(:procedure_executions, type: :binary_id, on_delete: :delete_all),
          null: false

      add :step_id, references(:procedure_steps, type: :binary_id, on_delete: :restrict),
        null: false

      add :status, :string, default: "pending"

      # Timing
      add :started_at, :utc_datetime
      add :completed_at, :utc_datetime

      # Result
      add :result, :string
      add :error_message, :text

      # Skip tracking
      add :skipped_reason, :string
      add :skipped_by_id, references(:users, type: :binary_id, on_delete: :nilify_all)

      timestamps(type: :utc_datetime)
    end

    create index(:step_executions, [:procedure_execution_id])
    create index(:step_executions, [:procedure_execution_id, :status])

    create unique_index(:step_executions, [:procedure_execution_id, :step_id],
             name: :step_executions_execution_step_index
           )

    create table(:block_executions, primary_key: false) do
      add :id, :binary_id, primary_key: true

      add :step_execution_id,
          references(:step_executions, type: :binary_id, on_delete: :delete_all),
          null: false

      add :block_id, references(:procedure_blocks, type: :binary_id, on_delete: :restrict),
        null: false

      add :status, :string, default: "pending"

      # For input blocks: captured value
      add :value, :map

      # For validation blocks: pass/fail
      add :passed, :boolean
      add :validation_message, :string

      # For command blocks: execution result
      add :command_result, :map

      # For telemetry blocks: captured reading
      add :telemetry_reading, :map

      # Timing
      add :started_at, :utc_datetime
      add :completed_at, :utc_datetime

      add :entered_by_id, references(:users, type: :binary_id, on_delete: :nilify_all)

      timestamps(type: :utc_datetime)
    end

    create index(:block_executions, [:step_execution_id])

    create unique_index(:block_executions, [:step_execution_id, :block_id],
             name: :block_executions_step_block_index
           )

    create table(:step_signoffs, primary_key: false) do
      add :id, :binary_id, primary_key: true

      add :step_execution_id,
          references(:step_executions, type: :binary_id, on_delete: :delete_all),
          null: false

      add :user_id, references(:users, type: :binary_id, on_delete: :restrict), null: false
      add :role, :string, null: false
      add :note, :text

      timestamps(type: :utc_datetime, updated_at: false)
    end

    create index(:step_signoffs, [:step_execution_id])

    create unique_index(:step_signoffs, [:step_execution_id, :user_id],
             name: :step_signoffs_execution_user_index
           )

    # ─────────────────────────────────────────────────────────────
    # Collaboration Tables
    # ─────────────────────────────────────────────────────────────

    create table(:execution_comments, primary_key: false) do
      add :id, :binary_id, primary_key: true

      add :procedure_execution_id,
          references(:procedure_executions, type: :binary_id, on_delete: :delete_all),
          null: false

      add :step_execution_id,
          references(:step_executions, type: :binary_id, on_delete: :delete_all)

      add :user_id, references(:users, type: :binary_id, on_delete: :restrict), null: false

      add :parent_comment_id,
          references(:execution_comments, type: :binary_id, on_delete: :delete_all)

      add :content, :text, null: false
      add :comment_type, :string, default: "note"

      timestamps(type: :utc_datetime)
    end

    create index(:execution_comments, [:procedure_execution_id])
    create index(:execution_comments, [:step_execution_id])
    create index(:execution_comments, [:parent_comment_id])

    create table(:suggested_edits, primary_key: false) do
      add :id, :binary_id, primary_key: true

      add :procedure_execution_id,
          references(:procedure_executions, type: :binary_id, on_delete: :delete_all),
          null: false

      add :step_execution_id,
          references(:step_executions, type: :binary_id, on_delete: :delete_all)

      add :suggested_by_id, references(:users, type: :binary_id, on_delete: :restrict),
        null: false

      add :resolved_by_id, references(:users, type: :binary_id, on_delete: :nilify_all)

      add :edit_type, :string, null: false
      add :status, :string, default: "pending"

      # Target location
      add :target_section_id, :binary_id
      add :target_step_id, :binary_id
      add :target_block_id, :binary_id
      add :target_position, :integer

      # The change
      add :before_snapshot, :map
      add :after_snapshot, :map
      add :reason, :text

      # Resolution
      add :resolved_at, :utc_datetime
      add :resolution_note, :text

      timestamps(type: :utc_datetime)
    end

    create index(:suggested_edits, [:procedure_execution_id])
    create index(:suggested_edits, [:procedure_execution_id, :status])

    # ─────────────────────────────────────────────────────────────
    # Snippets (Reusable Content Library)
    # ─────────────────────────────────────────────────────────────

    create table(:procedure_snippets, primary_key: false) do
      add :id, :binary_id, primary_key: true

      add :organization_id, references(:organizations, type: :binary_id, on_delete: :delete_all),
        null: false

      add :created_by_id, references(:users, type: :binary_id, on_delete: :nilify_all),
        null: false

      add :name, :string, null: false
      add :description, :text
      add :snippet_type, :string, null: false
      add :tags, {:array, :string}, default: []
      add :content, :map, null: false

      timestamps(type: :utc_datetime)
    end

    create index(:procedure_snippets, [:organization_id])
    create index(:procedure_snippets, [:organization_id, :snippet_type])

    # ─────────────────────────────────────────────────────────────
    # Data Source Configuration
    # ─────────────────────────────────────────────────────────────

    create table(:procedure_data_source_configs, primary_key: false) do
      add :id, :binary_id, primary_key: true

      add :mission_id, references(:missions, type: :binary_id, on_delete: :delete_all),
        null: false

      add :source_type, :string, null: false
      add :name, :string, null: false
      add :is_default, :boolean, default: false
      add :priority, :integer, default: 0

      # Type-specific configuration
      add :config, :map, default: %{}

      # Item path patterns this source handles
      add :path_patterns, {:array, :string}, default: ["*"]

      timestamps(type: :utc_datetime)
    end

    create index(:procedure_data_source_configs, [:mission_id])
    create index(:procedure_data_source_configs, [:mission_id, :source_type])

    # ─────────────────────────────────────────────────────────────
    # Update existing procedure_versions table
    # ─────────────────────────────────────────────────────────────

    alter table(:procedure_versions) do
      add :execution_mode, :string, default: "manual"
      add :allow_suggested_edits, :boolean, default: true
    end

    # ─────────────────────────────────────────────────────────────
    # Update existing procedure_executions table
    # ─────────────────────────────────────────────────────────────

    alter table(:procedure_executions) do
      add :parent_execution_id,
          references(:procedure_executions, type: :binary_id, on_delete: :nilify_all)
    end

    create index(:procedure_executions, [:parent_execution_id])

    # ─────────────────────────────────────────────────────────────
    # New Recordables for Procedures V2
    # ─────────────────────────────────────────────────────────────

    create table(:step_activateds, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :step_name, :string, null: false
      add :step_title, :string
      add :section_name, :string
      add :step_position, :integer

      timestamps(type: :utc_datetime, updated_at: false)
    end

    create table(:step_signed_offs, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :step_name, :string, null: false
      add :step_title, :string
      add :role, :string, null: false
      add :signoff_count, :integer
      add :signoffs_required, :integer
      add :step_result, :string

      timestamps(type: :utc_datetime, updated_at: false)
    end

    create table(:block_value_entereds, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :step_name, :string, null: false
      add :block_name, :string, null: false
      add :block_type, :string
      add :value_summary, :string
      add :passed_validation, :boolean

      timestamps(type: :utc_datetime, updated_at: false)
    end

    create table(:block_telemetry_checkeds, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :step_name, :string, null: false
      add :block_name, :string
      add :item_path, :string, null: false
      add :value, :string
      add :pass_criteria, :string
      add :passed, :boolean, null: false

      timestamps(type: :utc_datetime, updated_at: false)
    end

    create table(:execution_comment_addeds, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :step_name, :string
      add :comment_type, :string
      add :content_preview, :string

      timestamps(type: :utc_datetime, updated_at: false)
    end

    create table(:suggested_edit_proposeds, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :edit_type, :string, null: false
      add :target_step_name, :string
      add :summary, :string

      timestamps(type: :utc_datetime, updated_at: false)
    end

    create table(:suggested_edit_resolveds, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :edit_type, :string, null: false
      add :resolution, :string, null: false
      add :target_step_name, :string

      timestamps(type: :utc_datetime, updated_at: false)
    end
  end
end
