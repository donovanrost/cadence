defmodule Cadence.Repo.Migrations.IndexTerminalBackgroundJobsForRetention do
  use Ecto.Migration

  def change do
    # Match Cadence.Jobs.Retention's terminal statuses and its #976 workflow exemption.
    create(
      index(:background_jobs, [:completed_at, :job_id],
        where:
          "status IN ('completed', 'failed') AND job_type NOT IN ('telemetry_historical_data_workflow')",
        name: :background_jobs_terminal_completed_at_idx
      )
    )
  end
end
