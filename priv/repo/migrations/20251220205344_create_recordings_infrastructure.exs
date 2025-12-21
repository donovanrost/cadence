defmodule Cadence.Repo.Migrations.CreateRecordingsInfrastructure do
  @moduledoc """
  Creates the complete recordings infrastructure following the 37signals Recordables pattern.

  This migration creates:
  - buckets: Polymorphic containers (shifts, missions, anomalies) with access control
  - shifts: Operator shift management
  - bucket_memberships: User access and command authority within buckets
  - recordings: Pure index table linking events to aggregates and buckets
  - All recordable tables: One per event type (command_dispatcheds, alarm_triggereds, etc.)
  """

  use Ecto.Migration

  def change do
    # ============================================
    # BUCKETS - Polymorphic containers
    # ============================================

    create table(:buckets, primary_key: false) do
      add :id, :binary_id, primary_key: true

      add :organization_id,
          references(:organizations, type: :binary_id, on_delete: :delete_all),
          null: false

      add :mission_id, references(:missions, type: :binary_id, on_delete: :delete_all)

      # Tree structure
      add :parent_id, references(:buckets, type: :binary_id, on_delete: :nilify_all)
      add :path, :string

      # Bucket type and polymorphic reference
      add :bucket_type, :string, null: false
      add :bucketable_type, :string, null: false
      add :bucketable_id, :binary_id, null: false

      add :name, :string
      add :started_at, :utc_datetime_usec
      add :ended_at, :utc_datetime_usec
      add :metadata, :map, default: %{}

      timestamps(type: :utc_datetime_usec)
    end

    create unique_index(:buckets, [:bucketable_type, :bucketable_id])
    create index(:buckets, [:mission_id, :bucket_type])
    create index(:buckets, [:organization_id, :bucket_type])
    create index(:buckets, [:path])
    create index(:buckets, [:parent_id])

    # ============================================
    # SHIFTS - Operator shift management
    # ============================================

    create table(:shifts, primary_key: false) do
      add :id, :binary_id, primary_key: true

      add :organization_id,
          references(:organizations, type: :binary_id, on_delete: :delete_all),
          null: false

      add :mission_id, references(:missions, type: :binary_id, on_delete: :delete_all), null: false

      add :name, :string
      add :shift_type, :string

      add :scheduled_start, :utc_datetime_usec, null: false
      add :scheduled_end, :utc_datetime_usec, null: false
      add :actual_start, :utc_datetime_usec
      add :actual_end, :utc_datetime_usec

      add :status, :string, default: "scheduled"
      add :metadata, :map, default: %{}

      timestamps(type: :utc_datetime_usec)
    end

    create index(:shifts, [:mission_id, :scheduled_start])
    create index(:shifts, [:mission_id, :status])

    # ============================================
    # BUCKET MEMBERSHIPS - Access control
    # ============================================

    create table(:bucket_memberships, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :bucket_id, references(:buckets, type: :binary_id, on_delete: :delete_all), null: false
      add :user_id, references(:users, type: :binary_id, on_delete: :delete_all), null: false

      add :role, :string, null: false

      # Command authority scoping
      add :can_command, :boolean, default: false
      add :max_hazard_level, :integer

      add :started_at, :utc_datetime_usec
      add :ended_at, :utc_datetime_usec

      timestamps(type: :utc_datetime_usec)
    end

    create unique_index(:bucket_memberships, [:bucket_id, :user_id],
             where: "ended_at IS NULL",
             name: :bucket_memberships_active_unique
           )

    create index(:bucket_memberships, [:user_id, :bucket_id])

    # ============================================
    # RECORDINGS - Pure index table
    # ============================================

    create table(:recordings, primary_key: false) do
      add :id, :binary_id, primary_key: true

      # Multi-tenancy
      add :organization_id,
          references(:organizations, type: :binary_id, on_delete: :delete_all),
          null: false

      add :bucket_id, references(:buckets, type: :binary_id, on_delete: :nilify_all)

      # Aggregate reference (the entity this event is about)
      add :aggregate_type, :string, null: false
      add :aggregate_id, :binary_id, null: false

      # Recordable reference (the event details)
      add :recordable_type, :string, null: false
      add :recordable_id, :binary_id, null: false

      # Hierarchy (causality chain)
      add :parent_id, references(:recordings, type: :binary_id, on_delete: :nilify_all)
      add :root_id, :binary_id

      # Actor
      add :actor_id, references(:users, type: :binary_id, on_delete: :nilify_all)
      add :actor_type, :string, default: "user"

      # Timestamp (when the event occurred)
      add :timestamp, :utc_datetime_usec, null: false

      timestamps(type: :utc_datetime_usec, updated_at: false)
    end

    # Primary query patterns
    create index(:recordings, [:bucket_id, :timestamp])
    create index(:recordings, [:aggregate_type, :aggregate_id, :timestamp])
    create unique_index(:recordings, [:recordable_type, :recordable_id])
    create index(:recordings, [:parent_id])
    create index(:recordings, [:root_id, :timestamp])

    # ============================================
    # COMMAND RECORDABLES
    # ============================================

    # Command dispatched (rich - has all command details)
    create table(:command_dispatcheds, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :command_name, :string, null: false
      add :opcode, :integer
      add :parameters, :map, default: %{}
      add :encoded_binary, :binary
      add :meta_command_id, :binary_id
      add :is_hazardous, :boolean, default: false
      timestamps(type: :utc_datetime_usec, updated_at: false)
    end

    # Command sent to interface (minimal - just marks transmission)
    create table(:command_sents, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :interface_id, :binary_id
      timestamps(type: :utc_datetime_usec, updated_at: false)
    end

    # Command verified (medium - verification result)
    create table(:command_verifieds, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :verification_item, :string
      add :verification_expected, :string
      add :verification_actual, :string
      add :verification_result, :map
      add :stages_completed, {:array, :string}, default: []
      timestamps(type: :utc_datetime_usec, updated_at: false)
    end

    # Command verification failed
    create table(:command_verification_faileds, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :error_reason, :string
      add :verification_actual, :string
      add :verification_expected, :string
      timestamps(type: :utc_datetime_usec, updated_at: false)
    end

    # Command rejected (validation/authorization failure)
    create table(:command_rejecteds, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :error_reason, :string
      add :rejection_type, :string
      timestamps(type: :utc_datetime_usec, updated_at: false)
    end

    # Command errored (transmission/encoding failure)
    create table(:command_erroreds, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :error_reason, :string
      add :error_type, :string
      timestamps(type: :utc_datetime_usec, updated_at: false)
    end

    # ============================================
    # ALARM RECORDABLES
    # ============================================

    # Alarm triggered (rich - full alarm context)
    create table(:alarm_triggereds, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :alarm_type, :string, null: false
      add :severity, :string, null: false
      add :source_type, :string, null: false
      add :source_id, :string, null: false
      add :message, :text
      add :trigger_value, :float
      add :limit_state, :string
      add :alarm_rule_id, :binary_id
      timestamps(type: :utc_datetime_usec, updated_at: false)
    end

    # Alarm acknowledged (minimal - just user and note)
    create table(:alarm_acknowledgeds, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :note, :text
      timestamps(type: :utc_datetime_usec, updated_at: false)
    end

    # Alarm cleared
    create table(:alarm_cleareds, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :clear_type, :string
      add :final_value, :float
      timestamps(type: :utc_datetime_usec, updated_at: false)
    end

    # Alarm shelved
    create table(:alarm_shelveds, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :shelve_until, :utc_datetime_usec
      add :reason, :text
      timestamps(type: :utc_datetime_usec, updated_at: false)
    end

    # Alarm unshelved
    create table(:alarm_unshelveds, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :unshelve_type, :string
      timestamps(type: :utc_datetime_usec, updated_at: false)
    end

    # Alarm escalated
    create table(:alarm_escalateds, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :previous_severity, :string
      add :new_severity, :string
      add :trigger_value, :float
      timestamps(type: :utc_datetime_usec, updated_at: false)
    end

    # Alarm value updated (while still in violation)
    create table(:alarm_value_updateds, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :trigger_value, :float
      add :previous_value, :float
      timestamps(type: :utc_datetime_usec, updated_at: false)
    end

    # ============================================
    # PROCEDURE RECORDABLES
    # ============================================

    # Procedure started (rich - full execution context)
    create table(:procedure_starteds, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :procedure_id, :binary_id, null: false
      add :procedure_version_id, :binary_id, null: false
      add :parameters, :map, default: %{}
      add :triggered_by, :string
      add :trigger_context, :map
      timestamps(type: :utc_datetime_usec, updated_at: false)
    end

    # Procedure step completed
    create table(:procedure_step_completeds, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :step_id, :string
      add :step_index, :integer
      add :result, :map
      timestamps(type: :utc_datetime_usec, updated_at: false)
    end

    # Procedure step skipped
    create table(:procedure_step_skippeds, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :step_id, :string
      add :step_index, :integer
      add :reason, :string
      timestamps(type: :utc_datetime_usec, updated_at: false)
    end

    # Procedure paused
    create table(:procedure_pauseds, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :checkpoint_state, :binary
      add :current_step_index, :integer
      timestamps(type: :utc_datetime_usec, updated_at: false)
    end

    # Procedure resumed
    create table(:procedure_resumeds, primary_key: false) do
      add :id, :binary_id, primary_key: true
      timestamps(type: :utc_datetime_usec, updated_at: false)
    end

    # Procedure completed
    create table(:procedure_completeds, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :completed_steps, {:array, :string}, default: []
      add :skipped_steps, {:array, :string}, default: []
      add :step_results, :map, default: %{}
      timestamps(type: :utc_datetime_usec, updated_at: false)
    end

    # Procedure failed
    create table(:procedure_faileds, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :error_message, :text
      add :error_step_index, :integer
      add :failed_steps, {:array, :string}, default: []
      timestamps(type: :utc_datetime_usec, updated_at: false)
    end

    # Procedure cancelled
    create table(:procedure_cancelleds, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :reason, :string
      timestamps(type: :utc_datetime_usec, updated_at: false)
    end

    # ============================================
    # PROCEDURE VERSION RECORDABLES (Approval Workflow)
    # ============================================

    # Procedure version created (initial draft)
    create table(:procedure_version_createds, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :procedure_id, :binary_id, null: false
      add :version_number, :integer
      add :source_code, :text
      timestamps(type: :utc_datetime_usec, updated_at: false)
    end

    # Procedure version submitted for review
    create table(:procedure_version_submitteds, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :note, :text
      timestamps(type: :utc_datetime_usec, updated_at: false)
    end

    # Procedure version withdrawn from review
    create table(:procedure_version_withdrawns, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :reason, :text
      timestamps(type: :utc_datetime_usec, updated_at: false)
    end

    # Approval added to procedure version
    create table(:procedure_approval_addeds, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :decision, :string, null: false
      add :comment, :text
      timestamps(type: :utc_datetime_usec, updated_at: false)
    end

    # Procedure version approved (met approval threshold)
    create table(:procedure_version_approveds, primary_key: false) do
      add :id, :binary_id, primary_key: true
      timestamps(type: :utc_datetime_usec, updated_at: false)
    end

    # Procedure version rejected
    create table(:procedure_version_rejecteds, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :reason, :text
      timestamps(type: :utc_datetime_usec, updated_at: false)
    end

    # Procedure version deprecated
    create table(:procedure_version_deprecateds, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :reason, :text
      add :replacement_version_id, :binary_id
      timestamps(type: :utc_datetime_usec, updated_at: false)
    end

    # ============================================
    # AUTOMATION RECORDABLES
    # ============================================

    # Automation triggered
    create table(:automation_triggereds, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :automation_id, :binary_id, null: false
      add :trigger_event, :map
      add :trigger_type, :string
      timestamps(type: :utc_datetime_usec, updated_at: false)
    end

    # Automation completed successfully
    create table(:automation_completeds, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :action_result, :map
      timestamps(type: :utc_datetime_usec, updated_at: false)
    end

    # Automation failed
    create table(:automation_faileds, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :error_message, :text
      timestamps(type: :utc_datetime_usec, updated_at: false)
    end

    # Automation skipped (condition not met)
    create table(:automation_skippeds, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :reason, :string
      timestamps(type: :utc_datetime_usec, updated_at: false)
    end

    # ============================================
    # QUEUE RECORDABLES
    # ============================================

    # Command queued
    create table(:command_queueds, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :command_name, :string, null: false
      add :parameters, :map, default: %{}
      add :priority, :integer, default: 3
      add :scheduled_at, :utc_datetime_usec
      add :expires_at, :utc_datetime_usec
      add :max_attempts, :integer, default: 3
      add :dispatch_opts, :map, default: %{}
      timestamps(type: :utc_datetime_usec, updated_at: false)
    end

    # Command dequeued (executed, cancelled, or expired)
    create table(:command_dequeueds, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :reason, :string
      add :command_aggregate_id, :binary_id
      add :attempts, :integer
      add :last_error, :string
      timestamps(type: :utc_datetime_usec, updated_at: false)
    end

    # ============================================
    # OUTBOX EVENTS - Add recording_id reference
    # ============================================

    alter table(:outbox_events) do
      add :recording_id, references(:recordings, type: :binary_id, on_delete: :nilify_all)
    end

    create index(:outbox_events, [:recording_id])

    # ============================================
    # ADD BUCKET REFERENCE TO TARGETS
    # ============================================

    alter table(:targets) do
      add :bucket_id, references(:buckets, type: :binary_id, on_delete: :nilify_all)
    end

    create index(:targets, [:bucket_id])
  end
end
