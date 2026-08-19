defmodule Cadence.Projections.Supervisor do
  @moduledoc false

  use Supervisor

  alias Cadence.Dashboards.{RuntimeCache, RuntimeComposition, SourceCircuitBreaker}

  def start_link(opts \\ []) do
    Supervisor.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @impl true
  def init(opts) do
    dashboard_runtime = dashboard_runtime_composition(opts)

    children =
      [
        Cadence.Telemetry.RuntimeHealth,
        Cadence.Projections.RuntimeFactConsumer,
        Cadence.Projections.TelemetryFactConsumer,
        Cadence.Projections.DomainFactConsumer
      ] ++
        dashboard_runtime_cache_children(dashboard_runtime) ++
        dashboard_runtime_fact_consumer_children(dashboard_runtime) ++
        dashboard_source_circuit_breaker_children(dashboard_runtime) ++
        data_source_probe_scheduler_children() ++
        mission_health_observability_children()

    Supervisor.init(children, strategy: :one_for_one)
  end

  defp mission_health_observability_children do
    [Cadence.Observability.mission_health_sampler_child_spec()]
    |> Enum.reject(&is_nil/1)
  end

  defp dashboard_runtime_cache_children(%RuntimeComposition{} = composition) do
    if composition.runtime_cache_enabled? do
      [{RuntimeCache, composition.runtime_cache_child_opts}]
    else
      []
    end
  end

  defp dashboard_runtime_fact_consumer_children(%RuntimeComposition{} = composition) do
    if composition.runtime_cache_enabled? do
      [
        {Cadence.Dashboards.RuntimeFactConsumer,
         enabled?: composition.runtime_invalidation?,
         runtime_cache: composition.runtime_invalidation_cache}
      ]
    else
      []
    end
  end

  defp dashboard_source_circuit_breaker_children(%RuntimeComposition{} = composition) do
    if composition.source_circuit_breaker_enabled? do
      [{SourceCircuitBreaker, composition.source_circuit_breaker_child_opts}]
    else
      []
    end
  end

  defp dashboard_runtime_composition(opts) do
    Keyword.get_lazy(opts, :dashboard_runtime_composition, fn ->
      RuntimeComposition.from_application(
        runtime_cache_server: RuntimeCache,
        source_circuit_breaker_server: SourceCircuitBreaker
      )
    end)
  end

  defp data_source_probe_scheduler_children do
    config = Application.get_env(:cadence, :data_source_probe_scheduler, [])

    if Keyword.get(config, :enabled?, false) do
      [{Cadence.DataSources.ProbeScheduler, config}]
    else
      []
    end
  end
end
