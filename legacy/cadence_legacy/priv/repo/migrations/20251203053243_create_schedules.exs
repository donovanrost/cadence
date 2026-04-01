defmodule Cadence.Repo.Migrations.CreateSchedules do
  use Ecto.Migration

  def change do
    create table(:schedules, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :name, :string, null: false
      add :description, :text
      add :enabled, :boolean, default: true, null: false

      # Schedule type and timing
      add :schedule_type, :string, null: false, default: "cron"
      add :cron_expression, :string
      add :scheduled_at, :utc_datetime
      add :timezone, :string, default: "UTC"

      # Execution configuration
      add :parameters, :map, default: %{}

      # Tracking
      add :last_run_at, :utc_datetime
      add :next_run_at, :utc_datetime
      add :run_count, :integer, default: 0

      # Relationships
      add :procedure_id, references(:procedures, type: :binary_id, on_delete: :delete_all),
        null: false

      add :organization_id, references(:organizations, type: :binary_id, on_delete: :delete_all),
        null: false

      add :mission_id, references(:missions, type: :binary_id, on_delete: :delete_all)
      add :target_id, references(:targets, type: :binary_id, on_delete: :delete_all)

      timestamps(type: :utc_datetime)
    end

    create index(:schedules, [:organization_id])
    create index(:schedules, [:mission_id])
    create index(:schedules, [:procedure_id])
    create index(:schedules, [:enabled])
    create index(:schedules, [:schedule_type])
    create index(:schedules, [:scheduled_at])
  end
end
