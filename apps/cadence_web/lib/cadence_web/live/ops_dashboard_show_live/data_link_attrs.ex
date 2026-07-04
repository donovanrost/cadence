defmodule CadenceWeb.OpsDashboardShowLive.DataLinkAttrs do
  @moduledoc false

  alias Cadence.Dashboards.ScopeContext

  @event_attr_names %{
    "link-id" => "phx-value-link-id",
    "target" => "phx-value-target",
    "target-id" => "phx-value-target-id",
    "placement-id" => "phx-value-placement-id",
    "timestamp-ms" => "phx-value-timestamp-ms",
    "data-view" => "phx-value-data-view",
    "series-role" => "phx-value-series-role",
    "compare-of" => "phx-value-compare-of",
    "comparison-state" => "phx-value-comparison-state",
    "comparison-delta" => "phx-value-comparison-delta",
    "primary-sample-id" => "phx-value-primary-sample-id",
    "compare-sample-id" => "phx-value-compare-sample-id",
    "primary-data-view" => "phx-value-primary-data-view",
    "compare-data-view" => "phx-value-compare-data-view",
    "primary-data-management" => "phx-value-primary-data-management",
    "compare-data-management" => "phx-value-compare-data-management",
    "primary-count" => "phx-value-primary-count",
    "compare-count" => "phx-value-compare-count",
    "widget-id" => "phx-value-widget-id",
    "widget-title" => "phx-value-widget-title",
    "widget-type" => "phx-value-widget-type",
    "widget-source" => "phx-value-widget-source",
    "primary-kind" => "phx-value-primary-kind",
    "compare-kind" => "phx-value-compare-kind",
    "primary-observables" => "phx-value-primary-observables",
    "compare-observables" => "phx-value-compare-observables",
    "scope-kind" => "phx-value-scope-kind",
    "scope-id" => "phx-value-scope-id",
    "scope-ids" => "phx-value-scope-ids",
    "resource-id" => "phx-value-resource-id",
    "spacecraft-id" => "phx-value-spacecraft-id",
    "contact-id" => "phx-value-contact-id",
    "transport-id" => "phx-value-transport-id",
    "source-endpoint-id" => "phx-value-source-endpoint-id",
    "ground-station-id" => "phx-value-ground-station-id",
    "scope-link-id" => "phx-value-scope-link-id",
    "realm" => "phx-value-realm",
    "data-source-id" => "phx-value-data-source-id",
    "source-binding-id" => "phx-value-source-binding-id",
    "time-mode" => "phx-value-time-mode",
    "time-axis" => "phx-value-time-axis",
    "replay-run-id" => "phx-value-replay-run-id",
    "nav-from-link-id" => "phx-value-nav-from-link-id",
    "nav-from-target" => "phx-value-nav-from-target",
    "nav-from-target-id" => "phx-value-nav-from-target-id",
    "nav-from-label" => "phx-value-nav-from-label",
    "nav-from-relationship-kind" => "phx-value-nav-from-relationship-kind",
    "nav-from-relationship-label" => "phx-value-nav-from-relationship-label",
    "nav-trail" => "phx-value-nav-trail"
  }

  @event_keys %{
    link_id: "link-id",
    target: "target",
    target_id: "target-id",
    placement_id: "placement-id",
    timestamp_ms: "timestamp-ms",
    data_view: "data-view",
    series_role: "series-role",
    compare_of: "compare-of",
    comparison_state: "comparison-state",
    comparison_delta: "comparison-delta",
    primary_sample_id: "primary-sample-id",
    compare_sample_id: "compare-sample-id",
    primary_data_view: "primary-data-view",
    compare_data_view: "compare-data-view",
    primary_data_management: "primary-data-management",
    compare_data_management: "compare-data-management",
    primary_count: "primary-count",
    compare_count: "compare-count",
    widget_id: "widget-id",
    widget_title: "widget-title",
    widget_type: "widget-type",
    widget_source: "widget-source",
    primary_kind: "primary-kind",
    compare_kind: "compare-kind",
    primary_observables: "primary-observables",
    compare_observables: "compare-observables",
    scope_kind: "scope-kind",
    scope_id: "scope-id",
    scope_ids: "scope-ids",
    resource_id: "resource-id",
    spacecraft_id: "spacecraft-id",
    contact_id: "contact-id",
    transport_id: "transport-id",
    source_endpoint_id: "source-endpoint-id",
    ground_station_id: "ground-station-id",
    scope_link_id: "scope-link-id",
    realm: "realm",
    data_source_id: "data-source-id",
    source_binding_id: "source-binding-id",
    time_mode: "time-mode",
    time_axis: "time-axis",
    replay_run_id: "replay-run-id",
    nav_from_link_id: "nav-from-link-id",
    nav_from_target: "nav-from-target",
    nav_from_target_id: "nav-from-target-id",
    nav_from_label: "nav-from-label",
    nav_from_relationship_kind: "nav-from-relationship-kind",
    nav_from_relationship_label: "nav-from-relationship-label",
    nav_trail: "nav-trail"
  }

  @spec open(term(), map() | keyword()) :: map()
  def open(source, attrs \\ %{}) do
    attrs = attrs_map(attrs)
    context_fallback = map_value(attrs, :context_fallback, %{})

    %{}
    |> Map.merge(context_params(context_fallback))
    |> Map.merge(source_params(source))
    |> Map.merge(
      attrs
      |> Map.delete(:context_fallback)
      |> Map.delete("context_fallback")
      |> event_params()
    )
    |> phx_value_attrs()
  end

  defp source_params(source) do
    source
    |> identity_params()
    |> Map.merge(context_params(source))
    |> Map.merge(selection_params(source))
  end

  defp identity_params(source) when is_map(source) do
    %{
      "link-id" => first_value(source, [:link_id]),
      "target" => first_value(source, [:target, :target_text]),
      "target-id" => first_value(source, [:target_id])
    }
    |> compact_flat()
  end

  defp identity_params(_source), do: %{}

  defp context_params(source) when is_map(source) do
    context = map_value(source, :context, %{})
    data = map_value(context, :data, %{})
    time = map_value(context, :time, %{})
    scope = map_value(context, :scope, %{})

    %{
      "realm" => first_nested_value(source, data, [:realm]),
      "data-view" => first_nested_value(source, data, [:data_view, :view]),
      "data-source-id" => first_nested_value(source, data, [:data_source_id]),
      "source-binding-id" => first_nested_value(source, data, [:source_binding_id, :binding_id]),
      "time-mode" => first_nested_value(source, time, [:time_mode, :mode]),
      "time-axis" => first_nested_value(source, time, [:time_axis, :axis]),
      "replay-run-id" =>
        first_nested_value(source, data, [:replay_run_id]) || map_value(time, :replay_run_id),
      "scope-kind" => first_nested_value(source, scope, [:scope_kind]) || scope_kind_value(scope),
      "scope-id" => first_nested_value(source, scope, [:scope_id]) || scope_id_value(scope),
      "scope-ids" => scope_ids_value(first_nested_value(source, scope, [:scope_ids]) || scope)
    }
    |> compact_flat()
  end

  defp context_params(_source), do: %{}

  defp selection_params(source) when is_map(source) do
    %{
      "placement-id" => first_value(source, [:placement_id]),
      "timestamp-ms" => first_value(source, [:timestamp_ms])
    }
    |> compact_flat()
  end

  defp selection_params(_source), do: %{}

  defp event_params(attrs) when is_map(attrs) do
    attrs
    |> Enum.flat_map(fn {key, value} ->
      event_key = event_key(key)
      if event_key, do: [{event_key, event_value(value)}], else: []
    end)
    |> Map.new()
    |> compact_flat()
  end

  defp phx_value_attrs(params) when is_map(params) do
    params
    |> Enum.flat_map(fn {key, value} ->
      case Map.get(@event_attr_names, key) do
        nil -> []
        attr_name -> [{attr_name, event_value(value)}]
      end
    end)
    |> Map.new()
    |> compact_flat()
  end

  defp first_nested_value(source, nested, keys) do
    first_value(source, keys) || first_value(nested, keys)
  end

  defp first_value(source, keys) do
    Enum.find_value(keys, &map_value(source, &1))
  end

  defp map_value(map, key, default \\ nil)

  defp map_value(map, key, default) when is_map(map) and is_atom(key) do
    Map.get(map, key, Map.get(map, Atom.to_string(key), default))
  end

  defp map_value(map, key, default) when is_map(map), do: Map.get(map, key, default)
  defp map_value(_map, _key, default), do: default

  defp event_key(key) when is_atom(key), do: Map.get(@event_keys, key)
  defp event_key(key) when is_binary(key), do: Map.get(@event_attr_names, key) && key
  defp event_key(_key), do: nil

  defp scope_kind_value(scope) when is_map(scope), do: ScopeContext.primary_kind(scope)
  defp scope_kind_value(_scope), do: nil

  defp scope_id_value(scope) when is_map(scope) do
    scope
    |> ScopeContext.primary_ids()
    |> List.first()
  end

  defp scope_id_value(_scope), do: nil

  defp scope_ids_value(value) when is_list(value), do: Enum.join(value, ",")

  defp scope_ids_value(value) when is_map(value),
    do: value |> ScopeContext.primary_ids() |> Enum.join(",")

  defp scope_ids_value(value), do: value

  defp attrs_map(attrs) when is_list(attrs), do: Map.new(attrs)
  defp attrs_map(attrs) when is_map(attrs), do: attrs
  defp attrs_map(_attrs), do: %{}

  defp compact_flat(map) when is_map(map) do
    map
    |> Enum.reject(fn {_key, value} -> value in [nil, ""] end)
    |> Map.new()
  end

  defp event_value(nil), do: nil
  defp event_value(value) when is_atom(value), do: Atom.to_string(value)
  defp event_value(value), do: to_string(value)
end
