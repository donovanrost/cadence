defmodule Cadence.Repo.Migrations.CreateAlarms do
  use Ecto.Migration

  def change do
    create table(:alarms, primary_key: false) do
      add :id, :binary_id, primary_key: true

      # Multi-tenancy scoping
      add :organization_id, references(:organizations, type: :binary_id, on_delete: :delete_all),
        null: false

      add :mission_id, references(:missions, type: :binary_id, on_delete: :delete_all),
        null: false

      add :target_id, references(:targets, type: :binary_id, on_delete: :nilify_all)

      # Which rule generated this alarm (nullable for catch-all or legacy)
      add :alarm_rule_id, references(:alarm_rules, type: :binary_id, on_delete: :nilify_all)

      # Classification
      add :alarm_type, :string, null: false  # "telemetry_limit", "command_failure", etc.
      add :severity, :string, null: false    # "info", "warning", "critical"
      add :status, :string, null: false, default: "active"  # "active", "acknowledged", "cleared", "shelved"

      # Source identification - what triggered this alarm
      add :source_type, :string, null: false  # "telemetry_item", "command", etc.
      add :source_id, :string, null: false    # e.g., "HEALTH.cpu_temp"

      # Current state (for telemetry limit alarms)
      add :limit_state, :string              # "yellow", "red", "blue"
      add :current_value, :float
      add :message, :text

      # Acknowledgment tracking
      add :acknowledged_by_id, references(:users, type: :binary_id, on_delete: :nilify_all)
      add :acknowledged_at, :utc_datetime
      add :acknowledgment_note, :text

      # Shelving
      add :shelved_by_id, references(:users, type: :binary_id, on_delete: :nilify_all)
      add :shelved_at, :utc_datetime
      add :shelved_until, :utc_datetime
      add :shelve_reason, :text

      # Lifecycle timestamps
      add :triggered_at, :utc_datetime_usec, null: false
      add :cleared_at, :utc_datetime_usec
      add :last_value_at, :utc_datetime_usec  # Last time value was updated

      # Metadata for additional context
      add :metadata, :map, default: %{}

      timestamps(type: :utc_datetime)
    end

    create index(:alarms, [:organization_id])
    create index(:alarms, [:mission_id])
    create index(:alarms, [:target_id])
    create index(:alarms, [:alarm_rule_id])
    create index(:alarms, [:alarm_type])
    create index(:alarms, [:severity])
    create index(:alarms, [:status])
    create index(:alarms, [:source_type, :source_id])
    create index(:alarms, [:triggered_at])

    # Composite indexes for common queries
    create index(:alarms, [:mission_id, :status])
    create index(:alarms, [:mission_id, :status, :severity])
    create index(:alarms, [:mission_id, :target_id, :source_id, :status])

    # For finding active alarm for a specific source (deduplication)
    create index(:alarms, [:mission_id, :target_id, :source_type, :source_id],
      where: "status IN ('active', 'acknowledged', 'shelved')",
      name: :alarms_active_source_idx
    )
  end
end
