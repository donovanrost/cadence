defmodule Cadence.JobsWorkerLifecycleTest do
  @moduledoc """
  api-ops 11-14 (qa's L11 run): job workers were :permanent, so every finished worker was started
  again and ran run_job a second time, which overwrote the job's outcome with job_not_running
  (every dev job ended 'failed', 0 completed). A job runs once; its recorded outcome stays; a worker
  that exits abnormally fails its job (worker_exited) instead of running it again.
  """
  use Cadence.RuntimeCase, async: false

  alias Cadence.Jobs
  alias Cadence.Jobs.Runner, as: JobRunner

  test "a finished job stays completed: its worker isn't started again" do
    owner = self()

    runtime =
      start_job_runtime(%{
        catalog_import_run: fn run_id ->
          send(owner, {:ran, run_id})
          {:ok, :done}
        end
      })

    {:ok, job} = Jobs.enqueue(:catalog_import_run, "mission-worker-life", "run-once", %{})
    Jobs.Available.publish(job)

    assert_receive {:ran, "run-once"}, 2_000
    completed = wait_for_job_status(job.job_id, :completed)

    # A restarted worker would have run run_job again within this window.
    Process.sleep(300)
    assert {:ok, ^completed} = Cadence.fetch_background_job(job.job_id)
    refute_received {:ran, "run-once"}
    assert %{active: 0} = DynamicSupervisor.count_children(runtime.worker_supervisor)
  end

  test "run_job on a job it didn't claim records nothing" do
    runner = JobRunner.new(%{catalog_import_run: fn _run_id -> {:ok, :done} end})

    {:ok, job} = Jobs.enqueue(:catalog_import_run, "mission-worker-life", "not-claimed", %{})
    assert [claimed] = Jobs.claim_jobs(1)
    assert {:ok, completed} = JobRunner.run_job(runner, claimed.job_id)
    assert completed.status == :completed

    assert {:error, {:job_not_running, :completed}} = JobRunner.run_job(runner, job.job_id)
    assert {:ok, ^completed} = Cadence.fetch_background_job(job.job_id)
  end

  test "a worker killed mid-handler fails its job (worker_exited) and doesn't run it again" do
    owner = self()

    runtime =
      start_job_runtime(%{
        catalog_import_run: fn run_id ->
          send(owner, {:running, run_id, self()})

          receive do
            :never -> {:ok, :done}
          end
        end
      })

    {:ok, job} = Jobs.enqueue(:catalog_import_run, "mission-worker-life", "killed", %{})
    Jobs.Available.publish(job)

    assert_receive {:running, "killed", worker}, 2_000
    Process.exit(worker, :kill)

    failed = wait_for_job_status(job.job_id, :failed)
    assert %{"tuple" => ["worker_exited", reason]} = failed.failure_reason
    assert reason =~ "killed"
    assert failed.attempt_count == 1

    Process.sleep(300)
    refute_received {:running, "killed", _again}
    assert %{active: 0} = DynamicSupervisor.count_children(runtime.worker_supervisor)
  end

  defp start_job_runtime(handlers) do
    unique = make_ref()
    worker_supervisor = {:global, {__MODULE__, :worker_supervisor, unique}}

    start_supervised!(
      {Cadence.Jobs.Supervisor,
       name: nil,
       dispatcher_name: {:global, {__MODULE__, :dispatcher, unique}},
       worker_supervisor_name: worker_supervisor,
       runner: JobRunner.new(handlers)}
    )

    %{worker_supervisor: worker_supervisor}
  end

  defp wait_for_job_status(job_id, status, attempts_left \\ 80)

  defp wait_for_job_status(job_id, status, attempts_left) when attempts_left > 0 do
    case Cadence.fetch_background_job(job_id) do
      {:ok, %{status: ^status} = job} ->
        job

      _other ->
        Process.sleep(25)
        wait_for_job_status(job_id, status, attempts_left - 1)
    end
  end

  defp wait_for_job_status(job_id, status, 0),
    do: flunk("job #{job_id} did not reach #{status} before timeout")
end
