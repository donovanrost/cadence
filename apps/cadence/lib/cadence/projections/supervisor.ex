defmodule Cadence.Projections.Supervisor do
  @moduledoc false

  use Supervisor

  def start_link(opts \\ []) do
    Supervisor.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @impl true
  def init(_opts) do
    children =
      [
        Cadence.Telemetry.RuntimeHealth,
        Cadence.Projections.RuntimeFactConsumer,
        Cadence.Projections.DomainFactConsumer
      ] ++
        dashboard_runtime_cache_children() ++
        dashboard_source_circuit_breaker_children() ++
        dashboard_source_probe_scheduler_children() ++
        mission_health_observability_children()

    Supervisor.init(children, strategy: :one_for_one)
  end

  defp mission_health_observability_children do
    [Cadence.Observability.mission_health_sampler_child_spec()]
    |> Enum.reject(&is_nil/1)
  end

  defp dashboard_runtime_cache_children do
    config = Application.get_env(:cadence, :dashboard_runtime_cache, [])

    if Keyword.get(config, :enabled?, true) do
      [{Cadence.Dashboards.RuntimeCache, config}]
    else
      []
    end
  end

  defp dashboard_source_circuit_breaker_children do
    config = Application.get_env(:cadence, :dashboard_source_circuit_breaker, [])

    if Keyword.get(config, :enabled?, false) do
      [{Cadence.Dashboards.SourceCircuitBreaker, config}]
    else
      []
    end
  end

  defp dashboard_source_probe_scheduler_children do
    config = Application.get_env(:cadence, :dashboard_source_probe_scheduler, [])

    if Keyword.get(config, :enabled?, false) do
      [{Cadence.Dashboards.SourceProbeScheduler, config}]
    else
      []
    end
  end
end
