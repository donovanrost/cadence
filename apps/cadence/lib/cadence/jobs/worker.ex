defmodule Cadence.Jobs.Worker do
  @moduledoc false

  use GenServer

  alias Cadence.Jobs.Runner

  def start_link(job_id) when is_binary(job_id) do
    GenServer.start_link(__MODULE__, job_id)
  end

  @impl true
  def init(job_id) do
    {:ok, job_id, {:continue, :run}}
  end

  @impl true
  def handle_continue(:run, job_id) do
    _ = Runner.run_job(job_id)
    {:stop, :normal, job_id}
  end
end
