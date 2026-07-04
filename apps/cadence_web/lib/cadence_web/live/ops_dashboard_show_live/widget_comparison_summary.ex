defmodule CadenceWeb.OpsDashboardShowLive.WidgetComparisonSummary do
  @moduledoc false

  @data_view_labels %{
    "canonical" => "Canonical",
    "as_recorded" => "As recorded",
    "all_revisions" => "All revisions",
    "recomputed" => "Recomputed"
  }

  @scope_detail_keys [
    :scope_kind,
    :scope_id,
    :resource_id,
    :spacecraft_id,
    :contact_id,
    :transport_id,
    :source_endpoint_id,
    :ground_station_id,
    :scope_link_id
  ]

  @comparison_detail_keys [
    :widget_type,
    :widget_source,
    :primary_kind,
    :compare_kind,
    :primary_observable_ids,
    :compare_observable_ids
  ]

  @spec summary(map()) :: map() | nil
  def summary(%{compare_data_view: compare_data_view} = props) do
    case present_text(compare_data_view) do
      nil ->
        nil

      compare_view ->
        precision = widget_precision(Map.get(props, :widget))
        primary_data = Map.get(props, :data)
        compare_data = Map.get(props, :compare_data)
        primary_backfill = Map.get(props, :backfill)
        compare_backfill = Map.get(props, :compare_backfill)

        primary_count = comparison_point_count(primary_data, primary_backfill)

        compare_count =
          comparison_point_count(compare_data, compare_backfill)

        primary_view = present_text(Map.get(props, :data_view)) || "canonical"

        data_details =
          comparison_data_details(primary_data, compare_data, primary_backfill, compare_backfill)

        source_details =
          comparison_source_details(
            props,
            primary_data,
            compare_data,
            primary_backfill,
            compare_backfill
          )

        props
        |> numeric_summary(primary_view, compare_view, precision, primary_count, compare_count)
        |> case do
          nil -> count_summary(primary_view, compare_view, primary_count, compare_count)
          summary -> summary
        end
        |> Map.merge(data_details)
        |> Map.merge(source_details)
    end
  end

  def summary(_props), do: nil

  @spec rollup([map()]) :: map()
  def rollup(widget_items) when is_list(widget_items) do
    summaries =
      widget_items
      |> summaries()

    %{
      visible?: summaries != [],
      widget_count: length(summaries),
      delta_count: count_state(summaries, ["increased", "decreased"]),
      unchanged_count: count_state(summaries, ["unchanged"]),
      coverage_count: count_state(summaries, ["available"]),
      missing_count: count_state(summaries, ["missing"]),
      states: state_summary(summaries),
      groups: groups(summaries)
    }
  end

  def rollup(_widget_items), do: rollup([])

  @spec root_attrs([map()] | map()) :: map()
  def root_attrs(%{} = rollup) do
    %{
      "data-dashboard-comparison-widgets" => rollup.widget_count,
      "data-dashboard-comparison-deltas" => rollup.delta_count,
      "data-dashboard-comparison-unchanged" => rollup.unchanged_count,
      "data-dashboard-comparison-coverage" => rollup.coverage_count,
      "data-dashboard-comparison-missing" => rollup.missing_count,
      "data-dashboard-comparison-handled" => Map.get(rollup, :handled_count, 0),
      "data-dashboard-comparison-open" =>
        Map.get(rollup, :open_count, Map.get(rollup, :unhandled_count, rollup.widget_count)),
      "data-dashboard-comparison-unhandled" =>
        Map.get(rollup, :unhandled_count, rollup.widget_count),
      "data-dashboard-comparison-states" => rollup.states,
      "data-dashboard-comparison-delta-placements" => placement_ids(rollup.groups, "deltas"),
      "data-dashboard-comparison-missing-placements" => placement_ids(rollup.groups, "missing"),
      "data-dashboard-comparison-coverage-placements" => placement_ids(rollup.groups, "coverage"),
      "data-dashboard-comparison-unchanged-placements" =>
        placement_ids(rollup.groups, "unchanged"),
      "data-dashboard-comparison-open-placements" =>
        placement_ids(Map.get(rollup, :workflow_groups, []), "open"),
      "data-dashboard-comparison-handled-placements" =>
        placement_ids(Map.get(rollup, :workflow_groups, []), "handled")
    }
  end

  def root_attrs(widget_items) when is_list(widget_items) do
    widget_items
    |> rollup()
    |> root_attrs()
  end

  def root_attrs(_widget_items), do: root_attrs([])

  defp summaries(widget_items) do
    widget_items
    |> Enum.map(&widget_item_summary/1)
    |> Enum.reject(&is_nil/1)
  end

  defp widget_item_summary(%{item: item, props: %{comparison_summary: summary}}) do
    enrich_summary(summary, item)
  end

  defp widget_item_summary(%{item: item, props: props}) when is_map(props) do
    props
    |> summary()
    |> enrich_summary(item)
  end

  defp widget_item_summary(%{props: %{comparison_summary: summary}}), do: summary
  defp widget_item_summary(%{props: props}) when is_map(props), do: summary(props)
  defp widget_item_summary(_item), do: nil

  defp enrich_summary(nil, _item), do: nil

  defp enrich_summary(summary, item) when is_map(summary) and is_map(item) do
    widget = Map.get(item, :widget, %{})

    summary
    |> Map.put(:placement_id, Map.get(item, :placement_id))
    |> Map.put(:widget_id, Map.get(widget, :widget_id))
    |> Map.put(:widget_title, Map.get(widget, :title) || Map.get(item, :placement_id))
  end

  defp numeric_summary(
         %{widget: %{type: type}},
         _primary_view,
         _compare_view,
         _precision,
         _primary_count,
         _compare_count
       )
       when type != :value_tile,
       do: nil

  defp numeric_summary(props, primary_view, compare_view, precision, primary_count, compare_count) do
    case value_tile_comparison(Map.get(props, :data), Map.get(props, :compare_data), precision) do
      nil ->
        nil

      comparison ->
        %{
          state: comparison.state,
          label: "#{data_view_label(compare_view)} #{comparison.delta_text}",
          title:
            "#{data_view_label(primary_view)} compared with #{data_view_label(compare_view)}: #{comparison.delta_text} from #{comparison.compare_text}",
          primary_view: primary_view,
          compare_view: compare_view,
          primary_count: primary_count,
          compare_count: compare_count,
          delta: comparison.delta_text
        }
    end
  end

  defp count_summary(primary_view, compare_view, primary_count, compare_count) do
    if compare_count > 0 do
      %{
        state: "available",
        label: "#{primary_count} vs #{compare_count} pts",
        title:
          "#{data_view_label(primary_view)} has #{primary_count} points; #{data_view_label(compare_view)} has #{compare_count} points.",
        primary_view: primary_view,
        compare_view: compare_view,
        primary_count: primary_count,
        compare_count: compare_count
      }
    else
      %{
        state: "missing",
        label: "No compare data",
        title: "#{data_view_label(compare_view)} returned no comparable widget data.",
        primary_view: primary_view,
        compare_view: compare_view,
        primary_count: primary_count,
        compare_count: compare_count
      }
    end
  end

  defp count_state(summaries, states) do
    Enum.count(summaries, &(Map.get(&1, :state) in states))
  end

  defp state_summary(summaries) do
    summaries
    |> Enum.map(&Map.get(&1, :state))
    |> Enum.reject(&is_nil/1)
    |> Enum.uniq()
    |> Enum.join(",")
  end

  defp groups(summaries) do
    [
      group("deltas", "Deltas", summaries, ["increased", "decreased"]),
      group("missing", "Missing compare data", summaries, ["missing"]),
      group("coverage", "Coverage", summaries, ["available"]),
      group("unchanged", "Unchanged", summaries, ["unchanged"])
    ]
    |> Enum.reject(&(&1.count == 0))
  end

  defp group(key, label, summaries, states) do
    items =
      summaries
      |> Enum.filter(&(Map.get(&1, :state) in states))
      |> Enum.map(&group_item/1)

    %{
      key: key,
      label: label,
      count: length(items),
      placement_ids:
        items |> Enum.map(& &1.placement_id) |> Enum.reject(&is_nil/1) |> Enum.join(","),
      items: items
    }
  end

  defp group_item(summary) do
    base_item = %{
      placement_id: Map.get(summary, :placement_id),
      widget_id: Map.get(summary, :widget_id),
      title: Map.get(summary, :widget_title) || Map.get(summary, :placement_id) || "Widget",
      state: Map.get(summary, :state),
      label: Map.get(summary, :label),
      detail: Map.get(summary, :title),
      primary_view: Map.get(summary, :primary_view),
      compare_view: Map.get(summary, :compare_view),
      primary_count: Map.get(summary, :primary_count),
      compare_count: Map.get(summary, :compare_count),
      delta: Map.get(summary, :delta),
      primary_sample_id: Map.get(summary, :primary_sample_id),
      compare_sample_id: Map.get(summary, :compare_sample_id),
      primary_data_management: Map.get(summary, :primary_data_management),
      compare_data_management: Map.get(summary, :compare_data_management),
      primary_data_link: Map.get(summary, :primary_data_link),
      compare_data_link: Map.get(summary, :compare_data_link)
    }

    base_item
    |> Map.merge(compact_scope_details(summary))
    |> Map.merge(compact_comparison_details(summary))
    |> Map.merge(compact_observation_identity_details(summary))
  end

  defp compact_scope_details(summary) do
    summary
    |> Map.take(@scope_detail_keys)
    |> Enum.reject(fn {_key, value} -> is_nil(value) end)
    |> Map.new()
  end

  defp compact_comparison_details(summary) do
    summary
    |> Map.take(@comparison_detail_keys)
    |> Enum.reject(fn {_key, value} -> is_nil(value) or value == [] end)
    |> Map.new()
  end

  defp compact_observation_identity_details(summary) do
    %{
      observation_identity_id:
        Map.get(summary, :primary_observation_identity_id) ||
          Map.get(summary, :compare_observation_identity_id),
      primary_observation_identity_id: Map.get(summary, :primary_observation_identity_id),
      compare_observation_identity_id: Map.get(summary, :compare_observation_identity_id),
      primary_observation_id: Map.get(summary, :primary_observation_id),
      compare_observation_id: Map.get(summary, :compare_observation_id),
      primary_revision: Map.get(summary, :primary_revision),
      compare_revision: Map.get(summary, :compare_revision)
    }
    |> Enum.reject(fn {_key, value} -> is_nil(value) end)
    |> Map.new()
  end

  defp placement_ids(groups, key) do
    groups
    |> Enum.find_value("", fn group ->
      if group.key == key, do: group.placement_ids
    end)
  end

  defp value_tile_comparison(primary_data, compare_data, precision) do
    with primary when is_number(primary) <- point_sample_number(primary_data),
         comparison when is_number(comparison) <- point_sample_number(compare_data) do
      delta = primary - comparison

      %{
        delta_text: format_signed_number(delta, precision),
        compare_text: format_number(comparison, precision),
        state: comparison_state(delta)
      }
    else
      _missing -> nil
    end
  end

  defp point_sample_number(%{sample: sample}) when is_map(sample) do
    sample
    |> display_value()
    |> case do
      value when is_number(value) -> value
      _value -> nil
    end
  end

  defp point_sample_number(_data), do: nil

  defp display_value(sample) do
    if is_nil(sample.engineering_value), do: sample.raw_value, else: sample.engineering_value
  end

  defp comparison_point_count(data, backfill) do
    case backfill_point_count(backfill) do
      0 -> sample_point_count(data)
      count -> count
    end
  end

  defp comparison_data_details(primary_data, compare_data, primary_backfill, compare_backfill) do
    %{
      primary_sample_id: sample_id(primary_data) || backfill_sample_id(primary_backfill),
      compare_sample_id: sample_id(compare_data) || backfill_sample_id(compare_backfill),
      primary_observation_identity_id: observation_identity_id(primary_data),
      compare_observation_identity_id: observation_identity_id(compare_data),
      primary_observation_id: observation_id(primary_data),
      compare_observation_id: observation_id(compare_data),
      primary_revision: sample_revision(primary_data),
      compare_revision: sample_revision(compare_data),
      primary_data_management: data_management_summary(primary_data, primary_backfill),
      compare_data_management: data_management_summary(compare_data, compare_backfill),
      primary_data_link: first_data_link(primary_data),
      compare_data_link: first_data_link(compare_data)
    }
    |> Map.merge(scope_details(primary_data, compare_data, primary_backfill, compare_backfill))
  end

  defp comparison_source_details(
         props,
         primary_data,
         compare_data,
         primary_backfill,
         compare_backfill
       ) do
    %{
      widget_type: widget_type(Map.get(props, :widget)),
      widget_source: widget_source(Map.get(props, :widget)),
      primary_kind: data_kind(primary_data) || data_kind(primary_backfill),
      compare_kind: data_kind(compare_data) || data_kind(compare_backfill),
      primary_observable_ids:
        observable_ids(primary_data)
        |> fallback_observable_ids(primary_backfill)
        |> fallback_observable_ids(Map.get(props, :widget)),
      compare_observable_ids:
        observable_ids(compare_data)
        |> fallback_observable_ids(compare_backfill)
        |> fallback_observable_ids(Map.get(props, :widget))
    }
    |> Enum.reject(fn {_key, value} -> is_nil(value) or value == [] end)
    |> Map.new()
  end

  defp scope_details(primary_data, compare_data, primary_backfill, compare_backfill) do
    [primary_data, primary_backfill, compare_data, compare_backfill]
    |> Enum.flat_map(&scope_candidates/1)
    |> Enum.reduce(%{}, &merge_scope_details/2)
    |> finalize_scope_details()
  end

  defp scope_candidates(%{series: series} = data) when is_list(series) do
    [data, first_data_link(data)] ++
      Enum.flat_map(series, fn series ->
        [series, first_point_metadata(series)]
      end)
  end

  defp scope_candidates(%{"series" => series} = data) when is_list(series) do
    [data, first_data_link(data)] ++
      Enum.flat_map(series, fn series ->
        [series, first_point_metadata(series)]
      end)
  end

  defp scope_candidates(data) when is_map(data) do
    data_link = first_data_link(data)
    context = map_value(data_link, :context, %{})

    [
      data,
      map_value(data, :sample),
      data_link,
      context,
      map_value(context, :scope),
      map_value(context, :operational),
      map_value(context, :data)
    ] ++
      row_scope_candidates(map_value(data, :rows, []))
  end

  defp scope_candidates(points) when is_list(points), do: [first_point_metadata(points)]
  defp scope_candidates(_data), do: []

  defp row_scope_candidates(rows) when is_list(rows), do: rows
  defp row_scope_candidates(_rows), do: []

  defp widget_type(widget) when is_map(widget), do: text_value(widget, :type)
  defp widget_type(_widget), do: nil

  defp widget_source(widget) when is_map(widget) do
    widget
    |> map_value(:binding, %{})
    |> text_value(:source)
  end

  defp widget_source(_widget), do: nil

  defp data_kind(data) when is_map(data), do: text_value(data, :kind)
  defp data_kind(data) when is_list(data), do: "series"
  defp data_kind(_data), do: nil

  defp fallback_observable_ids([], fallback), do: observable_ids(fallback)
  defp fallback_observable_ids(ids, _fallback), do: ids

  defp observable_ids(data) when is_map(data) do
    []
    |> add_observable_value(map_value(data, :observable_id))
    |> add_observable_values(map_value(data, :observable_ids, []))
    |> add_observable_values(row_observable_ids(map_value(data, :rows, [])))
    |> add_observable_values(series_observable_ids(map_value(data, :series, [])))
    |> add_observable_values(widget_observable_ids(map_value(data, :binding, %{})))
    |> Enum.uniq()
  end

  defp observable_ids(data) when is_list(data) do
    data
    |> Enum.flat_map(&observable_ids/1)
    |> Enum.uniq()
  end

  defp observable_ids(_data), do: []

  defp row_observable_ids(rows) when is_list(rows), do: Enum.flat_map(rows, &observable_ids/1)
  defp row_observable_ids(_rows), do: []

  defp series_observable_ids(series) when is_list(series),
    do: Enum.flat_map(series, &observable_ids/1)

  defp series_observable_ids(_series), do: []

  defp widget_observable_ids(binding) when is_map(binding) do
    []
    |> add_observable_value(map_value(binding, :point_id))
    |> add_observable_values(map_value(binding, :point_ids, []))
    |> add_observable_values(map_value(binding, :observables, []))
  end

  defp widget_observable_ids(_binding), do: []

  defp add_observable_value(ids, value) do
    case text_value(value) do
      nil -> ids
      value -> ids ++ [value]
    end
  end

  defp add_observable_values(ids, values) when is_list(values) do
    Enum.reduce(values, ids, &add_observable_value(&2, &1))
  end

  defp add_observable_values(ids, value), do: add_observable_value(ids, value)

  defp first_point_metadata(%{points: points}) when is_list(points),
    do: first_point_metadata(points)

  defp first_point_metadata(%{"points" => points}) when is_list(points),
    do: first_point_metadata(points)

  defp first_point_metadata(points) when is_list(points) do
    Enum.find_value(points, fn
      [_time, _value, metadata] when is_map(metadata) -> metadata
      _point -> nil
    end)
  end

  defp first_point_metadata(_points), do: nil

  defp merge_scope_details(candidate, acc) when is_map(candidate) do
    details = scope_detail_map(candidate)

    Enum.reduce(@scope_detail_keys, acc, fn key, acc ->
      case Map.get(acc, key) || Map.get(details, key) do
        nil -> acc
        value -> Map.put(acc, key, value)
      end
    end)
  end

  defp merge_scope_details(_candidate, acc), do: acc

  defp scope_detail_map(candidate) when is_map(candidate) do
    {primary_kind, primary_id} = primary_scope_identity(candidate)
    scope_kind = text_value(candidate, :scope_kind) || primary_kind

    %{
      scope_kind: scope_kind,
      scope_id: text_value(candidate, :scope_id) || primary_id,
      resource_id: text_value(candidate, :resource_id),
      spacecraft_id: text_value(candidate, :spacecraft_id),
      contact_id: text_value(candidate, :contact_id),
      transport_id: text_value(candidate, :transport_id),
      source_endpoint_id: text_value(candidate, :source_endpoint_id),
      ground_station_id: text_value(candidate, :ground_station_id),
      scope_link_id:
        text_value(candidate, :scope_link_id) || scoped_link_id(candidate, scope_kind)
    }
  end

  defp primary_scope_identity(candidate) when is_map(candidate) do
    primary = map_value(candidate, :primary, %{})
    primary_kind = text_value(primary, :kind)

    primary_id =
      text_value(primary, :id) ||
        case map_value(primary, :ids, []) do
          [id | _rest] -> text_value(%{id: id}, :id)
          _ids -> nil
        end

    {primary_kind, primary_id}
  end

  defp scoped_link_id(candidate, scope_kind) when scope_kind in ["link", :link],
    do: text_value(candidate, :link_id)

  defp scoped_link_id(_candidate, _scope_kind), do: nil

  defp finalize_scope_details(details) when map_size(details) == 0, do: %{}

  defp finalize_scope_details(details) do
    scope_id =
      Map.get(details, :scope_id) ||
        scoped_resource_id(details) ||
        Map.get(details, :resource_id)

    resource_id = Map.get(details, :resource_id) || scoped_resource_id(details)

    details
    |> Map.put(:scope_id, scope_id)
    |> Map.put(:resource_id, resource_id)
    |> Enum.reject(fn {_key, value} -> is_nil(value) end)
    |> Map.new()
  end

  defp scoped_resource_id(%{scope_kind: "spacecraft"} = details),
    do: Map.get(details, :spacecraft_id)

  defp scoped_resource_id(%{scope_kind: "contact"} = details), do: Map.get(details, :contact_id)

  defp scoped_resource_id(%{scope_kind: "transport"} = details),
    do: Map.get(details, :transport_id)

  defp scoped_resource_id(%{scope_kind: "source_endpoint"} = details),
    do: Map.get(details, :source_endpoint_id)

  defp scoped_resource_id(%{scope_kind: "ground_station"} = details),
    do: Map.get(details, :ground_station_id)

  defp scoped_resource_id(%{scope_kind: "link"} = details), do: Map.get(details, :scope_link_id)
  defp scoped_resource_id(_details), do: nil

  defp data_management_summary(data, fallback_data) do
    data_management(data) || data_management(fallback_data)
  end

  defp data_management(%{data_management: summary}) when is_map(summary), do: summary
  defp data_management(%{"data_management" => summary}) when is_map(summary), do: summary
  defp data_management(_data), do: nil

  defp sample_id(%{sample: sample}) when is_map(sample) do
    present_text(Map.get(sample, :sample_id, Map.get(sample, "sample_id")))
  end

  defp sample_id(_data), do: nil

  defp observation_identity_id(data), do: sample_storage_value(data, :observation_identity_id)
  defp observation_id(data), do: sample_storage_value(data, :observation_id)
  defp sample_revision(data), do: sample_storage_value(data, :revision)

  defp sample_storage_value(%{sample: sample}, key) when is_map(sample) do
    sample_value(sample, key) ||
      sample
      |> map_value(:provenance, %{})
      |> map_value(:storage, %{})
      |> sample_value(key)
  end

  defp sample_storage_value(_data, _key), do: nil

  defp sample_value(sample, :revision) when is_map(sample) do
    case map_value(sample, :revision) do
      value when is_integer(value) -> value
      value when is_binary(value) -> parse_integer(value)
      _value -> nil
    end
  end

  defp sample_value(sample, key) when is_map(sample), do: text_value(sample, key)

  defp parse_integer(value) when is_binary(value) do
    value = String.trim(value)

    case Integer.parse(value) do
      {integer, ""} -> integer
      _invalid -> nil
    end
  end

  defp backfill_sample_id(%{series: series}) when is_list(series),
    do: Enum.find_value(series, &series_sample_id/1)

  defp backfill_sample_id(%{"series" => series}) when is_list(series),
    do: Enum.find_value(series, &series_sample_id/1)

  defp backfill_sample_id(points) when is_list(points), do: points_sample_id(points)
  defp backfill_sample_id(_backfill), do: nil

  defp series_sample_id(%{points: points}) when is_list(points), do: points_sample_id(points)
  defp series_sample_id(%{"points" => points}) when is_list(points), do: points_sample_id(points)
  defp series_sample_id(_series), do: nil

  defp points_sample_id(points) do
    Enum.find_value(points, fn
      [_time, _value, metadata] when is_map(metadata) ->
        present_text(Map.get(metadata, :sample_id, Map.get(metadata, "sample_id")))

      _point ->
        nil
    end)
  end

  defp first_data_link(%{links: links}) when is_list(links), do: preferred_data_link(links)
  defp first_data_link(%{"links" => links}) when is_list(links), do: preferred_data_link(links)
  defp first_data_link(_data), do: nil

  defp preferred_data_link([]), do: nil

  defp preferred_data_link(links) do
    Enum.find(links, &(link_value(&1, :target) in [:telemetry_sample, "telemetry_sample"])) ||
      List.first(links)
  end

  defp link_value(link, key) when is_map(link),
    do: Map.get(link, key, Map.get(link, Atom.to_string(key)))

  defp link_value(_link, _key), do: nil

  defp map_value(map, key, default \\ nil)

  defp map_value(map, key, default) when is_map(map) and is_atom(key) do
    Map.get(map, key, Map.get(map, Atom.to_string(key), default))
  end

  defp map_value(map, key, default) when is_map(map), do: Map.get(map, key, default)
  defp map_value(_map, _key, default), do: default

  defp text_value(map, key) when is_map(map) do
    map
    |> map_value(key)
    |> text_value()
  end

  defp text_value(nil), do: nil
  defp text_value(value) when is_atom(value), do: Atom.to_string(value)
  defp text_value(value) when is_binary(value), do: present_text(value)
  defp text_value(value) when is_integer(value), do: Integer.to_string(value)
  defp text_value(_value), do: nil

  defp backfill_point_count(%{series: series}) when is_list(series),
    do: Enum.reduce(series, 0, &(&2 + series_point_count(&1)))

  defp backfill_point_count(%{"series" => series}) when is_list(series),
    do: Enum.reduce(series, 0, &(&2 + series_point_count(&1)))

  defp backfill_point_count(points) when is_list(points), do: length(points)
  defp backfill_point_count(_backfill), do: 0

  defp series_point_count(%{points: points}) when is_list(points), do: length(points)
  defp series_point_count(%{"points" => points}) when is_list(points), do: length(points)
  defp series_point_count(_series), do: 0

  defp sample_point_count(%{sample: sample}) when is_map(sample), do: 1
  defp sample_point_count(%{rows: rows}) when is_list(rows), do: length(rows)
  defp sample_point_count(%{"rows" => rows}) when is_list(rows), do: length(rows)
  defp sample_point_count(_data), do: 0

  defp widget_precision(%{options: options}) when is_map(options),
    do: Map.get(options, :precision, 2)

  defp widget_precision(_widget), do: 2

  defp data_view_label(value), do: Map.get(@data_view_labels, value, value || "Canonical")

  defp format_signed_number(value, precision) when is_number(value) do
    sign = if value > 0, do: "+", else: ""
    sign <> format_number(value, precision)
  end

  defp format_number(value, precision) when is_float(value),
    do: :erlang.float_to_binary(value, decimals: precision)

  defp format_number(value, _precision) when is_integer(value), do: Integer.to_string(value)

  defp comparison_state(value) when value > 0, do: "increased"
  defp comparison_state(value) when value < 0, do: "decreased"
  defp comparison_state(_value), do: "unchanged"

  defp present_text(value) when is_binary(value) do
    value
    |> String.trim()
    |> case do
      "" -> nil
      value -> value
    end
  end

  defp present_text(_value), do: nil
end
