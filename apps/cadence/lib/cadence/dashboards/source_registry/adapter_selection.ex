defmodule Cadence.Dashboards.SourceRegistry.AdapterSelection do
  @moduledoc """
  Selects default, overridden, or binding-owned source adapters.
  """

  alias Cadence.Dashboards.ResolvedSourceBinding
  alias Cadence.Dashboards.Sources.{Events, Limits, OperationalObservables, Telemetry}

  @type adapter :: module()

  @default_adapters %{
    telemetry: Telemetry,
    limits: Limits,
    events: Events,
    operational_observables: OperationalObservables
  }

  @spec logical_sources() :: [atom()]
  def logical_sources do
    @default_adapters
    |> Map.keys()
    |> Enum.sort()
  end

  @spec for_logical_source(atom(), keyword()) :: {:ok, adapter()} | :error
  def for_logical_source(logical_source, opts) when is_atom(logical_source) and is_list(opts) do
    adapters = Keyword.get(opts, :adapters, %{})

    case Map.fetch(adapters, logical_source) do
      {:ok, adapter} when is_atom(adapter) -> {:ok, adapter}
      :error -> Map.fetch(@default_adapters, logical_source)
    end
  end

  @spec for_binding(ResolvedSourceBinding.t(), keyword()) :: {:ok, adapter()} | :error
  def for_binding(%ResolvedSourceBinding{} = resolved_binding, opts) when is_list(opts) do
    adapters = Keyword.get(opts, :adapters, %{})
    logical_source = resolved_binding.binding.logical_source

    case Map.fetch(adapters, logical_source) do
      {:ok, adapter} ->
        {:ok, adapter}

      :error ->
        case resolved_binding.data_source.adapter do
          adapter when is_atom(adapter) and not is_nil(adapter) -> {:ok, adapter}
          _other -> :error
        end
    end
  end
end
