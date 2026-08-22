defmodule CadenceWeb.OpsDashboardShowLive.DataLinkPresentation do
  @moduledoc false

  alias CadenceWeb.OpsDashboardShowLive.HistoricalWorkflowContext
  alias CadenceWeb.OpsDashboardShowLive.HistoricalWorkflowControlsPresentation
  alias CadenceWeb.OpsDashboardShowLive.LateDataPolicyContext
  alias CadenceWeb.OpsDashboardShowLive.LateDataPolicyPresentation
  alias CadenceWeb.OpsDashboardShowLive.RevisionDecisionContext
  alias CadenceWeb.OpsDashboardShowLive.RevisionDecisionPresentation

  @relationship_kinds [
    :evidence,
    :source_event,
    :retry_event,
    :correction_request,
    :correction_transition,
    :late_data_policy_event,
    :stage_transition_event,
    :follow_up_event,
    :comparison_review_origin
  ]
  @max_navigation_trail 3

  def panel(inspector) when is_map(inspector) do
    selection_summary = selection_summary(inspector)
    navigation = inspector_navigation(inspector)

    %{
      selection_summary: selection_summary,
      selection_summary_rows: selection_summary_rows(selection_summary),
      navigation: navigation,
      navigation_trail: navigation_trail(navigation, inspector),
      related_groups: inspector |> inspector_related_links() |> related_groups(),
      workflow_explanation?: workflow_explanation?(inspector),
      revision_decision_controls?: revision_decision_controls?(inspector),
      late_data_policy_controls?: late_data_policy_controls?(inspector),
      historical_workflow_controls?: historical_workflow_controls?(inspector)
    }
  end

  def panel(_inspector) do
    %{
      selection_summary: %{},
      selection_summary_rows: [],
      navigation: nil,
      navigation_trail: [],
      related_groups: [],
      workflow_explanation?: false,
      revision_decision_controls?: false,
      late_data_policy_controls?: false,
      historical_workflow_controls?: false
    }
  end

  def related(links) when is_list(links) do
    Enum.map(links, &row(&1, nil))
  end

  def related(_links), do: []

  def related_groups(links) do
    links
    |> related()
    |> Enum.group_by(&related_group/1)
    |> Enum.map(fn {{key, label, order}, group_links} ->
      %{key: key, label: label, order: order, links: group_links}
    end)
    |> Enum.sort_by(& &1.order)
  end

  def evidence(links, inspector) when is_list(links) do
    Enum.map(links, &row(&1, inspector))
  end

  def evidence(_links, _inspector), do: []

  def navigation_event_attrs(inspector, related_link) do
    %{
      nav_from_link_id: inspector_value(inspector, :link_id),
      nav_from_target: inspector_value(inspector, :target),
      nav_from_target_id: inspector_value(inspector, :target_id),
      nav_from_label:
        inspector_value(inspector, :link_label) || inspector_value(inspector, :title),
      nav_from_relationship_kind:
        relationship_kind_text(map_value(related_link, :relationship_kind)),
      nav_from_relationship_label: map_value(related_link, :label),
      nav_trail: navigation_trail_param(inspector, related_link)
    }
    |> Map.merge(navigation_selection_entry(inspector, related_link))
  end

  def row(link, inspector \\ nil) do
    %{
      link: link,
      link_id: link_value(link, :link_id),
      target: target_value(link),
      target_text: target_text(link),
      target_id: link_value(link, :target_id),
      label: label(link),
      relationship_kind: relationship_kind(link),
      realm: context_value(link, inspector, :realm),
      data_view: context_value(link, inspector, :view),
      data_source_id: context_value(link, inspector, :data_source_id),
      source_binding_id: context_value(link, inspector, :source_binding_id),
      time_mode: context_value(link, inspector, :time_mode),
      time_axis: context_value(link, inspector, :time_axis),
      replay_run_id: context_value(link, inspector, :replay_run_id)
    }
  end

  def target_text(%{target_text: target_text}) when is_binary(target_text) and target_text != "",
    do: target_text

  def target_text(%{"target_text" => target_text})
      when is_binary(target_text) and target_text != "",
      do: target_text

  def target_text(%{target: target}), do: target_to_text(target)
  def target_text(%{"target" => target}), do: target_to_text(target)
  def target_text(_link), do: "unknown"

  defp label(link) do
    link_value(link, :label)
    |> empty_to_nil()
    |> Kernel.||(target_text(link))
  end

  defp target_value(%{target: target}) when is_atom(target), do: Atom.to_string(target)
  defp target_value(%{target: target}) when is_binary(target), do: target
  defp target_value(%{"target" => target}) when is_atom(target), do: Atom.to_string(target)
  defp target_value(%{"target" => target}) when is_binary(target), do: target
  defp target_value(_link), do: ""

  defp target_to_text(target) when is_atom(target) do
    target
    |> Atom.to_string()
    |> String.replace("_", " ")
  end

  defp target_to_text(target) when is_binary(target), do: String.replace(target, "_", " ")
  defp target_to_text(_target), do: "unknown"

  defp relationship_kind(link) do
    link
    |> link_value(:relationship_kind)
    |> empty_to_nil()
    |> relationship_kind_value()
  end

  defp relationship_kind_value(value) when is_atom(value) and value in @relationship_kinds,
    do: value

  defp relationship_kind_value(value) when is_atom(value), do: nil

  defp relationship_kind_value(value) when is_binary(value) do
    normalized =
      value
      |> String.trim()
      |> String.downcase()
      |> String.replace("-", "_")

    Enum.find(@relationship_kinds, &(Atom.to_string(&1) == normalized))
  end

  defp relationship_kind_value(_value), do: nil

  defp related_group(%{relationship_kind: relationship_kind})
       when relationship_kind in [:source_event, :comparison_review_origin] do
    {"source", "Source", 0}
  end

  defp related_group(%{relationship_kind: relationship_kind})
       when relationship_kind in [:retry_event, :correction_request, :late_data_policy_event] do
    {"recovery", "Recovery", 1}
  end

  defp related_group(%{relationship_kind: relationship_kind})
       when relationship_kind in [
              :correction_transition,
              :stage_transition_event,
              :follow_up_event
            ] do
    {"follow-up", "Follow-up", 2}
  end

  defp related_group(%{relationship_kind: :evidence}), do: {"evidence", "Evidence", 3}

  defp related_group(%{relationship_kind: nil, label: label}) when is_binary(label) do
    normalized_label = String.downcase(label)

    cond do
      String.contains?(normalized_label, "source event") ->
        {"source", "Source", 0}

      String.contains?(normalized_label, "transition") or
          String.starts_with?(normalized_label, "follow-up") ->
        {"follow-up", "Follow-up", 2}

      String.starts_with?(normalized_label, "retry ") or
        String.starts_with?(normalized_label, "correction ") or
          String.starts_with?(normalized_label, "late data policy") ->
        {"recovery", "Recovery", 1}

      true ->
        {"evidence", "Evidence", 3}
    end
  end

  defp related_group(_link), do: {"evidence", "Evidence", 3}

  defp inspector_related_links(%{related_links: links}) when is_list(links), do: links
  defp inspector_related_links(_inspector), do: []

  defp inspector_navigation(%{navigation: navigation}) when is_map(navigation) do
    from = navigation_value_map(navigation, :from)
    trail = navigation_value_map(navigation, :trail)

    %{from: from, trail: trail}
    |> Enum.reject(fn
      {_key, value} when value in [nil, []] -> true
      {_key, value} when is_map(value) -> map_size(value) == 0
      _entry -> false
    end)
    |> Map.new()
    |> case do
      navigation when map_size(navigation) > 0 -> navigation
      _empty -> nil
    end
  end

  defp inspector_navigation(%{"navigation" => navigation}) when is_map(navigation),
    do: inspector_navigation(%{navigation: navigation})

  defp inspector_navigation(_inspector), do: nil

  defp navigation_trail(%{trail: trail}, inspector) when is_list(trail) and trail != [] do
    trail
    |> Enum.map(&navigation_entry/1)
    |> Enum.reject(&(&1 == %{}))
    |> Enum.take(-@max_navigation_trail)
    |> Enum.map(&Map.put(&1, :back_link, navigation_back_link(&1, inspector)))
  end

  defp navigation_trail(%{from: from}, inspector) when is_map(from) do
    from
    |> navigation_entry()
    |> case do
      entry when map_size(entry) > 0 ->
        [Map.put(entry, :back_link, navigation_back_link(entry, inspector))]

      _empty ->
        []
    end
  end

  defp navigation_trail(_navigation, _inspector), do: []

  defp navigation_entry(%{from: from}) when is_map(from), do: navigation_entry(from)

  defp navigation_entry(entry) when is_map(entry) do
    %{
      link_id: navigation_value(entry, :link_id),
      target: navigation_value(entry, :target),
      target_id: navigation_value(entry, :target_id),
      label: navigation_value(entry, :label),
      relationship_kind: navigation_value(entry, :relationship_kind),
      relationship_label: navigation_value(entry, :relationship_label),
      placement_id: navigation_value(entry, :placement_id),
      timestamp_ms: navigation_value(entry, :timestamp_ms),
      realm: navigation_value(entry, :realm),
      data_view: navigation_value(entry, :data_view),
      data_source_id: navigation_value(entry, :data_source_id),
      source_binding_id: navigation_value(entry, :source_binding_id),
      time_mode: navigation_value(entry, :time_mode),
      time_axis: navigation_value(entry, :time_axis),
      replay_run_id: navigation_value(entry, :replay_run_id)
    }
    |> Enum.reject(fn {_key, value} -> value in [nil, ""] end)
    |> Map.new()
  end

  defp navigation_entry(_entry), do: %{}

  defp navigation_back_link(entry, context_fallback) when is_map(entry) do
    case {navigation_value(entry, :target), navigation_value(entry, :target_id)} do
      {target, target_id} when is_binary(target) and is_binary(target_id) ->
        context_fallback
        |> navigation_context_entry(nil)
        |> Map.merge(%{
          link_id: navigation_value(entry, :link_id),
          target: target,
          target_id: target_id,
          label: navigation_value(entry, :label)
        })
        |> Map.merge(navigation_entry_context(entry))
        |> Enum.reject(fn {_key, value} -> value in [nil, ""] end)
        |> Map.new()

      _missing ->
        nil
    end
  end

  defp navigation_trail_param(inspector, related_link) do
    entries =
      inspector
      |> inspector_navigation()
      |> existing_navigation_trail()
      |> Kernel.++([current_navigation_entry(inspector, related_link)])
      |> Enum.reject(&(&1 == %{}))
      |> Enum.take(-@max_navigation_trail)

    if entries == [], do: nil, else: Jason.encode!(entries)
  end

  defp existing_navigation_trail(%{trail: trail}) when is_list(trail) and trail != [] do
    trail
    |> Enum.map(&navigation_entry/1)
    |> Enum.reject(&(&1 == %{}))
  end

  defp existing_navigation_trail(%{from: from}) when is_map(from) do
    case navigation_entry(from) do
      entry when map_size(entry) > 0 -> [entry]
      _empty -> []
    end
  end

  defp existing_navigation_trail(_navigation), do: []

  defp current_navigation_entry(inspector, related_link) do
    %{
      link_id: inspector_value(inspector, :link_id),
      target: inspector_value(inspector, :target),
      target_id: inspector_value(inspector, :target_id),
      label: inspector_value(inspector, :link_label) || inspector_value(inspector, :title),
      relationship_kind: relationship_kind_text(map_value(related_link, :relationship_kind)),
      relationship_label: map_value(related_link, :label)
    }
    |> Map.merge(navigation_selection_entry(inspector, related_link))
    |> Map.merge(navigation_context_entry(inspector, related_link))
    |> Enum.reject(fn {_key, value} -> value in [nil, ""] end)
    |> Map.new()
  end

  defp navigation_selection_entry(inspector, related_link) do
    %{
      placement_id: navigation_context_value(inspector, related_link, :placement_id, "Placement"),
      timestamp_ms: navigation_context_value(inspector, related_link, :timestamp_ms, "Timestamp")
    }
  end

  defp navigation_context_entry(inspector, related_link) do
    %{
      realm: navigation_context_value(inspector, related_link, :realm, "Data realm"),
      data_view:
        navigation_context_value(inspector, related_link, :data_view, "Data view", :view),
      data_source_id:
        navigation_context_value(inspector, related_link, :data_source_id, "Data source"),
      source_binding_id:
        navigation_context_value(inspector, related_link, :source_binding_id, "Source binding"),
      time_mode: navigation_context_value(inspector, related_link, :time_mode, "Time mode"),
      time_axis: navigation_context_value(inspector, related_link, :time_axis, "Time axis"),
      replay_run_id:
        navigation_context_value(inspector, related_link, :replay_run_id, "Replay run")
    }
  end

  defp navigation_context_value(inspector, related_link, source_context_key, row_label) do
    navigation_context_value(
      inspector,
      related_link,
      source_context_key,
      row_label,
      source_context_key
    )
  end

  defp navigation_context_value(
         inspector,
         related_link,
         source_context_key,
         row_label,
         related_context_key
       ) do
    source_context_value(inspector, source_context_key) ||
      context_row_value(inspector, row_label) ||
      context_value(related_link, inspector, related_context_key)
  end

  defp navigation_entry_context(entry) do
    %{
      placement_id: navigation_value(entry, :placement_id),
      timestamp_ms: navigation_value(entry, :timestamp_ms),
      realm: navigation_value(entry, :realm),
      data_view: navigation_value(entry, :data_view),
      data_source_id: navigation_value(entry, :data_source_id),
      source_binding_id: navigation_value(entry, :source_binding_id),
      time_mode: navigation_value(entry, :time_mode),
      time_axis: navigation_value(entry, :time_axis),
      replay_run_id: navigation_value(entry, :replay_run_id)
    }
    |> Enum.reject(fn {_key, value} -> value in [nil, ""] end)
    |> Map.new()
  end

  defp selection_summary(inspector) when is_map(inspector) do
    %{
      link_id: inspector_value(inspector, :link_id),
      status: inspector_value(inspector, :status_text),
      target: inspector_value(inspector, :target_text),
      target_id: inspector_value(inspector, :target_id),
      source: inspector_value(inspector, :source_text),
      realm:
        source_context_value(inspector, :realm) || context_row_value(inspector, "Data realm"),
      data_view:
        source_context_value(inspector, :data_view) || context_row_value(inspector, "Data view"),
      data_source_id:
        source_context_value(inspector, :data_source_id) ||
          context_row_value(inspector, "Data source"),
      source_binding_id:
        source_context_value(inspector, :source_binding_id) ||
          context_row_value(inspector, "Source binding"),
      time_mode:
        source_context_value(inspector, :time_mode) || context_row_value(inspector, "Time mode"),
      time_axis:
        source_context_value(inspector, :time_axis) || context_row_value(inspector, "Time axis"),
      replay_run_id:
        source_context_value(inspector, :replay_run_id) ||
          context_row_value(inspector, "Replay run"),
      scope: context_row_value(inspector, "Scope"),
      limit_mode: context_row_value(inspector, "Limit mode")
    }
  end

  defp selection_summary_rows(summary) when is_map(summary) do
    [
      selection_row("State", Map.get(summary, :status)),
      selection_row("Target", Map.get(summary, :target)),
      selection_row("Target ID", Map.get(summary, :target_id)),
      selection_row("Link", Map.get(summary, :link_id)),
      selection_row("Source", Map.get(summary, :source)),
      selection_row("Data realm", Map.get(summary, :realm)),
      selection_row("Data view", Map.get(summary, :data_view)),
      selection_row("Data source", Map.get(summary, :data_source_id)),
      selection_row("Source binding", Map.get(summary, :source_binding_id)),
      selection_row("Time mode", Map.get(summary, :time_mode)),
      selection_row("Time axis", Map.get(summary, :time_axis)),
      selection_row("Replay run", Map.get(summary, :replay_run_id)),
      selection_row("Scope", Map.get(summary, :scope)),
      selection_row("Limit mode", Map.get(summary, :limit_mode))
    ]
    |> Enum.reject(&is_nil/1)
  end

  defp selection_row(_label, nil), do: nil
  defp selection_row(_label, ""), do: nil
  defp selection_row(label, value), do: %{label: label, value: value}

  defp source_context_value(inspector, key) when is_map(inspector) do
    inspector
    |> map_value(:source_context)
    |> map_value(key)
    |> text_or_nil()
  end

  defp source_context_value(_inspector, _key), do: nil

  defp context_row_value(%{context_rows: rows}, label) when is_list(rows) do
    Enum.find_value(rows, fn
      %{label: ^label, value: value} -> text_or_nil(value)
      %{"label" => ^label, "value" => value} -> text_or_nil(value)
      _row -> nil
    end)
  end

  defp context_row_value(_inspector, _label), do: nil

  defp workflow_explanation?(%{target: :telemetry_backfill_lifecycle_event, status: :resolved}),
    do: true

  defp workflow_explanation?(_inspector), do: false

  defp late_data_policy_controls?(
         %{target: :telemetry_backfill_lifecycle_event, status: :resolved} = inspector
       ) do
    inspector
    |> LateDataPolicyContext.build()
    |> LateDataPolicyPresentation.controls_available?()
  end

  defp late_data_policy_controls?(_inspector), do: false

  defp revision_decision_controls?(
         %{target: :telemetry_revision_decision_event, status: :resolved} = inspector
       ),
       do: revision_decision_controls_available?(inspector)

  defp revision_decision_controls?(
         %{target: :comparison_finding, status: :context_only} = inspector
       ),
       do: revision_decision_controls_available?(inspector)

  defp revision_decision_controls?(_inspector), do: false

  defp revision_decision_controls_available?(inspector) do
    inspector
    |> RevisionDecisionContext.build()
    |> RevisionDecisionPresentation.controls_available?()
  end

  defp historical_workflow_controls?(%{target: :telemetry_backfill_lifecycle_event} = inspector) do
    inspector
    |> HistoricalWorkflowContext.build()
    |> HistoricalWorkflowControlsPresentation.controls_available?()
  end

  defp historical_workflow_controls?(_inspector), do: false

  defp context_value(link, inspector, :time_mode) do
    data_link_context_value(link, :time, :mode) ||
      inspector_source_context_value(inspector, :time_mode)
  end

  defp context_value(link, inspector, :time_axis) do
    data_link_context_value(link, :time, :axis) ||
      inspector_source_context_value(inspector, :time_axis)
  end

  defp context_value(link, inspector, :view) do
    data_link_context_value(link, :data, :view) ||
      inspector_source_context_value(inspector, :view)
  end

  defp context_value(link, inspector, :placement_id) do
    data_link_context_value(link, :selection, :placement_id) ||
      inspector_source_context_value(inspector, :placement_id)
  end

  defp context_value(link, inspector, :timestamp_ms) do
    data_link_context_value(link, :selection, :timestamp_ms) ||
      inspector_source_context_value(inspector, :timestamp_ms)
  end

  defp context_value(link, inspector, key) do
    data_link_context_value(link, :data, key) ||
      inspector_source_context_value(inspector, key)
  end

  defp data_link_context_value(%{context: context}, section, key),
    do: nested_context_value(context, section, key)

  defp data_link_context_value(%{"context" => context}, section, key),
    do: nested_context_value(context, section, key)

  defp data_link_context_value(%{link: link}, section, key),
    do: data_link_context_value(link, section, key)

  defp data_link_context_value(%{"link" => link}, section, key),
    do: data_link_context_value(link, section, key)

  defp data_link_context_value(_link, _section, _key), do: nil

  defp nested_context_value(context, section, key) do
    context
    |> map_value(section)
    |> map_value(key)
    |> text_value()
    |> empty_to_nil()
  end

  defp inspector_source_context_value(%{source_context: source_context}, :view)
       when is_map(source_context) do
    source_context
    |> map_value(:data_view)
    |> text_value()
    |> empty_to_nil()
  end

  defp inspector_source_context_value(%{"source_context" => source_context}, :view)
       when is_map(source_context) do
    source_context
    |> map_value(:data_view)
    |> text_value()
    |> empty_to_nil()
  end

  defp inspector_source_context_value(%{source_context: source_context}, key)
       when is_map(source_context) do
    source_context
    |> map_value(key)
    |> text_value()
    |> empty_to_nil()
  end

  defp inspector_source_context_value(%{"source_context" => source_context}, key)
       when is_map(source_context) do
    source_context
    |> map_value(key)
    |> text_value()
    |> empty_to_nil()
  end

  defp inspector_source_context_value(_inspector, _key), do: nil

  defp link_value(link, key) when is_map(link) and is_atom(key) do
    Map.get(link, key, Map.get(link, Atom.to_string(key)))
  end

  defp map_value(context, key) when is_map(context) and is_atom(key) do
    Map.get(context, key, Map.get(context, Atom.to_string(key)))
  end

  defp map_value(_context, _key), do: nil

  defp inspector_value(inspector, key) when is_map(inspector) do
    inspector
    |> map_value(key)
    |> text_or_nil()
  end

  defp navigation_value_map(navigation, key) when is_map(navigation),
    do: map_value(navigation, key)

  defp navigation_value(navigation, key) when is_map(navigation) do
    navigation
    |> map_value(key)
    |> text_or_nil()
  end

  defp relationship_kind_text(nil), do: nil
  defp relationship_kind_text(kind) when is_atom(kind), do: Atom.to_string(kind)
  defp relationship_kind_text(kind) when is_binary(kind), do: kind
  defp relationship_kind_text(_kind), do: nil

  defp text_value(nil), do: ""
  defp text_value(value) when is_atom(value), do: Atom.to_string(value)
  defp text_value(value) when is_binary(value), do: value
  defp text_value(value), do: to_string(value)

  defp text_or_nil(nil), do: nil
  defp text_or_nil(value) when is_atom(value), do: Atom.to_string(value)
  defp text_or_nil(value) when is_binary(value) and value != "", do: value
  defp text_or_nil(value) when is_binary(value), do: nil
  defp text_or_nil(value), do: to_string(value)

  defp empty_to_nil(nil), do: nil
  defp empty_to_nil(""), do: nil
  defp empty_to_nil(value), do: value
end
