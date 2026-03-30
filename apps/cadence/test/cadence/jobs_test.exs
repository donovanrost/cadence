defmodule Cadence.JobsTest do
  use Cadence.DataCase, async: false

  test "requeues running jobs for recovery" do
    assert {:ok, job} =
             Cadence.Jobs.enqueue(
               :replay_telemetry_scope,
               "mission-alpha",
               "replay-run-recovery",
               %{"replay_run_id" => "replay-run-recovery"}
             )

    assert [claimed_job] = Cadence.Jobs.claim_jobs(1)
    assert claimed_job.job_id == job.job_id
    assert claimed_job.status == :running
    assert claimed_job.attempt_count == 1

    assert Cadence.Jobs.requeue_running_jobs() == 1

    assert {:ok, requeued_job} = Cadence.fetch_background_job(job.job_id)
    assert requeued_job.status == :queued
    assert requeued_job.started_at == nil
    assert requeued_job.failure_reason == %{"reason" => "requeued_after_restart"}
  end
end
