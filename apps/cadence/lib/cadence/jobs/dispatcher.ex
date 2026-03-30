defmodule Cadence.Jobs.Dispatcher do
  @moduledoc false

  use GenServer

  alias Cadence.Jobs
  alias Cadence.Jobs.Worker

  @default_poll_interval_ms 50
  @default_max_concurrency 4

  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @impl true
  def init(opts) do
    state = %{
      poll_interval_ms: Keyword.get(opts, :poll_interval_ms, @default_poll_interval_ms),
      max_concurrency: Keyword.get(opts, :max_concurrency, @default_max_concurrency)
    }

    {:ok, state, {:continue, :bootstrap}}
  end

  @impl true
  def handle_continue(:bootstrap, state) do
    _ = Jobs.requeue_running_jobs()
    send(self(), :dispatch)
    {:noreply, state}
  end

  @impl true
  def handle_info(:dispatch, state) do
    dispatch_available_jobs(state)
    schedule_dispatch(state.poll_interval_ms)
    {:noreply, state}
  end

  defp dispatch_available_jobs(state) do
    available_slots = available_slots(state.max_concurrency)

    if available_slots > 0 do
      available_slots
      |> Jobs.claim_jobs()
      |> Enum.each(&start_worker/1)
    end
  end

  defp available_slots(max_concurrency) do
    active_workers = DynamicSupervisor.count_children(Cadence.Jobs.WorkerSupervisor).active
    max(max_concurrency - active_workers, 0)
  end

  defp start_worker(job) do
    case DynamicSupervisor.start_child(Cadence.Jobs.WorkerSupervisor, {Worker, job.job_id}) do
      {:ok, _pid} ->
        :ok

      {:error, reason} ->
        _ = Jobs.fail_worker_start(job.job_id, reason)
        :error
    end
  end

  defp schedule_dispatch(poll_interval_ms) do
    Process.send_after(self(), :dispatch, poll_interval_ms)
  end
end
