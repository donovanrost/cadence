defmodule CadenceWeb.OpsDashboardShowLive.RuntimeCacheDiagnostics do
  @moduledoc false

  alias Cadence.Dashboards.DataContext
  alias CadenceWeb.OpsDashboardShowLive.RuntimeDiagnosticFormatter
  alias CadenceWeb.OpsDashboardShowLive.RuntimeResult
  alias CadenceWeb.OpsDashboardShowLive.SourceExecutionRuntimeSummary

  def summary(result, source_incidents \\ [])
  def summary(nil, _source_incidents), do: %{visible?: false}

  def summary(result, source_incidents) do
    plan_status = plan_status(result)
    source_statuses = source_statuses(result)
    frame_statuses = frame_statuses(result)
    drilldowns = drilldowns(result, source_incidents)

    %{
      visible?: true,
      classification: classification(plan_status, source_statuses, frame_statuses),
      plan: diagnostic_value(plan_status),
      source: diagnostic_value(source_statuses),
      frame: diagnostic_value(frame_statuses),
      headline: headline(plan_status, source_statuses, frame_statuses),
      drilldowns: drilldowns,
      evidence_state_summary: evidence_state_summary(drilldowns)
    }
  end

  def drilldowns(result, source_incidents \\ [])
  def drilldowns(nil, _source_incidents), do: []

  def drilldowns(result, source_incidents) do
    incident_by_request_id = source_incident_by_request_id(source_incidents)

    result
    |> source_drilldowns()
    |> Kernel.++(frame_drilldowns(result))
    |> Enum.map(&put_source_incident(&1, incident_by_request_id))
    |> Enum.map(&put_evidence_state/1)
    |> Enum.sort_by(&drilldown_sort_key/1)
    |> Enum.take(8)
  end

  def evidence_state_summary(drilldowns) when is_list(drilldowns) do
    counts = Enum.frequencies_by(drilldowns, &Map.get(&1, :evidence_state, "missing"))

    %{
      total: length(drilldowns),
      resolved: Map.get(counts, "resolved", 0),
      context_only: Map.get(counts, "context_only", 0),
      missing: Map.get(counts, "missing", 0)
    }
  end

  def evidence_state_summary(_drilldowns),
    do: %{total: 0, resolved: 0, context_only: 0, missing: 0}

  def source_cache_evidence_audit(result) do
    result
    |> SourceExecutionRuntimeSummary.build()
    |> Map.get(:source_incidents, [])
    |> then(&source_cache_evidence_audit(result, &1))
  end

  def source_cache_evidence_audit(nil, _source_incidents), do: %{}

  def source_cache_evidence_audit(result, source_incidents) do
    drilldowns = drilldowns(result, source_incidents)
    evidence_state_summary = evidence_state_summary(drilldowns)

    if evidence_state_summary.total == 0 do
      %{}
    else
      %{
        source_cache_evidence_state_summary: evidence_state_summary,
        source_cache_evidence_target_ids: evidence_target_ids(drilldowns),
        source_cache_evidence_request_ids: evidence_request_ids(drilldowns)
      }
    end
  end

  def plan_status(nil), do: nil

  def plan_status(result) do
    result
    |> RuntimeResult.metadata_path([:cache, :plan_cache, :status])
    |> cache_status_to_string()
  end

  def source_statuses(nil), do: nil

  def source_statuses(result) do
    result
    |> RuntimeResult.metadata_path([:cache, :source_result_cache_by_request_id])
    |> entry_statuses()
  end

  def frame_statuses(nil), do: nil

  def frame_statuses(result) do
    result
    |> RuntimeResult.metadata_path([:cache, :frame_cache_by_placement])
    |> entry_statuses()
  end

  defp source_drilldowns(result) do
    source_entries =
      result
      |> RuntimeResult.metadata_path([:cache, :source_result_cache_by_request_id])
      |> normalize_entry_map()

    request_by_id = planned_request_by_id(result)
    selections = RuntimeResult.metadata(result, :source_selection_by_request_id) || %{}

    Enum.map(source_entries, fn {request_id, entry} ->
      request = Map.get(request_by_id, request_id)
      key = entry_key(entry)
      parts = key_parts(key)
      key_request = part(parts, :request, %{})
      selection = Map.get(selections, request_id, %{})
      source_binding = part(parts, :source_binding, %{})
      data_source = part(parts, :data_source, %{})

      %{
        layer: "source",
        evidence_id: evidence_id("source", request_id, nil),
        status: status_value(entry),
        request_id: diagnostic_value(request_id),
        placement_id: "-",
        logical_source:
          drilldown_value(
            first_present([
              map_value(key_request, :logical_source),
              map_value(request, :logical_source)
            ])
          ),
        observables:
          list_value(
            first_present([
              map_value(key_request, :observables),
              map_value(request, :observables)
            ])
          ),
        realm:
          drilldown_value(
            first_present([
              map_value(source_binding, :realm),
              source_context_value(request, :realm)
            ])
          ),
        data_source_id:
          drilldown_value(
            first_present([
              map_value(data_source, :data_source_id),
              map_value(selection, :selected_data_source_id),
              source_context_value(request, :data_source_id)
            ])
          ),
        source_binding_id:
          drilldown_value(
            first_present([
              map_value(source_binding, :binding_id),
              map_value(selection, :selected_source_binding_id),
              source_context_value(request, :source_binding_id)
            ])
          ),
        selection_strategy: drilldown_value(map_value(selection, :strategy)),
        reasons: reason_value(entry),
        fingerprint: fingerprint_value(key),
        source_result_cache_status: "-"
      }
    end)
  end

  defp frame_drilldowns(result) do
    result
    |> RuntimeResult.metadata_path([:cache, :frame_cache_by_placement])
    |> normalize_frame_entries()
    |> Enum.map(fn {placement_id, request_id, entry} ->
      key = entry_key(entry)
      parts = key_parts(key)
      request = part(parts, :source_result_request, %{})
      binding = part(parts, :source_result_binding, %{})
      data_source = part(parts, :source_result_data_source, %{})

      %{
        layer: "frame",
        evidence_id: evidence_id("frame", request_id, placement_id),
        status: status_value(entry),
        request_id: diagnostic_value(request_id),
        placement_id: diagnostic_value(placement_id),
        logical_source: drilldown_value(map_value(request, :logical_source)),
        observables: list_value(map_value(request, :observables)),
        realm: drilldown_value(map_value(binding, :realm)),
        data_source_id: drilldown_value(map_value(data_source, :data_source_id)),
        source_binding_id: drilldown_value(map_value(binding, :binding_id)),
        selection_strategy: "-",
        reasons:
          reason_value(entry)
          |> merge_reason(map_value(entry, :source_result_cache_status)),
        fingerprint: fingerprint_value(key),
        source_result_cache_status:
          diagnostic_value(map_value(entry, :source_result_cache_status))
      }
    end)
  end

  defp drilldown_sort_key(drilldown) do
    {
      status_priority(drilldown.status),
      drilldown.layer,
      drilldown.placement_id,
      drilldown.request_id
    }
  end

  defp evidence_target_ids(drilldowns) do
    drilldowns
    |> Enum.map(fn drilldown ->
      target = Map.get(drilldown, :incident_evidence_target)
      target_id = Map.get(drilldown, :incident_evidence_target_id)

      if target in [nil, "", "-"] or target_id in [nil, "", "-"] do
        nil
      else
        "#{target}:#{target_id}"
      end
    end)
    |> compact_sorted_values()
  end

  defp evidence_request_ids(drilldowns) do
    drilldowns
    |> Enum.reject(&(Map.get(&1, :evidence_state) == "missing"))
    |> Enum.map(&Map.get(&1, :request_id))
    |> compact_sorted_values()
  end

  defp compact_sorted_values(values) do
    values
    |> Enum.reject(&(&1 in [nil, "", "-"]))
    |> Enum.uniq()
    |> Enum.sort()
  end

  defp status_priority(status) when status in ["stale", "rejected", "facts_error"], do: 0
  defp status_priority("refresh"), do: 1
  defp status_priority("miss"), do: 2
  defp status_priority("hit"), do: 3
  defp status_priority("disabled"), do: 4
  defp status_priority(_status), do: 5

  defp source_incident_by_request_id(source_incidents) when is_list(source_incidents) do
    source_incidents
    |> Enum.reject(&(map_value(&1, :request_id) in [nil, ""]))
    |> Map.new(fn incident -> {diagnostic_value(map_value(incident, :request_id)), incident} end)
  end

  defp source_incident_by_request_id(_source_incidents), do: %{}

  defp put_source_incident(drilldown, incident_by_request_id) do
    drilldown
    |> Map.get(:request_id)
    |> then(&Map.get(incident_by_request_id, &1))
    |> case do
      nil -> Map.merge(drilldown, empty_source_incident())
      incident -> Map.merge(drilldown, source_incident(incident))
    end
  end

  defp put_evidence_state(drilldown) do
    Map.put(drilldown, :evidence_state, evidence_state(drilldown))
  end

  defp evidence_state(%{incident_status_text: incident_status})
       when incident_status not in [nil, "-"],
       do: "resolved"

  defp evidence_state(drilldown) do
    if evidence_context?(drilldown), do: "context_only", else: "missing"
  end

  defp evidence_context?(drilldown) do
    [
      Map.get(drilldown, :request_id),
      Map.get(drilldown, :logical_source),
      Map.get(drilldown, :realm),
      Map.get(drilldown, :data_source_id),
      Map.get(drilldown, :source_binding_id)
    ]
    |> Enum.any?(&(&1 not in [nil, "-"]))
  end

  defp source_incident(incident) do
    incident_evidence = incident_evidence(incident)

    %{
      incident_status: diagnostic_value(map_value(incident, :incident_status)),
      incident_status_text:
        diagnostic_value(
          map_value(incident, :incident_status_text) || map_value(incident, :incident_status)
        ),
      incident_title: diagnostic_value(map_value(incident, :incident_title)),
      incident_message: diagnostic_value(map_value(incident, :incident_message)),
      incident_severity:
        diagnostic_value(
          map_value(incident, :execution_severity_text) ||
            map_value(incident, :execution_severity)
        ),
      incident_operator_action:
        diagnostic_value(
          map_value(incident, :execution_operator_action_text) ||
            map_value(incident, :execution_operator_action)
        ),
      incident_runtime_action:
        diagnostic_value(
          map_value(incident, :execution_runtime_action_text) ||
            map_value(incident, :execution_runtime_action)
        ),
      incident_actionable?:
        diagnostic_value(
          first_present([
            map_value(incident, :execution_actionable?),
            map_value(incident, :source_execution_actionable?)
          ])
        ),
      incident_retryable?:
        diagnostic_value(
          first_present([
            map_value(incident, :execution_retryable?),
            map_value(incident, :source_execution_retryable?)
          ])
        ),
      incident_evidence_target: diagnostic_value(map_value(incident_evidence, :target)),
      incident_evidence_target_id: diagnostic_value(map_value(incident_evidence, :target_id)),
      incident_evidence_kind: diagnostic_value(map_value(incident_evidence, :kind)),
      incident_evidence_kind_text: diagnostic_value(map_value(incident_evidence, :kind_text)),
      incident_evidence_observed_at:
        diagnostic_value(map_value(incident_evidence, :observed_at_text))
    }
  end

  defp empty_source_incident do
    %{
      incident_status: "-",
      incident_status_text: "-",
      incident_title: "-",
      incident_message: "-",
      incident_severity: "-",
      incident_operator_action: "-",
      incident_runtime_action: "-",
      incident_actionable?: "-",
      incident_retryable?: "-",
      incident_evidence_target: "-",
      incident_evidence_target_id: "-",
      incident_evidence_kind: "-",
      incident_evidence_kind_text: "-",
      incident_evidence_observed_at: "-"
    }
  end

  defp incident_evidence(incident) do
    incident
    |> map_value(:evidence)
    |> Kernel.||([])
    |> List.wrap()
    |> Enum.find_value(&source_event_evidence/1)
    |> case do
      nil ->
        incident
        |> map_value(:evidence)
        |> Kernel.||([])
        |> List.wrap()
        |> List.first()
        |> evidence_summary()

      evidence ->
        evidence
    end
  end

  defp source_event_evidence(evidence) do
    evidence = evidence_summary(evidence)

    if map_value(evidence, :kind) in [
         :source_health_event,
         "source_health_event",
         :source_watermark_event,
         "source_watermark_event"
       ] do
      evidence
    end
  end

  defp evidence_summary(nil), do: %{}

  defp evidence_summary(evidence) when is_map(evidence) do
    kind = map_value(evidence, :kind)
    id = map_value(evidence, :id)

    %{
      target: kind,
      target_id: id,
      kind: kind,
      kind_text: map_value(evidence, :kind_text),
      observed_at_text: map_value(evidence, :observed_at_text)
    }
  end

  defp evidence_summary(_evidence), do: %{}

  defp normalize_entry_map(entries) when is_map(entries) do
    entries
    |> Enum.map(fn {key, value} -> {diagnostic_value(key), value} end)
    |> Enum.reject(fn {_key, value} -> is_nil(value) end)
  end

  defp normalize_entry_map(_entries), do: []

  defp normalize_frame_entries(entries) when is_map(entries) do
    Enum.flat_map(entries, fn {placement_id, entries_by_request_id} ->
      normalize_frame_entries_for_placement(placement_id, entries_by_request_id)
    end)
  end

  defp normalize_frame_entries(_entries), do: []

  defp normalize_frame_entries_for_placement(placement_id, entries_by_request_id)
       when is_map(entries_by_request_id) do
    Enum.map(entries_by_request_id, fn {request_id, entry} ->
      {diagnostic_value(placement_id), diagnostic_value(request_id), entry}
    end)
  end

  defp normalize_frame_entries_for_placement(placement_id, entries_by_request_id)
       when is_list(entries_by_request_id) do
    entries_by_request_id
    |> Enum.with_index(1)
    |> Enum.map(fn {entry, index} ->
      {diagnostic_value(placement_id), Integer.to_string(index), entry}
    end)
  end

  defp normalize_frame_entries_for_placement(_placement_id, _entries_by_request_id),
    do: []

  defp planned_request_by_id(result) do
    result
    |> RuntimeResult.planned_source_requests()
    |> Enum.map(fn request -> {diagnostic_value(map_value(request, :request_id)), request} end)
    |> Enum.reject(fn {request_id, _request} -> request_id == "-" end)
    |> Map.new()
  end

  defp evidence_id(layer, request_id, placement_id) do
    [layer, request_id, placement_id]
    |> Enum.reject(&is_nil/1)
    |> Enum.map_join(":", &diagnostic_value/1)
  end

  defp status_value(entry) do
    entry
    |> map_value(:status)
    |> diagnostic_value()
  end

  defp reason_value(entry) do
    [
      map_value(entry, :reason),
      map_value(entry, :reasons)
    ]
    |> Enum.reject(&blank?/1)
    |> List.flatten()
    |> list_value()
  end

  defp merge_reason("-", value), do: diagnostic_value(value)
  defp merge_reason(reason, value) when value in [nil, ""], do: reason
  defp merge_reason(reason, value), do: "#{reason} #{diagnostic_value(value)}"

  defp fingerprint_value(key) do
    key
    |> map_value(:fingerprint)
    |> diagnostic_value()
  end

  defp entry_key(entry), do: map_value(entry, :key)

  defp key_parts(key) do
    case map_value(key, :parts) do
      parts when is_map(parts) -> parts
      _other -> %{}
    end
  end

  defp part(parts, key, default) do
    case map_value(parts, key) do
      value when is_map(value) -> value
      _other -> default
    end
  end

  defp source_context_value(nil, _key), do: nil

  defp source_context_value(request, key) do
    case map_value(request, :logical_source) do
      nil ->
        nil

      logical_source ->
        case map_value(request, :data_context) do
          nil -> nil
          data_context -> DataContext.source_value(data_context, logical_source, key)
        end
    end
  end

  defp map_value(nil, _key), do: nil

  defp map_value(%{} = map, key) when is_atom(key) do
    case Map.fetch(map, key) do
      {:ok, value} -> value
      :error -> Map.get(map, Atom.to_string(key))
    end
  end

  defp map_value(_value, _key), do: nil

  defp first_present(values), do: Enum.find(values, &(not blank?(&1)))

  defp blank?(value), do: value in [nil, "", []]

  defp list_value(nil), do: "-"
  defp list_value([]), do: "-"

  defp list_value(values) when is_list(values) do
    values
    |> Enum.map(&diagnostic_value/1)
    |> Enum.reject(&(&1 == "-"))
    |> Enum.sort()
    |> Enum.join(" ")
    |> case do
      "" -> "-"
      value -> value
    end
  end

  defp list_value(value), do: diagnostic_value(value)

  defp classification(_plan_status, nil, nil), do: "bypassed"

  defp classification(plan_status, source_statuses, frame_statuses) do
    statuses =
      [plan_status, source_statuses, frame_statuses]
      |> Enum.flat_map(&status_words/1)

    cond do
      statuses == [] ->
        "bypassed"

      Enum.any?(statuses, &(&1 in ["stale", "rejected"])) ->
        "stale"

      Enum.any?(statuses, &(&1 in ["hit", "refresh", "miss"])) ->
        reuse_classification(statuses)

      true ->
        "mixed"
    end
  end

  defp reuse_classification(statuses) do
    cond do
      Enum.any?(statuses, &(&1 == "hit")) -> "reused"
      Enum.all?(statuses, &(&1 in ["miss", "refresh"])) -> "fresh"
      true -> "mixed"
    end
  end

  defp headline(plan_status, source_statuses, frame_statuses) do
    case classification(plan_status, source_statuses, frame_statuses) do
      "bypassed" -> "No runtime cache entries were used."
      "fresh" -> "Dashboard rendered from fresh source/frame execution."
      "reused" -> "Dashboard reused one or more runtime cache entries."
      "stale" -> "Dashboard encountered stale runtime cache entries."
      _other -> "Dashboard used mixed runtime cache states."
    end
  end

  defp status_words(nil), do: []

  defp status_words(value) when is_binary(value) do
    value
    |> String.split(~r/\s+/, trim: true)
    |> Enum.map(&String.downcase/1)
  end

  defp status_words(value) when is_atom(value), do: [Atom.to_string(value)]
  defp status_words(_value), do: []

  defp entry_statuses(entries) do
    statuses =
      entries
      |> entry_status_values()
      |> Enum.map(&Atom.to_string/1)
      |> Enum.sort()

    if statuses == [], do: nil, else: Enum.join(statuses, " ")
  end

  defp entry_status_values(%{status: status}) when is_atom(status), do: [status]

  defp entry_status_values(entries) when is_map(entries) do
    entries
    |> Map.values()
    |> Enum.flat_map(&entry_status_values/1)
  end

  defp entry_status_values(entries) when is_list(entries),
    do: Enum.flat_map(entries, &entry_status_values/1)

  defp entry_status_values(_entry), do: []

  defp cache_status_to_string(status) when is_atom(status), do: Atom.to_string(status)
  defp cache_status_to_string(_status), do: nil

  defp diagnostic_value(value), do: RuntimeDiagnosticFormatter.value(value)

  defp drilldown_value(nil), do: nil
  defp drilldown_value(value) when is_atom(value), do: Atom.to_string(value)
  defp drilldown_value(value) when is_binary(value), do: value
  defp drilldown_value(value) when is_integer(value), do: Integer.to_string(value)
  defp drilldown_value(value), do: inspect(value)
end
