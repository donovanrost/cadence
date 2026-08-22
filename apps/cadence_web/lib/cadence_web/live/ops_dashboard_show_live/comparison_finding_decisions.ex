defmodule CadenceWeb.OpsDashboardShowLive.ComparisonFindingDecisions do
  @moduledoc false

  alias Cadence.Telemetry.Storage

  @event_limit 500

  def enrich_rollup(%{visible?: true, groups: groups} = rollup, assigns) when is_list(groups) do
    events = decision_events(assigns)
    decisions_by_placement = decisions_by_placement(events)

    groups =
      Enum.map(groups, fn group ->
        items =
          group
          |> Map.get(:items, [])
          |> Enum.map(&enrich_item(&1, decisions_by_placement))

        group
        |> Map.put(:items, items)
        |> Map.put(:handled_count, Enum.count(items, &handled?/1))
        |> Map.put(:unhandled_count, Enum.count(items, &(not handled?(&1))))
      end)

    rollup
    |> Map.put(:groups, groups)
    |> Map.put(:handled_count, handled_count(groups))
    |> Map.put(:unhandled_count, unhandled_count(groups))
    |> Map.put(:open_count, unhandled_count(groups))
    |> Map.put(:workflow_groups, workflow_groups(groups))
  end

  def enrich_rollup(rollup, _assigns), do: rollup

  defp decision_events(%{dashboard_comparison_decision_events: events}) when is_list(events),
    do: events

  defp decision_events(assigns) when is_map(assigns) do
    with %{organization_id: organization_id} <- Map.get(assigns, :current_scope),
         %{mission_id: mission_id} <- Map.get(assigns, :current_mission) do
      Storage.list_observation_identity_decision_events_for_mission(
        mission_id,
        [
          organization_id: organization_id,
          realm: present_text(Map.get(assigns, :dashboard_data_realm)),
          data_source_id: present_text(Map.get(assigns, :dashboard_data_source_id)),
          binding_id: present_text(Map.get(assigns, :dashboard_source_binding_id)),
          limit: @event_limit
        ]
        |> Enum.reject(fn {_key, value} -> is_nil(value) end)
      )
    else
      _missing_scope -> []
    end
  end

  defp decisions_by_placement(events) when is_list(events) do
    Enum.reduce(events, %{}, fn event, acc ->
      case placement_id(event) do
        nil -> acc
        placement_id -> Map.put(acc, placement_id, event)
      end
    end)
  end

  defp enrich_item(item, decisions_by_placement) when is_map(item) do
    case Map.get(decisions_by_placement, Map.get(item, :placement_id)) do
      nil ->
        item
        |> Map.put(:decision_status, "unhandled")
        |> Map.put(:handled?, false)

      event ->
        item
        |> Map.put(:decision_status, "applied")
        |> Map.put(:handled?, true)
        |> Map.put(:decision_event_id, map_value(event, :decision_event_id))
        |> Map.put(:decision, text_value(map_value(event, :decision)))
        |> Map.put(:decision_reason, map_value(event, :decision_reason))
        |> Map.put(:decision_occurred_at, map_value(event, :occurred_at))
        |> Map.put(:decision_authority, correction_workflow_value(event, :authority))
    end
  end

  defp handled?(item) when is_map(item), do: Map.get(item, :handled?) == true
  defp handled?(_item), do: false

  defp handled_count(groups), do: Enum.sum(Enum.map(groups, &Map.get(&1, :handled_count, 0)))
  defp unhandled_count(groups), do: Enum.sum(Enum.map(groups, &Map.get(&1, :unhandled_count, 0)))

  defp workflow_groups(groups) do
    items =
      groups
      |> Enum.flat_map(&Map.get(&1, :items, []))
      |> Enum.uniq_by(&Map.get(&1, :placement_id))

    [
      workflow_group("open", "Open findings", items, &(not handled?(&1))),
      workflow_group("handled", "Handled findings", items, &handled?/1)
    ]
    |> Enum.reject(&(&1.count == 0))
  end

  defp workflow_group(key, label, items, predicate) do
    items = Enum.filter(items, predicate)

    %{
      key: key,
      label: label,
      count: length(items),
      placement_ids:
        items
        |> Enum.map(&Map.get(&1, :placement_id))
        |> Enum.reject(&is_nil/1)
        |> Enum.join(","),
      items: items
    }
  end

  defp placement_id(event) do
    event
    |> evidence_ref()
    |> map_value(:comparison_finding, %{})
    |> map_value(:placement_id)
  end

  defp correction_workflow_value(event, key) do
    event
    |> evidence_ref()
    |> map_value(:correction_workflow, %{})
    |> map_value(key)
  end

  defp evidence_ref(event), do: map_value(event, :evidence_ref, %{})

  defp map_value(map, key, default \\ nil)

  defp map_value(map, key, default) when is_map(map),
    do: Map.get(map, key, Map.get(map, Atom.to_string(key), default))

  defp map_value(_map, _key, default), do: default

  defp present_text(value) when is_binary(value) do
    value
    |> String.trim()
    |> case do
      "" -> nil
      value -> value
    end
  end

  defp present_text(value) when is_atom(value), do: Atom.to_string(value)
  defp present_text(_value), do: nil

  defp text_value(nil), do: nil
  defp text_value(value) when is_atom(value), do: Atom.to_string(value)
  defp text_value(value) when is_binary(value), do: value
  defp text_value(value), do: to_string(value)
end
