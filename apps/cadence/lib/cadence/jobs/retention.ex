defmodule Cadence.Jobs.Retention do
  @moduledoc """
  Retention for terminal `background_jobs` (#973). Completed and failed jobs remain for
  `Cadence.Persistence.Retention.background_job_days/1` after completion; queued and running
  jobs, and unknown outcomes awaiting an operator decision, are never swept.

  Each chunk takes the oldest expired rows through the partial completion-time index, locks
  only those rows, and deletes them in the sweeper's short transaction.
  """

  @behaviour Cadence.Persistence.Retention.Rule

  alias Cadence.Persistence.Retention
  alias Cadence.Repo

  @impl true
  def name, do: :background_jobs

  @impl true
  def enabled?(_settings), do: true

  @impl true
  def initial_cursor, do: nil

  @impl true
  def sweep_chunk(_cursor, %DateTime{} = now, settings) do
    cutoff =
      now |> Retention.cutoff(Retention.background_job_days(settings)) |> DateTime.to_naive()

    limit = Keyword.fetch!(settings, :chunk_rows)

    %{num_rows: deleted} =
      Repo.query!(
        """
        WITH doomed AS (
          SELECT job_id FROM background_jobs
          WHERE status IN ('completed', 'failed') AND completed_at < $1
          ORDER BY completed_at, job_id
          LIMIT $2
          FOR UPDATE SKIP LOCKED
        )
        DELETE FROM background_jobs j USING doomed d WHERE j.job_id = d.job_id
        """,
        [cutoff, limit]
      )

    {if(deleted < limit, do: :done, else: :more), deleted, nil, fn -> :ok end}
  end
end
