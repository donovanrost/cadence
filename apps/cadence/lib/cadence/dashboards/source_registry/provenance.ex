defmodule Cadence.Dashboards.SourceRegistry.Provenance do
  @moduledoc """
  Shapes source binding provenance, link context, and evidence references.
  """

  alias Cadence.Dashboards.{
    DataBindingInterval,
    DataLink,
    DataLinks,
    Field,
    Frame,
    PlannedSourceRequest,
    ResolvedSourceBinding,
    ResolveWarning,
    SourceActions,
    SourceFacts,
    SourceResult,
    SourceWatermark
  }

  alias Cadence.Dashboards.SourceRegistry.OperationalIntervalProvenance

  @spec details(PlannedSourceRequest.t(), ResolvedSourceBinding.t()) :: map()
  def details(%PlannedSourceRequest{} = request, resolved_binding) do
    details = %{
      source_request_id: request.request_id,
      logical_source: request.logical_source,
      binding_id: resolved_binding.binding.binding_id,
      data_source_id: resolved_binding.data_source.data_source_id,
      realm: resolved_binding.realm,
      dataset: resolved_binding.dataset
    }

    details
    |> Map.merge(binding_metadata(resolved_binding))
    |> SourceActions.put_source_request_context(request)
    |> SourceActions.put_source_warning_actions()
  end

  @spec put_facts(SourceFacts.t(), ResolvedSourceBinding.t(), map()) :: SourceFacts.t()
  def put_facts(
        %SourceFacts{} = facts,
        resolved_binding,
        capability_provenance
      ) do
    facts = SourceFacts.normalize(facts)

    SourceFacts.new(%{
      facts
      | meta:
          facts.meta
          |> ensure_map()
          |> Map.merge(binding_metadata(resolved_binding))
          |> maybe_put(:capability_provenance, capability_provenance)
          |> maybe_put(:capability_posture, Map.get(capability_provenance, :capability_posture))
    })
  end

  @spec put_result(
          SourceResult.t(),
          ResolvedSourceBinding.t(),
          PlannedSourceRequest.t(),
          keyword()
        ) :: SourceResult.t()
  def put_result(
        %SourceResult{} = result,
        resolved_binding,
        request,
        opts
      ) do
    result = SourceResult.normalize(result)

    interval_provenance =
      OperationalIntervalProvenance.build(request, resolved_binding, opts, result)

    provenance =
      resolved_binding
      |> binding_metadata()
      |> Map.merge(interval_provenance)

    link_context = source_link_context(request, resolved_binding)

    evidence =
      source_binding_evidence_refs(resolved_binding, request) ++
        OperationalIntervalProvenance.evidence_refs(interval_provenance, request) ++
        source_status_evidence_refs(result)

    SourceResult.new(%{
      result
      | meta:
          result.meta
          |> ensure_map()
          |> Map.merge(provenance)
          |> merge_evidence(evidence),
        warnings:
          Enum.map(result.warnings, fn warning ->
            put_warning_provenance(warning, resolved_binding, request)
          end),
        frames:
          Enum.map(result.frames, &put_frame_provenance(&1, provenance, link_context, evidence))
    })
  end

  defp put_warning_provenance(
         %ResolveWarning{} = warning,
         %ResolvedSourceBinding{} = resolved_binding,
         %PlannedSourceRequest{} = request
       ) do
    details =
      warning.details
      |> ensure_map()
      |> Map.merge(source_warning_provenance_details(request, resolved_binding))
      |> SourceActions.put_source_warning_actions()

    links =
      warning
      |> warning_links_or_request_links(request, resolved_binding)
      |> enrich_data_links(source_link_context(request, resolved_binding))

    %ResolveWarning{warning | details: details, links: links}
  end

  defp put_warning_provenance(warning, _resolved_binding, _request), do: warning

  defp source_warning_provenance_details(
         %PlannedSourceRequest{} = request,
         %ResolvedSourceBinding{} = resolved_binding
       ) do
    %{
      source_request_id: request.request_id,
      logical_source: request.logical_source,
      binding_id: resolved_binding.binding.binding_id,
      data_source_id: resolved_binding.data_source.data_source_id,
      realm: resolved_binding.realm,
      dataset: resolved_binding.dataset
    }
    |> Map.merge(binding_metadata(resolved_binding))
    |> SourceActions.put_source_request_context(request)
  end

  defp put_frame_provenance(%Frame{} = frame, provenance, link_context, evidence) do
    meta =
      frame.meta
      |> ensure_map()
      |> Map.merge(provenance)
      |> merge_evidence(evidence)
      |> enrich_link_container(link_context)

    fields = Enum.map(frame.fields, &put_field_link_provenance(&1, link_context))

    Frame.new(%{frame | meta: meta, fields: fields})
  end

  defp put_frame_provenance(frame, _provenance, _link_context, _evidence), do: frame

  defp put_field_link_provenance(%Field{} = field, link_context) do
    Field.new(%{field | metadata: enrich_link_container(field.metadata, link_context)})
  end

  defp put_field_link_provenance(field, _link_context), do: field

  defp warning_links_or_request_links(
         %ResolveWarning{links: links},
         %PlannedSourceRequest{} = request,
         %ResolvedSourceBinding{} = resolved_binding
       )
       when links in [nil, []] do
    DataLinks.request_observable_links(request,
      source: :warning,
      source_binding: resolved_binding
    )
  end

  defp warning_links_or_request_links(%ResolveWarning{links: links}, _request, _resolved_binding),
    do: links

  defp enrich_link_container(container, link_context) when is_map(container) do
    cond do
      Map.has_key?(container, :links) ->
        Map.put(container, :links, enrich_data_links(Map.get(container, :links), link_context))

      Map.has_key?(container, "links") ->
        Map.put(container, "links", enrich_data_links(Map.get(container, "links"), link_context))

      true ->
        container
    end
  end

  defp enrich_link_container(container, _link_context), do: container

  defp enrich_data_links(links, link_context) when is_list(links) do
    Enum.map(links, &enrich_data_link(&1, link_context))
  end

  defp enrich_data_links(links, _link_context), do: links

  defp enrich_data_link(%DataLink{} = link, link_context) do
    %DataLink{link | context: merge_data_link_context(link.context, link_context)}
  end

  defp enrich_data_link(link, _link_context), do: link

  defp merge_data_link_context(context, link_context) do
    context = ensure_map(context)

    Map.merge(context, link_context, fn
      :data, left, right -> Map.merge(ensure_map(left), ensure_map(right))
      _key, _left, right -> right
    end)
  end

  defp source_link_context(
         %PlannedSourceRequest{} = request,
         %ResolvedSourceBinding{} = resolved_binding
       ) do
    %{
      source_request_id: request.request_id,
      logical_source: request.logical_source,
      data: %{
        realm: resolved_binding.realm,
        data_source_id: resolved_binding.data_source.data_source_id,
        source_binding_id: resolved_binding.binding.binding_id,
        dataset: resolved_binding.dataset
      }
    }
    |> Enum.reject(fn {_key, value} -> is_nil(value) end)
    |> Map.new()
  end

  @spec binding_metadata(ResolvedSourceBinding.t()) :: map()
  def binding_metadata(%ResolvedSourceBinding{} = resolved_binding) do
    binding = resolved_binding.binding

    %{
      source_binding_id: binding.binding_id,
      source_binding_version: binding.binding_version,
      source_binding_event_id: binding.current_event_id,
      source_binding_interval: interval(resolved_binding),
      source_binding_segment: segment(resolved_binding),
      source_selection: selection(resolved_binding)
    }
    |> Enum.reject(fn {_key, value} -> is_nil(value) end)
    |> Map.new()
  end

  @spec selection(ResolvedSourceBinding.t()) :: map() | nil
  def selection(%ResolvedSourceBinding{source_selection: selection})
      when is_map(selection) and map_size(selection) > 0,
      do: selection

  def selection(%ResolvedSourceBinding{}), do: nil

  @spec segment(ResolvedSourceBinding.t()) :: map() | nil
  def segment(
        %ResolvedSourceBinding{
          segment_from: %DateTime{} = from,
          segment_to: %DateTime{} = to
        } = resolved_binding
      ) do
    binding = resolved_binding.binding

    %{
      from: from,
      to: to,
      binding_id: binding.binding_id,
      binding_version: binding.binding_version,
      data_binding_event_id: binding.current_event_id,
      data_source_id: resolved_binding.data_source.data_source_id,
      dataset: resolved_binding.dataset,
      realm: resolved_binding.realm,
      interval: interval(resolved_binding)
    }
    |> Enum.reject(fn {_key, value} -> is_nil(value) end)
    |> Map.new()
  end

  def segment(%ResolvedSourceBinding{}), do: nil

  @spec interval(ResolvedSourceBinding.t()) :: map() | nil
  def interval(%ResolvedSourceBinding{
        binding_interval: %DataBindingInterval{} = interval
      }) do
    DataBindingInterval.metadata(interval)
  end

  def interval(%ResolvedSourceBinding{}), do: nil

  defp source_binding_evidence_refs(
         %ResolvedSourceBinding{} = resolved_binding,
         %PlannedSourceRequest{} = request
       ) do
    resolved_binding
    |> source_binding_evidence_metadata()
    |> List.wrap()
    |> DataLinks.source_binding_interval_evidence_refs(source: request.logical_source)
  end

  defp source_binding_evidence_metadata(%ResolvedSourceBinding{} = resolved_binding) do
    case interval(resolved_binding) do
      nil ->
        binding = resolved_binding.binding

        %{
          binding_id: binding.binding_id,
          data_binding_event_id: binding.current_event_id,
          started_at: binding.active_from,
          active_from: binding.active_from
        }
        |> Enum.reject(fn {_key, value} -> is_nil(value) end)
        |> Map.new()

      metadata ->
        metadata
    end
  end

  defp source_status_evidence_refs(%SourceResult{} = result) do
    result
    |> source_status_evidence_metadata()
    |> then(fn metadata ->
      DataLinks.source_watermark_event_evidence_refs(metadata) ++
        DataLinks.source_health_event_evidence_refs(metadata)
    end)
    |> dedupe_evidence_refs()
  end

  defp source_status_evidence_metadata(%SourceResult{} = result) do
    [
      status_metadata(result.meta)
      | Enum.map(List.wrap(result.watermarks), &watermark_status_metadata/1)
    ]
  end

  defp watermark_status_metadata(%SourceWatermark{} = watermark) do
    status_metadata(watermark.meta)
  end

  defp watermark_status_metadata(_watermark), do: %{}

  @spec status_metadata(term()) :: map()
  def status_metadata(metadata) do
    metadata = ensure_map(metadata)

    Map.put_new(
      metadata,
      :observed_at,
      Map.get(metadata, :source_watermark_observed_at) ||
        Map.get(metadata, :source_health_observed_at)
    )
  end

  @spec merge_evidence(map(), list()) :: map()
  def merge_evidence(meta, []), do: meta

  def merge_evidence(meta, evidence) when is_map(meta) and is_list(evidence) do
    Map.put(
      meta,
      :evidence,
      dedupe_evidence_refs(existing_evidence_refs(meta) ++ evidence)
    )
  end

  defp existing_evidence_refs(meta) when is_map(meta) do
    List.wrap(Map.get(meta, :evidence)) ++
      List.wrap(Map.get(meta, "evidence")) ++
      List.wrap(Map.get(meta, :evidence_refs)) ++
      List.wrap(Map.get(meta, "evidence_refs"))
  end

  defp dedupe_evidence_refs(evidence) do
    Enum.uniq_by(evidence, &evidence_ref_identity/1)
  end

  defp evidence_ref_identity(%{kind: kind, id: id}), do: {kind, id}

  defp evidence_ref_identity(%{} = ref) do
    {Map.get(ref, :kind, Map.get(ref, "kind")), Map.get(ref, :id, Map.get(ref, "id"))}
  end

  defp evidence_ref_identity(ref), do: ref

  defp maybe_put(map, _key, nil), do: map
  defp maybe_put(map, key, value), do: Map.put(map, key, value)

  defp ensure_map(map) when is_map(map), do: map
  defp ensure_map(_value), do: %{}
end
