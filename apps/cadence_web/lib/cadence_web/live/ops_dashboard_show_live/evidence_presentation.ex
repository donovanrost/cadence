defmodule CadenceWeb.OpsDashboardShowLive.EvidencePresentation do
  @moduledoc false

  alias Cadence.Dashboards.{
    DataLink,
    EvidenceRef,
    Frame,
    FrameEvidence,
    PlacementFrames,
    SourceActions
  }

  alias CadenceWeb.OpsDashboardShowLive.EvidenceQuery
  alias CadenceWeb.OpsDashboardShowLive.RuntimeResult
  alias CadenceWeb.OpsDashboardShowLive.SourcePresentation

  @widget_link_targets [
    :limit_event,
    :limit_definition,
    :telemetry_sample,
    :telemetry_point,
    :mission_event,
    :source_health_event,
    :source_watermark_event,
    :telemetry_revision_decision_event,
    :telemetry_backfill_lifecycle_event,
    :contact_interval
  ]

  @widget_source_status_states ~w(stale unavailable retention_gap degraded unknown no_data partial)

  @spec evidence_inspector(term(), map()) :: map() | nil
  def evidence_inspector(result, %{"kind" => "warning"} = params) do
    warning_code = Map.get(params, "warning-code")
    placement_id = Map.get(params, "placement-id")

    result
    |> warning_summaries_for(placement_id)
    |> Enum.find(&(&1.code_text == warning_code))
    |> case do
      nil ->
        nil

      warning ->
        %{
          kind: :warning,
          kind_text: "warning",
          title: "#{warning.label} Evidence",
          subject: warning.code_text,
          status_text: warning.severity_text,
          message: warning.message,
          subject_rows:
            [
              detail_row("Warning", warning.code_text),
              detail_row("Severity", warning.severity_text),
              detail_row("Placement", placement_id)
            ]
            |> Enum.reject(&is_nil/1),
          detail_rows: warning.detail_rows,
          evidence: warning.evidence,
          links: warning.links,
          source_context: warning.details,
          actions: warning.actions
        }
    end
  end

  def evidence_inspector(result, %{"kind" => "source"} = params) do
    request_id = Map.get(params, "source-request-id")
    logical_source = Map.get(params, "logical-source")
    realm = Map.get(params, "realm")
    data_source_id = Map.get(params, "data-source-id")
    source_binding_id = Map.get(params, "source-binding-id")

    result
    |> SourcePresentation.source_incident_summaries()
    |> Enum.find(
      &source_incident_match?(
        &1,
        request_id,
        logical_source,
        realm,
        data_source_id,
        source_binding_id
      )
    )
    |> case do
      nil ->
        source_context_evidence_inspector(params)

      source ->
        source_incident_evidence_inspector(
          source,
          Map.get(params, "source-evidence-mode"),
          params
        )
    end
  end

  def evidence_inspector(result, %{"kind" => "frame"} = params) do
    placement_id = Map.get(params, "placement-id")
    observable_id = Map.get(params, "observable-id")

    result
    |> placement_frames_for(placement_id)
    |> frame_evidence_inspector(placement_id, observable_id)
  end

  def evidence_inspector(_result, %{"kind" => "dashboard_health"} = params) do
    query = EvidenceQuery.from_event_params(params)

    %{
      kind: :dashboard_health,
      kind_text: "dashboard health",
      title: "Dashboard Health Evidence",
      subject: dashboard_health_subject(params),
      status_text: Map.get(params, "dashboard-health-state", "captured"),
      message: "Captured dashboard health rollup for sharing and investigation.",
      subject_rows: EvidenceQuery.subject_rows(query, &value_text/1),
      detail_rows: EvidenceQuery.detail_rows(query, &value_text/1),
      evidence: [],
      links: [],
      actions: []
    }
  end

  def evidence_inspector(_result, %{"kind" => "query"} = params) do
    query = EvidenceQuery.from_event_params(params)

    %{
      kind: :query,
      kind_text: "query",
      title: "Widget Query Evidence",
      subject: EvidenceQuery.subject(query),
      status_text: query_evidence_status(params),
      message: "Captured widget query context for sharing and investigation.",
      subject_rows: EvidenceQuery.subject_rows(query, &value_text/1),
      detail_rows: EvidenceQuery.detail_rows(query, &value_text/1),
      evidence: [],
      links: [],
      actions: source_context_actions(params)
    }
  end

  def evidence_inspector(_result, _params), do: nil

  @spec frame_evidence_inspector(PlacementFrames.t() | term(), binary() | nil, binary() | nil) ::
          map() | nil
  def frame_evidence_inspector(
        %PlacementFrames{} = placement_frames,
        placement_id,
        observable_id
      ) do
    case FrameEvidence.inspect(placement_frames, observable_id) do
      %{
        frame: %Frame{} = frame,
        links: links,
        evidence_refs: evidence_refs,
        actions: actions
      } = inspection ->
        %{
          kind: :frame,
          kind_text: "frame",
          title: "Frame Evidence",
          subject: frame.frame_id || placement_id,
          status_text: "resolved",
          message: frame_evidence_message(frame),
          subject_rows: frame_subject_rows(frame, placement_id),
          detail_rows:
            frame_evidence_detail_rows(frame, Map.get(inspection, :overlay_frames, [])),
          evidence:
            evidence_refs
            |> Enum.map(&evidence_summary/1)
            |> Enum.uniq_by(&{&1.kind_text, &1.id}),
          links:
            links
            |> Enum.map(&link_summary/1)
            |> Enum.sort_by(&summary_link_sort_key/1),
          actions: actions
        }

      nil ->
        nil
    end
  end

  def frame_evidence_inspector(_placement_frames, _placement_id, _observable_id), do: nil

  @spec evidence_summary(EvidenceRef.t() | map()) :: map()
  def evidence_summary(%EvidenceRef{} = ref) do
    %{
      kind: ref.kind,
      kind_text: ref.kind |> context_text() |> String.replace("_", " "),
      id: ref.id,
      source: ref.source,
      source_text: context_text(ref.source),
      confidence: ref.confidence,
      confidence_text: context_text(ref.confidence),
      observed_at: ref.observed_at,
      observed_at_text: value_text(ref.observed_at)
    }
  end

  def evidence_summary(ref) when is_map(ref) do
    case EvidenceRef.normalize(ref) do
      %EvidenceRef{kind: kind, id: id, source: source, confidence: confidence} = normalized
      when not is_nil(kind) and not is_nil(id) and not is_nil(source) and not is_nil(confidence) ->
        evidence_summary(normalized)

      _invalid_ref ->
        evidence_summary_map(ref)
    end
  end

  @spec link_summary(DataLink.t() | map()) :: map()
  def link_summary(%DataLink{} = link) do
    %{
      link_id: link.link_id,
      label: link.label,
      target: link.target,
      target_text: link.target |> context_text() |> String.replace("_", " "),
      target_id: link.target_id,
      route: link.route,
      context: link.context,
      source: link.source,
      source_text: context_text(link.source),
      presentation: link.presentation,
      presentation_text: context_text(link.presentation)
    }
  end

  def link_summary(link) when is_map(link) do
    case DataLink.normalize(link) do
      %DataLink{target: target, presentation: presentation, source: source} = normalized
      when not is_nil(target) and not is_nil(presentation) and not is_nil(source) ->
        link_summary(normalized)

      _invalid_link ->
        link_summary_map(link)
    end
  end

  @spec detail_rows(map()) :: [map()]
  def detail_rows(details) when is_map(details) do
    details
    |> Enum.reject(fn {key, _value} -> key in [:actions, "actions"] end)
    |> Enum.flat_map(fn {key, value} ->
      detail_values(key, value)
    end)
    |> Enum.sort_by(& &1.label)
  end

  def detail_rows(_details), do: []

  @spec detail_row(binary(), term()) :: map() | nil
  def detail_row(_label, nil), do: nil
  def detail_row(label, value), do: %{label: label, value: value_text(value)}

  @spec detail_value(map() | term(), atom()) :: term()
  def detail_value(map, key) when is_map(map) and is_atom(key) do
    Map.get(map, key, Map.get(map, Atom.to_string(key)))
  end

  def detail_value(_map, _key), do: nil

  @spec status_text(term()) :: binary() | nil
  def status_text(nil), do: nil
  def status_text(value) when is_atom(value), do: Atom.to_string(value)
  def status_text(value), do: to_string(value)

  @spec context_text(term()) :: binary()
  def context_text(nil), do: "none"
  def context_text(value) when is_atom(value), do: Atom.to_string(value)
  def context_text(value), do: to_string(value)

  @spec value_text(term()) :: binary()
  def value_text(nil), do: "none"
  def value_text(value) when is_boolean(value), do: to_string(value)
  def value_text(value) when is_atom(value), do: Atom.to_string(value)
  def value_text(value) when is_binary(value), do: value
  def value_text(value) when is_number(value), do: to_string(value)
  def value_text(%DateTime{} = value), do: DateTime.to_iso8601(value)
  def value_text(value), do: inspect(value)

  defp warning_summaries_for(result, placement_id)
       when is_binary(placement_id) and placement_id != "" do
    placement_warnings =
      result
      |> RuntimeResult.placement_frames(placement_id)
      |> SourcePresentation.placement_warning_summaries()

    placement_warnings ++ SourcePresentation.dashboard_warning_summaries(result)
  end

  defp warning_summaries_for(result, _placement_id),
    do: SourcePresentation.dashboard_warning_summaries(result)

  defp source_incident_evidence_inspector(source, requested_mode, params) do
    mode = source_evidence_mode(source, requested_mode)

    %{
      kind: :source,
      kind_text: "source",
      title: "#{source.logical_source_text} #{source_evidence_title(source, mode)}",
      subject: source.request_id || source.logical_source_text,
      status_text: source_status_text(params, source_evidence_status_text(source, mode)),
      message: source_status_message(params, source_evidence_message(source, mode)),
      subject_rows: EvidenceQuery.source_identity_rows_from_source(source, &value_text/1),
      detail_rows:
        source_status_detail_rows(params) ++
          source.detail_rows ++ source_request_evidence_rows(params),
      evidence: source.evidence,
      links: [],
      actions: merge_source_actions(source_context_actions(params), source.actions)
    }
  end

  defp merge_source_actions(context_actions, source_actions) do
    context_actions
    |> Kernel.++(List.wrap(source_actions))
    |> Enum.uniq_by(& &1.action_id)
  end

  defp source_request_evidence_rows(params) when is_map(params) do
    EvidenceQuery.source_request_detail_rows(params, &value_text/1)
  end

  defp source_request_evidence_rows(_params), do: []

  defp source_context_evidence_inspector(params) when is_map(params) do
    if source_context_evidence_query?(params) do
      %{
        kind: :source,
        kind_text: "source",
        title: source_context_evidence_title(params),
        subject: EvidenceQuery.source_subject_from_event_params(params),
        status_text: source_status_text(params, "context_only"),
        message:
          source_status_message(
            params,
            "No source incident matched this cache evidence row in the current runtime context."
          ),
        subject_rows: EvidenceQuery.source_identity_rows_from_event_params(params, &value_text/1),
        detail_rows: source_status_detail_rows(params) ++ source_request_evidence_rows(params),
        evidence: [],
        links: [],
        actions: source_context_actions(params)
      }
    end
  end

  defp source_context_actions(params) when is_map(params) do
    params
    |> source_context_action_details()
    |> SourceActions.source_warning_actions(source: :evidence_panel)
  end

  defp source_context_action_details(params) do
    %{
      source_request_id: Map.get(params, "source-request-id"),
      logical_source: Map.get(params, "logical-source"),
      realm: Map.get(params, "realm"),
      data_source_id: Map.get(params, "data-source-id"),
      source_binding_id: Map.get(params, "source-binding-id"),
      dataset: Map.get(params, "dataset"),
      time_mode: Map.get(params, "time-mode"),
      time_axis: Map.get(params, "time-axis"),
      replay_run_id: Map.get(params, "replay-run-id"),
      scope_kind: Map.get(params, "scope-kind"),
      scope_id: Map.get(params, "scope-id"),
      scope_ids: Map.get(params, "scope-ids"),
      contact_id: Map.get(params, "contact-id"),
      source_endpoint_id: Map.get(params, "source-endpoint-id"),
      source_empty_reason: Map.get(params, "source-empty-reason"),
      requested_realm: Map.get(params, "requested-realm"),
      requested_data_source_id: Map.get(params, "requested-data-source-id"),
      requested_source_binding_id: Map.get(params, "requested-source-binding-id"),
      requested_dataset: Map.get(params, "requested-dataset"),
      requested_validity_state: Map.get(params, "requested-validity-state")
    }
    |> Enum.reject(fn {_key, value} -> value in [nil, ""] end)
    |> Map.new()
  end

  defp source_context_evidence_query?(params) do
    EvidenceQuery.source_context_event_query?(params)
  end

  defp source_context_evidence_title(params) do
    case widget_source_status_state(params) do
      nil ->
        "Source Evidence"

      _state ->
        case Map.get(params, "logical-source") do
          source when source in [nil, ""] -> "Source Status"
          source -> "#{source |> value_text() |> source_label()} Source Status"
        end
    end
  end

  defp query_evidence_status(params) do
    Map.get(params, "source-evidence-state") ||
      Map.get(params, "data-state") ||
      "captured"
  end

  defp dashboard_health_subject(params) do
    case Map.get(params, "dashboard-health-state") do
      value when value in [nil, ""] -> "dashboard health"
      value -> "dashboard health #{value}"
    end
  end

  defp source_status_text(params, fallback) do
    case widget_source_status_state(params) do
      nil -> fallback
      state -> state
    end
  end

  defp source_status_message(params, fallback) do
    params
    |> widget_source_status_state()
    |> source_status_message_for(params, fallback)
  end

  defp source_status_message_for("stale", params, _fallback),
    do: stale_source_status_message(params)

  defp source_status_message_for("unavailable", _params, _fallback),
    do:
      "Widget source status is unavailable; inspect source execution and source-health actions before trusting this value."

  defp source_status_message_for("retention_gap", _params, _fallback),
    do:
      "Widget source status is a retention gap; the selected time context may be outside available source retention."

  defp source_status_message_for("degraded", _params, _fallback),
    do:
      "Widget source status is degraded; inspect source-health evidence before trusting this value."

  defp source_status_message_for("unknown", _params, _fallback),
    do:
      "Widget source status is unknown; source health or watermark evidence could not prove freshness for this value."

  defp source_status_message_for("no_data", params, _fallback), do: source_no_data_message(params)

  defp source_status_message_for("partial", _params, _fallback),
    do:
      "Widget source returned partial data for the selected context; inspect missing series, source scope, and source-health evidence before trusting this value."

  defp source_status_message_for(nil, _params, fallback), do: fallback

  defp source_status_message_for(state, _params, _fallback),
    do:
      "Widget source status is #{String.replace(state, "_", " ")}; inspect source context before trusting this value."

  defp source_status_detail_rows(params) when is_map(params) do
    [
      detail_row("Widget source status", widget_source_status_state(params)),
      detail_row("Widget evidence mode", Map.get(params, "source-evidence-mode"))
    ]
    |> Enum.reject(&is_nil/1)
  end

  defp source_status_detail_rows(_params), do: []

  defp stale_source_status_message(params) do
    if present?(Map.get(params, "source-empty-reason")) do
      source_no_data_message(params) <>
        " Source freshness is also stale; inspect source freshness, binding context, and cache evidence before trusting this value."
    else
      "Widget source status is stale; inspect source freshness, binding context, and cache evidence before trusting this value."
    end
  end

  defp source_no_data_message(params) do
    empty_reason = Map.get(params, "source-empty-reason")
    contact_id = Map.get(params, "contact-id")
    source_endpoint_id = Map.get(params, "source-endpoint-id")

    cond do
      empty_reason == "contact_scope_no_data" and present?(contact_id) and
          present?(source_endpoint_id) ->
        "Widget source returned no data for contact #{contact_id} after filtering telemetry to source endpoint #{source_endpoint_id}."

      empty_reason == "source_endpoint_scope_no_data" and present?(source_endpoint_id) ->
        "Widget source returned no data after filtering telemetry to source endpoint #{source_endpoint_id}."

      true ->
        "Widget source returned no data for the selected context; inspect the request scope before treating the value as valid."
    end
  end

  defp widget_source_status_state(params) do
    case source_status_state(params) do
      state when state in @widget_source_status_states -> state
      _state -> nil
    end
  end

  defp source_status_state(params) when is_map(params) do
    case Map.get(params, "source-evidence-state") do
      value when is_binary(value) ->
        value = String.trim(value)
        if value == "", do: nil, else: value

      value when is_atom(value) and not is_nil(value) ->
        Atom.to_string(value)

      _value ->
        nil
    end
  end

  defp source_status_state(_params), do: nil

  defp source_label(value), do: value |> String.replace("_", " ") |> String.capitalize()

  defp source_evidence_mode(_source, "health"), do: :health
  defp source_evidence_mode(_source, "execution"), do: :execution

  defp source_evidence_mode(%{execution_dashboard_degraded?: true}, _requested_mode),
    do: :execution

  defp source_evidence_mode(_source, _requested_mode), do: :health

  defp source_evidence_title(_source, :health), do: "Source Evidence"
  defp source_evidence_title(source, :execution), do: source.incident_title

  defp source_evidence_status_text(source, :health), do: source.state_text
  defp source_evidence_status_text(source, :execution), do: source.incident_status_text

  defp source_evidence_message(source, :health) do
    "Realm #{source.realm_text}; confidence #{source.confidence_text}; source cache #{source.source_cache_text || "none"}."
  end

  defp source_evidence_message(source, :execution), do: source.incident_message

  defp source_incident_match?(
         source,
         request_id,
         logical_source,
         realm,
         data_source_id,
         source_binding_id
       ) do
    cond do
      present?(request_id) ->
        source.request_id == request_id

      present?(data_source_id) ->
        source.data_source_id == data_source_id and
          optional_match?(source.source_binding_id, source_binding_id) and
          optional_match?(context_text(source.logical_source), logical_source) and
          optional_match?(context_text(source.realm), realm)

      true ->
        optional_match?(context_text(source.logical_source), logical_source) and
          optional_match?(context_text(source.realm), realm)
    end
  end

  defp optional_match?(_left, nil), do: true
  defp optional_match?(_left, ""), do: true
  defp optional_match?(left, right), do: left == right

  defp present?(value), do: value not in [nil, ""]

  defp placement_frames_for(result, placement_id) when is_binary(placement_id),
    do: RuntimeResult.placement_frames(result, placement_id)

  defp placement_frames_for(_result, _placement_id), do: nil

  defp evidence_summary_map(ref) do
    observed_at = Map.get(ref, :observed_at, Map.get(ref, "observed_at"))

    %{
      kind: Map.get(ref, :kind, Map.get(ref, "kind")),
      kind_text: ref |> Map.get(:kind, Map.get(ref, "kind")) |> context_text(),
      id: Map.get(ref, :id, Map.get(ref, "id")),
      source: Map.get(ref, :source, Map.get(ref, "source")),
      source_text: ref |> Map.get(:source, Map.get(ref, "source")) |> context_text(),
      confidence: Map.get(ref, :confidence, Map.get(ref, "confidence")),
      confidence_text: ref |> Map.get(:confidence, Map.get(ref, "confidence")) |> context_text(),
      observed_at: observed_at,
      observed_at_text: value_text(observed_at)
    }
  end

  defp link_summary_map(link) do
    target = Map.get(link, :target, Map.get(link, "target"))
    source = Map.get(link, :source, Map.get(link, "source"))
    presentation = Map.get(link, :presentation, Map.get(link, "presentation"))

    %{
      link_id: Map.get(link, :link_id, Map.get(link, "link_id")),
      label: Map.get(link, :label, Map.get(link, "label")),
      target: target,
      target_text: target |> context_text() |> String.replace("_", " "),
      target_id: Map.get(link, :target_id, Map.get(link, "target_id")),
      route: Map.get(link, :route, Map.get(link, "route")),
      context: Map.get(link, :context, Map.get(link, "context", %{})),
      source: source,
      source_text: context_text(source),
      presentation: presentation,
      presentation_text: context_text(presentation)
    }
  end

  defp frame_evidence_message(%Frame{} = frame) do
    "#{context_text(frame.source)} #{context_text(frame.shape)} frame resolved from #{context_text(Map.get(frame.meta, :logical_source))}."
  end

  defp frame_subject_rows(%Frame{} = frame, placement_id) do
    [
      detail_row("Placement", placement_id),
      detail_row("Frame", frame.frame_id),
      detail_row("Source", frame.source),
      detail_row("Shape", frame.shape),
      detail_row("Observable", observable_id(frame)),
      detail_row("Logical source", Map.get(frame.meta, :logical_source)),
      detail_row("Source request", Map.get(frame.meta, :source_request_id)),
      detail_row("Realm", Map.get(frame.meta, :realm)),
      detail_row("Data source", Map.get(frame.meta, :data_source_id)),
      detail_row("Source binding", Map.get(frame.meta, :source_binding_id))
    ]
    |> Enum.reject(&is_nil/1)
  end

  defp frame_detail_rows(%Frame{source: :telemetry, shape: :scalar} = frame) do
    scalar_rows =
      case telemetry_scalar_data(frame) do
        %{time: time, value: value, sample_id: sample_id, quality_state: quality_state} ->
          [
            detail_row("Sample", sample_id),
            detail_row("Value", value),
            detail_row("Quality", quality_state),
            detail_row("Time", time)
          ]

        _missing ->
          []
      end

    (scalar_rows ++ frame_meta_rows(frame))
    |> Enum.reject(&is_nil/1)
  end

  defp frame_detail_rows(%Frame{} = frame), do: frame_meta_rows(frame)

  defp frame_evidence_detail_rows(%Frame{} = frame, overlay_frames) do
    (frame_detail_rows(frame) ++ overlay_frame_detail_rows(overlay_frames))
    |> Enum.reject(&is_nil/1)
    |> Enum.uniq_by(&{&1.label, &1.value})
  end

  defp overlay_frame_detail_rows(frames) when is_list(frames) do
    frames
    |> Enum.flat_map(fn
      %Frame{meta: meta} when is_map(meta) -> frame_semantic_interval_rows(meta)
      _other -> []
    end)
  end

  defp overlay_frame_detail_rows(_frames), do: []

  defp frame_meta_rows(%Frame{} = frame) do
    meta = frame.meta || %{}

    ([
       detail_row("Sampling", Map.get(meta, :sampling)),
       detail_row("Data view", Map.get(meta, :data_view)),
       detail_row("Value type", Map.get(meta, :value_type)),
       detail_row("Supported capability", Map.get(meta, :supported_capability)),
       detail_row("Product family", Map.get(meta, :family) || Map.get(meta, :product_family)),
       detail_row("Dataset", Map.get(meta, :dataset)),
       detail_row("Observable IDs", Map.get(meta, :observable_ids)),
       detail_row("Returned points", Map.get(meta, :returned_points)),
       detail_row("Returned events", Map.get(meta, :returned_events)),
       detail_row("Truncated", Map.get(meta, :truncated?)),
       detail_row("Warning codes", Map.get(meta, :warning_codes))
     ] ++ frame_semantic_interval_rows(meta) ++ frame_revision_rows(meta))
    |> Enum.reject(&is_nil/1)
  end

  defp frame_semantic_interval_rows(meta) when is_map(meta) do
    source_binding_interval_rows(detail_value(meta, :source_binding_interval)) ++
      selected_operational_interval_rows(detail_value(meta, :selected_operational_intervals)) ++
      selected_limit_definition_interval_rows(
        detail_value(meta, :selected_limit_definition_intervals)
      )
  end

  defp source_binding_interval_rows(interval) when is_map(interval) do
    [
      detail_row("Source binding interval", detail_value(interval, :data_binding_event_id)),
      detail_row("Source binding interval binding", detail_value(interval, :binding_id)),
      detail_row("Source binding interval data source", detail_value(interval, :data_source_id)),
      detail_row(
        "Source binding interval window",
        interval_window(
          detail_value(interval, :active_from) || detail_value(interval, :started_at),
          detail_value(interval, :active_to) || detail_value(interval, :ended_at)
        )
      )
    ]
  end

  defp source_binding_interval_rows(_interval), do: []

  defp selected_operational_interval_rows(intervals) when is_list(intervals) do
    intervals
    |> Enum.flat_map(&selected_operational_interval_row/1)
  end

  defp selected_operational_interval_rows(_intervals), do: []

  defp selected_limit_definition_interval_rows(intervals) when is_list(intervals) do
    intervals
    |> Enum.flat_map(&selected_limit_definition_interval_row/1)
  end

  defp selected_limit_definition_interval_rows(_intervals), do: []

  defp selected_limit_definition_interval_row(interval) when is_map(interval) do
    [
      detail_row("Limit definition interval", limit_definition_interval_summary(interval)),
      detail_row(
        "Limit definition interval lifecycle event",
        interval_detail_value(interval, :limit_definition_lifecycle_event_id) ||
          detail_value(interval, :source_event_id)
      )
    ]
  end

  defp selected_limit_definition_interval_row(_interval), do: []

  defp selected_operational_interval_row(interval) when is_map(interval) do
    label = "#{interval_kind_label(detail_value(interval, :kind))} interval"

    [
      detail_row(label, operational_interval_summary(interval)),
      detail_row("#{label} source event", detail_value(interval, :source_event_id))
    ]
  end

  defp selected_operational_interval_row(_interval), do: []

  defp limit_definition_interval_summary(interval) do
    definition = limit_definition_label(interval)

    interval_window =
      interval_window(
        detail_value(interval, :active_from) || detail_value(interval, :starts_at),
        detail_value(interval, :active_to) || detail_value(interval, :ends_at)
      )

    interval_summary(definition, interval_window)
  end

  defp limit_definition_label(interval) do
    interval
    |> limit_definition_subject()
    |> append_limit_definition_version(interval_detail_value(interval, :limit_definition_version))
    |> append_limit_set_name(interval_detail_value(interval, :limit_set_name))
  end

  defp limit_definition_subject(interval) do
    interval_detail_value(interval, :limit_definition_id) ||
      interval_detail_value(interval, :definition_id) ||
      detail_value(interval, :subject_id) ||
      detail_value(interval, :definition_activation_key) ||
      detail_value(interval, :interval_id)
  end

  defp interval_detail_value(interval, key) when is_map(interval) do
    detail_value(interval, key) ||
      nested_detail_value(interval, :payload, key) ||
      nested_detail_value(interval, :current, key) ||
      nested_detail_value(interval, :metadata, key)
  end

  defp interval_detail_value(_interval, _key), do: nil

  defp nested_detail_value(interval, container_key, key) when is_map(interval) do
    case detail_value(interval, container_key) do
      nested when is_map(nested) -> detail_value(nested, key)
      _other -> nil
    end
  end

  defp append_limit_definition_version(nil, _version), do: nil
  defp append_limit_definition_version(definition, nil), do: definition
  defp append_limit_definition_version(definition, version), do: "#{definition} v#{version}"

  defp append_limit_set_name(nil, _limit_set_name), do: nil
  defp append_limit_set_name(definition, nil), do: definition
  defp append_limit_set_name(definition, limit_set_name), do: "#{definition} / #{limit_set_name}"

  defp interval_summary(subject, interval_window) do
    case {subject, interval_window} do
      {nil, nil} -> nil
      {nil, window} -> window
      {subject, nil} -> subject
      {subject, window} -> "#{subject} (#{window})"
    end
  end

  defp operational_interval_summary(interval) do
    subject = detail_value(interval, :subject_id) || detail_value(interval, :interval_id)

    interval_window =
      interval_window(detail_value(interval, :starts_at), detail_value(interval, :ends_at))

    interval_summary(subject, interval_window)
  end

  defp interval_kind_label(:binding_set), do: "Binding set"
  defp interval_kind_label("binding_set"), do: "Binding set"
  defp interval_kind_label(:application_binding), do: "Application binding"
  defp interval_kind_label("application_binding"), do: "Application binding"
  defp interval_kind_label(:catalog_revision), do: "Catalog revision"
  defp interval_kind_label("catalog_revision"), do: "Catalog revision"
  defp interval_kind_label(:source_binding), do: "Source binding"
  defp interval_kind_label("source_binding"), do: "Source binding"
  defp interval_kind_label(:transport_execution), do: "Transport execution"
  defp interval_kind_label("transport_execution"), do: "Transport execution"

  defp interval_kind_label(kind) do
    kind
    |> context_text()
    |> String.replace("_", " ")
    |> String.capitalize()
  end

  defp interval_window(nil, nil), do: nil
  defp interval_window(from, nil), do: "#{value_text(from)} -> open"
  defp interval_window(nil, to), do: "unknown -> #{value_text(to)}"
  defp interval_window(from, to), do: "#{value_text(from)} -> #{value_text(to)}"

  defp frame_revision_rows(meta) when is_map(meta) do
    revision_state =
      meta
      |> detail_value(:revision_state)
      |> request_context_or_empty()

    dependency =
      meta
      |> revision_dependency(revision_state)
      |> request_context_or_empty()

    [
      detail_row("Revision identities", detail_value(revision_state, :identity_count)),
      detail_row("Revision canonical", detail_value(revision_state, :canonical_count)),
      detail_row("Revision superseded", detail_value(revision_state, :superseded_count)),
      detail_row("Revision advisory", detail_value(revision_state, :advisory_count)),
      detail_row("Revision conflicts", detail_value(revision_state, :conflict_count)),
      detail_row("Revision duplicates", detail_value(revision_state, :duplicate_count)),
      detail_row(
        "Revision dependency",
        detail_value(revision_state, :dependency_fingerprint) ||
          detail_value(dependency, :fingerprint)
      ),
      detail_row(
        "Revision observation identities",
        detail_value(dependency, :observation_identity_ids)
      )
    ]
  end

  defp telemetry_scalar_data(%Frame{source: :telemetry, shape: :scalar, fields: fields}) do
    with %{values: [time | _]} <- field_by_name(fields, "time"),
         value_field when not is_nil(value_field) <- value_field(fields),
         [value | _] <- value_field.values do
      %{
        time: time,
        value: value,
        sample_id:
          value_field.metadata
          |> metadata_values(:sample_ids)
          |> List.first(),
        quality_state:
          value_field.metadata
          |> metadata_values(:quality_states)
          |> List.first()
      }
    else
      _missing -> nil
    end
  end

  defp telemetry_scalar_data(%Frame{}), do: nil

  defp value_field(fields) do
    Enum.find(fields, &representative_value_field?/1) ||
      Enum.find(fields, fn field -> field.name not in ["time", "bucket_start", "bucket_end"] end)
  end

  defp representative_value_field?(%{name: name}) when is_binary(name),
    do: String.ends_with?(name, "_value")

  defp representative_value_field?(_field), do: false

  defp metadata_values(metadata, key) when is_map(metadata) and is_atom(key) do
    metadata
    |> Map.get(key, Map.get(metadata, Atom.to_string(key), []))
    |> List.wrap()
  end

  defp metadata_values(_metadata, _key), do: []

  defp field_by_name(fields, name), do: Enum.find(fields, &(&1.name == name))

  defp observable_id(%Frame{meta: meta}) when is_map(meta) do
    Map.get(meta, :observable_id, Map.get(meta, "observable_id"))
  end

  defp request_context_or_empty(context) when is_map(context), do: context
  defp request_context_or_empty(_context), do: %{}

  defp revision_dependency(meta, revision_state) do
    case detail_value(meta, :telemetry_revision_dependency) do
      dependency when is_map(dependency) -> dependency
      _missing -> detail_value(revision_state, :dependency) |> request_context_or_empty()
    end
  end

  defp detail_values(key, values) when is_list(values) do
    if keyword_list?(values) do
      [%{label: detail_label(key), value: inspect(values)}]
    else
      values
      |> Enum.with_index(1)
      |> Enum.map(fn {value, index} ->
        %{label: "#{detail_label(key)} #{index}", value: value_text(value)}
      end)
    end
  end

  defp detail_values(key, value) do
    [%{label: detail_label(key), value: value_text(value)}]
  end

  defp detail_label(key) do
    key
    |> to_string()
    |> String.replace("_", " ")
    |> String.capitalize()
  end

  defp keyword_list?(values) do
    Enum.all?(values, fn
      {key, _value} when is_atom(key) -> true
      _other -> false
    end)
  end

  defp summary_link_sort_key(%{target: target}) when is_binary(target) do
    target_atom = Enum.find(@widget_link_targets, &(Atom.to_string(&1) == target))
    Enum.find_index(@widget_link_targets, &(&1 == target_atom)) || length(@widget_link_targets)
  end

  defp summary_link_sort_key(%{target: target}) when is_atom(target) do
    Enum.find_index(@widget_link_targets, &(&1 == target)) || length(@widget_link_targets)
  end

  defp summary_link_sort_key(_link), do: length(@widget_link_targets)
end
