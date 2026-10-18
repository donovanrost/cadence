defmodule Cadence.Jobs.Available do
  @moduledoc "A durable queued job is available; consumers must still claim it through Jobs."

  alias Cadence.Jobs.Job
  alias Cadence.Platform.EventBus

  @enforce_keys [:job_id, :mission_id, :job_type, :run_id]
  defstruct @enforce_keys

  @topic {:cadence, :jobs, :available}

  def subscribe(event_bus \\ EventBus), do: EventBus.subscribe(event_bus, @topic, self())

  def publish(%Job{status: :queued} = job) do
    EventBus.publish(@topic, %__MODULE__{
      job_id: job.job_id,
      mission_id: job.mission_id,
      job_type: job.job_type,
      run_id: job.run_id
    })
  end
end
