defmodule Cadence.Dashboards.DashboardContract do
  @moduledoc """
  Stable dashboard engine request/result contract checks.

  The dashboard engine is intentionally more than a render helper: downstream
  LiveViews, evidence panels, runtime invalidation, source health, and cache
  diagnostics all depend on a predictable request/result shape. This module
  captures that shape as executable checks so contract drift is visible in tests
  and at future runtime boundaries.
  """

  alias Cadence.Dashboards.{
    DashboardAction,
    DashboardResolveRequest,
    DashboardResolveResult,
    DataBinding,
    DataContext,
    DataLink,
    DataSource,
    EvidenceRef,
    Field,
    Frame,
    LimitContext,
    PlacementFrames,
    PlannedSourceRequest,
    ResolveWarning,
    RuntimeCacheKey,
    ScopeContext,
    SourceCapabilities,
    SourceFacts,
    SourceResult,
    SourceWatermark,
    TimeContext
  }

  @type violation :: %{path: [term()], code: atom(), message: binary()}

  @resolve_modes DashboardResolveRequest.resolve_modes()
  @document_modes DashboardResolveRequest.document_modes()
  @logical_sources PlannedSourceRequest.logical_sources()
  @frame_sources Frame.sources()
  @frame_shapes Frame.shapes()
  @frame_time_axes Frame.time_axes()
  @field_kinds Field.kinds()
  @source_capability_completeness SourceCapabilities.completeness_values()
  @source_fact_health_values SourceFacts.source_health_values()
  @source_value_types [:raw, :engineering]
  @warning_severities ResolveWarning.severities()
  @warning_scopes ResolveWarning.scopes()
  @watermark_confidences SourceWatermark.confidences()
  @watermark_freshness_states SourceWatermark.freshness_states()
  @evidence_kinds EvidenceRef.kinds()
  @evidence_confidences EvidenceRef.confidences()
  @data_link_targets DataLink.resolvable_targets()
  @data_link_presentations DataLink.presentations()
  @data_link_sources DataLink.sources()
  @action_targets DashboardAction.targets()
  @action_kinds DashboardAction.kinds()
  @action_presentations DashboardAction.presentations()
  @action_sources DashboardAction.sources()

  @plan_metadata_keys [
    :cache,
    :time,
    :snapshot?,
    :live_append_eligible?,
    :source_request_count,
    :unbatched_source_request_count,
    :batched_consumer_count,
    :degraded?
  ]

  @resolve_metadata_keys @plan_metadata_keys ++
                           [
                             :source_execution_policy,
                             :source_execution_policies_by_request_id,
                             :executed_source_request_count,
                             :skipped_source_request_count,
                             :source_selection_by_request_id,
                             :returned_frame_count
                           ]

  @spec validate_request(DashboardResolveRequest.t()) :: :ok | {:error, [violation()]}
  def validate_request(%DashboardResolveRequest{} = request) do
    request = DashboardResolveRequest.normalize(request)

    []
    |> require_binary([:organization_id], request.organization_id)
    |> require_binary([:mission_id], request.mission_id)
    |> require_binary([:dashboard_id], request.dashboard_id)
    |> require_struct([:document], request.document, Cadence.Dashboards.Document)
    |> require_in([:document_mode], request.document_mode, @document_modes)
    |> require_in([:resolve_mode], request.resolve_mode, @resolve_modes)
    |> require_struct([:time_context], request.time_context, TimeContext)
    |> require_struct([:scope_context], request.scope_context, ScopeContext)
    |> require_struct([:data_context], request.data_context, DataContext)
    |> require_struct([:limit_context], request.limit_context, LimitContext)
    |> require_map([:interaction_context], request.interaction_context)
    |> finish()
  end

  def validate_request(other) do
    error([], [], :invalid_request, "expected %DashboardResolveRequest{}, got #{inspect(other)}")
    |> finish()
  end

  @spec validate_source_capabilities(SourceCapabilities.t()) :: :ok | {:error, [violation()]}
  def validate_source_capabilities(%SourceCapabilities{} = capabilities) do
    capabilities = SourceCapabilities.normalize(capabilities)

    []
    |> require_in([:logical_source], capabilities.logical_source, @logical_sources)
    |> require_atom_list([:supported_sampling], capabilities.supported_sampling)
    |> require_atom_list([:supported_products], capabilities.supported_products)
    |> require_in_list([:supported_time_axes], capabilities.supported_time_axes, @frame_time_axes)
    |> require_in_list(
      [:supported_value_types],
      capabilities.supported_value_types,
      @source_value_types
    )
    |> require_in_list([:supported_shapes], capabilities.supported_shapes, @frame_shapes)
    |> require_boolean([:supports_watermarks?], capabilities.supports_watermarks?)
    |> require_in([:completeness], capabilities.completeness, @source_capability_completeness)
    |> require_map([:metadata], capabilities.metadata)
    |> finish()
  end

  def validate_source_capabilities(other) do
    error(
      [],
      [],
      :invalid_source_capabilities,
      "expected %SourceCapabilities{}, got #{inspect(other)}"
    )
    |> finish()
  end

  @spec validate_source_facts(SourceFacts.t()) :: :ok | {:error, [violation()]}
  def validate_source_facts(%SourceFacts{} = facts) do
    facts = SourceFacts.normalize(facts)

    []
    |> require_optional_struct([:source_binding], facts.source_binding, DataBinding)
    |> require_optional_struct([:data_source], facts.data_source, DataSource)
    |> validate_optional_watermark([:watermark], facts.watermark)
    |> validate_watermarks([:watermarks], facts.watermarks)
    |> validate_source_binding_segments([:source_binding_segments], facts.source_binding_segments)
    |> require_in([:source_health], facts.source_health, @source_fact_health_values)
    |> require_map([:meta], facts.meta)
    |> validate_metadata_refs([:meta], facts.meta)
    |> finish()
  end

  def validate_source_facts(other) do
    error([], [], :invalid_source_facts, "expected %SourceFacts{}, got #{inspect(other)}")
    |> finish()
  end

  @spec validate_source_result(SourceResult.t()) :: :ok | {:error, [violation()]}
  def validate_source_result(%SourceResult{} = result) do
    result = SourceResult.normalize(result)

    []
    |> require_binary([:request_id], result.request_id)
    |> validate_frames([:frames], result.frames)
    |> validate_warnings([:warnings], result.warnings)
    |> validate_watermarks([:watermarks], result.watermarks)
    |> require_map([:meta], result.meta)
    |> validate_metadata_refs([:meta], result.meta)
    |> finish()
  end

  def validate_source_result(other) do
    error([], [], :invalid_source_result, "expected %SourceResult{}, got #{inspect(other)}")
    |> finish()
  end

  @spec validate_planned_source_request(PlannedSourceRequest.t()) ::
          :ok | {:error, [violation()]}
  def validate_planned_source_request(%PlannedSourceRequest{} = request) do
    request = PlannedSourceRequest.normalize(request)

    []
    |> validate_planned_source_request([], request)
    |> finish()
  end

  def validate_planned_source_request(other) do
    error(
      [],
      [],
      :invalid_planned_source_request,
      "expected %PlannedSourceRequest{}, got #{inspect(other)}"
    )
    |> finish()
  end

  @spec validate_plan_result(DashboardResolveResult.t()) :: :ok | {:error, [violation()]}
  def validate_plan_result(%DashboardResolveResult{} = result) do
    result = DashboardResolveResult.normalize(result)

    validate_result(result, @plan_metadata_keys, :plan)
  end

  def validate_plan_result(other) do
    error([], [], :invalid_result, "expected %DashboardResolveResult{}, got #{inspect(other)}")
    |> finish()
  end

  @spec validate_resolve_result(DashboardResolveResult.t()) :: :ok | {:error, [violation()]}
  def validate_resolve_result(%DashboardResolveResult{} = result) do
    result = DashboardResolveResult.normalize(result)

    validate_result(result, @resolve_metadata_keys, :resolve)
  end

  def validate_resolve_result(other) do
    error([], [], :invalid_result, "expected %DashboardResolveResult{}, got #{inspect(other)}")
    |> finish()
  end

  defp validate_result(%DashboardResolveResult{} = result, metadata_keys, phase) do
    []
    |> require_binary([:dashboard_id], result.dashboard_id)
    |> require_in([:resolve_mode], result.resolve_mode, @resolve_modes)
    |> validate_frames_by_placement(result.frames_by_placement)
    |> validate_warnings([:dashboard_warnings], result.dashboard_warnings)
    |> validate_watermarks([:watermarks], result.watermarks)
    |> require_list([:subscriptions], result.subscriptions)
    |> validate_planned_requests(result.planned_source_requests)
    |> validate_plan_metadata(result.plan_metadata, metadata_keys, phase)
    |> finish()
  end

  defp validate_frames_by_placement(errors, frames_by_placement)
       when is_map(frames_by_placement) do
    Enum.reduce(frames_by_placement, errors, fn
      {placement_id, %PlacementFrames{} = placement_frames}, errors
      when is_binary(placement_id) ->
        errors
        |> validate_frames(
          [:frames_by_placement, placement_id, :primary],
          placement_frames.primary
        )
        |> require_map([:frames_by_placement, placement_id, :overlays], placement_frames.overlays)
        |> validate_warnings(
          [:frames_by_placement, placement_id, :warnings],
          placement_frames.warnings
        )
        |> require_binary_list(
          [:frames_by_placement, placement_id, :planned_request_ids],
          placement_frames.planned_request_ids
        )

      {placement_id, value}, errors ->
        error(
          errors,
          [:frames_by_placement, placement_id],
          :invalid_placement_frames,
          "expected binary placement id and %PlacementFrames{}, got #{inspect(value)}"
        )
    end)
  end

  defp validate_frames_by_placement(errors, value) do
    error(errors, [:frames_by_placement], :invalid_map, "expected map, got #{inspect(value)}")
  end

  defp validate_frames(errors, path, frames) when is_list(frames) do
    frames
    |> Enum.with_index()
    |> Enum.reduce(errors, fn
      {%Frame{} = frame, index}, errors ->
        errors
        |> require_in(path ++ [index, :source], frame.source, @frame_sources)
        |> require_in(path ++ [index, :shape], frame.shape, @frame_shapes)
        |> require_optional_in(path ++ [index, :time_axis], frame.time_axis, @frame_time_axes)
        |> validate_fields(path ++ [index, :fields], frame.fields)
        |> require_map(path ++ [index, :scope], frame.scope)
        |> require_map(path ++ [index, :overlays], frame.overlays)
        |> require_map(path ++ [index, :meta], frame.meta)
        |> validate_metadata_refs(path ++ [index, :meta], frame.meta)

      {value, index}, errors ->
        error(errors, path ++ [index], :invalid_frame, "expected %Frame{}, got #{inspect(value)}")
    end)
  end

  defp validate_frames(errors, path, value) do
    error(errors, path, :invalid_list, "expected list, got #{inspect(value)}")
  end

  defp validate_fields(errors, path, fields) when is_list(fields) do
    fields
    |> Enum.with_index()
    |> Enum.reduce(errors, fn
      {%Field{} = field, index}, errors ->
        errors
        |> require_binary(path ++ [index, :name], field.name)
        |> require_in(path ++ [index, :kind], field.kind, @field_kinds)
        |> require_list(path ++ [index, :values], field.values)
        |> require_map(path ++ [index, :metadata], field.metadata)
        |> validate_metadata_refs(path ++ [index, :metadata], field.metadata)

      {value, index}, errors ->
        error(errors, path ++ [index], :invalid_field, "expected %Field{}, got #{inspect(value)}")
    end)
  end

  defp validate_fields(errors, path, value) do
    error(errors, path, :invalid_list, "expected list, got #{inspect(value)}")
  end

  defp validate_warnings(errors, path, warnings) when is_list(warnings) do
    warnings
    |> Enum.with_index()
    |> Enum.reduce(errors, fn
      {%ResolveWarning{} = warning, index}, errors ->
        errors
        |> require_atom(path ++ [index, :code], warning.code)
        |> require_in(path ++ [index, :severity], warning.severity, @warning_severities)
        |> require_in(path ++ [index, :scope], warning.scope, @warning_scopes)
        |> require_map(path ++ [index, :details], warning.details)
        |> validate_metadata_refs(path ++ [index, :details], warning.details)
        |> validate_evidence_refs(path ++ [index, :evidence], warning.evidence)
        |> validate_data_links(path ++ [index, :links], warning.links)

      {value, index}, errors ->
        error(
          errors,
          path ++ [index],
          :invalid_warning,
          "expected %ResolveWarning{}, got #{inspect(value)}"
        )
    end)
  end

  defp validate_warnings(errors, path, value) do
    error(errors, path, :invalid_list, "expected list, got #{inspect(value)}")
  end

  defp validate_evidence_refs(errors, path, evidence) when is_list(evidence) do
    evidence
    |> Enum.with_index()
    |> Enum.reduce(errors, fn
      {%EvidenceRef{} = ref, index}, errors ->
        errors
        |> require_in(path ++ [index, :kind], ref.kind, @evidence_kinds)
        |> require_binary(path ++ [index, :id], ref.id)
        |> require_in(path ++ [index, :source], ref.source, @logical_sources)
        |> require_in(path ++ [index, :confidence], ref.confidence, @evidence_confidences)

      {value, index}, errors ->
        error(
          errors,
          path ++ [index],
          :invalid_evidence_ref,
          "expected %EvidenceRef{}, got #{inspect(value)}"
        )
    end)
  end

  defp validate_evidence_refs(errors, path, value) do
    error(errors, path, :invalid_list, "expected list, got #{inspect(value)}")
  end

  defp validate_data_links(errors, path, links) when is_list(links) do
    links
    |> Enum.with_index()
    |> Enum.reduce(errors, fn
      {%DataLink{} = link, index}, errors ->
        errors
        |> require_binary(path ++ [index, :link_id], link.link_id)
        |> require_binary(path ++ [index, :label], link.label)
        |> require_in(path ++ [index, :target], link.target, @data_link_targets)
        |> require_binary(path ++ [index, :target_id], link.target_id)
        |> require_optional_binary(path ++ [index, :route], link.route)
        |> require_map(path ++ [index, :context], link.context)
        |> require_in(path ++ [index, :presentation], link.presentation, @data_link_presentations)
        |> require_in(path ++ [index, :source], link.source, @data_link_sources)

      {value, index}, errors ->
        error(
          errors,
          path ++ [index],
          :invalid_data_link,
          "expected %DataLink{}, got #{inspect(value)}"
        )
    end)
  end

  defp validate_data_links(errors, path, value) do
    error(errors, path, :invalid_list, "expected list, got #{inspect(value)}")
  end

  defp validate_actions(errors, path, actions) when is_list(actions) do
    actions
    |> Enum.with_index()
    |> Enum.reduce(errors, fn
      {%DashboardAction{} = action, index}, errors ->
        errors
        |> require_binary(path ++ [index, :action_id], action.action_id)
        |> require_binary(path ++ [index, :label], action.label)
        |> require_in(path ++ [index, :target], action.target, @action_targets)
        |> require_in(path ++ [index, :kind], action.kind, @action_kinds)
        |> require_action_route(path ++ [index, :route], action.route, action.kind)
        |> require_map(path ++ [index, :query], action.query)
        |> require_map(path ++ [index, :context], action.context)
        |> require_in(path ++ [index, :presentation], action.presentation, @action_presentations)
        |> require_in(path ++ [index, :source], action.source, @action_sources)

      {value, index}, errors ->
        error(
          errors,
          path ++ [index],
          :invalid_dashboard_action,
          "expected %DashboardAction{}, got #{inspect(value)}"
        )
    end)
  end

  defp validate_actions(errors, path, value) do
    error(errors, path, :invalid_list, "expected list, got #{inspect(value)}")
  end

  defp validate_metadata_refs(errors, path, metadata) when is_map(metadata) do
    errors
    |> validate_optional_evidence_refs(path ++ [:evidence], metadata_attr(metadata, :evidence))
    |> validate_optional_data_links(path ++ [:links], metadata_attr(metadata, :links))
    |> validate_optional_actions(path ++ [:actions], metadata_attr(metadata, :actions))
  end

  defp validate_metadata_refs(errors, _path, _metadata), do: errors

  defp validate_optional_evidence_refs(errors, _path, nil), do: errors

  defp validate_optional_evidence_refs(errors, path, evidence) when is_list(evidence) do
    validate_evidence_refs(errors, path, Enum.map(evidence, &normalize_evidence_ref/1))
  end

  defp validate_optional_evidence_refs(errors, path, evidence),
    do: validate_evidence_refs(errors, path, evidence)

  defp validate_optional_data_links(errors, _path, nil), do: errors

  defp validate_optional_data_links(errors, path, links) when is_list(links) do
    validate_data_links(errors, path, Enum.map(links, &normalize_data_link/1))
  end

  defp validate_optional_data_links(errors, path, links),
    do: validate_data_links(errors, path, links)

  defp validate_optional_actions(errors, _path, nil), do: errors

  defp validate_optional_actions(errors, path, actions) when is_list(actions) do
    validate_actions(errors, path, Enum.map(actions, &normalize_action/1))
  end

  defp validate_optional_actions(errors, path, actions),
    do: validate_actions(errors, path, actions)

  defp normalize_evidence_ref(%EvidenceRef{} = ref), do: ref
  defp normalize_evidence_ref(ref) when is_map(ref), do: EvidenceRef.normalize(ref)
  defp normalize_evidence_ref(ref), do: ref

  defp normalize_data_link(%DataLink{} = link), do: link
  defp normalize_data_link(link) when is_map(link), do: DataLink.normalize(link)
  defp normalize_data_link(link), do: link

  defp normalize_action(%DashboardAction{} = action), do: action

  defp normalize_action(action) when is_map(action),
    do: DashboardAction.normalize(action)

  defp normalize_action(action), do: action

  defp validate_watermarks(errors, path, watermarks) when is_list(watermarks) do
    watermarks
    |> Enum.with_index()
    |> Enum.reduce(errors, fn
      {%SourceWatermark{} = watermark, index}, errors ->
        errors
        |> require_in(
          path ++ [index, :logical_source],
          watermark.logical_source,
          @logical_sources
        )
        |> require_in(path ++ [index, :confidence], watermark.confidence, @watermark_confidences)
        |> require_optional_in(
          path ++ [index, :freshness_state],
          watermark.freshness_state,
          @watermark_freshness_states
        )
        |> require_map(path ++ [index, :freshness_policy], watermark.freshness_policy)
        |> require_map(path ++ [index, :meta], watermark.meta)

      {value, index}, errors ->
        error(
          errors,
          path ++ [index],
          :invalid_watermark,
          "expected %SourceWatermark{}, got #{inspect(value)}"
        )
    end)
  end

  defp validate_watermarks(errors, path, value) do
    error(errors, path, :invalid_list, "expected list, got #{inspect(value)}")
  end

  defp validate_optional_watermark(errors, _path, nil), do: errors

  defp validate_optional_watermark(errors, path, %SourceWatermark{} = watermark) do
    validate_watermarks(errors, path, [watermark])
  end

  defp validate_optional_watermark(errors, path, value) do
    error(
      errors,
      path,
      :invalid_watermark,
      "expected nil or %SourceWatermark{}, got #{inspect(value)}"
    )
  end

  defp validate_source_binding_segments(errors, path, segments) when is_list(segments) do
    segments
    |> Enum.with_index()
    |> Enum.reduce(errors, fn
      {segment, _index}, errors when is_map(segment) ->
        errors

      {value, index}, errors ->
        error(
          errors,
          path ++ [index],
          :invalid_map,
          "expected map, got #{inspect(value)}"
        )
    end)
  end

  defp validate_source_binding_segments(errors, path, value) do
    error(errors, path, :invalid_list, "expected list, got #{inspect(value)}")
  end

  defp validate_planned_requests(errors, requests) when is_list(requests) do
    requests
    |> Enum.with_index()
    |> Enum.reduce(errors, fn
      {%PlannedSourceRequest{} = request, index}, errors ->
        validate_planned_source_request(errors, [:planned_source_requests, index], request)

      {value, index}, errors ->
        error(
          errors,
          [:planned_source_requests, index],
          :invalid_planned_source_request,
          "expected %PlannedSourceRequest{}, got #{inspect(value)}"
        )
    end)
  end

  defp validate_planned_requests(errors, value) do
    error(
      errors,
      [:planned_source_requests],
      :invalid_list,
      "expected list, got #{inspect(value)}"
    )
  end

  defp validate_planned_source_request(errors, path, %PlannedSourceRequest{} = request) do
    errors
    |> require_binary(path ++ [:request_id], request.request_id)
    |> require_binary(path ++ [:organization_id], request.organization_id)
    |> require_binary(path ++ [:mission_id], request.mission_id)
    |> require_in(path ++ [:logical_source], request.logical_source, @logical_sources)
    |> require_binary_list(path ++ [:observables], request.observables)
    |> require_struct(path ++ [:time_context], request.time_context, TimeContext)
    |> require_struct(path ++ [:scope_context], request.scope_context, ScopeContext)
    |> require_struct(path ++ [:data_context], request.data_context, DataContext)
    |> require_struct(path ++ [:limit_context], request.limit_context, LimitContext)
    |> require_optional_in(path ++ [:value_type], request.value_type, @source_value_types)
    |> require_map(path ++ [:sampling], request.sampling)
    |> validate_source_dependencies(path ++ [:source_dependencies], request.source_dependencies)
    |> require_list(path ++ [:overlays], request.overlays)
    |> require_map(path ++ [:metadata], request.metadata)
    |> validate_consumers(path ++ [:consumers], request.consumers)
  end

  defp validate_source_dependencies(errors, path, dependencies) when is_list(dependencies) do
    dependencies
    |> Enum.with_index()
    |> Enum.reduce(errors, fn {dependency, index}, errors ->
      dependency_path = path ++ [index]

      if is_map(dependency) do
        errors
        |> require_in(
          dependency_path ++ [:logical_source],
          Map.get(dependency, :logical_source),
          @logical_sources
        )
        |> require_atom(dependency_path ++ [:reason], Map.get(dependency, :reason))
        |> require_atom_list(dependency_path ++ [:products], Map.get(dependency, :products, []))
        |> require_map(dependency_path ++ [:sampling], Map.get(dependency, :sampling, %{}))
      else
        error(
          errors,
          dependency_path,
          :invalid_source_dependency,
          "expected map, got #{inspect(dependency)}"
        )
      end
    end)
  end

  defp validate_source_dependencies(errors, path, value) do
    error(errors, path, :invalid_list, "expected list, got #{inspect(value)}")
  end

  defp validate_consumers(errors, path, consumers) when is_list(consumers) do
    consumers
    |> Enum.with_index()
    |> Enum.reduce(errors, fn {consumer, index}, errors ->
      if is_map(consumer) do
        errors
        |> require_binary(path ++ [index, :placement_id], Map.get(consumer, :placement_id))
        |> require_atom(path ++ [index, :role], Map.get(consumer, :role))
        |> require_binary(path ++ [index, :widget_type_id], Map.get(consumer, :widget_type_id))
      else
        error(
          errors,
          path ++ [index],
          :invalid_consumer,
          "expected map, got #{inspect(consumer)}"
        )
      end
    end)
  end

  defp validate_consumers(errors, path, value) do
    error(errors, path, :invalid_list, "expected list, got #{inspect(value)}")
  end

  defp validate_plan_metadata(errors, metadata, required_keys, phase) when is_map(metadata) do
    errors =
      Enum.reduce(required_keys, errors, fn key, errors ->
        if Map.has_key?(metadata, key) do
          errors
        else
          error(errors, [:plan_metadata, key], :missing_key, "required metadata key is missing")
        end
      end)

    errors
    |> validate_cache_metadata(metadata)
    |> validate_execution_counts(metadata, phase)
  end

  defp validate_plan_metadata(errors, value, _required_keys, _phase) do
    error(errors, [:plan_metadata], :invalid_map, "expected map, got #{inspect(value)}")
  end

  defp validate_cache_metadata(errors, %{cache: cache}) when is_map(cache) do
    errors
    |> require_struct(
      [:plan_metadata, :cache, :plan_key],
      Map.get(cache, :plan_key),
      RuntimeCacheKey
    )
    |> require_map([:plan_metadata, :cache, :dependencies], Map.get(cache, :dependencies))
    |> require_map([:plan_metadata, :cache, :plan_cache], Map.get(cache, :plan_cache))
  end

  defp validate_cache_metadata(errors, _metadata), do: errors

  defp validate_execution_counts(errors, metadata, :resolve) do
    planned = Map.get(metadata, :source_request_count)
    executed = Map.get(metadata, :executed_source_request_count)
    skipped = Map.get(metadata, :skipped_source_request_count)

    errors =
      errors
      |> require_non_negative_integer([:plan_metadata, :source_request_count], planned)
      |> require_non_negative_integer([:plan_metadata, :executed_source_request_count], executed)
      |> require_non_negative_integer([:plan_metadata, :skipped_source_request_count], skipped)
      |> require_non_negative_integer(
        [:plan_metadata, :returned_frame_count],
        Map.get(metadata, :returned_frame_count)
      )

    if is_integer(planned) and is_integer(executed) and is_integer(skipped) and
         planned == executed + skipped do
      errors
    else
      error(
        errors,
        [:plan_metadata, :skipped_source_request_count],
        :inconsistent_execution_counts,
        "source_request_count must equal executed_source_request_count + skipped_source_request_count"
      )
    end
  end

  defp validate_execution_counts(errors, metadata, :plan) do
    errors
    |> require_non_negative_integer(
      [:plan_metadata, :source_request_count],
      Map.get(metadata, :source_request_count)
    )
    |> require_non_negative_integer(
      [:plan_metadata, :unbatched_source_request_count],
      Map.get(metadata, :unbatched_source_request_count)
    )
    |> require_non_negative_integer(
      [:plan_metadata, :batched_consumer_count],
      Map.get(metadata, :batched_consumer_count)
    )
  end

  defp require_struct(errors, path, value, module) do
    if is_struct(value, module) do
      errors
    else
      error(errors, path, :invalid_struct, "expected #{inspect(module)}, got #{inspect(value)}")
    end
  end

  defp require_optional_struct(errors, _path, nil, _module), do: errors

  defp require_optional_struct(errors, path, value, module),
    do: require_struct(errors, path, value, module)

  defp require_binary(errors, _path, value) when is_binary(value) and value != "", do: errors

  defp require_binary(errors, path, value) do
    error(errors, path, :invalid_binary, "expected non-empty binary, got #{inspect(value)}")
  end

  defp require_optional_binary(errors, _path, nil), do: errors

  defp require_optional_binary(errors, _path, value) when is_binary(value) and value != "",
    do: errors

  defp require_optional_binary(errors, path, value) do
    error(
      errors,
      path,
      :invalid_binary,
      "expected nil or non-empty binary, got #{inspect(value)}"
    )
  end

  defp require_action_route(errors, path, route, kind) when kind in [:navigate, :new_tab] do
    require_binary(errors, path, route)
  end

  defp require_action_route(errors, path, route, _kind),
    do: require_optional_binary(errors, path, route)

  defp require_atom(errors, _path, value) when is_atom(value) and not is_nil(value), do: errors

  defp require_atom(errors, path, value) do
    error(errors, path, :invalid_atom, "expected atom, got #{inspect(value)}")
  end

  defp require_atom_list(errors, path, values) when is_list(values) do
    values
    |> Enum.with_index()
    |> Enum.reduce(errors, fn
      {value, _index}, errors when is_atom(value) and not is_nil(value) ->
        errors

      {value, index}, errors ->
        error(errors, path ++ [index], :invalid_atom, "expected atom, got #{inspect(value)}")
    end)
  end

  defp require_atom_list(errors, path, value) do
    error(errors, path, :invalid_list, "expected list, got #{inspect(value)}")
  end

  defp require_in(errors, path, value, allowed) do
    if value in allowed do
      errors
    else
      error(
        errors,
        path,
        :unsupported_value,
        "expected one of #{inspect(allowed)}, got #{inspect(value)}"
      )
    end
  end

  defp require_optional_in(errors, _path, nil, _allowed), do: errors

  defp require_optional_in(errors, path, value, allowed),
    do: require_in(errors, path, value, allowed)

  defp require_in_list(errors, path, values, allowed) when is_list(values) do
    values
    |> Enum.with_index()
    |> Enum.reduce(errors, fn {value, index}, errors ->
      require_in(errors, path ++ [index], value, allowed)
    end)
  end

  defp require_in_list(errors, path, value, _allowed) do
    error(errors, path, :invalid_list, "expected list, got #{inspect(value)}")
  end

  defp require_boolean(errors, _path, value) when is_boolean(value), do: errors

  defp require_boolean(errors, path, value) do
    error(errors, path, :invalid_boolean, "expected boolean, got #{inspect(value)}")
  end

  defp require_map(errors, _path, value) when is_map(value), do: errors

  defp require_map(errors, path, value) do
    error(errors, path, :invalid_map, "expected map, got #{inspect(value)}")
  end

  defp require_list(errors, _path, value) when is_list(value), do: errors

  defp require_list(errors, path, value) do
    error(errors, path, :invalid_list, "expected list, got #{inspect(value)}")
  end

  defp require_binary_list(errors, path, values) when is_list(values) do
    values
    |> Enum.with_index()
    |> Enum.reduce(errors, fn
      {value, _index}, errors when is_binary(value) and value != "" ->
        errors

      {value, index}, errors ->
        error(
          errors,
          path ++ [index],
          :invalid_binary,
          "expected non-empty binary, got #{inspect(value)}"
        )
    end)
  end

  defp require_binary_list(errors, path, value) do
    error(errors, path, :invalid_list, "expected list, got #{inspect(value)}")
  end

  defp require_non_negative_integer(errors, _path, value) when is_integer(value) and value >= 0,
    do: errors

  defp require_non_negative_integer(errors, path, value) do
    error(errors, path, :invalid_count, "expected non-negative integer, got #{inspect(value)}")
  end

  defp finish([]), do: :ok
  defp finish(errors), do: {:error, Enum.reverse(errors)}

  defp metadata_attr(metadata, key) when is_map(metadata) do
    Map.get(metadata, key, Map.get(metadata, Atom.to_string(key)))
  end

  defp error(errors, path, code, message) do
    [%{path: path, code: code, message: message} | errors]
  end
end
