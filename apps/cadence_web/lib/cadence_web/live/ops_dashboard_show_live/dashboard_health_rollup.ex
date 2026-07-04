defmodule CadenceWeb.OpsDashboardShowLive.DashboardHealthRollup do
  @moduledoc false

  @snapshot_schema "dashboard_health_snapshot.v1"
  @state_order [:blocked, :stale, :degraded, :ready]

  @spec rollup([map()]) :: map()
  def rollup(widget_items) when is_list(widget_items) do
    items = Enum.map(widget_items, &widget_health_item/1)
    counts = counts_by_state(items)
    state = Enum.find(@state_order, :ready, &(Map.get(counts, &1, 0) > 0))

    %{
      visible?: items != [],
      state: state,
      state_text: Atom.to_string(state),
      label: state_label(state),
      severity: severity(state),
      severity_text: severity(state) |> Atom.to_string(),
      widget_count: length(items),
      ready_count: Map.get(counts, :ready, 0),
      degraded_count: Map.get(counts, :degraded, 0),
      stale_count: Map.get(counts, :stale, 0),
      blocked_count: Map.get(counts, :blocked, 0),
      affected_count: Enum.count(items, &(&1.state != :ready)),
      states: states_attr(items),
      affected_placements: placements_attr(items, &(&1.state != :ready)),
      blocked_placements: placements_attr(items, &(&1.state == :blocked)),
      stale_placements: placements_attr(items, &(&1.state == :stale)),
      degraded_placements: placements_attr(items, &(&1.state == :degraded)),
      groups: groups(items),
      items: items
    }
  end

  def rollup(_widget_items), do: rollup([])

  @spec with_snapshot(map(), map()) :: map()
  def with_snapshot(rollup, context \\ %{})

  def with_snapshot(rollup, context) when is_map(rollup) do
    snapshot = snapshot(rollup, context)

    rollup
    |> Map.put(:snapshot_schema, @snapshot_schema)
    |> Map.put(:snapshot_id, Map.get(snapshot, "snapshot_id"))
    |> Map.put(:snapshot, snapshot)
  end

  def with_snapshot(_rollup, context), do: rollup([]) |> with_snapshot(context)

  @spec snapshot(map(), map()) :: map()
  def snapshot(rollup, context \\ %{})

  def snapshot(rollup, context) when is_map(rollup) do
    payload =
      %{
        "schema" => @snapshot_schema,
        "organization_id" => string_value(context, :organization_id),
        "mission_id" => string_value(context, :mission_id),
        "dashboard_id" => string_value(context, :dashboard_id),
        "runtime_context" => runtime_context(context),
        "state" => Map.get(rollup, :state_text),
        "severity" => Map.get(rollup, :severity_text),
        "counts" => %{
          "widgets" => Map.get(rollup, :widget_count, 0),
          "ready" => Map.get(rollup, :ready_count, 0),
          "degraded" => Map.get(rollup, :degraded_count, 0),
          "stale" => Map.get(rollup, :stale_count, 0),
          "blocked" => Map.get(rollup, :blocked_count, 0),
          "affected" => Map.get(rollup, :affected_count, 0)
        },
        "states" => split_attr(Map.get(rollup, :states)),
        "placement_ids" => %{
          "affected" => split_attr(Map.get(rollup, :affected_placements)),
          "blocked" => split_attr(Map.get(rollup, :blocked_placements)),
          "stale" => split_attr(Map.get(rollup, :stale_placements)),
          "degraded" => split_attr(Map.get(rollup, :degraded_placements))
        },
        "items" => Enum.map(Map.get(rollup, :items, []), &snapshot_item/1)
      }
      |> compact_snapshot()

    Map.put(payload, "snapshot_id", snapshot_id(payload))
  end

  def snapshot(_rollup, context), do: rollup([]) |> snapshot(context)

  @spec snapshot_id(map()) :: binary()
  def snapshot_id(snapshot) when is_map(snapshot) do
    snapshot
    |> Map.delete("snapshot_id")
    |> canonicalize()
    |> :erlang.term_to_binary()
    |> then(&:crypto.hash(:sha256, &1))
    |> Base.encode16(case: :lower)
    |> then(&("dashboard_health_snapshot_" <> &1))
  end

  @spec root_attrs(map()) :: map()
  def root_attrs(rollup) when is_map(rollup) do
    %{
      "data-dashboard-health-snapshot-schema" =>
        Map.get(rollup, :snapshot_schema, @snapshot_schema),
      "data-dashboard-health-snapshot-id" => Map.get(rollup, :snapshot_id),
      "data-dashboard-health-state" => Map.get(rollup, :state_text),
      "data-dashboard-health-severity" => Map.get(rollup, :severity_text),
      "data-dashboard-health-widgets" => Map.get(rollup, :widget_count),
      "data-dashboard-health-ready" => Map.get(rollup, :ready_count),
      "data-dashboard-health-degraded" => Map.get(rollup, :degraded_count),
      "data-dashboard-health-stale" => Map.get(rollup, :stale_count),
      "data-dashboard-health-blocked" => Map.get(rollup, :blocked_count),
      "data-dashboard-health-affected" => Map.get(rollup, :affected_count),
      "data-dashboard-health-states" => Map.get(rollup, :states),
      "data-dashboard-health-affected-placements" => Map.get(rollup, :affected_placements),
      "data-dashboard-health-blocked-placements" => Map.get(rollup, :blocked_placements),
      "data-dashboard-health-stale-placements" => Map.get(rollup, :stale_placements),
      "data-dashboard-health-degraded-placements" => Map.get(rollup, :degraded_placements)
    }
  end

  def root_attrs(_rollup), do: root_attrs(rollup([]))

  defp runtime_context(context) do
    %{
      "realm" => string_value(context, :realm),
      "data_view" => string_value(context, :data_view),
      "compare_data_view" => string_value(context, :compare_data_view),
      "time_mode" => string_value(context, :time_mode),
      "time_from" => string_value(context, :time_from),
      "time_to" => string_value(context, :time_to),
      "replay_run_id" => string_value(context, :replay_run_id),
      "scope_kind" => string_value(context, :scope_kind),
      "scope_id" => string_value(context, :scope_id),
      "data_source_id" => string_value(context, :data_source_id),
      "source_binding_id" => string_value(context, :source_binding_id),
      "limit_mode" => string_value(context, :limit_mode)
    }
    |> compact_snapshot()
  end

  defp snapshot_item(item) when is_map(item) do
    %{
      "placement_id" => string_value(item, :placement_id),
      "widget_id" => string_value(item, :widget_id),
      "title" => string_value(item, :title),
      "state" => string_value(item, :state_text),
      "severity" => string_value(item, :severity_text),
      "lifecycle_state" => string_value(item, :lifecycle_state_text),
      "source_state" => string_value(item, :source_state_text),
      "warning_codes" =>
        item
        |> Map.get(:warning_codes, [])
        |> Enum.map(&atom_text/1),
      "reason" => string_value(item, :reason)
    }
    |> compact_snapshot()
  end

  defp snapshot_item(_item), do: %{}

  defp canonicalize(map) when is_map(map) do
    map
    |> Enum.map(fn {key, value} -> {to_string(key), canonicalize(value)} end)
    |> Enum.sort_by(fn {key, _value} -> key end)
  end

  defp canonicalize(values) when is_list(values), do: Enum.map(values, &canonicalize/1)
  defp canonicalize(value), do: value

  defp widget_health_item(%{item: item, props: props}) do
    placement_id = Map.get(item, :placement_id)
    widget = Map.get(item, :widget, %{})
    data = Map.get(props, :data)
    warnings = Map.get(props, :warnings, [])
    lifecycle_state = data |> map_value(:lifecycle_state) |> normalize_atom()
    source_state = data |> map_value(:source_status) |> map_value(:state) |> normalize_atom()
    warning_codes = Enum.map(warnings, &warning_code/1) |> Enum.reject(&is_nil/1) |> Enum.uniq()
    state = health_state(lifecycle_state, source_state, warning_codes)

    %{
      placement_id: placement_id,
      widget_id: map_value(widget, :widget_id),
      title: map_value(widget, :title) || placement_id,
      state: state,
      state_text: Atom.to_string(state),
      severity: severity(state),
      severity_text: severity(state) |> Atom.to_string(),
      lifecycle_state: lifecycle_state,
      lifecycle_state_text: atom_text(lifecycle_state),
      source_state: source_state,
      source_state_text: atom_text(source_state),
      warning_codes: warning_codes,
      warning_codes_text: Enum.map_join(warning_codes, ",", &atom_text/1),
      reason: reason(lifecycle_state, source_state, warning_codes)
    }
  end

  defp widget_health_item(%{} = item), do: widget_health_item(%{item: item, props: %{}})

  defp health_state(lifecycle_state, source_state, warning_codes) do
    cond do
      lifecycle_state in [:error, :unsupported] -> :blocked
      source_state in [:unavailable, :retention_gap] -> :blocked
      source_state == :degraded -> :degraded
      lifecycle_state == :stale or source_state in [:stale, :unknown] -> :stale
      lifecycle_state in [:partial, :no_data] -> :degraded
      warning_codes != [] -> :degraded
      true -> :ready
    end
  end

  defp reason(_lifecycle_state, source_state, _warning_codes)
       when source_state in [:unavailable, :retention_gap],
       do: "source_#{source_state}"

  defp reason(lifecycle_state, _source_state, _warning_codes)
       when lifecycle_state in [:error, :unsupported, :stale, :partial, :no_data],
       do: "lifecycle_#{lifecycle_state}"

  defp reason(_lifecycle_state, source_state, _warning_codes)
       when source_state in [:stale, :unknown, :degraded],
       do: "source_#{source_state}"

  defp reason(_lifecycle_state, _source_state, warning_codes) when warning_codes != [],
    do: "warnings"

  defp reason(_lifecycle_state, _source_state, _warning_codes), do: "ready"

  defp groups(items) do
    @state_order
    |> Enum.map(fn state ->
      state_items = Enum.filter(items, &(&1.state == state))

      %{
        key: Atom.to_string(state),
        state: state,
        label: state_label(state),
        count: length(state_items),
        placement_ids: placements_attr(state_items, fn _item -> true end),
        items: state_items
      }
    end)
    |> Enum.reject(&(&1.count == 0))
  end

  defp counts_by_state(items) do
    Enum.reduce(items, %{}, fn item, counts ->
      Map.update(counts, item.state, 1, &(&1 + 1))
    end)
  end

  defp states_attr(items) do
    items
    |> Enum.map(& &1.state)
    |> Enum.uniq()
    |> Enum.map_join(",", &Atom.to_string/1)
  end

  defp placements_attr(items, predicate) when is_function(predicate, 1) do
    items
    |> Enum.filter(predicate)
    |> Enum.map(& &1.placement_id)
    |> Enum.reject(&is_nil/1)
    |> Enum.uniq()
    |> Enum.join(",")
  end

  defp split_attr(value) when value in [nil, ""], do: []

  defp split_attr(value) when is_binary(value) do
    value
    |> String.split(",", trim: true)
    |> Enum.map(&String.trim/1)
    |> Enum.reject(&(&1 == ""))
  end

  defp split_attr(values) when is_list(values), do: values
  defp split_attr(_value), do: []

  defp compact_snapshot(map) when is_map(map) do
    map
    |> Enum.reject(fn {_key, value} -> value in [nil, ""] end)
    |> Map.new()
  end

  defp string_value(map, key) when is_map(map) do
    case map_value(map, key) do
      nil -> nil
      value when is_binary(value) -> value
      value when is_atom(value) -> Atom.to_string(value)
      value -> to_string(value)
    end
  end

  defp string_value(_map, _key), do: nil

  defp severity(:blocked), do: :error
  defp severity(:stale), do: :warning
  defp severity(:degraded), do: :warning
  defp severity(:ready), do: :ok

  defp state_label(:blocked), do: "Blocked"
  defp state_label(:stale), do: "Stale"
  defp state_label(:degraded), do: "Degraded"
  defp state_label(:ready), do: "Trustworthy"

  defp warning_code(%{code: code}), do: normalize_atom(code)
  defp warning_code(%{code_text: code_text}), do: normalize_atom(code_text)
  defp warning_code(_warning), do: nil

  defp map_value(map, key) when is_map(map) and is_atom(key),
    do: Map.get(map, key, Map.get(map, Atom.to_string(key)))

  defp map_value(_map, _key), do: nil

  defp normalize_atom(value) when is_atom(value), do: value

  defp normalize_atom(value) when is_binary(value) do
    value
    |> String.replace("-", "_")
    |> String.to_existing_atom()
  rescue
    ArgumentError -> nil
  end

  defp normalize_atom(_value), do: nil

  defp atom_text(nil), do: ""
  defp atom_text(value) when is_atom(value), do: Atom.to_string(value)
end
