defmodule CadenceWeb.OpsDashboardShowLive.SourcePresentation do
  @moduledoc false

  alias Cadence.Dashboards.{
    DashboardAction,
    DashboardResolveResult,
    PlacementFrames,
    SourceActions,
    SourceExecutionSemantics,
    SourceIncident
  }

  alias CadenceWeb.OpsDashboardShowLive.EvidencePresentation

  @spec dashboard_warning_summaries(term()) :: [map()]
  def dashboard_warning_summaries(nil), do: []

  def dashboard_warning_summaries(result) do
    result
    |> SourceIncident.source_execution_warnings()
    |> Enum.map(&warning_summary/1)
    |> dedupe_warning_summaries()
  end

  @spec dashboard_degraded?(term()) :: boolean()
  def dashboard_degraded?(nil), do: false

  def dashboard_degraded?(%DashboardResolveResult{plan_metadata: %{degraded?: true}}), do: true

  def dashboard_degraded?(%DashboardResolveResult{} = result) do
    result
    |> SourceExecutionSemantics.summarize()
    |> Map.fetch!(:outcomes)
    |> Enum.any?(& &1.dashboard_degraded?)
  end

  def dashboard_degraded?(%{plan_metadata: plan_metadata}) when is_map(plan_metadata),
    do: plan_metadata[:degraded?] == true or plan_metadata["degraded?"] == true

  def dashboard_degraded?(_result), do: false

  @spec placement_warning_summaries(PlacementFrames.t() | nil) :: [map()]
  def placement_warning_summaries(%PlacementFrames{warnings: warnings}) do
    warnings
    |> Enum.map(&warning_summary/1)
    |> dedupe_warning_summaries()
  end

  def placement_warning_summaries(_placement_frames), do: []

  @spec source_health_summaries(term()) :: [map()]
  def source_health_summaries(result), do: source_incident_summaries(result)

  @spec source_selection_summaries(term()) :: [map()]
  def source_selection_summaries(nil), do: []

  def source_selection_summaries(%DashboardResolveResult{plan_metadata: plan_metadata}) do
    selection_summaries_from_metadata(plan_metadata)
  end

  def source_selection_summaries(%{plan_metadata: plan_metadata}) do
    selection_summaries_from_metadata(plan_metadata)
  end

  def source_selection_summaries(%{"plan_metadata" => plan_metadata}) do
    selection_summaries_from_metadata(plan_metadata)
  end

  def source_selection_summaries(_result), do: []

  @spec source_incident_summaries(term()) :: [map()]
  def source_incident_summaries(result) do
    result
    |> SourceIncident.summaries()
    |> Enum.map(&present_source_incident/1)
  end

  defp warning_summary(
         %{code: code, severity: severity, message: message, details: details} = warning
       ) do
    %{
      code: code,
      code_text: Atom.to_string(code),
      severity: severity || :warning,
      severity_text: severity |> Kernel.||(:warning) |> Atom.to_string(),
      label: warning_label(code),
      message: message || warning_label(code),
      details: details || %{},
      detail_rows: warning_detail_rows(code, details || %{}),
      evidence: warning_evidence(Map.get(warning, :evidence, [])),
      links: warning_links(Map.get(warning, :links, [])),
      actions: warning_actions(details || %{})
    }
  end

  defp warning_evidence(evidence) when is_list(evidence) do
    Enum.map(evidence, &EvidencePresentation.evidence_summary/1)
  end

  defp warning_evidence(_evidence), do: []

  defp warning_links(links) when is_list(links) do
    Enum.map(links, &EvidencePresentation.link_summary/1)
  end

  defp warning_links(_links), do: []

  defp warning_actions(details) when is_map(details) do
    details
    |> EvidencePresentation.detail_value(:actions)
    |> DashboardAction.normalize_many()
  end

  defp warning_label(:missing_source_binding), do: "Source missing"
  defp warning_label(:missing_data_source), do: "Source missing"
  defp warning_label(:unsupported_widget_frame_contract), do: "Unsupported widget source"
  defp warning_label(:unsupported_source_capability), do: "Unsupported source capability"
  defp warning_label(:unsupported_time_axis), do: "Unsupported time"
  defp warning_label(:unsupported_overlay), do: "Overlay unavailable"
  defp warning_label(:watermark_unknown), do: "Freshness unknown"
  defp warning_label(:unknown_watermark), do: "Freshness unknown"
  defp warning_label(:missing_snapshot), do: "Snapshot missing"
  defp warning_label(:as_recorded_view), do: "As recorded"
  defp warning_label(:all_revisions_view), do: "All revisions"
  defp warning_label(:recomputed_values), do: "Recomputed"
  defp warning_label(:incomplete_limit_evaluation), do: "Incomplete limit analysis"
  defp warning_label(:limit_analysis_diverged), do: "Limit analysis diverged"
  defp warning_label(:unknown_limit_definition), do: "Limit definition missing"
  defp warning_label(:stale_limit_state), do: "Stale"
  defp warning_label(:stale_data), do: "Source stale"
  defp warning_label(:retention_gap), do: "Retention gap"
  defp warning_label(:partial_data), do: "Partial data"
  defp warning_label(:source_degraded), do: "Source degraded"
  defp warning_label(:source_unavailable), do: "Source unavailable"
  defp warning_label(:source_execution_failed), do: "Source failed"
  defp warning_label(:source_execution_facts_error), do: "Source facts unavailable"
  defp warning_label(:invalid_runtime_context), do: "Invalid context"
  defp warning_label(:unsupported_source_adapter), do: "Source unsupported"
  defp warning_label(_code), do: "Engine warning"

  defp warning_detail_rows(:unsupported_time_axis, details) do
    [
      EvidencePresentation.detail_row(
        "Requested axis",
        EvidencePresentation.detail_value(details, :requested_time_axis) ||
          EvidencePresentation.detail_value(details, :requested_axis)
      ),
      EvidencePresentation.detail_row(
        "Executed axis",
        EvidencePresentation.detail_value(details, :executed_time_axis) ||
          EvidencePresentation.detail_value(details, :fallback_axis)
      ),
      EvidencePresentation.detail_row(
        "Supported axes",
        joined_status_text(EvidencePresentation.detail_value(details, :supported_time_axes))
      ),
      EvidencePresentation.detail_row(
        "Source request",
        EvidencePresentation.detail_value(details, :source_request_id)
      )
    ]
    |> Enum.reject(&is_nil/1)
  end

  defp warning_detail_rows(:incomplete_limit_evaluation, details) do
    [
      EvidencePresentation.detail_row(
        "Observable",
        EvidencePresentation.detail_value(details, :observable_id)
      ),
      EvidencePresentation.detail_row(
        "Limit mode",
        EvidencePresentation.detail_value(details, :requested_semantics_mode)
      ),
      EvidencePresentation.detail_row(
        "Selected clock",
        selected_limit_clock_text(
          EvidencePresentation.detail_value(details, :selected_limit_clock)
        )
      ),
      EvidencePresentation.detail_row(
        "Missing samples",
        joined_status_text(EvidencePresentation.detail_value(details, :missing_sample_ids))
      ),
      EvidencePresentation.detail_row(
        "Unresolved",
        EvidencePresentation.detail_value(details, :unresolved_capability)
      ),
      EvidencePresentation.detail_row(
        "Source request",
        EvidencePresentation.detail_value(details, :source_request_id)
      )
    ]
    |> Enum.reject(&is_nil/1)
  end

  defp warning_detail_rows(_code, details), do: EvidencePresentation.detail_rows(details)

  defp dedupe_warning_summaries(summaries) do
    summaries
    |> Enum.uniq_by(&{&1.code, &1.severity, &1.label})
    |> Enum.sort_by(&warning_sort_key/1)
  end

  defp warning_sort_key(%{severity: :error, label: label}), do: {0, label}
  defp warning_sort_key(%{severity: :warning, label: label}), do: {1, label}
  defp warning_sort_key(%{label: label}), do: {2, label}

  defp selection_summaries_from_metadata(plan_metadata) when is_map(plan_metadata) do
    plan_metadata
    |> context_value(:source_selection_by_request_id, %{})
    |> case do
      selections when is_map(selections) ->
        selections
        |> Enum.map(fn {request_id, selection} ->
          source_selection_summary(request_id, selection)
        end)
        |> Enum.reject(&is_nil/1)
        |> Enum.sort_by(& &1.request_id)

      _other ->
        []
    end
  end

  defp selection_summaries_from_metadata(_plan_metadata), do: []

  defp source_selection_summary(request_id, selection) when is_map(selection) do
    candidates =
      selection
      |> context_value(:candidates, [])
      |> candidate_summaries()

    selected_candidate =
      Enum.find(candidates, &(&1.decision == :selected))

    selected_binding_id =
      context_value(selection, :selected_source_binding_id) ||
        context_value(selected_candidate || %{}, :binding_id)

    selected_data_source_id =
      context_value(selection, :selected_data_source_id) ||
        context_value(selected_candidate || %{}, :data_source_id)

    %{
      request_id: text_value(request_id),
      logical_source: context_value(selection, :logical_source),
      logical_source_text: context_value(selection, :logical_source) |> source_text(),
      strategy: context_value(selection, :strategy),
      strategy_text: context_value(selection, :strategy) |> EvidencePresentation.status_text(),
      selected_binding_id: text_value(selected_binding_id),
      selected_data_source_id: text_value(selected_data_source_id),
      selected_dataset: context_value(selection, :selected_dataset) |> text_value(),
      selected_realm:
        context_value(selection, :selected_realm) |> EvidencePresentation.status_text(),
      requested_realm:
        context_value(selection, :requested_realm) |> EvidencePresentation.status_text(),
      requested_time_mode:
        context_value(selection, :requested_time_mode) |> EvidencePresentation.status_text(),
      requested_time_axis:
        context_value(selection, :requested_time_axis) |> EvidencePresentation.status_text(),
      candidate_count: context_value(selection, :candidate_count, length(candidates)),
      eligible_candidate_count:
        context_value(selection, :eligible_candidate_count, eligible_candidate_count(candidates)),
      rejected_candidate_count: Enum.count(candidates, &(&1.decision == :rejected)),
      skipped_candidate_count:
        Enum.count(candidates, &(&1.decision in [:rejected, :not_selected])),
      state: selection_state(selected_binding_id, candidates),
      state_text:
        selection_state(selected_binding_id, candidates) |> EvidencePresentation.status_text(),
      candidates: candidates
    }
  end

  defp source_selection_summary(_request_id, _selection), do: nil

  defp candidate_summaries(candidates) when is_list(candidates) do
    candidates
    |> Enum.map(&candidate_summary/1)
    |> Enum.reject(&is_nil/1)
  end

  defp candidate_summaries(_candidates), do: []

  defp candidate_summary(candidate) when is_map(candidate) do
    decision = context_value(candidate, :decision)
    reasons = reason_values(context_value(candidate, :reasons, []))
    inventory_action = source_selection_candidate_inventory_action(candidate)
    capability_posture = context_value(candidate, :capability_posture, %{})

    %{
      binding_id: context_value(candidate, :binding_id) |> text_value(),
      data_source_id: context_value(candidate, :data_source_id) |> text_value(),
      logical_source_text: context_value(candidate, :logical_source) |> source_text(),
      realm_text: context_value(candidate, :realm) |> EvidencePresentation.status_text(),
      dataset: context_value(candidate, :dataset) |> text_value(),
      priority: context_value(candidate, :priority),
      started_at_text: context_value(candidate, :started_at) |> timestamp_text(),
      ended_at_text: context_value(candidate, :ended_at) |> timestamp_text(),
      decision: decision,
      decision_text: decision |> EvidencePresentation.status_text(),
      reasons: reasons,
      reasons_text: joined_status_text(reasons),
      source_health_text:
        context_value(candidate, :source_health) |> EvidencePresentation.status_text(),
      source_health_reason_text:
        context_value(candidate, :source_health_reason) |> EvidencePresentation.status_text(),
      source_health_freshness_text:
        context_value(candidate, :source_health_freshness) |> EvidencePresentation.status_text(),
      requested_products_text:
        candidate_product_values(candidate, capability_posture, :requested_products)
        |> joined_status_text(),
      supported_products_text:
        candidate_product_values(candidate, capability_posture, :supported_products)
        |> joined_status_text(),
      missing_products_text:
        candidate_missing_product_values(candidate, capability_posture)
        |> joined_status_text(),
      readiness_policy_id_text:
        context_value(candidate, :source_readiness_policy_id)
        |> EvidencePresentation.status_text(),
      inventory_query: action_query(inventory_action),
      inventory_action_label: action_label(inventory_action)
    }
  end

  defp candidate_summary(_candidate), do: nil

  defp candidate_product_values(candidate, capability_posture, key) do
    candidate
    |> context_value(key, context_value(capability_posture, key, []))
    |> list_values()
  end

  defp candidate_missing_product_values(candidate, capability_posture) do
    candidate_missing_product_values(candidate) ++
      capability_posture_missing_product_values(capability_posture)
  end

  defp candidate_missing_product_values(candidate) do
    candidate
    |> context_value(:missing_products, [])
    |> list_values()
  end

  defp capability_posture_missing_product_values(capability_posture)
       when is_map(capability_posture) do
    capability_posture
    |> context_value(:unsupported, [])
    |> list_values()
    |> Enum.filter(&(context_value(&1, :capability) in [:products, "products"]))
    |> Enum.flat_map(&list_values(context_value(&1, :missing, [])))
  end

  defp capability_posture_missing_product_values(_capability_posture), do: []

  defp source_selection_candidate_inventory_action(candidate) when is_map(candidate) do
    candidate
    |> source_selection_candidate_context()
    |> SourceActions.source_inventory_action(
      source: :source_selection,
      inventory_action_id: "dashboard-source-selection-inventory-action",
      inventory_label: "Open source inventory"
    )
  end

  defp source_selection_candidate_context(candidate) when is_map(candidate) do
    %{
      source_binding_id: context_value(candidate, :binding_id),
      data_source_id: context_value(candidate, :data_source_id),
      logical_source: context_value(candidate, :logical_source),
      realm: context_value(candidate, :realm)
    }
    |> Enum.reject(fn {_key, value} -> value in [nil, ""] end)
    |> Map.new()
  end

  defp action_query(%DashboardAction{query: query}) when is_map(query), do: query
  defp action_query(_action), do: %{}

  defp action_label(%DashboardAction{label: label}) when is_binary(label), do: label
  defp action_label(_action), do: nil

  defp eligible_candidate_count(candidates), do: Enum.count(candidates, &(&1.reasons == []))

  defp selection_state(selected_binding_id, _candidates) when is_binary(selected_binding_id),
    do: :selected

  defp selection_state(_selected_binding_id, candidates) do
    if Enum.any?(candidates, &(&1.decision == :rejected)) do
      :blocked
    else
      :unresolved
    end
  end

  defp reason_values(reasons) when is_list(reasons), do: reasons
  defp reason_values(_reasons), do: []

  defp joined_status_text(values) when is_list(values) do
    values
    |> Enum.map(&EvidencePresentation.status_text/1)
    |> Enum.reject(&is_nil/1)
    |> Enum.join(",")
  end

  defp joined_status_text(_values), do: nil

  defp list_values(values) when is_list(values), do: values
  defp list_values(nil), do: []
  defp list_values(value), do: [value]

  defp selected_limit_clock_text(clock) when is_map(clock) do
    clock
    |> Enum.map(fn {key, value} ->
      "#{EvidencePresentation.status_text(key)}=#{EvidencePresentation.status_text(value)}"
    end)
    |> Enum.sort()
    |> Enum.join(" ")
  end

  defp selected_limit_clock_text(_clock), do: nil

  defp text_value(nil), do: nil
  defp text_value(value) when is_binary(value), do: value
  defp text_value(value) when is_atom(value), do: Atom.to_string(value)
  defp text_value(value), do: to_string(value)

  defp timestamp_text(nil), do: nil
  defp timestamp_text(%DateTime{} = value), do: DateTime.to_iso8601(value)
  defp timestamp_text(value), do: text_value(value)

  defp context_value(nil, _key, default), do: default

  defp context_value(map, key, default) when is_map(map),
    do: Map.get(map, key, Map.get(map, Atom.to_string(key), default))

  defp context_value(_map, _key, default), do: default

  defp context_value(map, key), do: context_value(map, key, nil)

  defp present_source_incident(incident) do
    source_cache = Map.get(incident, :source_cache, %{})
    frame_cache = Map.get(incident, :frame_cache, %{})
    source_warning = Map.get(incident, :source_warning, %{})
    execution_outcome = execution_outcome_from_incident(incident)

    incident
    |> Map.merge(%{
      incident_status_text:
        incident.incident_status && EvidencePresentation.status_text(incident.incident_status),
      incident_title: source_incident_title(incident),
      incident_message: source_incident_message(incident),
      logical_source_text: source_text(incident.logical_source),
      realm_text: EvidencePresentation.context_text(incident.realm),
      state_text: Atom.to_string(incident.state),
      label: source_health_label(incident.logical_source, incident.state),
      source_health_probe_kind_text:
        EvidencePresentation.context_text(Map.get(incident, :source_health_probe_kind)),
      source_health_probe_message_text:
        EvidencePresentation.context_text(Map.get(incident, :source_health_probe_message)),
      source_health_probe_metadata_text:
        probe_metadata_summary(Map.get(incident, :source_health_probe_metadata)),
      confidence_text: incident.confidence |> EvidencePresentation.context_text(),
      source_cache_text: cache_status_text(source_cache),
      source_cache_reasons_text: cache_reasons_text(source_cache),
      frame_cache_text: cache_status_text(frame_cache),
      circuit_state_text: EvidencePresentation.status_text(incident.circuit_state),
      execution_status_text: execution_status_text(execution_outcome),
      execution_severity_text: execution_severity_text(execution_outcome),
      execution_operator_action_text: execution_operator_action_text(execution_outcome),
      execution_runtime_action_text: execution_runtime_action_text(execution_outcome),
      execution_warning_codes_text: execution_warning_codes_text(execution_outcome),
      source_warning_text: source_warning_text(source_warning),
      detail_rows: source_health_detail_rows(incident),
      evidence:
        incident
        |> Map.get(:evidence_refs, [])
        |> Enum.map(&EvidencePresentation.evidence_summary/1)
    })
  end

  defp execution_outcome_from_incident(incident) do
    %{
      status: incident.execution_status,
      severity: incident.execution_severity,
      operator_action: incident.execution_operator_action,
      runtime_action: incident.execution_runtime_action,
      degraded?: incident.execution_degraded?,
      actionable?: incident.execution_actionable?,
      retryable?: incident.execution_retryable?,
      warning_codes: incident.execution_warning_codes
    }
  end

  defp source_incident_title(%{incident_kind: :source_execution}), do: "Source Execution"
  defp source_incident_title(_incident), do: "Source Evidence"

  defp source_incident_message(%{incident_kind: :source_execution} = incident) do
    "Source execution #{EvidencePresentation.status_text(incident.execution_status)}; action #{EvidencePresentation.status_text(incident.execution_operator_action)}."
  end

  defp source_incident_message(incident) do
    "Realm #{EvidencePresentation.context_text(incident.realm)}; confidence #{EvidencePresentation.context_text(incident.confidence)}; source cache #{cache_status_text(incident.source_cache) || "none"}."
  end

  defp source_health_label(logical_source, state) do
    "#{source_text(logical_source)} #{state_text(state)}"
  end

  defp source_text(nil), do: "Source"

  defp source_text(logical_source) when is_atom(logical_source) do
    logical_source
    |> Atom.to_string()
    |> String.replace("_", " ")
    |> String.capitalize()
  end

  defp source_text(logical_source) when is_binary(logical_source) do
    logical_source
    |> String.replace("_", " ")
    |> String.capitalize()
  end

  defp state_text(:fresh), do: "fresh"
  defp state_text(:stale), do: "stale"
  defp state_text(:unknown), do: "unknown"
  defp state_text(:retention_gap), do: "retention gap"
  defp state_text(state), do: Atom.to_string(state)

  defp source_health_detail_rows(incident) do
    source_cache = Map.get(incident, :source_cache, %{})
    frame_cache = Map.get(incident, :frame_cache, %{})
    source_warning = Map.get(incident, :source_warning, %{})
    warning_details = Map.get(source_warning, :details, %{})
    execution_outcome = execution_outcome_from_incident(incident)

    [
      EvidencePresentation.detail_row("Logical source", incident.logical_source),
      EvidencePresentation.detail_row("Source request", incident.request_id),
      EvidencePresentation.detail_row("Realm", incident.realm),
      EvidencePresentation.detail_row("Source binding", incident.source_binding_id),
      EvidencePresentation.detail_row("Data source", incident.data_source_id),
      EvidencePresentation.detail_row("Dataset", incident.dataset),
      EvidencePresentation.detail_row("Source health event", incident.source_health_event_id),
      EvidencePresentation.detail_row("Source health reason", incident.source_health_reason),
      EvidencePresentation.detail_row("Probe kind", incident.source_health_probe_kind),
      EvidencePresentation.detail_row("Probe message", incident.source_health_probe_message),
      EvidencePresentation.detail_row(
        "Probe metadata",
        probe_metadata_summary(incident.source_health_probe_metadata)
      ),
      EvidencePresentation.detail_row("Confidence", incident.confidence),
      EvidencePresentation.detail_row("Freshness", incident.state),
      EvidencePresentation.detail_row("Source cache", cache_status_text(source_cache)),
      EvidencePresentation.detail_row("Source cache reason", cache_reasons_text(source_cache)),
      EvidencePresentation.detail_row("Frame cache", cache_status_text(frame_cache)),
      EvidencePresentation.detail_row(
        "Execution status",
        execution_status_text(execution_outcome)
      ),
      EvidencePresentation.detail_row(
        "Execution severity",
        execution_severity_text(execution_outcome)
      ),
      EvidencePresentation.detail_row(
        "Execution action",
        execution_operator_action_text(execution_outcome)
      ),
      EvidencePresentation.detail_row(
        "Execution runtime action",
        execution_runtime_action_text(execution_outcome)
      ),
      EvidencePresentation.detail_row(
        "Execution degraded",
        Map.get(execution_outcome, :degraded?)
      ),
      EvidencePresentation.detail_row(
        "Execution actionable",
        Map.get(execution_outcome, :actionable?)
      ),
      EvidencePresentation.detail_row(
        "Execution retryable",
        Map.get(execution_outcome, :retryable?)
      ),
      EvidencePresentation.detail_row(
        "Execution warnings",
        execution_warning_codes_text(execution_outcome)
      ),
      EvidencePresentation.detail_row(
        "Circuit",
        EvidencePresentation.detail_value(warning_details, :circuit_state)
      ),
      EvidencePresentation.detail_row("Circuit failures", circuit_failures(warning_details)),
      EvidencePresentation.detail_row(
        "Circuit retry after",
        EvidencePresentation.detail_value(warning_details, :retry_after_ms)
      ),
      EvidencePresentation.detail_row("Source warning", source_warning_text(source_warning))
    ]
    |> Enum.reject(&is_nil/1)
  end

  defp cache_status_text(%{statuses: [_ | _] = statuses}) do
    statuses
    |> Enum.map(&cache_status_label/1)
    |> Enum.sort()
    |> Enum.join(" ")
  end

  defp cache_status_text(%{status: status}), do: cache_status_label(status)
  defp cache_status_text(_summary), do: nil

  defp cache_status_label(:stale), do: "stale rejected"
  defp cache_status_label(:refresh), do: "refresh"
  defp cache_status_label(status) when is_atom(status), do: Atom.to_string(status)
  defp cache_status_label(status) when is_binary(status), do: status
  defp cache_status_label(_status), do: nil

  defp cache_reasons_text(%{reasons: [_ | _] = reasons}) do
    reasons
    |> Enum.map(&EvidencePresentation.status_text/1)
    |> Enum.sort()
    |> Enum.join(" ")
  end

  defp cache_reasons_text(_summary), do: nil

  defp source_warning_text(%{code: code}) when is_atom(code), do: warning_label(code)
  defp source_warning_text(_warning), do: nil

  defp probe_metadata_summary(metadata) when is_map(metadata) and map_size(metadata) > 0 do
    metadata
    |> Enum.map(fn {key, value} -> "#{key}=#{safe_probe_metadata_value(key, value)}" end)
    |> Enum.sort()
    |> Enum.join(" ")
  end

  defp probe_metadata_summary(_metadata), do: nil

  defp safe_probe_metadata_value(key, _value)
       when key in [
              :access_key,
              :api_key,
              :api_token,
              :apikey,
              :bearer_token,
              :credential,
              :credentials,
              :password,
              :passwd,
              :secret,
              :secret_key,
              :token,
              "access_key",
              "api_key",
              "api_token",
              "apikey",
              "bearer_token",
              "credential",
              "credentials",
              "password",
              "passwd",
              "secret",
              "secret_key",
              "token"
            ],
       do: "redacted"

  defp safe_probe_metadata_value(_key, value) when is_boolean(value), do: to_string(value)
  defp safe_probe_metadata_value(_key, nil), do: "none"
  defp safe_probe_metadata_value(_key, value) when is_binary(value), do: value
  defp safe_probe_metadata_value(_key, value) when is_atom(value), do: Atom.to_string(value)
  defp safe_probe_metadata_value(_key, value) when is_number(value), do: to_string(value)
  defp safe_probe_metadata_value(_key, _value), do: "complex"

  defp execution_status_text(%{status: status}) when is_atom(status), do: Atom.to_string(status)
  defp execution_status_text(_outcome), do: nil

  defp execution_severity_text(%{severity: severity}) when is_atom(severity),
    do: Atom.to_string(severity)

  defp execution_severity_text(_outcome), do: nil

  defp execution_operator_action_text(%{operator_action: action}) when is_atom(action),
    do: Atom.to_string(action)

  defp execution_operator_action_text(_outcome), do: nil

  defp execution_runtime_action_text(%{runtime_action: action}) when is_atom(action),
    do: Atom.to_string(action)

  defp execution_runtime_action_text(_outcome), do: nil

  defp execution_warning_codes_text(%{warning_codes: [_ | _] = warning_codes}) do
    warning_codes
    |> Enum.map(&EvidencePresentation.status_text/1)
    |> Enum.sort()
    |> Enum.join(" ")
  end

  defp execution_warning_codes_text(_outcome), do: nil

  defp circuit_failures(details) when is_map(details) do
    case {
      EvidencePresentation.detail_value(details, :failure_count),
      EvidencePresentation.detail_value(details, :failure_threshold)
    } do
      {nil, _threshold} -> nil
      {count, nil} -> count
      {count, threshold} -> "#{count}/#{threshold}"
    end
  end

  defp circuit_failures(_details), do: nil
end
