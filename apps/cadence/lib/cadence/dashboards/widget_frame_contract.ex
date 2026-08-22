defmodule Cadence.Dashboards.WidgetFrameContract do
  @moduledoc """
  Resolves widget primary frame contracts against a placement binding.

  The registry owns the frame shapes a widget can consume. Bindings may select a
  different logical source only when the frame contract declares that override.
  """

  alias Cadence.Dashboards.{OperationalObservable, WidgetType}

  @supported_sources [:telemetry, :operational_observables]
  @scope_kinds [
    :mission,
    :spacecraft,
    :contact,
    :ground_station,
    :source_endpoint,
    :transport,
    :link
  ]

  @spec primary_frame_specs(WidgetType.t(), map()) :: {:ok, [map()]} | {:error, map()}
  def primary_frame_specs(%WidgetType{} = widget_type, binding) when is_map(binding) do
    widget_type.data_contract
    |> Map.get(:frames, [])
    |> Enum.filter(&(Map.get(&1, :role, :primary) == :primary))
    |> Enum.reduce_while({:ok, []}, fn frame_spec, {:ok, frame_specs} ->
      case effective_frame_spec(widget_type, frame_spec, binding) do
        {:ok, effective_frame_spec} ->
          {:cont, {:ok, frame_specs ++ [effective_frame_spec]}}

        {:error, details} ->
          {:halt, {:error, details}}
      end
    end)
  end

  def primary_frame_specs(%WidgetType{} = widget_type, _binding),
    do: primary_frame_specs(widget_type, %{})

  @spec primary_supported_sources(WidgetType.t()) :: [atom()]
  def primary_supported_sources(%WidgetType{} = widget_type) do
    widget_type.data_contract
    |> Map.get(:frames, [])
    |> Enum.filter(&(Map.get(&1, :role, :primary) == :primary))
    |> Enum.flat_map(&supported_sources/1)
    |> Enum.uniq()
    |> order_sources()
  end

  @spec supports_primary_source?(WidgetType.t(), atom() | binary()) :: boolean()
  def supports_primary_source?(%WidgetType{} = widget_type, source) do
    normalize_source(source) in primary_supported_sources(widget_type)
  end

  @spec operational_observable_supported?(WidgetType.t(), OperationalObservable.t()) :: boolean()
  def operational_observable_supported?(
        %WidgetType{} = widget_type,
        %OperationalObservable{} = observable
      ) do
    constraints = operational_observable_constraints(widget_type)

    constraints.products != [] and
      observable_dashboard_product(observable) in constraints.products and
      (constraints.value_kinds == [] or observable.value_kind in constraints.value_kinds)
  end

  @spec operational_observable_constraints(WidgetType.t()) :: %{
          products: [atom()],
          value_kinds: [atom()]
        }
  def operational_observable_constraints(%WidgetType{} = widget_type) do
    case primary_frame_specs(widget_type, %{source: :operational_observables}) do
      {:ok, frame_specs} ->
        frame_specs
        |> Enum.filter(&(Map.get(&1, :source) == :operational_observables))
        |> Enum.reduce(%{products: [], value_kinds: []}, fn frame_spec, acc ->
          %{
            products: acc.products ++ Map.get(frame_spec, :products, []),
            value_kinds: acc.value_kinds ++ Map.get(frame_spec, :observable_value_kinds, [])
          }
        end)
        |> Map.update!(:products, &Enum.uniq/1)
        |> Map.update!(:value_kinds, &Enum.uniq/1)

      {:error, _details} ->
        %{products: [], value_kinds: []}
    end
  end

  @spec operational_observable_scopes(OperationalObservable.t() | binary()) :: [atom()]
  def operational_observable_scopes(%OperationalObservable{} = observable) do
    [observable.primary_scope | observable.optional_scopes]
    |> Enum.map(&normalize_scope_kind/1)
    |> Enum.reject(&is_nil/1)
    |> Enum.uniq()
  end

  def operational_observable_scopes(observable_id) when is_binary(observable_id) do
    case OperationalObservable.fetch(observable_id) do
      {:ok, observable} -> operational_observable_scopes(observable)
      {:error, _reason} -> []
    end
  end

  @spec supported_operational_observable_scopes([binary()]) :: %{optional(binary()) => [atom()]}
  def supported_operational_observable_scopes(observable_ids) when is_list(observable_ids) do
    observable_ids
    |> Enum.uniq()
    |> Map.new(&{&1, operational_observable_scopes(&1)})
  end

  @spec unsupported_operational_observable_scope_ids([binary()], atom() | binary() | nil) :: [
          binary()
        ]
  def unsupported_operational_observable_scope_ids(_observable_ids, nil), do: []

  def unsupported_operational_observable_scope_ids(observable_ids, scope_kind)
      when is_list(observable_ids) do
    case normalize_scope_kind(scope_kind) do
      nil ->
        []

      normalized_scope_kind ->
        Enum.filter(observable_ids, fn observable_id ->
          normalized_scope_kind not in operational_observable_scopes(observable_id)
        end)
    end
  end

  @spec supported_sources(map()) :: [atom()]
  def supported_sources(frame_spec) when is_map(frame_spec) do
    frame_spec
    |> source_overrides()
    |> Enum.map(&Map.fetch!(&1, :source))
    |> Kernel.++([Map.fetch!(frame_spec, :source)])
    |> Enum.uniq()
  end

  defp effective_frame_spec(%WidgetType{} = widget_type, frame_spec, binding) do
    default_source = Map.fetch!(frame_spec, :source)
    requested_source = requested_source(binding, frame_spec)

    case effective_source_frame_spec(frame_spec, requested_source, default_source) do
      {:ok, effective_frame_spec} ->
        validate_frame_observables(widget_type, effective_frame_spec, binding)

      {:error, details} ->
        {:error, contract_error_details(widget_type, frame_spec, details)}
    end
  end

  defp effective_source_frame_spec(frame_spec, requested_source, default_source) do
    cond do
      requested_source == default_source ->
        {:ok, normalize_frame_spec(frame_spec)}

      override = source_override(frame_spec, requested_source) ->
        {:ok,
         frame_spec
         |> Map.merge(override)
         |> Map.put(:role, Map.get(frame_spec, :role, :primary))
         |> Map.put(:contract_source, default_source)
         |> normalize_frame_spec()}

      true ->
        {:error,
         %{
           requested_source: requested_source,
           contract_source: default_source,
           supported_sources: supported_sources(frame_spec)
         }}
    end
  end

  defp validate_frame_observables(
         %WidgetType{} = widget_type,
         %{source: :operational_observables} = frame_spec,
         binding
       ) do
    observables = binding |> Map.get(:observables, []) |> List.wrap()
    constraints = frame_observable_constraints(frame_spec)
    unsupported = unsupported_operational_observable_ids(observables, constraints)

    if unsupported == [] do
      {:ok, frame_spec}
    else
      {:error,
       contract_error_details(widget_type, frame_spec, %{
         requested_source: :operational_observables,
         requested_observables: observables,
         unsupported_observables: unsupported,
         supported_products: constraints.products,
         supported_value_kinds: constraints.value_kinds,
         requested_products: requested_observable_products(observables),
         requested_value_kinds: requested_observable_value_kinds(observables)
       })}
    end
  end

  defp validate_frame_observables(_widget_type, frame_spec, _binding), do: {:ok, frame_spec}

  defp unsupported_operational_observable_ids(observable_ids, constraints) do
    Enum.filter(observable_ids, fn observable_id ->
      case OperationalObservable.fetch(observable_id) do
        {:ok, observable} ->
          not operational_observable_matches_constraints?(observable, constraints)

        {:error, _reason} ->
          true
      end
    end)
  end

  defp operational_observable_matches_constraints?(
         %OperationalObservable{} = observable,
         constraints
       ) do
    observable_dashboard_product(observable) in constraints.products and
      (constraints.value_kinds == [] or observable.value_kind in constraints.value_kinds)
  end

  defp requested_observable_products(observable_ids) do
    observable_ids
    |> Enum.flat_map(fn observable_id ->
      case OperationalObservable.fetch(observable_id) do
        {:ok, observable} -> [observable_dashboard_product(observable)]
        {:error, _reason} -> []
      end
    end)
    |> Enum.uniq()
  end

  defp requested_observable_value_kinds(observable_ids) do
    observable_ids
    |> Enum.flat_map(fn observable_id ->
      case OperationalObservable.fetch(observable_id) do
        {:ok, observable} -> [observable.value_kind]
        {:error, _reason} -> []
      end
    end)
    |> Enum.uniq()
  end

  defp contract_error_details(%WidgetType{} = widget_type, frame_spec, details) do
    constraints = frame_observable_constraints(frame_spec)

    %{
      widget_type_id: widget_type.widget_type_id,
      widget_type_version: widget_type.version,
      role: Map.get(frame_spec, :role, :primary),
      requested_source: Map.get(details, :requested_source),
      contract_source: Map.get(details, :contract_source, Map.get(frame_spec, :contract_source)),
      supported_sources: Map.get(details, :supported_sources, [Map.get(frame_spec, :source)]),
      accepted_shapes: Map.get(frame_spec, :accepted_shapes, []),
      products: constraints.products,
      observable_value_kinds: constraints.value_kinds
    }
    |> Map.merge(details)
  end

  defp frame_observable_constraints(frame_spec) do
    %{
      products: Map.get(frame_spec, :products, []),
      value_kinds: Map.get(frame_spec, :observable_value_kinds, [])
    }
  end

  defp requested_source(binding, frame_spec) do
    default_source = Map.fetch!(frame_spec, :source)

    case normalize_source(Map.get(binding, :source)) do
      nil ->
        default_source

      :telemetry when default_source != :telemetry ->
        if default_operational_binding?(binding, frame_spec), do: default_source, else: :telemetry

      source ->
        source
    end
  end

  defp normalize_scope_kind(scope_kind) when is_atom(scope_kind) do
    if scope_kind in @scope_kinds, do: scope_kind
  end

  defp normalize_scope_kind(scope_kind) when is_binary(scope_kind) do
    normalized =
      scope_kind
      |> String.trim()
      |> String.downcase()
      |> String.replace("-", "_")

    Enum.find(@scope_kinds, &(Atom.to_string(&1) == normalized))
  end

  defp normalize_scope_kind(_scope_kind), do: nil

  defp default_operational_binding?(binding, frame_spec) do
    Map.get(binding, :observables, []) == [] and
      Map.get(binding, :sampling) in [nil, Map.get(frame_spec, :sampling)]
  end

  defp source_override(frame_spec, requested_source) do
    frame_spec
    |> source_overrides()
    |> Enum.find(&(Map.get(&1, :source) == requested_source))
  end

  defp source_overrides(frame_spec) do
    frame_spec
    |> Map.get(:source_overrides, [])
    |> Enum.map(&normalize_frame_spec/1)
  end

  defp normalize_frame_spec(frame_spec) when is_map(frame_spec) do
    frame_spec
    |> Map.update(:source, nil, &normalize_source/1)
    |> Map.update(:accepted_shapes, [], &normalize_atom_list/1)
    |> Map.update(:products, [], &normalize_atom_list/1)
    |> Map.update(:observable_value_kinds, [], &normalize_atom_list/1)
  end

  defp normalize_source(source) when source in @supported_sources, do: source

  defp normalize_source(source) when is_binary(source) do
    source
    |> String.replace("-", "_")
    |> String.to_existing_atom()
    |> normalize_source()
  rescue
    ArgumentError -> source
  end

  defp normalize_source(source), do: source

  defp normalize_atom_list(values) when is_list(values) do
    Enum.map(values, fn
      value when is_atom(value) ->
        value

      value when is_binary(value) ->
        value
        |> String.replace("-", "_")
        |> String.to_existing_atom()

      value ->
        value
    end)
  end

  defp normalize_atom_list(value), do: List.wrap(value)

  defp order_sources(sources) do
    Enum.filter([:telemetry, :operational_observables], &(&1 in sources)) ++
      Enum.reject(sources, &(&1 in [:telemetry, :operational_observables]))
  end

  defp observable_dashboard_product(%OperationalObservable{observable_id: "contacts.phase"}),
    do: :contacts_phase

  defp observable_dashboard_product(%OperationalObservable{
         observable_id: "comms.transport.downlink_bitrate"
       }),
       do: :transport_bitrate

  defp observable_dashboard_product(%OperationalObservable{
         observable_id: "comms.transport.uplink_bitrate"
       }),
       do: :transport_bitrate

  defp observable_dashboard_product(%OperationalObservable{
         observable_id: "comms.transport.connection_state"
       }),
       do: :connection_state

  defp observable_dashboard_product(%OperationalObservable{
         observable_id: "ground.station.connection_state"
       }),
       do: :connection_state

  defp observable_dashboard_product(%OperationalObservable{
         observable_id: "comms.transport.execution_state"
       }),
       do: :transport_execution_state

  defp observable_dashboard_product(%OperationalObservable{} = observable), do: observable.product
end
