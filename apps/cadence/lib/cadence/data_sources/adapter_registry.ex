defmodule Cadence.DataSources.AdapterRegistry do
  @moduledoc """
  Configured mapping from durable source adapter identifiers to provider modules.

  Management records persist stable logical identifiers; executable modules are
  selected only when a read or probe is performed.
  """

  alias Cadence.DataSources.{AdapterDefinition, DataSource}

  @configured_adapters Application.compile_env(:cadence, :data_source_adapters, [])

  @type definition_fetch_error ::
          :unknown_source_adapter
          | :unsupported_source_adapter_version
          | :invalid_source_adapter_definition

  @type policy :: %{
          required(:definitions) => [AdapterDefinition.t()],
          required(:by_logical_source) => %{optional(atom()) => AdapterDefinition.t()}
        }

  @spec list_definitions() :: [AdapterDefinition.t()]
  def list_definitions, do: list_definitions(default_policy())

  @spec list_definitions(policy()) :: [AdapterDefinition.t()]
  def list_definitions(%{definitions: definitions}), do: definitions

  @doc false
  @spec policy(keyword() | map()) :: policy()
  def policy(config) when is_list(config) or is_map(config) do
    definitions = Enum.map(config, &definition_from_config/1)

    %{
      definitions: definitions,
      by_logical_source: Map.new(definitions, &{&1.logical_source, &1})
    }
  end

  @doc false
  @spec default_policy() :: policy()
  def default_policy, do: policy(@configured_adapters)

  @spec fetch_definition(atom(), pos_integer() | :latest | nil) ::
          {:ok, AdapterDefinition.t()} | {:error, definition_fetch_error()}
  def fetch_definition(logical_source, version \\ :latest)

  def fetch_definition(logical_source, version) do
    fetch_definition(logical_source, version, default_policy())
  end

  @spec fetch_definition(atom(), pos_integer() | :latest | nil, policy()) ::
          {:ok, AdapterDefinition.t()} | {:error, definition_fetch_error()}
  def fetch_definition(logical_source, version, policy)
      when is_atom(logical_source) and is_map(policy) do
    case get_in(policy, [:by_logical_source, logical_source]) do
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

  def fetch_definition(_logical_source, _version, _policy), do: {:error, :unknown_source_adapter}

  @spec logical_sources() :: [atom()]
  def logical_sources, do: logical_sources(default_policy())

  @spec logical_sources(policy()) :: [atom()]
  def logical_sources(%{by_logical_source: definitions}) do
    definitions |> Map.keys() |> Enum.sort()
  end

  @spec fetch(atom()) :: {:ok, module()} | :error
  def fetch(logical_source), do: fetch(logical_source, default_policy())

  @spec fetch(atom(), policy()) :: {:ok, module()} | :error
  def fetch(logical_source, policy) do
    case fetch_definition(logical_source, :latest, policy) do
      {:ok, definition} -> {:ok, definition.module}
      {:error, _reason} -> :error
    end
  end

  @spec logical_source(atom() | nil) :: atom() | nil
  def logical_source(adapter), do: logical_source(adapter, default_policy())

  @spec logical_source(atom() | nil, policy()) :: atom() | nil
  def logical_source(adapter, policy)
      when is_atom(adapter) and not is_nil(adapter) and is_map(policy) do
    case fetch(adapter, policy) do
      {:ok, _module} ->
        adapter

      :error ->
        Enum.find_value(list_definitions(policy), &logical_source_for_adapter(&1, adapter))
    end
  end

  def logical_source(_adapter, _policy), do: nil

  @spec resolve(atom() | nil, atom() | nil) :: {:ok, module()} | :error
  def resolve(adapter, logical_source \\ nil)

  def resolve(adapter, logical_source) do
    resolve(adapter, logical_source, default_policy())
  end

  @spec resolve(atom() | nil, atom() | nil, policy()) :: {:ok, module()} | :error
  def resolve(adapter, _logical_source, policy)
      when is_atom(adapter) and not is_nil(adapter) and is_map(policy),
      do: fetch(adapter, policy) |> resolve_configured_or_module(adapter)

  def resolve(_adapter, _logical_source, _policy), do: :error

  @spec resolve_probe(atom() | nil) :: {:ok, module()} | :error
  def resolve_probe(adapter), do: resolve_probe(adapter, default_policy())

  @spec resolve_probe(atom() | nil, policy()) :: {:ok, module()} | :error
  def resolve_probe(adapter, policy)
      when is_atom(adapter) and not is_nil(adapter) and is_map(policy) do
    case definition_for_adapter(adapter, policy) do
      %AdapterDefinition{probe_module: probe_module, module: module} ->
        {:ok, probe_module || module}

      nil ->
        {:ok, adapter}
    end
  end

  def resolve_probe(_adapter, _policy), do: :error

  @spec materialize(DataSource.t(), atom() | nil) :: DataSource.t()
  def materialize(%DataSource{} = source, logical_source) do
    materialize(source, logical_source, default_policy())
  end

  @spec materialize(DataSource.t(), atom() | nil, policy()) :: DataSource.t()
  def materialize(%DataSource{} = source, logical_source, policy) do
    case resolve(source.adapter, logical_source, policy) do
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

  defp definition_for_adapter(adapter, policy) do
    Enum.find(list_definitions(policy), fn definition ->
      definition.logical_source == adapter or definition.module == adapter
    end)
  end
end
