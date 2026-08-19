defmodule Cadence.Dashboards.SourceRegistry.AdapterSelection do
  @moduledoc """
  Selects default, overridden, or binding-owned source adapters.
  """

  alias Cadence.Dashboards.ResolvedSourceBinding

  alias Cadence.DataSources.AdapterRegistry

  @type adapter :: module()

  @spec logical_sources() :: [atom()]
  def logical_sources, do: logical_sources([])

  @spec logical_sources(keyword()) :: [atom()]
  def logical_sources(opts) when is_list(opts) do
    opts |> adapter_policy() |> AdapterRegistry.logical_sources()
  end

  @spec for_logical_source(atom(), keyword()) :: {:ok, adapter()} | :error
  def for_logical_source(logical_source, opts) when is_atom(logical_source) and is_list(opts) do
    adapters = Keyword.get(opts, :adapters, %{})

    case Map.fetch(adapters, logical_source) do
      {:ok, adapter} when is_atom(adapter) -> {:ok, adapter}
      :error -> AdapterRegistry.fetch(logical_source, adapter_policy(opts))
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
        AdapterRegistry.resolve(
          resolved_binding.data_source.adapter,
          logical_source,
          adapter_policy(opts)
        )
    end
  end

  defp adapter_policy(opts) do
    Keyword.get_lazy(opts, :data_source_adapter_policy, &AdapterRegistry.default_policy/0)
  end
end
