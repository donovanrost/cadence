defmodule Cadence.Repo.Migrations.IndexTerminalBackgroundJobsForRetention do
  use Ecto.Migration

  def change do
    create(
      index(:background_jobs, [:completed_at, :job_id],
        where: "status IN ('completed', 'failed')",
        name: :background_jobs_terminal_completed_at_idx
      )
    )
  end
end
