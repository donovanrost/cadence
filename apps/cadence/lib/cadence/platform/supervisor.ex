defmodule Cadence.Platform.Supervisor do
  @moduledoc false

  use Supervisor

  def start_link(opts \\ []) do
    Supervisor.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @impl true
  def init(_opts) do
    children =
      observability_children() ++
        [
          Cadence.Repo,
          {Phoenix.PubSub, name: Cadence.PubSub}
        ]

    Supervisor.init(children, strategy: :one_for_one)
  end

  defp observability_children do
    [
      Cadence.Observability.log_exporter_child_spec(),
      Cadence.Observability.metrics_reporter_child_spec(),
      Cadence.Observability.metrics_sampler_child_spec()
    ]
    |> Enum.reject(&is_nil/1)
  end
end
