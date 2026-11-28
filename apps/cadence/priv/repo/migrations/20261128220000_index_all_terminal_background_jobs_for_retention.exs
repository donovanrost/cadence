defmodule Cadence.Repo.Migrations.IndexAllTerminalBackgroundJobsForRetention do
  use Ecto.Migration

  @disable_ddl_transaction true
  @disable_migration_lock true

  # #702 retired historical telemetry workflows, so Cadence.Jobs.Retention no longer exempts their
  # jobs (#976). The partial index follows the sweep's predicate: every completed or failed job.
  def up do
    drop_if_exists(
      index(:background_jobs, [:completed_at, :job_id],
        name: :background_jobs_terminal_completed_at_idx,
        concurrently: true
      )
    )

    create(
      index(:background_jobs, [:completed_at, :job_id],
        where: "status IN ('completed', 'failed')",
        name: :background_jobs_terminal_completed_at_idx,
        concurrently: true
      )
    )
  end

  def down do
    drop_if_exists(
      index(:background_jobs, [:completed_at, :job_id],
        name: :background_jobs_terminal_completed_at_idx,
        concurrently: true
      )
    )

    create(
      index(:background_jobs, [:completed_at, :job_id],
        where:
          "status IN ('completed', 'failed') AND job_type NOT IN ('telemetry_historical_data_workflow')",
        name: :background_jobs_terminal_completed_at_idx,
        concurrently: true
      )
    )
  end
end
