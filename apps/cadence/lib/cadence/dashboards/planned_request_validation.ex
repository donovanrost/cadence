defmodule Cadence.Dashboards.PlannedRequestValidation do
  @moduledoc """
  Validates planned dashboard source requests against scope and source capabilities.

  The dashboard engine remains responsible for assembling requests. This module
  owns the policy that decides whether those requests can be executed and builds
  the placement-scoped warnings used when they cannot.
  """

  alias Cadence.Dashboards.{
    DataLinks,
    Placement,
    PlannedSourceRequest,
    ResolveWarning,
    ScopeContext,
    SourceRegistry,
    WidgetFrameContract
  }

  alias Cadence.DataSources.SourceCapabilities

  @known_scope_kinds [
    :mission,
    :spacecraft,
    :contact,
    :ground_station,
    :source_endpoint,
    :transport,
    :link
  ]

  @spec validate_primary(
          PlannedSourceRequest.t(),
          Placement.t(),
          map(),
          keyword()
        ) ::
          {:ok, PlannedSourceRequest.t()} | {:warning, ResolveWarning.t()}
  def validate_primary(
        %PlannedSourceRequest{} = request,
        %Placement{} = placement,
        frame_spec,
        registry_opts
      )
      when is_map(frame_spec) and is_list(registry_opts) do
    case validate_observable_scope(request, placement, frame_spec) do
      {:ok, request} ->
        validate_capability(request, placement, frame_spec, registry_opts)

      {:warning, %ResolveWarning{} = warning} ->
        {:warning, warning}
    end
  end

  @spec validate_capability(
          PlannedSourceRequest.t(),
          Placement.t(),
          map(),
          keyword()
        ) ::
          {:ok, PlannedSourceRequest.t()} | {:warning, ResolveWarning.t()}
  def validate_capability(
        %PlannedSourceRequest{} = request,
        %Placement{} = placement,
        frame_spec,
        registry_opts
      )
      when is_map(frame_spec) and is_list(registry_opts) do
    requested_sampling = Map.get(request.sampling, :mode)

    case SourceRegistry.capability_context(request, registry_opts) do
      {:ok, %{capabilities: %SourceCapabilities{} = capabilities, provenance: provenance}} ->
        request = put_capability_provenance(request, provenance)
        requested_source_products = requested_source_products(request, capabilities)

        if SourceCapabilities.supports_sampling?(capabilities, requested_sampling) and
             supports_source_products?(capabilities, requested_source_products) do
          {:ok, request}
        else
          {:warning,
           unsupported_source_capability_warning(
             request,
             placement,
             frame_spec,
             capabilities,
             provenance,
             requested_sampling,
             requested_source_products
           )}
        end

      {:error, %ResolveWarning{} = warning} ->
        {:warning, placement_warning(warning, placement)}
    end
  end

  @spec unsupported_widget_frame_contract_warning(Placement.t(), map()) ::
          ResolveWarning.t()
  def unsupported_widget_frame_contract_warning(%Placement{} = placement, details)
      when is_map(details) do
    %ResolveWarning{
      code: :unsupported_widget_frame_contract,
      severity: :warning,
      scope: :placement,
      placement_id: placement.placement_id,
      message: "Widget cannot consume requested source",
      details:
        details
        |> Map.put(:placement_id, placement.placement_id)
        |> Map.put(:widget_id, placement.placement_id)
        |> Map.put(:fallback, :none)
    }
  end

  defp validate_observable_scope(
         %PlannedSourceRequest{logical_source: :operational_observables} = request,
         %Placement{} = placement,
         frame_spec
       ) do
    scope_kind = normalized_primary_scope_kind(request.scope_context)
    scope_ids = ScopeContext.primary_ids(request.scope_context)
    observables = List.wrap(request.observables)

    unsupported =
      WidgetFrameContract.unsupported_operational_observable_scope_ids(observables, scope_kind)

    if unsupported == [] do
      {:ok, request}
    else
      {:warning,
       unsupported_observable_scope_warning(
         request,
         placement,
         frame_spec,
         scope_kind,
         scope_ids,
         unsupported
       )}
    end
  end

  defp validate_observable_scope(
         %PlannedSourceRequest{} = request,
         %Placement{},
         _frame_spec
       ),
       do: {:ok, request}

  defp unsupported_observable_scope_warning(
         %PlannedSourceRequest{} = request,
         %Placement{} = placement,
         frame_spec,
         scope_kind,
         scope_ids,
         unsupported
       ) do
    %ResolveWarning{
      code: :unsupported_observable_scope,
      severity: :warning,
      scope: :placement,
      placement_id: placement.placement_id,
      message: "Widget observables do not support selected runtime scope",
      details: %{
        source_request_id: request.request_id,
        logical_source: request.logical_source,
        requested_scope_kind: scope_kind,
        requested_scope_ids: scope_ids,
        unsupported_observables: unsupported,
        supported_scopes:
          WidgetFrameContract.supported_operational_observable_scopes(
            List.wrap(request.observables)
          ),
        accepted_shapes: Map.get(frame_spec, :accepted_shapes, []),
        fallback: :none
      },
      links: DataLinks.request_observable_links(request, source: :warning)
    }
  end

  defp unsupported_source_capability_warning(
         %PlannedSourceRequest{} = request,
         %Placement{} = placement,
         frame_spec,
         %SourceCapabilities{} = capabilities,
         provenance,
         requested_sampling,
         requested_source_products
       ) do
    %ResolveWarning{
      code: :unsupported_source_capability,
      severity: :warning,
      scope: :placement,
      placement_id: placement.placement_id,
      message: "Source cannot satisfy requested capability",
      details: %{
        source_request_id: request.request_id,
        logical_source: request.logical_source,
        requested_observables: request.observables,
        unsupported_observables: request.observables,
        requested_sampling: requested_sampling,
        supported_sampling: capabilities.supported_sampling,
        requested_products: Map.get(request.sampling, :products, []),
        requested_source_products: requested_source_products,
        supported_products: capabilities.supported_products,
        requested_product_families: requested_product_families(request, capabilities),
        supported_product_families: supported_product_families(capabilities),
        requested_value_kinds: Map.get(frame_spec, :observable_value_kinds, []),
        supported_value_kinds: Map.get(frame_spec, :observable_value_kinds, []),
        accepted_shapes: Map.get(frame_spec, :accepted_shapes, []),
        supported_shapes: capabilities.supported_shapes,
        fallback: :none,
        capability_provenance: provenance,
        source_binding_id: Map.get(provenance, :binding_id),
        data_source_id: Map.get(provenance, :data_source_id),
        realm: Map.get(provenance, :realm),
        dataset: Map.get(provenance, :dataset),
        capability_fingerprint: Map.get(provenance, :capability_fingerprint)
      },
      links: DataLinks.request_observable_links(request, source: :warning)
    }
  end

  defp supports_source_products?(_capabilities, []), do: true

  defp supports_source_products?(%SourceCapabilities{} = capabilities, requested_products) do
    supported_products = MapSet.new(supported_source_products(capabilities))

    Enum.all?(requested_products, &MapSet.member?(supported_products, &1))
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

  defp supported_product_families(%SourceCapabilities{} = capabilities) do
    capabilities
    |> source_backing_contracts()
    |> Enum.filter(fn contract ->
      source_backing_product_supported?(capabilities, Map.get(contract, :product))
    end)
    |> Enum.map(&Map.get(&1, :product_family))
    |> Enum.reject(&is_nil/1)
    |> Enum.uniq()
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
    Map.get(request.sampling, :products, [])
  end

  defp requested_product_families(
         %PlannedSourceRequest{logical_source: :operational_observables} = request,
         %SourceCapabilities{} = capabilities
       ) do
    request
    |> source_backing_contracts_for_request(capabilities)
    |> Enum.map(&Map.get(&1, :product_family))
    |> Enum.reject(&is_nil/1)
    |> Enum.uniq()
  end

  defp requested_product_families(%PlannedSourceRequest{} = request, _capabilities) do
    Map.get(request.sampling, :families, [])
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

  defp put_capability_provenance(%PlannedSourceRequest{} = request, provenance) do
    metadata = if is_map(request.metadata), do: request.metadata, else: %{}

    %PlannedSourceRequest{
      request
      | metadata: Map.put(metadata, :capability_provenance, provenance)
    }
  end

  defp placement_warning(%ResolveWarning{} = warning, %Placement{} = placement) do
    %ResolveWarning{warning | scope: :placement, placement_id: placement.placement_id}
  end

  defp normalized_primary_scope_kind(scope_context) do
    case ScopeContext.primary_kind(scope_context) do
      scope_kind when is_atom(scope_kind) ->
        scope_kind

      scope_kind when is_binary(scope_kind) ->
        normalized_scope_kind =
          scope_kind
          |> String.trim()
          |> String.downcase()
          |> String.replace("-", "_")

        Enum.find(@known_scope_kinds, normalized_scope_kind, fn known_scope_kind ->
          Atom.to_string(known_scope_kind) == normalized_scope_kind
        end)

      _scope_kind ->
        nil
    end
  end
end
