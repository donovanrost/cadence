defmodule Cadence.Dashboards.DefaultSourceAdapters do
  @moduledoc """
  Projection-owned mapping from durable source adapter identifiers to reader modules.

  Management records persist stable logical identifiers; executable modules are
  selected only when a read or probe is performed.
  """

  alias Cadence.Dashboards.DataSource
  alias Cadence.Dashboards.Sources.{Events, Limits, OperationalObservables, Telemetry}

  @adapters %{
    telemetry: Telemetry,
    limits: Limits,
    events: Events,
    operational_observables: OperationalObservables
  }

  @spec logical_sources() :: [atom()]
  def logical_sources, do: @adapters |> Map.keys() |> Enum.sort()

  @spec fetch(atom()) :: {:ok, module()} | :error
  def fetch(logical_source), do: Map.fetch(@adapters, logical_source)

  @spec logical_source(atom() | nil) :: atom() | nil
  def logical_source(adapter) when is_map_key(@adapters, adapter), do: adapter

  def logical_source(adapter) when is_atom(adapter) and not is_nil(adapter) do
    Enum.find_value(@adapters, fn {logical_source, module} ->
      if module == adapter, do: logical_source
    end)
  end

  def logical_source(_adapter), do: nil

  @spec resolve(atom() | nil, atom() | nil) :: {:ok, module()} | :error
  def resolve(adapter, logical_source \\ nil)

  def resolve(adapter, _logical_source) when is_map_key(@adapters, adapter),
    do: Map.fetch(@adapters, adapter)

  def resolve(adapter, _logical_source) when is_atom(adapter) and not is_nil(adapter),
    do: {:ok, adapter}

  def resolve(_adapter, _logical_source), do: :error

  @spec materialize(DataSource.t(), atom() | nil) :: DataSource.t()
  def materialize(%DataSource{} = source, logical_source) do
    case resolve(source.adapter, logical_source) do
      {:ok, adapter} -> %DataSource{source | adapter: adapter}
      :error -> source
    end
  end
end
