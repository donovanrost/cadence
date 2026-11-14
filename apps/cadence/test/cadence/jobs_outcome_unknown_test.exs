defmodule Cadence.JobsOutcomeUnknownTest do
  @moduledoc """
  api-ops 11-14 (director): a job whose real outcome was lost reads as outcome_unknown, and
  nothing retries it: not the runner, not Retry or Requeue.
  """
  use Cadence.RuntimeCase, async: false

  import Ecto.Query

  alias Cadence.Jobs
  alias Cadence.Jobs.BackgroundJobRow
  alias Cadence.Jobs.Runner, as: JobRunner

  test "an outcome_unknown job reads back, isn't run, retried or requeued" do
    {:ok, job} = Jobs.enqueue(:catalog_import_run, "mission-outcome-unknown", "lost", %{})

    # What the one-off relabel writes for a row whose outcome was overwritten.
    {1, _rows} =
      Repo.update_all(from(row in BackgroundJobRow, where: row.job_id == ^job.job_id),
        set: [
          status: "outcome_unknown",
          failure_reason: %{"value" => %{"reason" => "outcome_unknown"}}
        ]
      )

    assert {:ok, %{status: :outcome_unknown} = unknown} = Cadence.fetch_background_job(job.job_id)
    assert unknown.failure_reason == %{"reason" => "outcome_unknown"}

    runner = JobRunner.new(%{catalog_import_run: fn _run_id -> flunk("must not run") end})

    assert {:error, {:job_not_running, :outcome_unknown}} =
             JobRunner.run_job(runner, job.job_id)

    assert {:error, {:job_not_failed, :outcome_unknown}} = Jobs.retry_failed_job(job.job_id)
    assert {:error, {:job_not_running, :outcome_unknown}} = Jobs.requeue_running_job(job.job_id)
    assert [] = Jobs.claim_jobs(5) |> Enum.filter(&(&1.job_id == job.job_id))
    assert {:ok, ^unknown} = Cadence.fetch_background_job(job.job_id)
  end
end
