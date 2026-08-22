defmodule Cadence.Dashboards.SourceResultAnnotation do
  @moduledoc """
  Applies dashboard freshness policy and request provenance to source results.

  Source adapters return provider-facing facts and results. This module turns
  them into consumer-facing runtime evidence before caching or materialization.
  """

  alias Cadence.Dashboards.{
    DashboardResolveRequest,
    DashboardResolveResult,
    Placement,
    PlannedSourceRequest,
    SourceFacts,
    SourceFreshness
  }

  @spec annotate_facts(
          SourceFacts.t(),
          PlannedSourceRequest.t(),
          keyword() | map() | nil,
          DateTime.t()
        ) :: SourceFacts.t()
  def annotate_facts(
        %SourceFacts{watermark: nil, watermarks: []} = source_facts,
        %PlannedSourceRequest{},
        _freshness_policy,
        %DateTime{}
      ) do
    source_facts
  end

  def annotate_facts(
        %SourceFacts{} = source_facts,
        %PlannedSourceRequest{} = source_request,
        freshness_policy,
        %DateTime{} = freshness_now
      ) do
    %SourceFacts{
      source_facts
      | watermark:
          annotate_watermark(
            source_facts.watermark,
            source_request,
            freshness_policy,
            freshness_now
          ),
        watermarks:
          Enum.map(source_facts.watermarks, fn watermark ->
            annotate_watermark(watermark, source_request, freshness_policy, freshness_now)
          end)
    }
  end

  @spec annotate_result(
          DashboardResolveRequest.t(),
          DashboardResolveResult.t(),
          PlannedSourceRequest.t(),
          struct(),
          DateTime.t(),
          keyword()
        ) :: struct()
  def annotate_result(
        %DashboardResolveRequest{} = resolve_request,
        %DashboardResolveResult{} = plan_result,
        %PlannedSourceRequest{} = source_request,
        source_result,
        %DateTime{} = now,
        opts
      ) do
    freshness_policy = freshness_policy(resolve_request, plan_result, source_request, opts)

    watermarks =
      Enum.map(source_result.watermarks, fn watermark ->
        SourceFreshness.annotate(watermark, source_request, freshness_policy, now)
      end)

    freshness_warnings =
      watermarks
      |> Enum.map(&SourceFreshness.warning(&1, source_request))
      |> Enum.reject(&is_nil/1)

    %{
      source_result
      | watermarks: watermarks,
        warnings: source_result.warnings ++ freshness_warnings
    }
    |> annotate_provenance(source_request)
  end

  @spec annotate_provenance(struct(), PlannedSourceRequest.t()) :: struct()
  def annotate_provenance(source_result, %PlannedSourceRequest{} = source_request) do
    provenance = capability_provenance(source_request)

    %{
      source_result
      | meta:
          source_result.meta
          |> ensure_map()
          |> maybe_put_capability_provenance(provenance)
          |> maybe_put_source_dependencies(source_request.source_dependencies)
    }
  end

  @spec freshness_policy(
          DashboardResolveRequest.t(),
          DashboardResolveResult.t(),
          PlannedSourceRequest.t(),
          keyword()
        ) :: keyword() | map()
  def freshness_policy(
        %DashboardResolveRequest{} = resolve_request,
        %DashboardResolveResult{} = plan_result,
        %PlannedSourceRequest{} = source_request,
        opts
      ) do
    SourceFreshness.resolve_policy(
      [
        source_freshness_policy(source_request.logical_source, opts),
        dashboard_freshness_policy(resolve_request),
        request_freshness_policy(source_request),
        consumer_freshness_policy(resolve_request.document, plan_result, source_request)
      ]
      |> List.flatten()
    )
  end

  @spec put_cache_entry_capability_provenance(map(), PlannedSourceRequest.t()) :: map()
  def put_cache_entry_capability_provenance(
        cache_entry,
        %PlannedSourceRequest{} = source_request
      )
      when is_map(cache_entry) do
    case capability_provenance(source_request) do
      nil -> cache_entry
      provenance -> Map.put(cache_entry, :capability_provenance, provenance)
    end
  end

  defp annotate_watermark(nil, %PlannedSourceRequest{}, _freshness_policy, %DateTime{}),
    do: nil

  defp annotate_watermark(
         watermark,
         %PlannedSourceRequest{} = source_request,
         freshness_policy,
         %DateTime{} = freshness_now
       ) do
    SourceFreshness.annotate(
      watermark,
      source_request,
      freshness_policy,
      freshness_now
    )
  end

  defp source_freshness_policy(logical_source, opts) do
    opts
    |> Keyword.get(:source_freshness_policies, %{})
    |> get_attr(logical_source)
  end

  defp dashboard_freshness_policy(%DashboardResolveRequest{document: document}) do
    defaults = document.defaults || %{}
    health_defaults = get_attr(defaults, :health) || %{}

    [
      get_attr(defaults, :freshness_policy),
      get_attr(health_defaults, :freshness_policy)
    ]
  end

  defp request_freshness_policy(%PlannedSourceRequest{} = request) do
    [
      get_attr(request.sampling, :freshness_policy),
      get_attr(request.data_context, :freshness_policy),
      get_attr(request.limit_context, :freshness_policy)
    ]
  end

  defp consumer_freshness_policy(
         document,
         %DashboardResolveResult{} = plan_result,
         source_request
       ) do
    placement_by_id = Map.new(document.placements, &{&1.placement_id, &1})
    planned_request_ids = MapSet.new([source_request.request_id])

    plan_result.frames_by_placement
    |> Enum.filter(fn {_placement_id, frames} ->
      Enum.any?(frames.planned_request_ids, &MapSet.member?(planned_request_ids, &1))
    end)
    |> Enum.flat_map(fn {placement_id, _frames} ->
      case Map.get(placement_by_id, placement_id) do
        nil -> []
        placement -> placement_freshness_policies(placement)
      end
    end)
  end

  defp placement_freshness_policies(%Placement{} = placement) do
    widget_options =
      case placement.widget_def do
        %{options: options} when is_map(options) -> options
        _other -> %{}
      end

    widget_health = get_attr(widget_options, :health) || %{}
    overrides = placement.overrides || %{}
    override_health = get_attr(overrides, :health) || %{}

    [
      get_attr(widget_options, :freshness_policy),
      get_attr(widget_health, :freshness_policy),
      get_attr(overrides, :freshness_policy),
      get_attr(override_health, :freshness_policy)
    ]
  end

  defp capability_provenance(%PlannedSourceRequest{} = source_request) do
    source_request.metadata
    |> ensure_map()
    |> Map.get(:capability_provenance)
  end

  defp maybe_put_capability_provenance(meta, nil), do: meta

  defp maybe_put_capability_provenance(meta, provenance) do
    Map.put(meta, :capability_provenance, provenance)
  end

  defp maybe_put_source_dependencies(meta, []), do: meta

  defp maybe_put_source_dependencies(meta, dependencies),
    do: Map.put(meta, :source_dependencies, dependencies)

  defp ensure_map(map) when is_map(map), do: map
  defp ensure_map(_value), do: %{}

  defp get_attr(%_{} = attrs, key) when is_atom(key) do
    Map.get(Map.from_struct(attrs), key)
  end

  defp get_attr(attrs, key) when is_map(attrs) do
    Map.get(attrs, key, Map.get(attrs, to_string(key)))
  end

  defp get_attr(_attrs, _key), do: nil
end
