defmodule Cadence.Repo.Migrations.CreateAlarmRules do
  use Ecto.Migration

  def change do
    create table(:alarm_rules, primary_key: false) do
      add :id, :binary_id, primary_key: true

      # Scoping - rules can be org-wide, mission-specific, or target-specific
      add :organization_id, references(:organizations, type: :binary_id, on_delete: :delete_all),
        null: false

      add :mission_id, references(:missions, type: :binary_id, on_delete: :delete_all)
      add :target_id, references(:targets, type: :binary_id, on_delete: :delete_all)

      # Rule identification
      add :name, :string, null: false
      add :description, :text

      # What triggers this rule
      add :event_type, :string, null: false  # "telemetry_limit", "command_failure", etc.
      add :conditions, :map, null: false, default: %{}

      # What alarm to generate
      add :severity, :string, null: false, default: "warning"
      add :message_template, :string

      # Behavior modifiers
      add :auto_acknowledge, :boolean, default: false
      add :auto_shelve_duration_minutes, :integer
      add :cooldown_seconds, :integer

      # Notification routing (array of channel identifiers)
      add :notification_channels, {:array, :string}, default: []

      # Enable/disable with audit trail
      add :enabled, :boolean, default: true, null: false
      add :disabled_at, :utc_datetime
      add :disabled_by_id, references(:users, type: :binary_id, on_delete: :nilify_all)
      add :disabled_reason, :text

      timestamps(type: :utc_datetime)
    end

    create index(:alarm_rules, [:organization_id])
    create index(:alarm_rules, [:mission_id])
    create index(:alarm_rules, [:target_id])
    create index(:alarm_rules, [:event_type])
    create index(:alarm_rules, [:enabled])

    # Composite indexes for rule lookup
    create index(:alarm_rules, [:organization_id, :mission_id, :target_id, :enabled])
    create index(:alarm_rules, [:mission_id, :event_type, :enabled])
  end
end
