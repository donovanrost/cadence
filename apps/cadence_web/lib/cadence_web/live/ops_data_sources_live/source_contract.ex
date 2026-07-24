defmodule CadenceWeb.OpsDataSourcesLive.SourceContract do
  @moduledoc """
  Source compatibility and dashboard focus contract evaluation for the data sources page.
  """

  alias Cadence.Dashboards.{DataBinding, DataSource, DefaultSourceAdapters, SourceCapabilities}

  @spec compatible_sources([DataSource.t()], DataBinding.t()) :: [DataSource.t()]
  def compatible_sources(sources, %DataBinding{} = binding) when is_list(sources) do
    sources
    |> Enum.filter(&compatible?(&1, binding))
    |> Enum.sort_by(& &1.data_source_id)
  end

  @spec satisfies_focus?(DataSource.t(), map()) :: boolean()
  def satisfies_focus?(%DataSource{} = source, focus) when is_map(focus) do
    missing_requirements(source, focus) == []
  end

  @spec missing_requirements(DataSource.t(), map()) :: [{atom(), [binary()]}]
  def missing_requirements(%DataSource{} = source, focus) when is_map(focus) do
    case effective_capabilities(source) do
      %SourceCapabilities{} = capabilities ->
        [
          missing_capability(
            :sampling,
            requested_values(focus.requested_sampling),
            capabilities.supported_sampling
          ),
          missing_capability(
            :source_products,
            requested_product_values(focus),
            supported_products(capabilities)
          ),
          missing_capability(
            :product_families,
            requested_values(focus.requested_product_families),
            supported_product_families(capabilities)
          ),
          missing_capability(
            :value_kinds,
            requested_values(focus.requested_value_kinds),
            capabilities.supported_value_types
          ),
          missing_capability(
            :shapes,
            requested_values(focus.requested_shapes),
            capabilities.supported_shapes
          ),
          missing_capability(
            :time_axes,
            requested_values(focus.requested_time_axes),
            capabilities.supported_time_axes
          )
        ]
        |> Enum.reject(&is_nil/1)

      nil ->
        [{:capabilities, ["unknown"]}]
    end
  end

  @spec effective_capabilities(DataSource.t()) :: SourceCapabilities.t() | nil
  def effective_capabilities(%DataSource{adapter: adapter} = source) when is_atom(adapter) do
    with {:ok, adapter_module} <- DefaultSourceAdapters.resolve(adapter),
         {:module, ^adapter_module} <- Code.ensure_loaded(adapter_module),
         true <- function_exported?(adapter_module, :capabilities, 0),
         %SourceCapabilities{} = capabilities <-
           SourceCapabilities.normalize(adapter_module.capabilities()) do
      SourceCapabilities.with_data_source_capabilities(capabilities, source)
    else
      _other -> nil
    end
  end

  def effective_capabilities(%DataSource{}), do: nil

  @spec logical_source(DataSource.t()) :: atom() | nil
  def logical_source(%DataSource{adapter: adapter}),
    do: DefaultSourceAdapters.logical_source(adapter)

  @spec logical_source_text(DataSource.t()) :: binary()
  def logical_source_text(%DataSource{} = source), do: text(logical_source(source))

  @spec supported_product_families(SourceCapabilities.t()) :: [atom()]
  def supported_product_families(%SourceCapabilities{} = capabilities) do
    capabilities
    |> backing_contracts()
    |> Enum.filter(fn contract ->
      backing_product_supported?(capabilities, Map.get(contract, :product))
    end)
    |> Enum.map(&Map.get(&1, :product_family))
    |> Enum.reject(&is_nil/1)
    |> Enum.uniq()
  end

  @spec supported_metric_history_products(SourceCapabilities.t()) :: [atom()]
  def supported_metric_history_products(%SourceCapabilities{} = capabilities) do
    capabilities
    |> backing_contracts()
    |> Enum.filter(&(Map.get(&1, :sampling) == :raw_series))
    |> Enum.map(&Map.get(&1, :product))
    |> Enum.reject(&is_nil/1)
    |> Enum.filter(&backing_product_supported?(capabilities, &1))
    |> Enum.uniq()
  end

  defp compatible?(%DataSource{} = source, %DataBinding{} = binding) do
    DataSource.active?(source) and logical_source(source) == binding.logical_source
  end

  defp missing_capability(_field, [], _supported), do: nil

  defp missing_capability(field, requested, supported) do
    supported = MapSet.new(Enum.map(supported, &text/1))
    missing = Enum.reject(requested, &MapSet.member?(supported, &1))

    case missing do
      [] -> nil
      missing -> {field, missing}
    end
  end

  defp requested_values(nil), do: []

  defp requested_values(value) when is_binary(value) do
    value
    |> String.split(",", trim: true)
    |> Enum.map(&String.trim/1)
    |> Enum.reject(&(&1 == ""))
  end

  defp requested_values(value), do: [text(value)]

  defp requested_product_values(focus) do
    case requested_values(focus.requested_source_products) do
      [] -> requested_values(focus.requested_products)
      values -> values
    end
  end

  defp supported_products(%SourceCapabilities{} = capabilities) do
    capabilities.supported_products
    |> Kernel.++(supported_backing_products(capabilities))
    |> Enum.uniq()
  end

  defp supported_backing_products(%SourceCapabilities{} = capabilities) do
    capabilities
    |> backing_contracts()
    |> Enum.map(&Map.get(&1, :product))
    |> Enum.reject(&is_nil/1)
    |> Enum.filter(&backing_product_supported?(capabilities, &1))
    |> Enum.uniq()
  end

  defp backing_contracts(%SourceCapabilities{} = capabilities) do
    capabilities.metadata
    |> metadata_value(:source_backing_contracts)
    |> List.wrap()
    |> Enum.filter(&is_map/1)
  end

  defp backing_product_supported?(%SourceCapabilities{} = capabilities, product) do
    products = capabilities.supported_products

    product in products or
      (product in supported_products_for_aggregate(:operational_latest, capabilities) and
         :operational_latest in products) or
      (product in supported_products_for_aggregate(
         :operational_state_history,
         capabilities
       ) and
         :operational_state_history in products) or
      (product in supported_products_for_aggregate(
         :operational_metric_history,
         capabilities
       ) and
         :operational_metric_history in products)
  end

  defp supported_products_for_aggregate(
         aggregate_product,
         %SourceCapabilities{} = capabilities
       ) do
    capabilities
    |> backing_contracts()
    |> Enum.filter(&(Map.get(&1, :product) == aggregate_product))
    |> Enum.flat_map(fn aggregate_contract ->
      aggregate_observables = Map.get(aggregate_contract, :observables, [])
      aggregate_sampling = Map.get(aggregate_contract, :sampling)

      capabilities
      |> backing_contracts()
      |> Enum.filter(fn contract ->
        Map.get(contract, :sampling) == aggregate_sampling and
          Enum.all?(Map.get(contract, :observables, []), &(&1 in aggregate_observables))
      end)
      |> Enum.map(&Map.get(&1, :product))
    end)
    |> Enum.reject(&is_nil/1)
    |> Enum.uniq()
  end

  defp metadata_value(metadata, key) when is_map(metadata) and is_atom(key) do
    Map.get(metadata, key, Map.get(metadata, Atom.to_string(key)))
  end

  defp metadata_value(_metadata, _key), do: nil

  defp text(nil), do: "none"
  defp text(value) when is_atom(value), do: Atom.to_string(value)
  defp text(value) when is_binary(value), do: value
  defp text(value), do: to_string(value)
end
