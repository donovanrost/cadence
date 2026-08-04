defmodule Cadence.Dashboards.SourceRegistry.CapabilityPosture do
  @moduledoc """
  Builds request-local sampling, product, and time-axis compatibility posture.
  """

  alias Cadence.Dashboards.PlannedSourceRequest

  alias Cadence.DataSources.SourceCapabilities

  @spec build(PlannedSourceRequest.t(), SourceCapabilities.t()) :: map()
  def build(%PlannedSourceRequest{} = request, %SourceCapabilities{} = capabilities) do
    requested_sampling = Map.get(request.sampling || %{}, :mode)
    requested_products = requested_source_products(request, capabilities)
    requested_time_axis = requested_time_axis(request)

    unsupported =
      []
      |> maybe_add_unsupported_sampling(requested_sampling, capabilities)
      |> maybe_add_unsupported_products(requested_products, capabilities)
      |> maybe_add_unsupported_time_axis(
        request.logical_source,
        requested_time_axis,
        capabilities
      )

    fallbacks =
      []
      |> maybe_add_time_axis_fallback(request.logical_source, requested_time_axis, capabilities)

    status =
      cond do
        unsupported != [] -> :unsupported
        fallbacks != [] -> :fallback
        true -> :native
      end

    %{
      status: status,
      requested_sampling: requested_sampling,
      supported_sampling: capabilities.supported_sampling,
      requested_products: requested_products,
      supported_products: capabilities.supported_products,
      requested_time_axis: requested_time_axis,
      supported_time_axes: capabilities.supported_time_axes,
      fallbacks: fallbacks,
      unsupported: unsupported
    }
    |> maybe_put_executed_time_axis(requested_time_axis, fallbacks)
    |> Enum.reject(fn {_key, value} -> value in [nil, []] end)
    |> Map.new()
  end

  defp requested_source_products(
         %PlannedSourceRequest{logical_source: :operational_observables} = request,
         %SourceCapabilities{} = capabilities
       ) do
    request
    |> source_backing_contracts_for_request(capabilities)
    |> Enum.map(&Map.get(&1, :product))
    |> Enum.reject(&is_nil/1)
    |> Enum.uniq()
  end

  defp requested_source_products(%PlannedSourceRequest{} = request, _capabilities) do
    (request.sampling || %{})
    |> Map.get(:products, [])
    |> List.wrap()
  end

  defp source_backing_contracts_for_request(%PlannedSourceRequest{} = request, capabilities) do
    requested_observables = List.wrap(request.observables)
    requested_sampling = Map.get(request.sampling || %{}, :mode)

    capabilities
    |> source_backing_contracts()
    |> Enum.filter(fn contract ->
      observables = Map.get(contract, :observables, [])

      Map.get(contract, :sampling) == requested_sampling and
        requested_observables != [] and
        Enum.all?(requested_observables, &(&1 in observables))
    end)
    |> Enum.sort_by(fn contract -> contract |> Map.get(:observables, []) |> length() end)
    |> case do
      [contract | _rest] -> [contract]
      [] -> []
    end
  end

  defp source_backing_contracts(%SourceCapabilities{} = capabilities) do
    capabilities.metadata
    |> Map.get(:source_backing_contracts, [])
    |> List.wrap()
    |> Enum.filter(&is_map/1)
  end

  defp maybe_add_unsupported_sampling(unsupported, nil, %SourceCapabilities{}), do: unsupported

  defp maybe_add_unsupported_sampling(
         unsupported,
         requested_sampling,
         %SourceCapabilities{} = caps
       ) do
    if requested_sampling in caps.supported_sampling do
      unsupported
    else
      unsupported ++
        [
          %{
            capability: :sampling,
            requested: requested_sampling,
            supported: caps.supported_sampling,
            fallback: :none
          }
        ]
    end
  end

  defp maybe_add_unsupported_products(unsupported, [], %SourceCapabilities{}), do: unsupported

  defp maybe_add_unsupported_products(
         unsupported,
         requested_products,
         %SourceCapabilities{} = capabilities
       ) do
    supported_products = MapSet.new(supported_source_products(capabilities))
    missing = Enum.reject(requested_products, &MapSet.member?(supported_products, &1))

    case missing do
      [] ->
        unsupported

      missing ->
        unsupported ++
          [
            %{
              capability: :products,
              requested: requested_products,
              supported: capabilities.supported_products,
              missing: missing,
              fallback: :none
            }
          ]
    end
  end

  defp supported_source_products(%SourceCapabilities{} = capabilities) do
    capabilities.supported_products
    |> Kernel.++(supported_source_backing_products(capabilities))
    |> Enum.uniq()
  end

  defp supported_source_backing_products(%SourceCapabilities{} = capabilities) do
    capabilities
    |> source_backing_contracts()
    |> Enum.map(&Map.get(&1, :product))
    |> Enum.reject(&is_nil/1)
    |> Enum.filter(&source_backing_product_supported?(capabilities, &1))
    |> Enum.uniq()
  end

  defp source_backing_product_supported?(%SourceCapabilities{} = capabilities, product) do
    products = capabilities.supported_products

    product in products or
      (product in supported_source_products_for_aggregate(:operational_latest, capabilities) and
         :operational_latest in products) or
      (product in supported_source_products_for_aggregate(
         :operational_state_history,
         capabilities
       ) and
         :operational_state_history in products) or
      (product in supported_source_products_for_aggregate(
         :operational_metric_history,
         capabilities
       ) and
         :operational_metric_history in products)
  end

  defp supported_source_products_for_aggregate(
         aggregate_product,
         %SourceCapabilities{} = capabilities
       ) do
    capabilities
    |> source_backing_contracts()
    |> Enum.filter(&(Map.get(&1, :product) == aggregate_product))
    |> Enum.flat_map(fn aggregate_contract ->
      aggregate_observables = Map.get(aggregate_contract, :observables, [])
      aggregate_sampling = Map.get(aggregate_contract, :sampling)

      capabilities
      |> source_backing_contracts()
      |> Enum.filter(fn contract ->
        Map.get(contract, :sampling) == aggregate_sampling and
          Enum.all?(Map.get(contract, :observables, []), &(&1 in aggregate_observables))
      end)
      |> Enum.map(&Map.get(&1, :product))
    end)
    |> Enum.reject(&is_nil/1)
    |> Enum.uniq()
  end

  defp maybe_add_unsupported_time_axis(unsupported, logical_source, requested_axis, caps) do
    cond do
      requested_axis in [nil | caps.supported_time_axes] ->
        unsupported

      telemetry_receipt_time_fallback?(logical_source, requested_axis, caps) ->
        unsupported

      caps.supported_time_axes == [] ->
        unsupported

      true ->
        unsupported ++
          [
            %{
              capability: :time_axis,
              requested: requested_axis,
              supported: caps.supported_time_axes,
              fallback: :none
            }
          ]
    end
  end

  defp maybe_add_time_axis_fallback(fallbacks, logical_source, requested_axis, caps) do
    if telemetry_receipt_time_fallback?(logical_source, requested_axis, caps) do
      fallbacks ++
        [
          %{
            capability: :time_axis,
            requested: requested_axis,
            executed: :receipt_time,
            supported: caps.supported_time_axes,
            reason: :unsupported_time_axis
          }
        ]
    else
      fallbacks
    end
  end

  defp telemetry_receipt_time_fallback?(:telemetry, requested_axis, %SourceCapabilities{} = caps) do
    not is_nil(requested_axis) and requested_axis not in caps.supported_time_axes and
      :receipt_time in caps.supported_time_axes
  end

  defp telemetry_receipt_time_fallback?(_logical_source, _requested_axis, %SourceCapabilities{}),
    do: false

  defp maybe_put_executed_time_axis(posture, nil, _fallbacks), do: posture

  defp maybe_put_executed_time_axis(posture, requested_axis, fallbacks) do
    executed_axis =
      fallbacks
      |> Enum.find_value(fn
        %{capability: :time_axis, executed: executed} -> executed
        _fallback -> nil
      end)
      |> Kernel.||(requested_axis)

    Map.put(posture, :executed_time_axis, executed_axis)
  end

  defp requested_time_axis(%PlannedSourceRequest{} = request) do
    request.time_context
    |> get_attr(:axis)
    |> normalize_time_axis()
  end

  defp normalize_time_axis(:generation_time), do: :generation_time
  defp normalize_time_axis(:receipt_time), do: :receipt_time
  defp normalize_time_axis(:occurred_at), do: :occurred_at
  defp normalize_time_axis("generation_time"), do: :generation_time
  defp normalize_time_axis("generation-time"), do: :generation_time
  defp normalize_time_axis("receipt_time"), do: :receipt_time
  defp normalize_time_axis("receipt-time"), do: :receipt_time
  defp normalize_time_axis("occurred_at"), do: :occurred_at
  defp normalize_time_axis("occurred-at"), do: :occurred_at
  defp normalize_time_axis(_axis), do: nil

  defp get_attr(%_{} = attrs, key) when is_atom(key) do
    attrs
    |> Map.from_struct()
    |> get_attr(key)
  end

  defp get_attr(attrs, key) when is_map(attrs) and is_atom(key) do
    Map.get(attrs, key, Map.get(attrs, Atom.to_string(key)))
  end

  defp get_attr(_attrs, _key), do: nil
end
