defmodule CadenceWeb.OpsDashboardShowLive.ActivityEventSummary do
  @moduledoc false

  alias Cadence.Dashboards.LifecycleEvent
  alias CadenceWeb.OpsDashboardShowLive.LifecycleRuntimeCorrelation

  def build(events, selected_event_id, visible_events, activity) when is_list(events) do
    build(events, selected_event_id, visible_events, activity, [])
  end

  def build(_events, _selected_event_id, _visible_events, _activity),
    do: %{
      render?: false,
      runtime_impact: LifecycleRuntimeCorrelation.empty_runtime_impact("not_applicable")
    }

  def build(events, selected_event_id, visible_events, activity, invalidations)
      when is_list(events) do
    build(events, selected_event_id, visible_events, activity, invalidations, [])
  end

  def build(_events, _selected_event_id, _visible_events, _activity, _invalidations),
    do: %{
      render?: false,
      runtime_impact: LifecycleRuntimeCorrelation.empty_runtime_impact("not_applicable")
    }

  def build(
        events,
        selected_event_id,
        visible_events,
        activity,
        invalidations,
        source_action_events
      )
      when is_list(events) do
    case selected_event_id(selected_event_id) do
      nil ->
        %{
          render?: false,
          runtime_impact: LifecycleRuntimeCorrelation.empty_runtime_impact("not_applicable")
        }

      event_id ->
        event = selected_event(events, event_id)
        visible? = visible_event?(visible_events, event_id)
        readiness_comparison = publish_readiness_comparison(event, events)
        source_actions = source_action_correlation(event, source_action_events)

        %{
          render?: true,
          event: event,
          event_id: event_id,
          found?: match?(%LifecycleEvent{}, event),
          found_text: boolean_text(match?(%LifecycleEvent{}, event)),
          visible?: visible?,
          visible_text: boolean_text(visible?),
          filter_value: activity_filter_value(activity),
          event_type_text: event_type_text(event),
          title: title(event),
          version_text: version_text(event),
          filter_state: filter_state(event, visible?),
          filter_state_text: filter_state_text(event, visible?),
          visibility_class: visibility_class(event, visible?),
          runtime_impact: LifecycleRuntimeCorrelation.runtime_impact(event, invalidations),
          remediation_actions: publish_readiness_actions(event),
          source_actions: source_actions,
          readiness_comparison: readiness_comparison,
          fields:
            fields(event,
              include_event?: true,
              invalidations: invalidations,
              readiness_comparison: readiness_comparison,
              source_actions: source_actions
            )
        }
    end
  end

  def build(
        _events,
        _selected_event_id,
        _visible_events,
        _activity,
        _invalidations,
        _source_action_events
      ),
      do: %{
        render?: false,
        runtime_impact: LifecycleRuntimeCorrelation.empty_runtime_impact("not_applicable")
      }

  def rows(events, selected_event_id) when is_list(events) do
    rows(events, selected_event_id, [])
  end

  def rows(_events, _selected_event_id), do: []

  def rows(events, selected_event_id, invalidations) when is_list(events) do
    Enum.map(events, &row(&1, selected_event_id, invalidations, events))
  end

  def rows(_events, _selected_event_id, _invalidations), do: []

  def row(%LifecycleEvent{} = event, selected_event_id) do
    row(event, selected_event_id, [])
  end

  def row(_event, _selected_event_id), do: nil

  def row(%LifecycleEvent{} = event, selected_event_id, invalidations) do
    row(event, selected_event_id, invalidations, [event])
  end

  def row(_event, _selected_event_id, _invalidations), do: nil

  def row(%LifecycleEvent{} = event, selected_event_id, invalidations, events) do
    selected? = selected?(event, selected_event_id)
    runtime_impact = LifecycleRuntimeCorrelation.runtime_impact(event, invalidations)
    readiness_comparison = publish_readiness_comparison(event, events)
    remediation_actions = publish_readiness_actions(event)

    %{
      event: event,
      event_id: event.dashboard_lifecycle_event_id,
      event_type: event.event_type,
      event_type_text: Atom.to_string(event.event_type),
      title: label(event.event_type),
      version_text: version_value(event.dashboard_version),
      selected?: selected?,
      selected_text: boolean_text(selected?),
      class: row_class(selected?),
      source_version_text: version_attr_value(LifecycleEvent.source_version(event)),
      reverted_version_text: version_attr_value(LifecycleEvent.reverted_version(event)),
      runtime_impact: runtime_impact,
      readiness_comparison: readiness_comparison,
      remediation_actions: remediation_actions,
      remediation_count: length(remediation_actions),
      remediation_count_text: Integer.to_string(length(remediation_actions)),
      fields:
        fields(event,
          include_event?: false,
          invalidations: invalidations,
          readiness_comparison: readiness_comparison
        )
    }
  end

  def row(_event, _selected_event_id, _invalidations, _events), do: nil

  def label(:published), do: "Published"
  def label(:reverted), do: "Restored as draft"
  def label(:archived), do: "Archived"
  def label(:restored), do: "Restored"
  def label(:comparison_review_requested), do: "Comparison review requested"
  def label(:comparison_review_resolved), do: "Comparison review resolved"
  def label(:health_snapshot_captured), do: "Health snapshot captured"
  def label(:publish_readiness_checked), do: "Publish readiness checked"
  def label(event_type), do: to_string(event_type)

  def event_id(%LifecycleEvent{dashboard_lifecycle_event_id: event_id}), do: event_id
  def event_id(_event), do: nil

  defp selected_event_id(event_id) when is_binary(event_id) and event_id != "", do: event_id
  defp selected_event_id(_event_id), do: nil

  defp selected_event(events, event_id) do
    Enum.find(events, &(event_id(&1) == event_id))
  end

  defp visible_event?(events, event_id) when is_list(events) do
    Enum.any?(events, &(event_id(&1) == event_id))
  end

  defp visible_event?(_events, _event_id), do: false

  defp activity_filter_value(%{filter_value: filter_value}) when is_binary(filter_value),
    do: filter_value

  defp activity_filter_value(_activity), do: ""

  defp event_type_text(%LifecycleEvent{event_type: event_type}), do: Atom.to_string(event_type)
  defp event_type_text(_event), do: nil

  defp title(%LifecycleEvent{event_type: event_type}), do: label(event_type)
  defp title(_event), do: "Activity event unavailable"

  defp version_text(%LifecycleEvent{dashboard_version: version}), do: version_value(version)
  defp version_text(_event), do: nil

  defp filter_state(%LifecycleEvent{}, true), do: nil
  defp filter_state(%LifecycleEvent{}, false), do: :hidden
  defp filter_state(_event, _visible?), do: :missing

  defp filter_state_text(event, visible?) do
    case filter_state(event, visible?) do
      nil -> nil
      state -> Atom.to_string(state)
    end
  end

  defp visibility_class(%LifecycleEvent{}, true), do: nil
  defp visibility_class(nil, _visible?), do: "border-error/40 bg-error/10"
  defp visibility_class(_event, false), do: "border-warning/40 bg-warning/10"

  defp fields(%LifecycleEvent{} = event, opts) do
    event_fields =
      if Keyword.get(opts, :include_event?, true) do
        [
          field(
            "Event",
            event.dashboard_lifecycle_event_id,
            "break-all font-mono text-base-content/70"
          )
        ]
      else
        []
      end

    event_fields
    |> Kernel.++([
      field("Occurred", format_time(event.occurred_at), "font-mono text-base-content/70"),
      field("Actor", event.actor_id || "unknown", "truncate text-base-content/70"),
      publish_readiness_field(event, "Result", "result"),
      publish_readiness_field(event, "Errors", "error_count"),
      publish_readiness_field(event, "Warnings", "warning_count"),
      publish_readiness_field(event, "Issues", "issue_count"),
      publish_readiness_list_field(event, "Issue codes", "issue_codes"),
      publish_readiness_list_field(event, "Source blockers", "source_warning_codes"),
      publish_readiness_source_evidence_field(
        event,
        "Source evidence",
        "source_evidence_contexts"
      ),
      publish_readiness_field(event, "Freshness", "freshness_state"),
      publish_readiness_field(event, "Freshness reason", "freshness_reason_label"),
      publish_readiness_field(event, "Freshness detail", "freshness_message"),
      publish_readiness_action_field(event, "Remediation", "remediation_targets"),
      publish_readiness_comparison_field(Keyword.get(opts, :readiness_comparison)),
      publish_readiness_source_action_field(Keyword.get(opts, :source_actions)),
      field(
        "Published",
        "#{version_value(event.previous_published_version)} -> #{version_value(event.current_published_version)}",
        "font-mono text-base-content/70"
      ),
      version_field("Source", LifecycleEvent.source_version(event)),
      version_field("New draft", LifecycleEvent.reverted_version(event)),
      runtime_impact_field(
        LifecycleRuntimeCorrelation.runtime_impact(event, Keyword.get(opts, :invalidations, []))
      )
    ])
    |> Enum.reject(&is_nil/1)
  end

  defp fields(_event, _opts), do: []

  defp field(label, value, class) do
    %{
      label: label,
      value: value,
      class: class
    }
  end

  defp version_field(_label, nil), do: nil

  defp version_field(label, version),
    do: field(label, version_value(version), "font-mono text-base-content/70")

  defp publish_readiness_field(
         %LifecycleEvent{event_type: :publish_readiness_checked, payload: payload},
         label,
         key
       ) do
    case payload_value(payload, key) do
      value when value in [nil, ""] -> nil
      value -> field(label, to_string(value), "font-mono text-base-content/70")
    end
  end

  defp publish_readiness_field(%LifecycleEvent{}, _label, _key), do: nil

  defp publish_readiness_list_field(
         %LifecycleEvent{event_type: :publish_readiness_checked, payload: payload},
         label,
         key
       ) do
    case payload_value(payload, key) do
      values when is_list(values) and values != [] ->
        field(label, Enum.join(values, ", "), "font-mono text-base-content/70")

      _value ->
        nil
    end
  end

  defp publish_readiness_list_field(%LifecycleEvent{}, _label, _key), do: nil

  defp publish_readiness_action_field(
         %LifecycleEvent{event_type: :publish_readiness_checked, payload: payload},
         label,
         key
       ) do
    case payload_value(payload, key) do
      actions when is_list(actions) and actions != [] ->
        actions
        |> Enum.map(&publish_readiness_action_label/1)
        |> Enum.reject(&(&1 in [nil, ""]))
        |> case do
          [] -> nil
          values -> field(label, Enum.join(values, ", "), "font-mono text-base-content/70")
        end

      _value ->
        nil
    end
  end

  defp publish_readiness_action_field(%LifecycleEvent{}, _label, _key), do: nil

  defp publish_readiness_source_evidence_field(
         %LifecycleEvent{event_type: :publish_readiness_checked, payload: payload},
         label,
         key
       ) do
    case payload_value(payload, key) do
      contexts when is_list(contexts) and contexts != [] ->
        contexts
        |> Enum.map(&publish_readiness_source_evidence_label/1)
        |> Enum.reject(&(&1 in [nil, ""]))
        |> case do
          [] -> nil
          values -> field(label, Enum.join(values, ", "), "font-mono text-base-content/70")
        end

      _value ->
        nil
    end
  end

  defp publish_readiness_source_evidence_field(%LifecycleEvent{}, _label, _key), do: nil

  defp publish_readiness_source_evidence_label(context) when is_map(context) do
    logical_source =
      payload_value(context, "logical_source") || payload_value(context, "warning_code")

    source_binding_id = payload_value(context, "source_binding_id")
    data_source_id = payload_value(context, "data_source_id")
    identity = source_evidence_identity(logical_source, source_binding_id, data_source_id)

    source_evidence_label(identity, source_evidence_suffixes(context))
  end

  defp publish_readiness_source_evidence_label(_context), do: nil

  defp source_evidence_identity(nil, nil, nil), do: nil
  defp source_evidence_identity(source, nil, nil), do: to_string(source)
  defp source_evidence_identity(nil, binding, nil), do: to_string(binding)
  defp source_evidence_identity(nil, nil, data_source), do: to_string(data_source)
  defp source_evidence_identity(nil, binding, data_source), do: "#{binding} -> #{data_source}"
  defp source_evidence_identity(source, nil, data_source), do: "#{source}: #{data_source}"
  defp source_evidence_identity(source, binding, nil), do: "#{source}: #{binding}"

  defp source_evidence_identity(source, binding, data_source),
    do: "#{source}: #{binding} -> #{data_source}"

  defp source_evidence_suffixes(context) do
    [
      source_evidence_suffix("replay", payload_value(context, "replay_run_id")),
      source_evidence_suffix("request", payload_value(context, "source_request_id"))
    ]
    |> Enum.reject(&is_nil/1)
  end

  defp source_evidence_label(nil, []), do: nil
  defp source_evidence_label(nil, suffixes), do: Enum.join(suffixes, ", ")
  defp source_evidence_label(identity, []), do: identity
  defp source_evidence_label(identity, suffixes), do: "#{identity} (#{Enum.join(suffixes, ", ")})"

  defp source_evidence_suffix(_label, value) when value in [nil, ""], do: nil
  defp source_evidence_suffix(label, value), do: "#{label} #{value}"

  defp publish_readiness_action_label(action) when is_map(action) do
    label = payload_value(action, "label")
    target = payload_value(action, "target")

    cond do
      label in [nil, ""] ->
        nil

      target in [nil, ""] ->
        to_string(label)

      true ->
        "#{label} -> #{target}"
    end
  end

  defp publish_readiness_action_label(_action), do: nil

  defp publish_readiness_actions(%LifecycleEvent{
         event_type: :publish_readiness_checked,
         payload: payload
       }) do
    payload
    |> publish_readiness_payload_actions()
    |> Kernel.++(publish_readiness_source_evidence_actions(payload))
    |> Enum.reject(&is_nil/1)
    |> Enum.uniq_by(&publish_readiness_action_identity/1)
  end

  defp publish_readiness_actions(_event), do: []

  defp publish_readiness_payload_actions(payload) do
    typed_actions =
      payload
      |> payload_value("typed_remediation_actions")
      |> case do
        actions when is_list(actions) -> Enum.map(actions, &publish_readiness_typed_action/1)
        _actions -> []
      end
      |> Enum.reject(&is_nil/1)

    if typed_actions != [] do
      typed_actions
    else
      legacy_publish_readiness_payload_actions(payload)
    end
  end

  defp legacy_publish_readiness_payload_actions(payload) do
    payload
    |> payload_value("remediation_targets")
    |> case do
      actions when is_list(actions) -> Enum.map(actions, &publish_readiness_action/1)
      _actions -> []
    end
  end

  defp publish_readiness_source_evidence_actions(payload) do
    payload
    |> payload_value("source_evidence_contexts")
    |> case do
      contexts when is_list(contexts) ->
        Enum.map(contexts, &publish_readiness_source_evidence_action/1)

      _contexts ->
        []
    end
  end

  defp publish_readiness_source_evidence_action(context) when is_map(context) do
    params = source_evidence_action_params(context)

    if map_size(params) == 0 do
      nil
    else
      %{
        label: source_evidence_action_label(context),
        target: "data_sources",
        message: "Open the source evidence associated with this readiness check.",
        params: params
      }
    end
  end

  defp publish_readiness_source_evidence_action(_context), do: nil

  @source_evidence_action_param_keys [
    "data_source_id",
    "source_binding_id",
    "logical_source",
    "realm",
    "dataset",
    "replay_run_id",
    "source_empty_reason"
  ]

  defp source_evidence_action_params(context) do
    context
    |> Map.put_new("source_empty_reason", payload_value(context, "warning_code"))
    |> Map.put_new("selected_evidence_kind", "source")
    |> Map.put_new("selected_source_evidence_mode", "health")
    |> Map.put_new("selected_source_evidence_state", source_evidence_selected_state(context))
    |> Map.take(@source_evidence_action_param_keys ++ source_evidence_selection_param_keys())
    |> Enum.reject(fn {_key, value} -> value in [nil, ""] end)
    |> Map.new(fn {key, value} -> {to_string(key), to_string(value)} end)
  end

  defp source_evidence_selection_param_keys do
    [
      "selected_evidence_kind",
      "selected_source_evidence_mode",
      "selected_source_evidence_state"
    ]
  end

  defp source_evidence_selected_state(context) do
    context
    |> payload_value("warning_code")
    |> case do
      "stale_data" -> "stale"
      "retention_gap" -> "retention_gap"
      "watermark_unknown" -> "unknown"
      "unknown_watermark" -> "unknown"
      "missing_snapshot" -> "unknown"
      _code -> nil
    end
  end

  defp source_evidence_action_label(context) do
    case publish_readiness_source_evidence_label(context) do
      nil -> "Inspect source evidence"
      label -> "Inspect #{label}"
    end
  end

  defp publish_readiness_action_identity(%{target: target, params: params}) do
    {target, params}
  end

  defp publish_readiness_action_identity(action), do: action

  defp publish_readiness_comparison(
         %LifecycleEvent{event_type: :publish_readiness_checked} = event,
         events
       )
       when is_list(events) do
    case previous_publish_readiness_event(event, events) do
      nil ->
        %{
          state: "first_check",
          label: "first check",
          message: "No previous publish readiness check is available for comparison.",
          previous_event_id: nil,
          previous_result: nil,
          previous_issue_count: nil,
          current_result: readiness_result(event),
          current_issue_count: readiness_issue_count(event)
        }

      previous ->
        readiness_comparison(event, previous)
    end
  end

  defp publish_readiness_comparison(_event, _events), do: nil

  defp previous_publish_readiness_event(%LifecycleEvent{} = event, events) do
    events
    |> Enum.filter(&previous_readiness_candidate?(&1, event))
    |> Enum.sort_by(&readiness_event_sort_key/1)
    |> List.last()
  end

  defp previous_readiness_candidate?(
         %LifecycleEvent{event_type: :publish_readiness_checked} = candidate,
         %LifecycleEvent{} = event
       ) do
    candidate.dashboard_lifecycle_event_id != event.dashboard_lifecycle_event_id and
      compare_readiness_events(candidate, event) == :lt
  end

  defp previous_readiness_candidate?(_candidate, _event), do: false

  defp readiness_comparison(%LifecycleEvent{} = current, %LifecycleEvent{} = previous) do
    previous_issue_count = readiness_issue_count(previous)
    current_issue_count = readiness_issue_count(current)
    previous_score = readiness_score(previous)
    current_score = readiness_score(current)

    state =
      cond do
        current_score < previous_score -> "improved"
        current_score > previous_score -> "regressed"
        true -> "unchanged"
      end

    %{
      state: state,
      label: readiness_comparison_label(state),
      message: readiness_comparison_message(state, previous_issue_count, current_issue_count),
      previous_event_id: previous.dashboard_lifecycle_event_id,
      previous_result: readiness_result(previous),
      previous_issue_count: previous_issue_count,
      current_result: readiness_result(current),
      current_issue_count: current_issue_count
    }
  end

  defp readiness_score(%LifecycleEvent{} = event) do
    {
      readiness_result_rank(readiness_result(event)),
      readiness_issue_count(event)
    }
  end

  defp readiness_result_rank("resolved"), do: 0
  defp readiness_result_rank("resolved_with_warnings"), do: 1
  defp readiness_result_rank("still_blocked"), do: 2
  defp readiness_result_rank(_result), do: 3

  defp readiness_comparison_label("improved"), do: "improved"
  defp readiness_comparison_label("regressed"), do: "regressed"
  defp readiness_comparison_label("unchanged"), do: "unchanged"

  defp readiness_comparison_message(state, previous_issue_count, current_issue_count) do
    "#{readiness_comparison_sentence(state)}: #{issue_count_text(previous_issue_count)} -> #{issue_count_text(current_issue_count)}."
  end

  defp readiness_comparison_sentence("improved"), do: "Readiness improved"
  defp readiness_comparison_sentence("regressed"), do: "Readiness regressed"
  defp readiness_comparison_sentence("unchanged"), do: "Readiness unchanged"

  defp issue_count_text(count) when is_integer(count), do: "#{count} #{issue_word(count)}"
  defp issue_count_text(_count), do: "unknown issues"

  defp issue_word(1), do: "issue"
  defp issue_word(_count), do: "issues"

  defp readiness_result(%LifecycleEvent{payload: payload}), do: payload_value(payload, "result")

  defp readiness_issue_count(%LifecycleEvent{payload: payload}) do
    payload
    |> payload_value("issue_count")
    |> normalize_count()
  end

  defp normalize_count(value) when is_integer(value) and value >= 0, do: value

  defp normalize_count(value) when is_binary(value) do
    case Integer.parse(value) do
      {count, ""} when count >= 0 -> count
      _invalid -> 0
    end
  end

  defp normalize_count(_value), do: 0

  defp publish_readiness_comparison_field(%{message: message}) when is_binary(message) do
    field("Readiness trend", message, "font-mono text-base-content/70")
  end

  defp publish_readiness_comparison_field(_comparison), do: nil

  defp publish_readiness_source_action_field(%{latest: %{field_value: field_value}})
       when is_binary(field_value) do
    field("Source follow-up", field_value, "font-mono text-base-content/70")
  end

  defp publish_readiness_source_action_field(_source_actions), do: nil

  defp source_action_correlation(
         %LifecycleEvent{event_type: :publish_readiness_checked} = event,
         source_action_events
       )
       when is_list(source_action_events) do
    rows =
      source_action_events
      |> Enum.filter(&source_action_matches?(&1, event))
      |> Enum.sort_by(&source_action_sort_key/1, {:desc, DateTime})
      |> Enum.map(&source_action_row/1)

    %{
      present?: rows != [],
      count: length(rows),
      count_text: Integer.to_string(length(rows)),
      latest: List.first(rows),
      rows: rows
    }
  end

  defp source_action_correlation(_event, _source_action_events) do
    %{
      present?: false,
      count: 0,
      count_text: "0",
      latest: nil,
      rows: []
    }
  end

  defp source_action_matches?(source_event, %LifecycleEvent{} = readiness_event) do
    payload = source_action_payload(source_event)

    payload_value(payload, "source_return_activity_event") ==
      readiness_event.dashboard_lifecycle_event_id and
      source_action_dashboard_matches?(payload, readiness_event) and
      source_action_after_readiness?(source_event, readiness_event)
  end

  defp source_action_dashboard_matches?(payload, %LifecycleEvent{} = readiness_event) do
    case payload_value(payload, "source_dashboard_id") do
      value when value in [nil, ""] -> true
      value -> to_string(value) == readiness_event.dashboard_id
    end
  end

  defp source_action_after_readiness?(source_event, %LifecycleEvent{occurred_at: occurred_at}) do
    case source_action_time(source_event) do
      %DateTime{} = source_action_time -> DateTime.compare(source_action_time, occurred_at) == :gt
      _time -> false
    end
  end

  defp source_action_row(source_event) do
    occurred_at = source_action_time(source_event)
    action = source_action_label(source_event)

    %{
      action: action,
      kind: source_action_kind(source_event),
      message: "#{action} after this check",
      occurred_at: format_time(occurred_at),
      source: source_action_source(source_event),
      field_value: "#{action} at #{format_time(occurred_at)}"
    }
  end

  defp source_action_payload(%{payload: payload}) when is_map(payload), do: payload
  defp source_action_payload(_source_event), do: %{}

  defp source_action_time(%{observed_at: %DateTime{} = observed_at}), do: observed_at
  defp source_action_time(%{occurred_at: %DateTime{} = occurred_at}), do: occurred_at
  defp source_action_time(_source_event), do: nil

  defp source_action_sort_key(source_event), do: source_action_time(source_event)

  defp source_action_kind(%{source_health_event_id: _event_id}), do: "source_health"
  defp source_action_kind(%{data_binding_event_id: _event_id}), do: "source_binding"
  defp source_action_kind(%{data_source_event_id: _event_id}), do: "data_source"
  defp source_action_kind(_source_event), do: "source_action"

  defp source_action_label(%{source_health_event_id: _event_id}), do: "Source probed"
  defp source_action_label(%{data_binding_event_id: _event_id}), do: "Source binding updated"
  defp source_action_label(%{data_source_event_id: _event_id}), do: "Data source updated"
  defp source_action_label(_source_event), do: "Source updated"

  defp source_action_source(source_event) do
    [
      source_action_value(source_event, :logical_source),
      source_action_value(source_event, :source_binding_id) ||
        source_action_value(source_event, :binding_id),
      source_action_value(source_event, :data_source_id) ||
        source_action_value(source_event, :current_data_source_id)
    ]
    |> Enum.reject(&(&1 in [nil, ""]))
    |> Enum.join(" / ")
  end

  defp source_action_value(source_event, key) when is_map(source_event) do
    Map.get(source_event, key) ||
      source_event
      |> source_action_payload()
      |> payload_value(to_string(key))
  end

  defp compare_readiness_events(%LifecycleEvent{} = left, %LifecycleEvent{} = right) do
    left
    |> readiness_event_sort_key()
    |> compare_sort_key(readiness_event_sort_key(right))
  end

  defp readiness_event_sort_key(%LifecycleEvent{} = event) do
    {DateTime.to_unix(event.occurred_at, :microsecond), event.dashboard_lifecycle_event_id}
  end

  defp compare_sort_key(left, right) when left < right, do: :lt
  defp compare_sort_key(left, right) when left > right, do: :gt
  defp compare_sort_key(_left, _right), do: :eq

  defp publish_readiness_action(action) when is_map(action) do
    label = payload_value(action, "label")
    target = payload_value(action, "target")

    if label in [nil, ""] or target in [nil, ""] do
      nil
    else
      %{
        label: to_string(label),
        target: to_string(target),
        message: action |> payload_value("message") |> optional_string(),
        params: publish_readiness_action_params(payload_value(action, "params"))
      }
      |> maybe_put_issue_id(publish_readiness_action_issue_id(action))
    end
  end

  defp publish_readiness_action(_action), do: nil

  defp publish_readiness_typed_action(action) when is_map(action) do
    label = payload_value(action, "label")
    target = publish_readiness_typed_action_target(payload_value(action, "target"))

    if label in [nil, ""] or target in [nil, ""] do
      nil
    else
      %{
        label: to_string(label),
        target: target,
        message: action |> payload_value("message") |> optional_string(),
        params: publish_readiness_action_params(payload_value(action, "query"))
      }
      |> maybe_put_issue_id(payload_value(action, "issue_id"))
    end
  end

  defp publish_readiness_typed_action(_action), do: nil

  defp publish_readiness_typed_action_target(target)
       when target in ["source_health", "source_inventory", :source_health, :source_inventory],
       do: "data_sources"

  defp publish_readiness_typed_action_target(target)
       when target in ["dashboard_editor", :dashboard_editor],
       do: "dashboard_editor"

  defp publish_readiness_typed_action_target(target) when is_atom(target),
    do: Atom.to_string(target)

  defp publish_readiness_typed_action_target(target) when is_binary(target), do: target
  defp publish_readiness_typed_action_target(_target), do: nil

  defp maybe_put_issue_id(action, issue_id) when is_binary(issue_id) and issue_id != "" do
    Map.put(action, :issue_id, issue_id)
  end

  defp maybe_put_issue_id(action, _issue_id), do: action

  defp publish_readiness_action_issue_id(action) when is_map(action) do
    payload_value(action, "issue_id") ||
      action
      |> payload_value("params")
      |> publish_readiness_action_param("selected_publish_issue")
  end

  defp publish_readiness_action_params(params) when is_map(params) do
    params
    |> Enum.reject(fn {_key, value} -> value in [nil, ""] end)
    |> Map.new(fn {key, value} -> {to_string(key), to_string(value)} end)
  end

  defp publish_readiness_action_params(_params), do: %{}

  defp publish_readiness_action_param(params, key) when is_map(params),
    do: payload_value(params, key)

  defp publish_readiness_action_param(_params, _key), do: nil

  defp optional_string(value) when value in [nil, ""], do: nil
  defp optional_string(value), do: to_string(value)

  defp runtime_impact_field(%{state: "not_applicable"}), do: nil

  defp runtime_impact_field(%{label: label}) when is_binary(label) do
    field("Runtime", label, "font-mono text-base-content/70")
  end

  defp runtime_impact_field(_impact), do: nil

  defp version_value(nil), do: "-"
  defp version_value(version) when is_integer(version), do: "v#{version}"
  defp version_value(version), do: to_string(version)

  defp version_attr_value(nil), do: nil
  defp version_attr_value(version) when is_integer(version), do: Integer.to_string(version)

  defp payload_value(payload, key) when is_map(payload) do
    Map.get(payload, key) || Map.get(payload, maybe_atom_key(key))
  end

  defp payload_value(_payload, _key), do: nil

  defp maybe_atom_key("result"), do: :result
  defp maybe_atom_key("error_count"), do: :error_count
  defp maybe_atom_key("warning_count"), do: :warning_count
  defp maybe_atom_key("issue_count"), do: :issue_count
  defp maybe_atom_key("issue_codes"), do: :issue_codes
  defp maybe_atom_key("source_warning_codes"), do: :source_warning_codes
  defp maybe_atom_key("source_evidence_contexts"), do: :source_evidence_contexts
  defp maybe_atom_key("warning_code"), do: :warning_code
  defp maybe_atom_key("source_request_id"), do: :source_request_id
  defp maybe_atom_key("logical_source"), do: :logical_source
  defp maybe_atom_key("source_binding_id"), do: :source_binding_id
  defp maybe_atom_key("data_source_id"), do: :data_source_id
  defp maybe_atom_key("replay_run_id"), do: :replay_run_id
  defp maybe_atom_key("remediation_targets"), do: :remediation_targets
  defp maybe_atom_key("label"), do: :label
  defp maybe_atom_key("target"), do: :target
  defp maybe_atom_key("message"), do: :message
  defp maybe_atom_key("params"), do: :params
  defp maybe_atom_key("source_dashboard_id"), do: :source_dashboard_id
  defp maybe_atom_key("source_return_activity_event"), do: :source_return_activity_event
  defp maybe_atom_key(key), do: key

  defp selected?(%LifecycleEvent{dashboard_lifecycle_event_id: event_id}, selected_event_id)
       when is_binary(selected_event_id) do
    event_id == selected_event_id
  end

  defp selected?(_event, _selected_event_id), do: false

  defp row_class(true), do: ["border-l-2 bg-base-100/40 px-2 py-2", "border-info bg-info/10"]
  defp row_class(false), do: ["border-l-2 bg-base-100/40 px-2 py-2", "border-primary/60"]

  defp format_time(nil), do: "-"

  defp format_time(%DateTime{} = datetime) do
    Calendar.strftime(datetime, "%Y-%m-%d %H:%M:%S UTC")
  end

  defp boolean_text(true), do: "true"
  defp boolean_text(false), do: "false"
end
