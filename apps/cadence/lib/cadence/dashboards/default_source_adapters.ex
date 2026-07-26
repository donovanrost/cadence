defmodule Cadence.Dashboards.DefaultSourceAdapters do
  @moduledoc """
  Projection-owned mapping from durable source adapter identifiers to reader modules.

  Management records persist stable logical identifiers; executable modules are
  selected only when a read or probe is performed.
  """

  alias Cadence.Dashboards.{DataSource, SourceAdapterDefinition}
  alias Cadence.Dashboards.Sources.{Events, Limits, OperationalObservables, Telemetry}

  @definitions [
    %SourceAdapterDefinition{
      logical_source: :telemetry,
      version: 1,
      label: "Telemetry",
      description: "Latest and historical spacecraft telemetry.",
      module: Telemetry,
      default_data_source_capabilities: %{
        latest?: true,
        range_scan?: true,
        bounded_history?: true,
        watermarks?: true,
        native_decimation?: false
      }
    },
    %SourceAdapterDefinition{
      logical_source: :limits,
      version: 1,
      label: "Limits",
      description: "Current and historical telemetry limit state.",
      module: Limits,
      default_data_source_capabilities: %{
        latest_state?: true,
        event_history?: true,
        definition_intervals?: true,
        watermarks?: true
      }
    },
    %SourceAdapterDefinition{
      logical_source: :operational_observables,
      version: 1,
      label: "Operational observables",
      description: "Cadence operational state and metric projections.",
      module: OperationalObservables,
      default_data_source_capabilities: %{
        constellation_health?: true,
        watermarks?: false
      }
    },
    %SourceAdapterDefinition{
      logical_source: :events,
      version: 1,
      label: "Events",
      description: "Mission, contact, source, and data-management events.",
      module: Events,
      default_data_source_capabilities: %{
        contact_intervals?: true,
        mission_timeline?: true,
        source_health_transitions?: true,
        source_watermark_events?: true,
        source_capability_postures?: true,
        telemetry_backfill_lifecycle?: true,
        telemetry_revision_decisions?: true,
        watermarks?: false
      }
    }
  ]

  @adapters Map.new(@definitions, &{&1.logical_source, &1.module})

  @type definition_fetch_error ::
          :unknown_source_adapter
          | :unsupported_source_adapter_version
          | :invalid_source_adapter_definition

  @spec list_definitions() :: [SourceAdapterDefinition.t()]
  def list_definitions, do: @definitions

  @spec fetch_definition(atom(), pos_integer() | :latest | nil) ::
          {:ok, SourceAdapterDefinition.t()} | {:error, definition_fetch_error()}
  def fetch_definition(logical_source, version \\ :latest)

  def fetch_definition(logical_source, version) when is_atom(logical_source) do
    case Enum.find(@definitions, &(&1.logical_source == logical_source)) do
      %SourceAdapterDefinition{} = definition
      when version in [:latest, nil, definition.version] ->
        case SourceAdapterDefinition.validate(definition) do
          :ok ->
            {:ok, definition}

          {:error, :invalid_source_adapter_definition} ->
            {:error, :invalid_source_adapter_definition}
        end

      %SourceAdapterDefinition{} ->
        {:error, :unsupported_source_adapter_version}

      nil ->
        {:error, :unknown_source_adapter}
    end
  end

  def fetch_definition(_logical_source, _version), do: {:error, :unknown_source_adapter}

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
