defmodule Cadence.Jobs.Worker do
  @moduledoc false

  # Temporary: a worker runs its claimed job once. As :permanent (the default) a worker that
  # finished was restarted and ran run_job again, which overwrote the job's outcome with
  # job_not_running (every dev job ended 'failed'), and a worker killed mid-handler would have run
  # the handler again. The dispatcher monitors workers and fails a job whose worker exits
  # abnormally (worker_exited); an operator decides about a retry.
  use GenServer, restart: :temporary

  alias Cadence.Jobs.Runner

  def start_link(opts) when is_list(opts) do
    state = %{
      job_id: Keyword.fetch!(opts, :job_id),
      runner: Keyword.fetch!(opts, :runner)
    }

    GenServer.start_link(__MODULE__, state)
  end

  @impl true
  def init(state) do
    {:ok, state, {:continue, :run}}
  end

  @impl true
  def handle_continue(:run, state) do
    _ = Runner.run_job(state.runner, state.job_id)
    {:stop, :normal, state}
  end
end
