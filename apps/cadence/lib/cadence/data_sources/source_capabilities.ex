defmodule Cadence.DataSources.SourceCapabilities do
  @moduledoc """
  Capability contract advertised by Data Source adapters.

  The planner uses this to decide whether it can emit a truthful source request.
  `SourceRegistry.capabilities/2` can layer physical data-source capabilities on
  top of this adapter-level contract for request-aware planning.
  """

  alias Cadence.DataSources.AdapterRegistry
  alias Cadence.Platform.ContractNormalization
  @frame_shapes [:scalar, :wide, :long, :events, :intervals, :matrix]
  @time_axes [:generation_time, :receipt_time, :occurred_at]

  @type t :: %__MODULE__{
          logical_source: atom(),
          supported_sampling: [atom()],
          supported_products: [atom()],
          annotation_products: [atom()],
          supported_time_axes: [atom()],
          supported_value_types: [atom()],
          supported_shapes: [atom()],
          supports_watermarks?: boolean(),
          completeness: :known | :unknown | :partial,
          metadata: map()
        }

  defstruct [
    :logical_source,
    supported_sampling: [],
    supported_products: [],
    annotation_products: [],
    supported_time_axes: [],
    supported_value_types: [],
    supported_shapes: [],
    supports_watermarks?: false,
    completeness: :unknown,
    metadata: %{}
  ]

  @completeness_values [:known, :unknown, :partial]

  @spec completeness_values() :: [:known | :unknown | :partial]
  def completeness_values, do: @completeness_values

  @spec new(map() | t(), keyword()) :: t()
  def new(attrs, opts \\ []), do: normalize(attrs, opts)

  @spec normalize(map() | t(), keyword()) :: t() | nil
  def normalize(capabilities, opts \\ [])

  def normalize(%__MODULE__{} = capabilities, opts) do
    %__MODULE__{
      capabilities
      | logical_source:
          ContractNormalization.known_atom(
            capabilities.logical_source,
            adapter_logical_sources(opts)
          ),
        supported_sampling: ContractNormalization.atom_list(capabilities.supported_sampling),
        supported_products: ContractNormalization.atom_list(capabilities.supported_products),
        annotation_products: ContractNormalization.atom_list(capabilities.annotation_products),
        supported_time_axes:
          normalize_known_atom_list(capabilities.supported_time_axes, @time_axes),
        supported_value_types:
          normalize_known_atom_list(capabilities.supported_value_types, [:raw, :engineering]),
        supported_shapes: normalize_known_atom_list(capabilities.supported_shapes, @frame_shapes),
        supports_watermarks?: normalize_boolean(capabilities.supports_watermarks?),
        completeness:
          ContractNormalization.known_atom(capabilities.completeness, @completeness_values),
        metadata: ContractNormalization.map_or_default(capabilities.metadata)
    }
  end

  def normalize(capabilities, opts) when is_map(capabilities) do
    %__MODULE__{
      logical_source:
        capabilities
        |> ContractNormalization.attr(:logical_source)
        |> ContractNormalization.known_atom(adapter_logical_sources(opts)),
      supported_sampling:
        capabilities
        |> ContractNormalization.attr(:supported_sampling, [])
        |> ContractNormalization.atom_list(),
      supported_products:
        capabilities
        |> ContractNormalization.attr(:supported_products, [])
        |> ContractNormalization.atom_list(),
      annotation_products:
        capabilities
        |> ContractNormalization.attr(:annotation_products, [])
        |> ContractNormalization.atom_list(),
      supported_time_axes:
        capabilities
        |> ContractNormalization.attr(:supported_time_axes, [])
        |> normalize_known_atom_list(@time_axes),
      supported_value_types:
        capabilities
        |> ContractNormalization.attr(:supported_value_types, [])
        |> normalize_known_atom_list([:raw, :engineering]),
      supported_shapes:
        capabilities
        |> ContractNormalization.attr(:supported_shapes, [])
        |> normalize_known_atom_list(@frame_shapes),
      supports_watermarks?:
        capabilities
        |> ContractNormalization.attr(:supports_watermarks?, false)
        |> normalize_boolean(),
      completeness:
        capabilities
        |> ContractNormalization.attr(:completeness, :unknown)
        |> ContractNormalization.known_atom(@completeness_values),
      metadata:
        capabilities
        |> ContractNormalization.attr(:metadata, %{})
        |> ContractNormalization.map_or_default()
    }
  end

  def normalize(_other, _opts), do: nil

  @spec supports_sampling?(t(), atom()) :: boolean()
  def supports_sampling?(%__MODULE__{} = capabilities, mode) do
    modes = normalize(capabilities).supported_sampling
    mode in modes
  end

  @spec with_data_source_capabilities(t(), map() | struct() | nil) :: t()
  def with_data_source_capabilities(%__MODULE__{} = capabilities, data_source) do
    physical_capabilities = Map.get(data_source || %{}, :capabilities, %{})

    capabilities
    |> maybe_set_latest(physical_capabilities)
    |> maybe_set_range_scan(physical_capabilities)
    |> maybe_set_products(physical_capabilities)
    |> maybe_set_time_axes(physical_capabilities)
    |> maybe_add_native_decimation(physical_capabilities)
    |> maybe_set_definition_intervals(physical_capabilities)
    |> maybe_set_watermarks(physical_capabilities)
    |> put_in([Access.key!(:metadata), :data_source_capabilities], physical_capabilities)
    |> normalize()
  end

  defp normalize_known_atom_list(values, known_values) when is_list(values) do
    Enum.map(values, &ContractNormalization.known_atom(&1, known_values))
  end

  defp normalize_known_atom_list(nil, _known_values), do: []
  defp normalize_known_atom_list(values, _known_values), do: values

  defp normalize_boolean(value) when is_boolean(value), do: value
  defp normalize_boolean("true"), do: true
  defp normalize_boolean("false"), do: false
  defp normalize_boolean(value), do: value

  defp adapter_logical_sources(opts) do
    policy =
      Keyword.get_lazy(opts, :data_source_adapter_policy, &AdapterRegistry.default_policy/0)

    AdapterRegistry.logical_sources(policy)
  end

  defp maybe_set_latest(%__MODULE__{} = capabilities, physical_capabilities) do
    case capability_value(physical_capabilities, :latest?) do
      false -> remove_sampling(capabilities, [:latest])
      _other -> capabilities
    end
  end

  defp maybe_set_range_scan(%__MODULE__{} = capabilities, physical_capabilities) do
    if capability_value(physical_capabilities, :range_scan?) == false or
         capability_value(physical_capabilities, :bounded_history?) == false do
      remove_sampling(capabilities, [:raw_series, :bounded_history, :bounded_raw_series])
    else
      capabilities
    end
  end

  defp maybe_set_time_axes(%__MODULE__{} = capabilities, physical_capabilities) do
    case capability_value(physical_capabilities, :supported_time_axes) do
      axes when is_list(axes) ->
        supported_axes =
          axes
          |> normalize_known_atom_list(@time_axes)
          |> Enum.filter(&(&1 in capabilities.supported_time_axes))

        %{capabilities | supported_time_axes: supported_axes}

      _other ->
        capabilities
    end
  end

  defp maybe_set_products(%__MODULE__{} = capabilities, physical_capabilities) do
    case capability_value(physical_capabilities, :supported_products) do
      products when is_list(products) ->
        supported_products =
          products
          |> ContractNormalization.atom_list()
          |> Enum.filter(&(&1 in capabilities.supported_products))

        %{
          capabilities
          | supported_products: supported_products,
            annotation_products:
              Enum.filter(capabilities.annotation_products, &(&1 in supported_products))
        }

      _other ->
        capabilities
    end
  end

  defp maybe_add_native_decimation(%__MODULE__{} = capabilities, physical_capabilities) do
    if capability_value(physical_capabilities, :native_decimation?) do
      add_sampling(capabilities, [:decimated_envelope])
    else
      capabilities
    end
  end

  defp maybe_set_definition_intervals(
         %__MODULE__{logical_source: :limits} = capabilities,
         physical_capabilities
       ) do
    case capability_value(physical_capabilities, :definition_intervals?) do
      false ->
        capabilities
        |> remove_sampling([:definition_intervals])
        |> remove_products([:definition_intervals])
        |> remove_shapes([:intervals])

      _other ->
        capabilities
    end
  end

  defp maybe_set_definition_intervals(%__MODULE__{} = capabilities, _physical_capabilities),
    do: capabilities

  defp maybe_set_watermarks(%__MODULE__{} = capabilities, physical_capabilities) do
    case capability_value(physical_capabilities, :watermarks?) do
      true -> %{capabilities | supports_watermarks?: true}
      false -> %{capabilities | supports_watermarks?: false}
      _other -> capabilities
    end
  end

  defp add_sampling(%__MODULE__{} = capabilities, modes) do
    %{capabilities | supported_sampling: Enum.uniq(capabilities.supported_sampling ++ modes)}
  end

  defp remove_sampling(%__MODULE__{} = capabilities, modes) do
    %{capabilities | supported_sampling: capabilities.supported_sampling -- modes}
  end

  defp remove_products(%__MODULE__{} = capabilities, products) do
    %{capabilities | supported_products: capabilities.supported_products -- products}
  end

  defp remove_shapes(%__MODULE__{} = capabilities, shapes) do
    %{capabilities | supported_shapes: capabilities.supported_shapes -- shapes}
  end

  defp capability_value(capabilities, key) when is_map(capabilities) and is_atom(key) do
    Map.get(capabilities, key, Map.get(capabilities, Atom.to_string(key)))
  end

  defp capability_value(_capabilities, _key), do: nil
end
