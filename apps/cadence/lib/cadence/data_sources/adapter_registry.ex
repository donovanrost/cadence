defmodule Cadence.DataSources.AdapterRegistry do
  @moduledoc """
  Configured mapping from durable source adapter identifiers to provider modules.

  Management records persist stable logical identifiers; executable modules are
  selected only when a read or probe is performed.
  """

  alias Cadence.DataSources.{AdapterDefinition, DataSource}

  @type definition_fetch_error ::
          :unknown_source_adapter
          | :unsupported_source_adapter_version
          | :invalid_source_adapter_definition

  @spec list_definitions() :: [AdapterDefinition.t()]
  def list_definitions do
    :cadence
    |> Application.get_env(:data_source_adapters, [])
    |> Enum.map(&definition_from_config/1)
  end

  @spec fetch_definition(atom(), pos_integer() | :latest | nil) ::
          {:ok, AdapterDefinition.t()} | {:error, definition_fetch_error()}
  def fetch_definition(logical_source, version \\ :latest)

  def fetch_definition(logical_source, version) when is_atom(logical_source) do
    case Enum.find(list_definitions(), &(&1.logical_source == logical_source)) do
      %AdapterDefinition{} = definition
      when version in [:latest, nil, definition.version] ->
        case AdapterDefinition.validate(definition) do
          :ok ->
            {:ok, definition}

          {:error, :invalid_source_adapter_definition} ->
            {:error, :invalid_source_adapter_definition}
        end

      %AdapterDefinition{} ->
        {:error, :unsupported_source_adapter_version}

      nil ->
        {:error, :unknown_source_adapter}
    end
  end

  def fetch_definition(_logical_source, _version), do: {:error, :unknown_source_adapter}

  @spec logical_sources() :: [atom()]
  def logical_sources, do: list_definitions() |> Enum.map(& &1.logical_source) |> Enum.sort()

  @spec fetch(atom()) :: {:ok, module()} | :error
  def fetch(logical_source) do
    case fetch_definition(logical_source) do
      {:ok, definition} -> {:ok, definition.module}
      {:error, _reason} -> :error
    end
  end

  @spec logical_source(atom() | nil) :: atom() | nil
  def logical_source(adapter) when is_atom(adapter) and not is_nil(adapter) do
    case fetch(adapter) do
      {:ok, _module} ->
        adapter

      :error ->
        Enum.find_value(list_definitions(), &logical_source_for_adapter(&1, adapter))
    end
  end

  def logical_source(_adapter), do: nil

  @spec resolve(atom() | nil, atom() | nil) :: {:ok, module()} | :error
  def resolve(adapter, logical_source \\ nil)

  def resolve(adapter, _logical_source) when is_atom(adapter) and not is_nil(adapter),
    do: fetch(adapter) |> resolve_configured_or_module(adapter)

  def resolve(_adapter, _logical_source), do: :error

  @spec resolve_probe(atom() | nil) :: {:ok, module()} | :error
  def resolve_probe(adapter) when is_atom(adapter) and not is_nil(adapter) do
    case definition_for_adapter(adapter) do
      %AdapterDefinition{probe_module: probe_module, module: module} ->
        {:ok, probe_module || module}

      nil ->
        {:ok, adapter}
    end
  end

  def resolve_probe(_adapter), do: :error

  @spec materialize(DataSource.t(), atom() | nil) :: DataSource.t()
  def materialize(%DataSource{} = source, logical_source) do
    case resolve(source.adapter, logical_source) do
      {:ok, adapter} -> %DataSource{source | adapter: adapter}
      :error -> source
    end
  end

  defp resolve_configured_or_module({:ok, module}, _adapter), do: {:ok, module}
  defp resolve_configured_or_module(:error, adapter), do: {:ok, adapter}

  defp logical_source_for_adapter(%AdapterDefinition{} = definition, adapter) do
    if definition.module == adapter, do: definition.logical_source
  end

  defp definition_from_config({logical_source, attrs}) when is_atom(logical_source) do
    attrs = Map.new(attrs)

    %AdapterDefinition{
      logical_source: logical_source,
      version: Map.fetch!(attrs, :version),
      label: Map.fetch!(attrs, :label),
      description: Map.fetch!(attrs, :description),
      module: Map.fetch!(attrs, :module),
      probe_module: Map.get(attrs, :probe_module),
      default_data_source_capabilities: Map.fetch!(attrs, :default_data_source_capabilities)
    }
  end

  defp definition_for_adapter(adapter) do
    Enum.find(list_definitions(), fn definition ->
      definition.logical_source == adapter or definition.module == adapter
    end)
  end
end
