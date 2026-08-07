defmodule Cadence.Dashboards.PlannedSourceRequest do
  @moduledoc """
  Logical source request planned by the dashboard engine.
  """

  alias Cadence.Dashboards.{
    DataContext,
    LimitContext,
    ScopeContext,
    TimeContext
  }

  alias Cadence.Dashboards.SourceRegistry.AdapterSelection
  alias Cadence.Platform.ContractNormalization

  @type consumer :: %{
          required(:placement_id) => binary(),
          required(:role) => atom(),
          required(:widget_type_id) => binary(),
          optional(:annotation_layer_ids) => [binary()]
        }

  @type source_dependency :: %{
          required(:logical_source) => atom(),
          required(:reason) => atom() | binary(),
          required(:products) => [atom()],
          optional(:sampling) => map()
        }

  @type t :: %__MODULE__{
          request_id: binary(),
          organization_id: binary() | nil,
          mission_id: binary() | nil,
          logical_source: atom() | nil,
          observables: [binary()],
          scope_context: ScopeContext.t(),
          time_context: TimeContext.t(),
          data_context: DataContext.t(),
          limit_context: LimitContext.t(),
          value_type: :engineering | :raw | nil,
          sampling: map(),
          source_dependencies: [source_dependency()],
          overlays: [atom()],
          consumers: [consumer()],
          metadata: map()
        }

  defstruct [
    :request_id,
    :organization_id,
    :mission_id,
    :logical_source,
    observables: [],
    scope_context: %ScopeContext{},
    time_context: %TimeContext{},
    data_context: %DataContext{},
    limit_context: %LimitContext{},
    value_type: nil,
    sampling: %{},
    source_dependencies: [],
    overlays: [],
    consumers: [],
    metadata: %{}
  ]

  @spec logical_sources() :: [atom()]
  def logical_sources, do: AdapterSelection.logical_sources()

  @spec logical_source?(term()) :: boolean()
  def logical_source?(logical_source), do: logical_source in logical_sources()

  @spec new(map() | t()) :: t()
  def new(attrs), do: normalize(attrs)

  @spec normalize(map() | t()) :: t()
  def normalize(%__MODULE__{} = request) do
    %__MODULE__{
      request
      | logical_source: normalize_logical_source(request.logical_source),
        observables: ContractNormalization.binary_list(request.observables),
        scope_context:
          ContractNormalization.normalize_context(request.scope_context, ScopeContext),
        time_context: ContractNormalization.normalize_context(request.time_context, TimeContext),
        data_context: ContractNormalization.normalize_context(request.data_context, DataContext),
        limit_context:
          ContractNormalization.normalize_context(request.limit_context, LimitContext),
        overlays: ContractNormalization.atom_list(request.overlays),
        source_dependencies: normalize_source_dependencies(request.source_dependencies),
        consumers: normalize_consumers(request.consumers),
        sampling: ContractNormalization.map_or_default(request.sampling),
        metadata: ContractNormalization.map_or_default(request.metadata)
    }
  end

  def normalize(request) when is_map(request) do
    %__MODULE__{
      request_id: ContractNormalization.attr(request, :request_id),
      organization_id: ContractNormalization.attr(request, :organization_id),
      mission_id: ContractNormalization.attr(request, :mission_id),
      logical_source:
        request
        |> ContractNormalization.attr(:logical_source)
        |> normalize_logical_source(),
      observables:
        request
        |> ContractNormalization.attr(:observables, [])
        |> ContractNormalization.binary_list(),
      scope_context:
        request
        |> ContractNormalization.attr(:scope_context, %{})
        |> ContractNormalization.normalize_context(ScopeContext),
      time_context:
        request
        |> ContractNormalization.attr(:time_context, %{})
        |> ContractNormalization.normalize_context(TimeContext),
      data_context:
        request
        |> ContractNormalization.attr(:data_context, %{})
        |> ContractNormalization.normalize_context(DataContext),
      limit_context:
        request
        |> ContractNormalization.attr(:limit_context, %{})
        |> ContractNormalization.normalize_context(LimitContext),
      value_type:
        request
        |> ContractNormalization.attr(:value_type)
        |> ContractNormalization.existing_atom(),
      sampling:
        request
        |> ContractNormalization.attr(:sampling, %{})
        |> ContractNormalization.map_or_default(),
      overlays:
        request
        |> ContractNormalization.attr(:overlays, [])
        |> ContractNormalization.atom_list(),
      source_dependencies:
        request
        |> ContractNormalization.attr(:source_dependencies, [])
        |> normalize_source_dependencies(),
      consumers:
        request
        |> ContractNormalization.attr(:consumers, [])
        |> normalize_consumers(),
      metadata:
        request
        |> ContractNormalization.attr(:metadata, %{})
        |> ContractNormalization.map_or_default()
    }
  end

  defp normalize_source_dependencies(dependencies) when is_list(dependencies) do
    Enum.map(dependencies, fn
      dependency when is_map(dependency) ->
        dependency
        |> Map.new(fn {key, value} -> {normalize_dependency_key(key), value} end)
        |> then(fn dependency ->
          dependency
          |> Map.update(
            :logical_source,
            nil,
            &normalize_logical_source/1
          )
          |> Map.update(:reason, nil, &ContractNormalization.existing_atom/1)
          |> Map.update(:products, [], &ContractNormalization.atom_list/1)
          |> Map.update(:sampling, %{}, &ContractNormalization.map_or_default/1)
        end)

      dependency ->
        dependency
    end)
  end

  defp normalize_source_dependencies(nil), do: []
  defp normalize_source_dependencies(dependencies), do: dependencies

  defp normalize_logical_source(logical_source) do
    ContractNormalization.known_atom(logical_source, logical_sources())
  end

  defp normalize_dependency_key(key) when is_atom(key), do: key
  defp normalize_dependency_key("logical_source"), do: :logical_source
  defp normalize_dependency_key("reason"), do: :reason
  defp normalize_dependency_key("products"), do: :products
  defp normalize_dependency_key("sampling"), do: :sampling
  defp normalize_dependency_key(key), do: key

  defp normalize_consumers(consumers) when is_list(consumers) do
    Enum.map(consumers, fn
      consumer when is_map(consumer) ->
        %{
          placement_id: ContractNormalization.attr(consumer, :placement_id),
          role:
            consumer
            |> ContractNormalization.attr(:role)
            |> ContractNormalization.existing_atom(),
          widget_type_id: ContractNormalization.attr(consumer, :widget_type_id),
          annotation_layer_ids:
            consumer
            |> ContractNormalization.attr(:annotation_layer_ids, [])
            |> ContractNormalization.binary_list()
        }

      consumer ->
        consumer
    end)
  end

  defp normalize_consumers(consumers), do: consumers
end
