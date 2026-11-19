defmodule Cadence.JobsRecoveryTest do
  @moduledoc """
  Node-start recovery (director 11-14): a job left :running when the node stopped goes back in
  the queue only if its handler says it's safe to run again; any other becomes outcome_unknown
  and is never re-run on its own.
  """
  use Cadence.RuntimeCase, async: false

  alias Cadence.Jobs
  alias Cadence.Jobs.Runner, as: JobRunner

  @rerun_safe ~w(telemetry_latest_value_rebuild derived_telemetry_latest_value_rebuild
                 telemetry_latest_limit_state_refresh telemetry_latest_limit_state_rebuild
                 mission_event_rebuild catalog_import_run)a

  test "only the verified projection rebuilds and the catalog import are safe to run again" do
    runner = :cadence |> Application.fetch_env!(:job_handlers) |> JobRunner.new()

    for job_type <- @rerun_safe,
        do: assert(JobRunner.rerun_safe?(runner, job_type), "#{job_type}")

    for job_type <- ~w(contact_schedule_operation tsdb_backend_lifecycle
                       managed_questdb_provisioning telemetry_limit_evaluation
                       derived_telemetry_evaluation replay_telemetry_scope
                       telemetry_historical_data_workflow unknown_job_type)a do
      refute JobRunner.rerun_safe?(runner, job_type), "#{job_type}"
    end

    # A function handler never says it's safe.
    refute JobRunner.rerun_safe?(
             JobRunner.new(%{mission_event_rebuild: fn _run_id -> {:ok, :done} end}),
             :mission_event_rebuild
           )
  end

  test "recovery requeues a rerun-safe job and makes any other outcome_unknown" do
    {:ok, rebuild} = Jobs.enqueue(:mission_event_rebuild, "mission-recovery", "rebuild-1", %{})

    {:ok, booking} =
      Jobs.enqueue(:contact_schedule_operation, "mission-recovery", "booking-1", %{})

    {:ok, done} = Jobs.enqueue(:mission_event_rebuild, "mission-recovery", "done-1", %{})

    assert [_, _, _] = Jobs.claim_jobs(3)
    {:ok, _completed} = Jobs.record_execution_result(running(done.job_id), {:ok, :done})

    assert %{requeued: 1, outcome_unknown: 1} =
             Jobs.recover_running_jobs(&(&1 == :mission_event_rebuild))

    assert {:ok, %{status: :queued, failure_reason: %{"reason" => "requeued_after_restart"}}} =
             Cadence.fetch_background_job(rebuild.job_id)

    assert {:ok,
            %{
              status: :outcome_unknown,
              started_at: %DateTime{},
              completed_at: %DateTime{},
              failure_reason: %{
                "reason" => "outcome_unknown",
                "cause" => "node_stopped_while_running"
              }
            }} = Cadence.fetch_background_job(booking.job_id)

    # A job that already recorded its outcome is left alone.
    assert {:ok, %{status: :completed}} = Cadence.fetch_background_job(done.job_id)
  end

  test "the dispatcher's start recovers without re-running an unsafe job" do
    owner = self()

    {:ok, booking} =
      Jobs.enqueue(:contact_schedule_operation, "mission-recovery", "booking-boot", %{})

    assert [_] = Jobs.claim_jobs(1)

    unique = make_ref()

    start_supervised!(
      {Cadence.Jobs.Supervisor,
       name: nil,
       dispatcher_name: {:global, {__MODULE__, :dispatcher, unique}},
       worker_supervisor_name: {:global, {__MODULE__, :worker_supervisor, unique}},
       runner:
         JobRunner.new(%{
           contact_schedule_operation: fn run_id -> send(owner, {:ran, run_id}) end
         })}
    )

    assert_eventually(fn ->
      match?({:ok, %{status: :outcome_unknown}}, Cadence.fetch_background_job(booking.job_id))
    end)

    Process.sleep(200)
    refute_received {:ran, "booking-boot"}
  end

  defp running(job_id) do
    {:ok, job} = Cadence.fetch_background_job(job_id)
    job
  end

  defp assert_eventually(fun, attempts \\ 80)
  defp assert_eventually(_fun, 0), do: flunk("condition not met in time")

  defp assert_eventually(fun, attempts) do
    if fun.(), do: :ok, else: Process.sleep(25) && assert_eventually(fun, attempts - 1)
  end
end
