defmodule Cadence.Jobs.Worker do
  @moduledoc false

  use GenServer

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
