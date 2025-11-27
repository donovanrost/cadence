defmodule Cadence.Repo.Migrations.CreateCommandQueueEntries do
  use Ecto.Migration

  def change do
    create table(:command_queue_entries, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :organization_id, references(:organizations, type: :binary_id, on_delete: :delete_all),
        null: false
      add :mission_id, references(:missions, type: :binary_id, on_delete: :delete_all),
        null: false
      add :target_id, references(:targets, type: :binary_id, on_delete: :delete_all),
        null: false
      add :command_definition_id, references(:command_definitions, type: :binary_id, on_delete: :nilify_all)
      add :user_id, references(:users, type: :binary_id, on_delete: :nilify_all)

      # Command details
      add :command_name, :string, null: false
      add :parameters, :map, default: %{}

      # Queue management
      add :status, :string, null: false, default: "pending"
      add :priority, :integer, null: false, default: 3
      add :sequence_number, :bigint

      # Scheduling
      add :scheduled_at, :utc_datetime_usec
      add :expires_at, :utc_datetime_usec

      # Execution tracking
      add :attempts, :integer, null: false, default: 0
      add :max_attempts, :integer, null: false, default: 3
      add :last_attempt_at, :utc_datetime_usec
      add :last_error, :text

      # Result linking
      add :command_log_id, :binary_id

      # Options passed to dispatch
      add :dispatch_opts, :map, default: %{}

      # Metadata
      add :metadata, :map, default: %{}

      timestamps(type: :utc_datetime_usec)
    end

    # Index for fetching next command to execute (pending, ordered by priority and sequence)
    create index(:command_queue_entries, [:mission_id, :status, :priority, :sequence_number])

    # Index for finding entries by target
    create index(:command_queue_entries, [:target_id, :status])

    # Index for scheduled commands
    create index(:command_queue_entries, [:mission_id, :status, :scheduled_at],
      where: "scheduled_at IS NOT NULL")

    # Index for expiring commands
    create index(:command_queue_entries, [:status, :expires_at],
      where: "expires_at IS NOT NULL")

    # Index for user's queued commands
    create index(:command_queue_entries, [:user_id, :status])

    # Index for linking to command log
    create index(:command_queue_entries, [:command_log_id],
      where: "command_log_id IS NOT NULL")
  end
end
