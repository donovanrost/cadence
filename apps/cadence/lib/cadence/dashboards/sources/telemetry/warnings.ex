defmodule Cadence.Dashboards.Sources.Telemetry.Warnings do
  @moduledoc false

  alias Cadence.Dashboards.{
    DataLinks,
    Frame,
    PlannedSourceRequest,
    ResolveWarning,
    SourceActions,
    TelemetryActions
  }

  alias Cadence.DataSources.SourceWatermark

  alias Cadence.Dashboards.Sources.Telemetry.FrameContext

  @spec history_diagnostics(PlannedSourceRequest.t(), binary(), map()) ::
          [ResolveWarning.t()]
  def history_diagnostics(
        %PlannedSourceRequest{} = request,
        observable_id,
        %{candidate_window_exhausted?: true} = diagnostics
      ) do
    [
      %ResolveWarning{
        code: :candidate_window_exhausted,
        severity: :warning,
        scope: :frame,
        frame_id: "#{request.request_id}:#{observable_id}",
        message: "Telemetry history candidate window was exhausted before selection completed",
        details:
          diagnostics
          |> Map.merge(%{
            source_request_id: request.request_id,
            observable_id: observable_id,
            point_id: observable_id
          })
          |> put_warning_actions(request, observable_id),
        links: DataLinks.request_observable_links(request, source: :warning)
      }
    ]
  end

  def history_diagnostics(%PlannedSourceRequest{}, _observable_id, _diagnostics), do: []

  @spec partial_coverage(PlannedSourceRequest.t(), map() | nil, [Frame.t()]) ::
          [ResolveWarning.t()]
  def partial_coverage(%PlannedSourceRequest{} = request, source_binding, frames)
      when is_list(frames) do
    empty_observables =
      frames
      |> Enum.filter(&empty_frame?/1)
      |> Enum.map(&frame_observable_id/1)
      |> Enum.reject(&is_nil/1)

    returned_observables =
      frames
      |> Enum.reject(&empty_frame?/1)
      |> Enum.map(&frame_observable_id/1)
      |> Enum.reject(&is_nil/1)

    if empty_observables != [] and returned_observables != [] do
      [
        warning(
          request,
          :partial_data,
          :warning,
          "Telemetry range source returned partial data",
          %{
            logical_source: :telemetry,
            requested_observables: request.observables,
            returned_observables: returned_observables,
            empty_observables: empty_observables,
            source_binding_id: FrameContext.source_binding_id(source_binding),
            data_source_id: FrameContext.data_source_id(request, source_binding),
            realm: FrameContext.realm(request, source_binding),
            time_mode: time_mode(request),
            time_axis: :receipt_time
          }
        )
      ]
    else
      []
    end
  end

  def partial_coverage(%PlannedSourceRequest{}, _source_binding, _frames), do: []

  @spec annotate_frames([Frame.t()], [ResolveWarning.t()]) :: [Frame.t()]
  def annotate_frames(frames, []), do: frames

  def annotate_frames(frames, warnings) when is_list(frames) and is_list(warnings) do
    warning_codes =
      warnings
      |> Enum.map(& &1.code)
      |> Enum.reject(&is_nil/1)

    Enum.map(frames, &annotate_frame(&1, warning_codes))
  end

  @spec overlay(PlannedSourceRequest.t()) :: [ResolveWarning.t()]
  def overlay(%PlannedSourceRequest{overlays: []}), do: []
  def overlay(%PlannedSourceRequest{overlays: nil}), do: []

  def overlay(%PlannedSourceRequest{} = request) do
    [
      warning(
        request,
        :capability_fallback,
        :info,
        "Telemetry source does not resolve overlays yet",
        %{
          requested_overlays: request.overlays,
          unresolved_capability: :overlays
        }
      )
    ]
  end

  @spec watermark(PlannedSourceRequest.t(), map() | nil, SourceWatermark.t()) ::
          [ResolveWarning.t()]
  def watermark(
        %PlannedSourceRequest{},
        _source_binding,
        %SourceWatermark{confidence: confidence}
      )
      when confidence in [:authoritative, :best_effort],
      do: []

  def watermark(
        %PlannedSourceRequest{} = request,
        source_binding,
        %SourceWatermark{} = watermark
      ) do
    unknown_watermark(request, source_binding, watermark)
  end

  @spec unknown_watermark(PlannedSourceRequest.t()) :: [ResolveWarning.t()]
  def unknown_watermark(%PlannedSourceRequest{} = request) do
    unknown_watermark(request, nil, nil)
  end

  @spec native_aggregate_semantics(PlannedSourceRequest.t()) :: [ResolveWarning.t()]
  def native_aggregate_semantics(%PlannedSourceRequest{} = request) do
    [
      warning(
        request,
        :physical_aggregate_semantics,
        :info,
        "Native telemetry aggregates use physical storage semantics",
        %{
          canonical_mode: :physical,
          aggregate_semantics: :physical_as_recorded,
          affected_products: [:native_decimated_envelope, :source_watermark],
          future_mode: :effective_canonical
        }
      )
    ]
  end

  @spec source_query_failure(
          PlannedSourceRequest.t(),
          map() | nil,
          binary() | nil,
          atom(),
          atom(),
          term()
        ) :: ResolveWarning.t()
  def source_query_failure(
        %PlannedSourceRequest{} = request,
        source_binding,
        observable_id,
        query_kind,
        unresolved_capability,
        reason
      ) do
    warning(
      request,
      :source_unavailable,
      :error,
      source_query_failure_message(query_kind),
      source_query_failure_details(
        request,
        source_binding,
        observable_id,
        query_kind,
        unresolved_capability,
        reason
      )
    )
  end

  @spec data_view(PlannedSourceRequest.t()) :: [ResolveWarning.t()]
  def data_view(%PlannedSourceRequest{} = request) do
    case FrameContext.data_view(request) do
      :canonical ->
        []

      :as_recorded ->
        [
          warning(
            request,
            :as_recorded_view,
            :info,
            "Telemetry source is using as-recorded data view",
            data_view_warning_details(request, :as_recorded)
          )
        ]

      :all_revisions ->
        [
          warning(
            request,
            :all_revisions_view,
            :warning,
            "Telemetry source is showing all observation revisions",
            data_view_warning_details(request, :all_revisions)
          )
        ]

      :recomputed ->
        [
          warning(
            request,
            :recomputed_values,
            :warning,
            "Telemetry source is using recomputed data view semantics",
            data_view_warning_details(request, :recomputed)
          )
        ]
    end
  end

  @spec warning(PlannedSourceRequest.t(), atom(), atom(), binary(), map()) ::
          ResolveWarning.t()
  def warning(%PlannedSourceRequest{} = request, code, severity, message, details) do
    %ResolveWarning{
      code: code,
      severity: severity,
      scope: :dashboard,
      message: message,
      details:
        details
        |> Map.put(:source_request_id, request.request_id)
        |> put_warning_actions(request, warning_observable_id(request, details)),
      links: DataLinks.request_observable_links(request, source: :warning)
    }
  end

  @spec key(ResolveWarning.t()) :: tuple()
  def key(%ResolveWarning{} = warning) do
    {warning.code, warning.scope, warning.frame_id, warning.field_name}
  end

  @spec degraded?([ResolveWarning.t()]) :: boolean()
  def degraded?(warnings), do: Enum.any?(warnings, &(&1.severity != :info))

  defp unknown_watermark(
         %PlannedSourceRequest{} = request,
         source_binding,
         %SourceWatermark{} = watermark
       ) do
    details =
      case watermark_errors(watermark) do
        [{observable_id, reason} | _rest] ->
          source_query_failure_details(
            request,
            source_binding,
            observable_id,
            :watermark,
            :source_watermark,
            reason
          )

        [] ->
          %{unresolved_capability: :source_watermark}
      end

    [
      warning(
        request,
        :watermark_unknown,
        :info,
        "Telemetry source watermark confidence is unknown",
        details
      )
    ]
  end

  defp unknown_watermark(%PlannedSourceRequest{} = request, _source_binding, _watermark) do
    [
      warning(
        request,
        :watermark_unknown,
        :info,
        "Telemetry source watermark confidence is unknown",
        %{unresolved_capability: :source_watermark}
      )
    ]
  end

  defp watermark_errors(%SourceWatermark{meta: %{point_watermarks: point_watermarks}})
       when is_map(point_watermarks) do
    point_watermarks
    |> Enum.flat_map(fn {observable_id, result} ->
      case watermark_error(result) do
        nil -> []
        reason -> [{observable_id, reason}]
      end
    end)
  end

  defp watermark_errors(%SourceWatermark{}), do: []

  defp watermark_error(result) when is_map(result), do: context_value(result, :error)
  defp watermark_error(_result), do: nil

  defp source_query_failure_message(:native_decimated_history),
    do: "Telemetry data source cannot execute native decimated history"

  defp source_query_failure_message(:watermark),
    do: "Telemetry data source cannot read source watermark"

  defp source_query_failure_message(_query_kind),
    do: "Telemetry data source cannot execute bounded history"

  defp source_query_failure_details(
         %PlannedSourceRequest{} = request,
         source_binding,
         observable_id,
         query_kind,
         unresolved_capability,
         reason
       ) do
    %{
      logical_source: :telemetry,
      source_empty_reason: :source_query_failed,
      source_query_kind: query_kind,
      unresolved_capability: unresolved_capability,
      reason: format_reason(reason),
      observable_id: observable_id || List.first(List.wrap(request.observables)),
      point_id: observable_id || List.first(List.wrap(request.observables)),
      data_source_id: FrameContext.data_source_id(request, source_binding),
      source_binding_id: FrameContext.source_binding_id(source_binding),
      realm: FrameContext.realm(request, source_binding),
      dataset: FrameContext.dataset(source_binding),
      requested_sampling: FrameContext.sampling_mode(request)
    }
    |> SourceActions.put_source_request_context(request, :telemetry)
    |> SourceActions.put_source_warning_actions()
  end

  defp data_view_warning_details(%PlannedSourceRequest{} = request, data_view) do
    %{
      data_view: data_view,
      canonical_default?: false,
      point_id: List.first(List.wrap(request.observables)),
      observable_id: List.first(List.wrap(request.observables))
    }
  end

  defp annotate_frame(%Frame{meta: meta} = frame, warning_codes) when is_map(meta) do
    existing_codes =
      meta
      |> Map.get(:warning_codes, Map.get(meta, "warning_codes", []))
      |> List.wrap()

    %Frame{
      frame
      | meta: Map.put(meta, :warning_codes, Enum.uniq(existing_codes ++ warning_codes))
    }
  end

  defp annotate_frame(frame, _warning_codes), do: frame

  defp empty_frame?(%Frame{meta: meta}) when is_map(meta) do
    Map.get(meta, :returned_points, Map.get(meta, "returned_points", 0)) == 0
  end

  defp empty_frame?(%Frame{}), do: true

  defp frame_observable_id(%Frame{meta: meta}) when is_map(meta) do
    Map.get(meta, :observable_id, Map.get(meta, "observable_id"))
  end

  defp frame_observable_id(%Frame{}), do: nil

  defp put_warning_actions(details, %PlannedSourceRequest{} = request, observable_id) do
    actions =
      TelemetryActions.explore_actions(request, observable_id, [],
        source: :warning,
        action_id: "telemetry-warning-explore:#{request.request_id}:#{observable_id || "unknown"}"
      )

    existing_actions = List.wrap(Map.get(details, :actions))

    if existing_actions == [] and actions == [] do
      details
    else
      Map.put(details, :actions, merge_warning_actions(existing_actions, actions))
    end
  end

  defp merge_warning_actions(existing_actions, new_actions) do
    existing_actions
    |> Kernel.++(new_actions)
    |> Enum.uniq_by(fn
      %{action_id: action_id} when is_binary(action_id) -> action_id
      %{target: target, query: query} -> {target, query}
      action -> action
    end)
  end

  defp warning_observable_id(%PlannedSourceRequest{} = request, details) do
    details[:observable_id] || details["observable_id"] || details[:point_id] ||
      details["point_id"] ||
      List.first(List.wrap(request.observables))
  end

  defp time_mode(%PlannedSourceRequest{time_context: time_context}) do
    time_context
    |> context_value(:mode)
    |> normalize_atom()
  end

  defp context_value(context, key) when is_map(context) and is_atom(key) do
    Map.get(context, key, Map.get(context, Atom.to_string(key)))
  end

  defp context_value(_context, _key), do: nil

  defp normalize_atom(value) when is_atom(value), do: value

  defp normalize_atom(value) when is_binary(value) do
    value
    |> String.trim()
    |> String.downcase()
    |> String.replace("-", "_")
    |> String.to_existing_atom()
  rescue
    ArgumentError -> value
  end

  defp normalize_atom(value), do: value

  defp format_reason(reason) when is_binary(reason), do: reason
  defp format_reason(reason), do: inspect(reason)
end
