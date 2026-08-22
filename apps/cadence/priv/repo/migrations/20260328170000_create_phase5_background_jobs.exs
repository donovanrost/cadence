defmodule Cadence.Repo.Migrations.CreatePhase5BackgroundJobs do
  use Ecto.Migration

  def change do
    create table(:background_jobs, primary_key: false) do
      add :job_id, :string, primary_key: true
      add :mission_id, :string, null: false
      add :job_type, :string, null: false
      add :run_id, :string, null: false
      add :status, :string, null: false
      add :payload, :map, null: false, default: %{}
      add :attempt_count, :integer, null: false, default: 0
      add :failure_reason, :map
      add :started_at, :utc_datetime_usec
      add :completed_at, :utc_datetime_usec

      timestamps(type: :utc_datetime_usec, updated_at: false)
    end

    create index(:background_jobs, [:status, :inserted_at])
    create index(:background_jobs, [:mission_id, :inserted_at])
    create unique_index(:background_jobs, [:job_type, :run_id])
  end
end
