defmodule Cadence.JobsTest do
  use Cadence.RuntimeCase, async: false

  alias Cadence.Jobs.Runner, as: JobRunner

  alias Cadence.Jobs.{BackgroundJobRow, Job}

  @dispatcher_event_prefix [:cadence, :jobs, :dispatcher]
  @dispatcher_events [
    [:cadence, :jobs, :dispatcher, :notification],
    [:cadence, :jobs, :dispatcher, :dispatch_attempt],
    [:cadence, :jobs, :dispatcher, :jobs_claimed],
    [:cadence, :jobs, :dispatcher, :worker_started],
    [:cadence, :jobs, :dispatcher, :worker_start_failed],
    [:cadence, :jobs, :dispatcher, :safety_dispatch_scheduled],
    [:cadence, :jobs, :dispatcher, :stale_timer]
  ]

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

  test "requeues a specific running job with a reason" do
    assert {:ok, job} =
             Cadence.Jobs.enqueue(
               :replay_telemetry_scope,
               "mission-alpha",
               "replay-run-specific-requeue",
               %{"replay_run_id" => "replay-run-specific-requeue"}
             )

    assert [claimed_job] = Cadence.Jobs.claim_jobs(1)
    assert claimed_job.job_id == job.job_id
    assert claimed_job.status == :running
    assert claimed_job.attempt_count == 1

    assert {:ok, requeued_job} =
             Cadence.Jobs.requeue_running_job(job.job_id, :dashboard_stale_replacement_requeued)

    assert requeued_job.status == :queued
    assert requeued_job.attempt_count == 1
    assert requeued_job.started_at == nil
    assert requeued_job.completed_at == nil
    assert requeued_job.failure_reason == %{"reason" => "dashboard_stale_replacement_requeued"}
  end

  test "retries failed jobs without resetting attempt count" do
    assert {:ok, job} =
             Cadence.Jobs.enqueue(
               :catalog_import_run,
               "mission-background-jobs",
               "missing-catalog-import-retry",
               %{}
             )

    assert [claimed_job] = Cadence.Jobs.claim_jobs(1)
    assert claimed_job.job_id == job.job_id

    assert {:ok, failed_job} = JobRunner.run_job(claimed_job.job_id)
    assert failed_job.status == :failed
    assert failed_job.attempt_count == 1
    assert failed_job.failure_reason
    assert failed_job.started_at
    assert failed_job.completed_at

    assert {:ok, retried_job} = Cadence.Jobs.retry_failed_job(job.job_id)
    assert retried_job.status == :queued
    assert retried_job.attempt_count == 1
    assert retried_job.failure_reason == nil
    assert retried_job.started_at == nil
    assert retried_job.completed_at == nil
  end

  test "does not retry active or completed jobs" do
    assert {:ok, queued_job} =
             Cadence.Jobs.enqueue(
               :catalog_import_run,
               "mission-background-jobs",
               "missing-catalog-import-not-failed",
               %{}
             )

    assert {:error, {:job_not_failed, :queued}} =
             Cadence.Jobs.retry_failed_job(queued_job.job_id)
  end

  test "fails explicitly when a domain job handler is not configured" do
    configured_handlers = Application.fetch_env!(:cadence, :job_handlers)

    on_exit(fn ->
      Application.put_env(:cadence, :job_handlers, configured_handlers)
    end)

    Application.put_env(
      :cadence,
      :job_handlers,
      Map.delete(configured_handlers, :catalog_import_run)
    )

    assert {:ok, job} =
             Cadence.Jobs.enqueue(
               :catalog_import_run,
               "mission-background-jobs",
               "unconfigured-catalog-import-handler",
               %{}
             )

    assert [claimed_job] = Cadence.Jobs.claim_jobs(1)
    assert claimed_job.job_id == job.job_id

    assert {:ok, failed_job} = JobRunner.run_job(claimed_job.job_id)
    assert failed_job.status == :failed

    assert failed_job.failure_reason == %{
             "tuple" => ["job_handler_not_configured", "catalog_import_run"]
           }
  end

  test "does not requeue non-running jobs" do
    assert {:ok, queued_job} =
             Cadence.Jobs.enqueue(
               :catalog_import_run,
               "mission-background-jobs",
               "missing-catalog-import-not-running",
               %{}
             )

    assert {:error, {:job_not_running, :queued}} =
             Cadence.Jobs.requeue_running_job(queued_job.job_id)
  end

  test "enqueue notification wakes dispatcher without waiting for safety scan" do
    attach_dispatcher_telemetry(self())

    start_supervised!(
      {Cadence.Jobs.Supervisor, safety_poll_interval_ms: :timer.hours(1), max_concurrency: 1}
    )

    assert_dispatcher_event(:jobs_claimed, fn measurements, metadata ->
      measurements.count == 0 and metadata.reason == :boot
    end)

    assert {:ok, job} =
             Cadence.Jobs.enqueue(
               :catalog_import_run,
               "mission-background-jobs",
               "missing-catalog-import-notified",
               %{}
             )

    assert_dispatcher_event(:notification, fn measurements, metadata ->
      measurements.count == 1 and metadata.safety_poll_interval_ms == :timer.hours(1)
    end)

    assert_dispatcher_event(:jobs_claimed, fn measurements, metadata ->
      measurements.count == 1 and metadata.reason == :notification
    end)

    assert_dispatcher_event(:worker_started, fn measurements, metadata ->
      measurements.count == 1 and metadata.job_id == job.job_id
    end)

    failed_job = wait_for_job_status(job.job_id, :failed)
    assert failed_job.attempt_count == 1
    assert failed_job.completed_at

    assert {:ok, %{status: :quiesced, active_worker_count: 0, safety_timer_active?: false}} =
             Cadence.Jobs.Supervisor.quiesce()

    stop_supervised!(Cadence.Jobs.Supervisor)
  end

  test "safety dispatch recovers queued jobs when notification is missed" do
    attach_dispatcher_telemetry(self())

    start_supervised!({Cadence.Jobs.Supervisor, safety_poll_interval_ms: 20, max_concurrency: 1})

    assert_dispatcher_event(:jobs_claimed, fn measurements, metadata ->
      measurements.count == 0 and metadata.reason == :boot
    end)

    job =
      insert_background_job!(
        :catalog_import_run,
        "mission-background-jobs",
        "missing-catalog-import-safety"
      )

    assert_dispatcher_event(:jobs_claimed, fn measurements, metadata ->
      measurements.count == 1 and metadata.reason == :safety
    end)

    failed_job = wait_for_job_status(job.job_id, :failed)
    assert failed_job.attempt_count == 1
    assert failed_job.completed_at

    assert {:ok, %{status: :quiesced, active_worker_count: 0, safety_timer_active?: false}} =
             Cadence.Jobs.Supervisor.quiesce()

    stop_supervised!(Cadence.Jobs.Supervisor)
  end

  defp insert_background_job!(job_type, mission_id, run_id) do
    job =
      Job.new(%{
        mission_id: mission_id,
        job_type: job_type,
        run_id: run_id,
        payload: %{}
      })

    job
    |> BackgroundJobRow.changeset()
    |> Repo.insert!()
    |> BackgroundJobRow.to_domain()
  end

  defp wait_for_job_status(job_id, status, attempts_left \\ 40)

  defp wait_for_job_status(job_id, status, attempts_left) when attempts_left > 0 do
    case Cadence.fetch_background_job(job_id) do
      {:ok, %Job{status: ^status} = job} ->
        job

      _other ->
        Process.sleep(25)
        wait_for_job_status(job_id, status, attempts_left - 1)
    end
  end

  defp wait_for_job_status(job_id, status, 0) do
    flunk("job #{job_id} did not reach #{status} before timeout")
  end

  defp attach_dispatcher_telemetry(test_pid) do
    handler_id = "jobs-dispatcher-test-#{System.unique_integer([:positive])}"

    :ok =
      :telemetry.attach_many(
        handler_id,
        @dispatcher_events,
        fn event, measurements, metadata, _config ->
          send(test_pid, {:jobs_dispatcher_telemetry, event, measurements, metadata})
        end,
        nil
      )

    on_exit(fn -> :telemetry.detach(handler_id) end)
  end

  defp assert_dispatcher_event(event_name, predicate) do
    assert_dispatcher_event(event_name, predicate, System.monotonic_time(:millisecond) + 2_000)
  end

  defp assert_dispatcher_event(event_name, predicate, deadline_ms) do
    event = @dispatcher_event_prefix ++ [event_name]
    timeout_ms = max(deadline_ms - System.monotonic_time(:millisecond), 0)

    receive do
      {:jobs_dispatcher_telemetry, ^event, measurements, metadata} ->
        if predicate.(measurements, metadata) do
          {measurements, metadata}
        else
          assert_dispatcher_event(event_name, predicate, deadline_ms)
        end

      {:jobs_dispatcher_telemetry, _other_event, _measurements, _metadata} ->
        assert_dispatcher_event(event_name, predicate, deadline_ms)
    after
      timeout_ms -> flunk("expected jobs dispatcher telemetry event #{inspect(event)}")
    end
  end
end
