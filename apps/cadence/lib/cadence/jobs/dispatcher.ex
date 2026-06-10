defmodule Cadence.Jobs.Dispatcher do
  @moduledoc false

  use GenServer

  alias Cadence.Jobs
  alias Cadence.Jobs.Worker

  @default_safety_poll_interval_ms 60_000
  @default_max_concurrency 4
  @event_prefix [:cadence, :jobs, :dispatcher]

  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @spec notify_available(GenServer.server()) :: :ok
  def notify_available(server \\ __MODULE__) do
    case GenServer.whereis(server) do
      nil -> :ok
      pid when is_pid(pid) -> GenServer.cast(pid, :dispatch_available)
    end
  end

  @impl true
  def init(opts) do
    state = %{
      safety_poll_interval_ms:
        Keyword.get(
          opts,
          :safety_poll_interval_ms,
          Keyword.get(opts, :poll_interval_ms, @default_safety_poll_interval_ms)
        ),
      max_concurrency: Keyword.get(opts, :max_concurrency, @default_max_concurrency),
      safety_timer: nil,
      worker_refs: %{}
    }

    {:ok, state, {:continue, :bootstrap}}
  end

  @impl true
  def handle_continue(:bootstrap, state) do
    _ = Jobs.requeue_running_jobs()
    {:noreply, dispatch_available_jobs(state, :boot)}
  end

  @impl true
  def handle_cast(:dispatch_available, state) do
    emit(:notification, state, %{count: 1}, %{})

    state =
      state
      |> cancel_safety_timer()
      |> dispatch_available_jobs(:notification)

    {:noreply, state}
  end

  @impl true
  def handle_info({:safety_dispatch, token}, state) do
    case state.safety_timer do
      %{token: ^token} ->
        state =
          state
          |> clear_safety_timer()
          |> dispatch_available_jobs(:safety)

        {:noreply, state}

      _stale_or_canceled_timer ->
        emit(:stale_timer, state, %{count: 1}, %{})
        {:noreply, state}
    end
  end

  def handle_info({:DOWN, ref, :process, _pid, _reason}, state) do
    state =
      state
      |> unmonitor_worker(ref)
      |> dispatch_available_jobs(:worker_available)

    {:noreply, state}
  end

  defp dispatch_available_jobs(state, reason) do
    available_slots = available_slots(state.max_concurrency)

    emit(:dispatch_attempt, state, %{available_slots: available_slots}, %{reason: reason})

    state
    |> claim_available_jobs(available_slots, reason)
    |> schedule_safety_dispatch()
  end

  defp claim_available_jobs(state, available_slots, reason) when available_slots > 0 do
    jobs = Jobs.claim_jobs(available_slots)
    emit(:jobs_claimed, state, %{count: length(jobs)}, %{reason: reason})
    start_claimed_workers(state, jobs)
  end

  defp claim_available_jobs(state, _available_slots, reason) do
    emit(:jobs_claimed, state, %{count: 0}, %{reason: reason})
    state
  end

  defp start_claimed_workers(state, jobs) do
    Enum.reduce(jobs, state, fn job, acc ->
      start_worker(acc, job)
    end)
  end

  defp available_slots(max_concurrency) do
    active_workers = DynamicSupervisor.count_children(Cadence.Jobs.WorkerSupervisor).active
    max(max_concurrency - active_workers, 0)
  end

  defp start_worker(state, job) do
    case DynamicSupervisor.start_child(Cadence.Jobs.WorkerSupervisor, {Worker, job.job_id}) do
      {:ok, pid} ->
        monitor_started_worker(state, job, pid)

      {:ok, pid, _info} ->
        monitor_started_worker(state, job, pid)

      :ignore ->
        emit(:worker_start_failed, state, %{count: 1}, %{
          job_id: job.job_id,
          reason: ":ignore"
        })

        state

      {:error, reason} ->
        _ = Jobs.fail_worker_start(job.job_id, reason)

        emit(:worker_start_failed, state, %{count: 1}, %{
          job_id: job.job_id,
          reason: inspect(reason)
        })

        state
    end
  end

  defp monitor_started_worker(state, job, pid) do
    ref = Process.monitor(pid)
    emit(:worker_started, state, %{count: 1}, %{job_id: job.job_id})
    put_in(state.worker_refs[ref], job.job_id)
  end

  defp unmonitor_worker(state, ref) do
    %{state | worker_refs: Map.delete(state.worker_refs, ref)}
  end

  defp schedule_safety_dispatch(state) do
    state = cancel_safety_timer(state)
    token = make_ref()
    ref = Process.send_after(self(), {:safety_dispatch, token}, state.safety_poll_interval_ms)

    emit(
      :safety_dispatch_scheduled,
      state,
      %{count: 1, delay_ms: state.safety_poll_interval_ms},
      %{}
    )

    %{state | safety_timer: %{ref: ref, token: token}}
  end

  defp cancel_safety_timer(%{safety_timer: nil} = state), do: state

  defp cancel_safety_timer(%{safety_timer: %{ref: ref}} = state) do
    _ = Process.cancel_timer(ref)
    %{state | safety_timer: nil}
  end

  defp clear_safety_timer(state), do: %{state | safety_timer: nil}

  defp emit(event, state, measurements, metadata) when is_atom(event) do
    :telemetry.execute(
      @event_prefix ++ [event],
      measurements,
      Map.merge(metadata, %{
        max_concurrency: state.max_concurrency,
        running_worker_count: map_size(state.worker_refs),
        safety_poll_interval_ms: state.safety_poll_interval_ms
      })
    )
  end
end
