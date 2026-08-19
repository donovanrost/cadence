defmodule Cadence.Jobs.Dispatcher do
  @moduledoc false

  use GenServer

  alias Cadence.Jobs
  alias Cadence.Jobs.Worker

  @default_safety_poll_interval_ms 60_000
  @default_max_concurrency 4
  @default_name :cadence_job_dispatcher
  @event_prefix [:cadence, :jobs, :dispatcher]

  def start_link(opts \\ []) do
    case Keyword.get(opts, :name, @default_name) do
      nil -> GenServer.start_link(__MODULE__, opts)
      name -> GenServer.start_link(__MODULE__, opts, name: name)
    end
  end

  @doc false
  @spec default_name() :: atom()
  def default_name, do: @default_name

  @spec notify_available(GenServer.server()) :: :ok
  def notify_available(server \\ @default_name) do
    case GenServer.whereis(server) do
      nil -> :ok
      pid when is_pid(pid) -> GenServer.cast(pid, :dispatch_available)
    end
  end

  @spec quiesce(GenServer.server()) :: {:ok, map()} | {:error, :noproc}
  def quiesce(server \\ @default_name) do
    case GenServer.whereis(server) do
      nil -> {:error, :noproc}
      pid when is_pid(pid) -> GenServer.call(pid, :quiesce, :infinity)
    end
  end

  @impl true
  def init(opts) do
    state = %{
      safety_poll_interval_ms:
        Keyword.get(opts, :safety_poll_interval_ms, @default_safety_poll_interval_ms),
      max_concurrency: Keyword.get(opts, :max_concurrency, @default_max_concurrency),
      worker_supervisor: Keyword.fetch!(opts, :worker_supervisor),
      runner: Keyword.fetch!(opts, :runner),
      safety_timer: nil,
      worker_refs: %{},
      lifecycle_status: :active,
      quiesce_waiters: []
    }

    {:ok, state, {:continue, :bootstrap}}
  end

  @impl true
  def handle_continue(:bootstrap, state) do
    _ = Jobs.requeue_running_jobs()
    {:noreply, dispatch_available_jobs(state, :boot)}
  end

  @impl true
  def handle_call(:quiesce, _from, %{lifecycle_status: :quiesced} = state) do
    {:reply, {:ok, quiescence_settlement(state)}, state}
  end

  def handle_call(:quiesce, from, %{lifecycle_status: :quiescing} = state) do
    {:noreply, %{state | quiesce_waiters: [from | state.quiesce_waiters]}}
  end

  def handle_call(:quiesce, from, state) do
    state =
      state
      |> cancel_safety_timer()
      |> Map.put(:lifecycle_status, :quiescing)
      |> Map.put(:quiesce_waiters, [from])

    settle_if_quiescent(state)
  end

  @impl true
  def handle_cast(:dispatch_available, %{lifecycle_status: :active} = state) do
    emit(:notification, state, %{count: 1}, %{})

    state =
      state
      |> cancel_safety_timer()
      |> dispatch_available_jobs(:notification)

    {:noreply, state}
  end

  def handle_cast(:dispatch_available, state), do: {:noreply, state}

  @impl true
  def handle_info({:safety_dispatch, token}, %{lifecycle_status: :active} = state) do
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

  def handle_info({:safety_dispatch, _token}, state), do: {:noreply, state}

  def handle_info({:DOWN, ref, :process, _pid, reason}, state) do
    state =
      state
      |> unmonitor_worker(ref)

    emit(:worker_finished, state, %{count: 1}, %{outcome: worker_outcome(reason)})

    case state.lifecycle_status do
      :active -> {:noreply, dispatch_available_jobs(state, :worker_available)}
      _quiescing_or_quiesced -> settle_if_quiescent(state)
    end
  end

  defp dispatch_available_jobs(state, reason) do
    available_slots = available_slots(state)

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

  defp available_slots(state) do
    active_workers =
      state.worker_supervisor
      |> resolve_worker_supervisor()
      |> DynamicSupervisor.count_children()
      |> Map.fetch!(:active)

    max(state.max_concurrency - active_workers, 0)
  end

  defp start_worker(state, job) do
    worker_supervisor = resolve_worker_supervisor(state.worker_supervisor)
    worker_opts = [job_id: job.job_id, runner: state.runner]

    case DynamicSupervisor.start_child(worker_supervisor, {Worker, worker_opts}) do
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
    state = put_in(state.worker_refs[ref], job.job_id)
    emit(:worker_started, state, %{count: 1}, %{job_id: job.job_id})
    state
  end

  defp unmonitor_worker(state, ref) do
    %{state | worker_refs: Map.delete(state.worker_refs, ref)}
  end

  defp resolve_worker_supervisor({:supervisor_child, supervisor, child_id}) do
    supervisor
    |> Supervisor.which_children()
    |> Enum.find_value(fn
      {^child_id, pid, :supervisor, _modules} when is_pid(pid) -> pid
      _child -> nil
    end)
    |> case do
      nil -> raise "jobs worker supervisor is not running"
      pid -> pid
    end
  end

  defp resolve_worker_supervisor(worker_supervisor), do: worker_supervisor

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

  defp settle_if_quiescent(%{lifecycle_status: :quiescing, worker_refs: worker_refs} = state)
       when map_size(worker_refs) == 0 do
    settlement = quiescence_settlement(state)
    Enum.each(state.quiesce_waiters, &GenServer.reply(&1, {:ok, settlement}))

    {:noreply,
     %{
       state
       | lifecycle_status: :quiesced,
         quiesce_waiters: []
     }}
  end

  defp settle_if_quiescent(state), do: {:noreply, state}

  defp quiescence_settlement(state) do
    %{
      status: :quiesced,
      active_worker_count: map_size(state.worker_refs),
      safety_timer_active?: not is_nil(state.safety_timer)
    }
  end

  defp worker_outcome(:normal), do: :ok
  defp worker_outcome(:shutdown), do: :ok
  defp worker_outcome({:shutdown, _reason}), do: :ok
  defp worker_outcome(_reason), do: :error

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
