defmodule Cadence.Repo.Migrations.CreateAutomations do
  use Ecto.Migration

  def change do
    create table(:automations, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :name, :string, null: false
      add :description, :text
      add :enabled, :boolean, default: true, null: false

      # Trigger configuration
      add :trigger_type, :string, null: false
      add :trigger_conditions, :map, default: %{}

      # Action configuration
      add :action_type, :string, null: false
      add :action_config, :map, default: %{}

      # Rate limiting
      add :cooldown_seconds, :integer, default: 0
      add :max_executions_per_hour, :integer

      # Tracking
      add :last_triggered_at, :utc_datetime
      add :trigger_count, :integer, default: 0

      # Relationships
      add :organization_id, references(:organizations, type: :binary_id, on_delete: :delete_all),
        null: false

      add :mission_id, references(:missions, type: :binary_id, on_delete: :delete_all)
      add :target_id, references(:targets, type: :binary_id, on_delete: :delete_all)

      timestamps(type: :utc_datetime)
    end

    create index(:automations, [:organization_id])
    create index(:automations, [:mission_id])
    create index(:automations, [:trigger_type])
    create index(:automations, [:enabled])

    create table(:automation_executions, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :status, :string, null: false, default: "pending"
      add :trigger_event, :map, null: false
      add :action_result, :map
      add :error_message, :text
      add :started_at, :utc_datetime
      add :completed_at, :utc_datetime

      add :automation_id, references(:automations, type: :binary_id, on_delete: :delete_all),
        null: false

      add :organization_id, references(:organizations, type: :binary_id, on_delete: :delete_all),
        null: false

      add :mission_id, references(:missions, type: :binary_id, on_delete: :delete_all)

      add :procedure_execution_id,
          references(:procedure_executions, type: :binary_id, on_delete: :nilify_all)

      timestamps(type: :utc_datetime)
    end

    create index(:automation_executions, [:automation_id])
    create index(:automation_executions, [:organization_id])
    create index(:automation_executions, [:mission_id])
    create index(:automation_executions, [:status])
    create index(:automation_executions, [:inserted_at])
  end
end
