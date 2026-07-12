defmodule CadenceWeb.OpsDashboardShowLive.SelectedDataRef do
  @moduledoc false

  @atom_keys_by_string %{
    "data_source_id" => :data_source_id,
    "data_view" => :data_view,
    "compare_of" => :compare_of,
    "limit_mode" => :limit_mode,
    "link_id" => :link_id,
    "observable_id" => :observable_id,
    "placement_id" => :placement_id,
    "point_id" => :point_id,
    "realm" => :realm,
    "replay_run_id" => :replay_run_id,
    "resource_id" => :resource_id,
    "scope_id" => :scope_id,
    "scope_ids" => :scope_ids,
    "scope_kind" => :scope_kind,
    "scope_link_id" => :scope_link_id,
    "source_binding_id" => :source_binding_id,
    "series_role" => :series_role,
    "spacecraft_id" => :spacecraft_id,
    "contact_id" => :contact_id,
    "contact_ids" => :contact_ids,
    "transport_id" => :transport_id,
    "source_endpoint_id" => :source_endpoint_id,
    "ground_station_id" => :ground_station_id,
    "target" => :target,
    "target_id" => :target_id,
    "time_axis" => :time_axis,
    "time_mode" => :time_mode,
    "timestamp_ms" => :timestamp_ms,
    "primary_data_management" => :primary_data_management,
    "compare_data_management" => :compare_data_management
  }

  @scope_required_targets [
    "telemetry_sample",
    "limit_event",
    "mission_event",
    "operational_event",
    "contact"
  ]
  @timestamp_required_targets [
    "telemetry_sample",
    "limit_event",
    "mission_event",
    "operational_event"
  ]
  @archive_half_window_seconds 150

  @spec new(map() | nil | term()) :: map() | nil
  def new(selected_ref) when is_map(selected_ref) do
    selected_ref
    |> Enum.reject(fn {_key, value} -> value in [nil, ""] end)
    |> Map.new()
    |> case do
      ref when map_size(ref) == 0 -> nil
      ref -> ref
    end
  end

  def new(_selected_ref), do: nil

  @spec present?(map() | term()) :: boolean()
  def present?(selected_ref), do: is_map(new(selected_ref))

  @spec value(map() | nil | term(), binary()) :: term()
  def value(selected_ref, key) when is_map(selected_ref) and is_binary(key) do
    Map.get(selected_ref, key) || Map.get(selected_ref, Map.get(@atom_keys_by_string, key))
  end

  def value(_selected_ref, _key), do: nil

  @spec observable_id(map() | nil | term()) :: binary() | nil
  def observable_id(selected_ref) do
    case value(selected_ref, "observable_id") || value(selected_ref, "point_id") do
      observable_id when is_binary(observable_id) -> observable_id
      _other -> nil
    end
  end

  @spec for_placement(map() | nil | term(), binary()) :: map() | nil
  def for_placement(selected_ref, placement_id) when is_binary(placement_id) do
    case new(selected_ref) do
      nil ->
        nil

      selected_ref ->
        case value(selected_ref, "placement_id") do
          nil -> selected_ref
          ^placement_id -> selected_ref
          _other -> nil
        end
    end
  end

  def for_placement(_selected_ref, _placement_id), do: nil

  @spec for_runtime_context(map() | nil | term(), map()) :: map() | nil
  def for_runtime_context(selected_ref, runtime_context) do
    selected_ref = new(selected_ref)

    if matches_runtime_context?(selected_ref, runtime_context), do: selected_ref
  end

  @spec matches_runtime_context?(map() | nil | term(), map()) :: boolean()
  def matches_runtime_context?(selected_ref, runtime_context) do
    within_time_context?(selected_ref, runtime_context.time_context) and
      matches_data_runtime_context?(selected_ref, runtime_context)
  end

  @spec matches_query_runtime_context?(map() | nil | term(), map()) :: boolean()
  def matches_query_runtime_context?(selected_ref, runtime_context) do
    matches_runtime_context?(selected_ref, runtime_context) and
      has_required_scope?(selected_ref, runtime_context)
  end

  @spec archive_range(map() | nil | term()) :: {:ok, binary(), binary()} | :error
  def archive_range(selected_ref) do
    with timestamp_ms when is_integer(timestamp_ms) <- integer_value(selected_ref, "timestamp_ms"),
         {:ok, selected_time} <- DateTime.from_unix(timestamp_ms, :millisecond) do
      from_iso =
        selected_time
        |> DateTime.add(-@archive_half_window_seconds, :second)
        |> DateTime.to_iso8601()

      to_iso =
        selected_time
        |> DateTime.add(@archive_half_window_seconds, :second)
        |> DateTime.to_iso8601()

      {:ok, from_iso, to_iso}
    else
      _invalid -> :error
    end
  end

  defp has_required_scope?(selected_ref, runtime_context) do
    not scope_required_target?(selected_ref) or
      required_scope_matches?(selected_ref, runtime_context)
  end

  defp required_scope_matches?(selected_ref, runtime_context) do
    current_scope = current_scope_identity(runtime_context)
    selected_scope = selected_scope_identity(selected_ref)

    [
      &empty_current_scope?/2,
      &same_scope?/2,
      &selected_scope_in_current_scope_set?/2,
      &current_scope_in_selected_scope_set?/2,
      &same_spacecraft_scope?/2
    ]
    |> Enum.any?(& &1.(selected_scope, current_scope))
  end

  defp current_scope_identity(runtime_context) do
    %{
      kind: context_text(runtime_context.scope_kind),
      id: context_text(runtime_context.scope_id),
      ids: context_list(Map.get(runtime_context, :scope_ids)),
      spacecraft_id: context_text(runtime_context.spacecraft_id)
    }
  end

  defp selected_scope_identity(selected_ref) do
    %{
      kind: value(selected_ref, "scope_kind"),
      id: value(selected_ref, "scope_id"),
      ids: context_list(value(selected_ref, "scope_ids")),
      spacecraft_id: value(selected_ref, "spacecraft_id")
    }
  end

  defp empty_current_scope?(_selected_scope, current_scope), do: current_scope.id in [nil, ""]

  defp same_scope?(selected_scope, current_scope) do
    selected_scope.kind == current_scope.kind and selected_scope.id == current_scope.id
  end

  defp selected_scope_in_current_scope_set?(selected_scope, current_scope) do
    selected_scope.kind == current_scope.kind and selected_scope.id in current_scope.ids
  end

  defp current_scope_in_selected_scope_set?(selected_scope, current_scope) do
    selected_scope.kind == current_scope.kind and current_scope.id in selected_scope.ids
  end

  defp same_spacecraft_scope?(selected_scope, current_scope) do
    current_scope.kind == "spacecraft" and
      selected_scope.spacecraft_id == current_scope.spacecraft_id
  end

  defp matches_data_runtime_context?(selected_ref, runtime_context) do
    data_runtime_context_filters(selected_ref, runtime_context)
    |> Enum.all?(fn {key, current_value} ->
      selected_ref_matches_context_value?(selected_ref, key, current_value)
    end)
  end

  defp data_runtime_context_filters(selected_ref, runtime_context) do
    selected_ref
    |> scope_runtime_context_filters(runtime_context)
    |> Kernel.++([
      {"realm", runtime_context.realm || get_in(runtime_context.data_context || %{}, ["realm"])},
      {"data_view", selected_data_view_context(selected_ref, runtime_context)},
      {"data_source_id", runtime_context.data_source_id},
      {"source_binding_id", runtime_context.source_binding_id},
      {"replay_run_id", runtime_context_replay_run_id(runtime_context)},
      {"limit_mode", runtime_context.limit_mode}
    ])
  end

  defp scope_runtime_context_filters(selected_ref, runtime_context) do
    cond do
      scope_required_target?(selected_ref) ->
        [
          {"scope_kind", runtime_context.scope_kind},
          {"scope_id", runtime_context_scope_ids(runtime_context)},
          {"spacecraft_id", runtime_context.spacecraft_id}
        ]

      same_concrete_scope_kind?(selected_ref, runtime_context) ->
        [
          {"selected_scope_id", runtime_context_scope_ids(runtime_context)},
          {"spacecraft_id", runtime_context.spacecraft_id}
        ]

      true ->
        [
          {"spacecraft_id", runtime_context.spacecraft_id}
        ]
    end
  end

  defp same_concrete_scope_kind?(selected_ref, runtime_context) do
    selected_kind = value(selected_ref, "scope_kind")
    runtime_kind = context_text(runtime_context.scope_kind)

    selected_kind not in [nil, ""] and selected_kind == runtime_kind
  end

  defp selected_data_view_context(selected_ref, runtime_context) do
    if value(selected_ref, "series_role") == "compare" and
         context_text(runtime_context.compare_data_view) not in [nil, ""] do
      runtime_context.compare_data_view
    else
      runtime_context.data_view || get_in(runtime_context.data_context || %{}, ["view"])
    end
  end

  defp runtime_context_replay_run_id(runtime_context) do
    runtime_context.replay_run_id ||
      get_in(runtime_context.data_context || %{}, ["replay_run_id"]) ||
      get_in(runtime_context.time_context || %{}, ["replay_run_id"])
  end

  defp selected_ref_matches_context_value?(selected_ref, key, current_value) do
    selected_value = selected_filter_value(selected_ref, key)
    current_values = context_values(current_value)
    selected_values = selected_ref_context_values(selected_ref, key, selected_value)

    cond do
      selected_value in [nil, ""] -> true
      current_values == [] -> true
      true -> Enum.any?(selected_values, &(&1 in current_values))
    end
  end

  defp selected_filter_value(selected_ref, "selected_scope_id"),
    do: value(selected_ref, "scope_id")

  defp selected_filter_value(selected_ref, key), do: value(selected_ref, key)

  defp selected_ref_context_values(selected_ref, "scope_id", selected_value) do
    [selected_value | context_values(value(selected_ref, "scope_ids"))]
    |> context_values()
  end

  defp selected_ref_context_values(_selected_ref, "selected_scope_id", selected_value),
    do: context_values(selected_value)

  defp selected_ref_context_values(_selected_ref, _key, selected_value),
    do: context_values(selected_value)

  defp runtime_context_scope_ids(runtime_context) do
    runtime_context
    |> Map.get(:scope_ids, [])
    |> context_values()
    |> case do
      [] -> runtime_context.scope_id
      ids -> ids
    end
  end

  defp context_list(value), do: context_values(value)

  defp context_values(value) when is_list(value) do
    value
    |> Enum.flat_map(&context_values/1)
    |> Enum.uniq()
  end

  defp context_values(value) when is_binary(value) do
    value
    |> String.split(",", trim: true)
    |> Enum.map(&String.trim/1)
    |> Enum.reject(&(&1 == ""))
  end

  defp context_values(value) do
    case context_text(value) do
      nil -> []
      "" -> []
      value -> [value]
    end
  end

  defp within_time_context?(nil, _time_context), do: false

  defp within_time_context?(selected_ref, time_context) do
    case integer_value(selected_ref, "timestamp_ms") do
      nil -> not timestamp_required_target?(selected_ref)
      _timestamp_ms -> timestamp_within_time_context?(selected_ref, time_context)
    end
  end

  defp timestamp_within_time_context?(_selected_ref, %{"mode" => "live"}) do
    true
  end

  defp timestamp_within_time_context?(selected_ref, %{"mode" => "archive"} = time_context) do
    selected_time_within_time_context?(selected_ref, time_context)
  end

  defp timestamp_within_time_context?(selected_ref, %{"mode" => "replay_run"} = time_context) do
    selected_time_within_time_context?(selected_ref, time_context)
  end

  defp timestamp_within_time_context?(_selected_ref, _time_context), do: false

  defp timestamp_required_target?(selected_ref) do
    value(selected_ref, "target") in @timestamp_required_targets
  end

  defp scope_required_target?(selected_ref) do
    value(selected_ref, "target") in @scope_required_targets
  end

  defp selected_time_within_time_context?(selected_ref, time_context) do
    with timestamp_ms when is_integer(timestamp_ms) <- integer_value(selected_ref, "timestamp_ms"),
         {:ok, selected_time} <- DateTime.from_unix(timestamp_ms, :millisecond) do
      selected_time_within_bounds?(
        selected_time,
        Map.get(time_context, "from"),
        Map.get(time_context, "to")
      )
    else
      _invalid -> false
    end
  end

  defp selected_time_within_bounds?(selected_time, from_time, to_time) do
    after_from? = is_nil(from_time) or DateTime.compare(selected_time, from_time) != :lt
    before_to? = is_nil(to_time) or DateTime.compare(selected_time, to_time) != :gt

    after_from? and before_to?
  end

  defp integer_value(selected_ref, key) do
    case value(selected_ref, key) do
      value when is_integer(value) ->
        value

      value when is_binary(value) ->
        case Integer.parse(value) do
          {integer, ""} -> integer
          _invalid -> nil
        end

      _other ->
        nil
    end
  end

  defp context_text(nil), do: nil
  defp context_text(value) when is_atom(value), do: Atom.to_string(value)
  defp context_text(value) when is_binary(value), do: value
  defp context_text(_value), do: nil
end
