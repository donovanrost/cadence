defmodule Cadence.Projections.Supervisor do
  @moduledoc false

  use Supervisor

  alias Cadence.Dashboards.{RuntimeCache, RuntimeComposition, SourceCircuitBreaker}
  alias Cadence.Platform.RootComposition

  def child_spec(opts) do
    composition = root_composition(opts)

    %{
      id: supervisor_name(opts, composition),
      start: {__MODULE__, :start_link, [Keyword.put(opts, :root_composition, composition)]},
      type: :supervisor
    }
  end

  def start_link(opts \\ []) do
    composition = root_composition(opts)
    opts = Keyword.put(opts, :root_composition, composition)

    case supervisor_name(opts, composition) do
      nil -> Supervisor.start_link(__MODULE__, opts)
      name -> Supervisor.start_link(__MODULE__, opts, name: name)
    end
  end

  @impl true
  def init(opts) do
    composition = root_composition(opts)
    dashboard_runtime = composition.dashboard_runtime_composition

    children =
      [
        {Cadence.Telemetry.RuntimeHealth, runtime_health_child_opts(opts, composition)},
        {Cadence.Projections.RuntimeFactConsumer,
         fact_consumer_opts(
           opts,
           :runtime_fact_consumer_opts,
           composition.projections_runtime_fact_consumer_opts,
           composition
         )},
        {Cadence.Projections.TelemetryFactConsumer,
         fact_consumer_opts(
           opts,
           :telemetry_fact_consumer_opts,
           composition.projections_telemetry_fact_consumer_opts,
           composition
         )},
        {Cadence.Projections.DomainFactConsumer,
         fact_consumer_opts(
           opts,
           :domain_fact_consumer_opts,
           composition.projections_domain_fact_consumer_opts,
           composition
         )}
      ] ++
        dashboard_runtime_cache_children(dashboard_runtime) ++
        dashboard_runtime_fact_consumer_children(dashboard_runtime, opts, composition) ++
        dashboard_source_circuit_breaker_children(dashboard_runtime) ++
        data_source_probe_scheduler_children(composition) ++
        composition.mission_health_observability_children

    Supervisor.init(children, strategy: :one_for_one)
  end

  defp dashboard_runtime_cache_children(%RuntimeComposition{} = composition) do
    if composition.runtime_cache_enabled? do
      [{RuntimeCache, composition.runtime_cache_child_opts}]
    else
      []
    end
  end

  defp dashboard_runtime_fact_consumer_children(
         %RuntimeComposition{} = dashboard_runtime,
         _opts,
         %RootComposition{} = composition
       ) do
    if dashboard_runtime.runtime_cache_enabled? do
      [
        {Cadence.Dashboards.RuntimeFactConsumer,
         composition.dashboard_runtime_fact_consumer_opts
         |> Keyword.put(:event_bus, composition.event_bus)
         |> Keyword.put(:enabled?, dashboard_runtime.runtime_invalidation?)
         |> Keyword.put(:runtime_cache, dashboard_runtime.runtime_invalidation_cache)}
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

  defp data_source_probe_scheduler_children(%RootComposition{} = composition) do
    config = composition.data_source_probe_scheduler_config

    if Keyword.get(config, :enabled?, false) do
      [{Cadence.DataSources.ProbeScheduler, config}]
    else
      []
    end
  end

  defp runtime_health_child_opts(_opts, %RootComposition{} = composition),
    do: composition.runtime_health_child_opts

  defp fact_consumer_opts(_opts, _key, configured_opts, %RootComposition{} = composition) do
    Keyword.put(configured_opts, :event_bus, composition.event_bus)
  end

  defp supervisor_name(_opts, %RootComposition{} = composition),
    do: composition.projections_supervisor_name

  defp root_composition(opts) do
    case Keyword.fetch(opts, :root_composition) do
      {:ok, %RootComposition{} = composition} ->
        composition

      :error ->
        compatibility_opts =
          []
          |> copy_option(opts, :name, :projections_supervisor_name)
          |> copy_option(opts, :dashboard_runtime_composition)
          |> copy_option(opts, :runtime_health_child_opts)
          |> copy_option(opts, :dashboard_runtime_fact_consumer_opts)
          |> copy_option(
            opts,
            :runtime_fact_consumer_opts,
            :projections_runtime_fact_consumer_opts
          )
          |> copy_option(
            opts,
            :telemetry_fact_consumer_opts,
            :projections_telemetry_fact_consumer_opts
          )
          |> copy_option(
            opts,
            :domain_fact_consumer_opts,
            :projections_domain_fact_consumer_opts
          )

        RootComposition.from_application(compatibility_opts)
    end
  end

  defp copy_option(target, source, source_key, target_key \\ nil) do
    case Keyword.fetch(source, source_key) do
      {:ok, value} -> Keyword.put(target, target_key || source_key, value)
      :error -> target
    end
  end
end
