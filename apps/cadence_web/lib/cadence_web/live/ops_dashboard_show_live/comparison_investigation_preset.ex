defmodule CadenceWeb.OpsDashboardShowLive.ComparisonInvestigationPreset do
  @moduledoc false

  alias CadenceWeb.OpsDashboardShowLive.RuntimeQuery
  alias CadenceWeb.OpsDashboardShowLive.RuntimeQueryParams

  @schema "dashboard_comparison_investigation_preset.v1"
  @open_findings_schema "dashboard_comparison_open_findings.v1"
  @workflow_intent_schema "dashboard_comparison_workflow_intent.v1"

  @spec build(map(), binary(), map()) :: map() | nil
  def build(assigns, current_path, %{visible?: true} = rollup) when is_map(assigns) do
    compare_data_view = present_text(Map.get(assigns, :dashboard_compare_data_view))

    if compare_data_view do
      %{
        "schema" => @schema,
        "dashboard_id" => dashboard_id(Map.get(assigns, :dashboard_document)),
        "mission_id" => mission_id(Map.get(assigns, :current_mission)),
        "current_path" => current_path,
        "runtime_query" =>
          assigns |> RuntimeQuery.current_query() |> RuntimeQueryParams.compact(),
        "comparison" => comparison(assigns, rollup, compare_data_view),
        "groups" => groups(Map.get(rollup, :groups, [])),
        "workflow_groups" => groups(Map.get(rollup, :workflow_groups, []))
      }
      |> compact()
      |> json_safe()
    end
  end

  def build(_assigns, _current_path, _rollup), do: nil

  @spec encode(map() | nil) :: binary() | nil
  def encode(nil), do: nil
  def encode(preset) when is_map(preset), do: Jason.encode!(preset)

  @spec open_findings_export(map() | nil) :: map() | nil
  def open_findings_export(%{} = preset) do
    open_group = workflow_group(preset, "open")
    current_path = map_value(preset, :current_path)
    findings = open_group |> map_value(:items, []) |> normalize_items(current_path)

    if findings != [] do
      %{
        "schema" => @open_findings_schema,
        "source_schema" => map_value(preset, :schema),
        "dashboard_id" => map_value(preset, :dashboard_id),
        "mission_id" => map_value(preset, :mission_id),
        "current_path" => map_value(preset, :current_path),
        "runtime_query" => map_value(preset, :runtime_query),
        "workflow_intent" => workflow_intent(preset, open_group, findings),
        "comparison" => open_findings_comparison(preset, open_group, findings),
        "findings" => findings
      }
      |> compact()
      |> json_safe()
    end
  end

  def open_findings_export(_preset), do: nil

  @spec encode_open_findings(map() | nil) :: binary() | nil
  def encode_open_findings(preset) do
    preset
    |> open_findings_export()
    |> encode()
  end

  @spec path(map() | nil) :: binary() | nil
  def path(%{"current_path" => current_path}) when is_binary(current_path), do: current_path
  def path(_preset), do: nil

  defp comparison(assigns, rollup, compare_data_view) do
    %{
      "primary_data_view" => Map.get(assigns, :dashboard_data_view),
      "compare_data_view" => compare_data_view,
      "widget_count" => Map.get(rollup, :widget_count),
      "delta_count" => Map.get(rollup, :delta_count),
      "unchanged_count" => Map.get(rollup, :unchanged_count),
      "coverage_count" => Map.get(rollup, :coverage_count),
      "missing_count" => Map.get(rollup, :missing_count),
      "handled_count" => Map.get(rollup, :handled_count),
      "open_count" => Map.get(rollup, :open_count),
      "unhandled_count" => Map.get(rollup, :unhandled_count),
      "states" => Map.get(rollup, :states)
    }
  end

  defp groups(groups) when is_list(groups) do
    Enum.map(groups, fn group ->
      %{
        "key" => Map.get(group, :key),
        "label" => Map.get(group, :label),
        "count" => Map.get(group, :count),
        "placement_ids" => placement_ids(Map.get(group, :placement_ids)),
        "items" => group |> Map.get(:items, []) |> items()
      }
      |> compact()
    end)
  end

  defp groups(_groups), do: []

  defp workflow_group(preset, key) do
    preset
    |> map_value(:workflow_groups, [])
    |> Enum.find(%{}, &(map_value(&1, :key) == key))
  end

  defp open_findings_comparison(preset, open_group, findings) do
    preset
    |> map_value(:comparison, %{})
    |> Map.take([
      "primary_data_view",
      "compare_data_view",
      "widget_count",
      "delta_count",
      "missing_count",
      "handled_count",
      "open_count",
      "unhandled_count",
      "states"
    ])
    |> Map.merge(%{
      "open_count" => length(findings),
      "open_placement_ids" => placement_ids(map_value(open_group, :placement_ids))
    })
    |> compact()
  end

  defp workflow_intent(preset, open_group, findings) do
    comparison = map_value(preset, :comparison, %{})
    placement_ids = placement_ids(map_value(open_group, :placement_ids))

    %{
      "schema" => @workflow_intent_schema,
      "kind" => "bulk_correction_authority_review",
      "source" => "dashboard_comparison_rollup",
      "action" => "request_comparison_review",
      "selection_kind" => "open_comparison_findings",
      "selection_count" => length(findings),
      "placement_ids" => placement_ids,
      "primary_data_view" => map_value(comparison, :primary_data_view),
      "compare_data_view" => map_value(comparison, :compare_data_view)
    }
    |> compact()
  end

  defp items(items), do: items(items, nil)

  defp items(items, current_path) when is_list(items) do
    Enum.map(items, fn item ->
      %{
        "placement_id" => map_value(item, :placement_id),
        "widget_id" => map_value(item, :widget_id),
        "title" => map_value(item, :title),
        "state" => map_value(item, :state),
        "label" => map_value(item, :label),
        "widget_type" => map_value(item, :widget_type),
        "widget_source" => map_value(item, :widget_source),
        "primary_kind" => map_value(item, :primary_kind),
        "compare_kind" => map_value(item, :compare_kind),
        "primary_observable_ids" => string_list(map_value(item, :primary_observable_ids)),
        "compare_observable_ids" => string_list(map_value(item, :compare_observable_ids)),
        "primary_count" => map_value(item, :primary_count),
        "compare_count" => map_value(item, :compare_count),
        "delta" => map_value(item, :delta),
        "decision_status" => map_value(item, :decision_status),
        "decision_event_id" => map_value(item, :decision_event_id),
        "decision" => map_value(item, :decision),
        "decision_reason" => map_value(item, :decision_reason),
        "decision_authority" => map_value(item, :decision_authority),
        "observation_identity_id" => map_value(item, :observation_identity_id),
        "primary_sample_id" => map_value(item, :primary_sample_id),
        "compare_sample_id" => map_value(item, :compare_sample_id),
        "primary_observation_identity_id" => map_value(item, :primary_observation_identity_id),
        "compare_observation_identity_id" => map_value(item, :compare_observation_identity_id),
        "primary_observation_id" => map_value(item, :primary_observation_id),
        "compare_observation_id" => map_value(item, :compare_observation_id),
        "primary_revision" => map_value(item, :primary_revision),
        "compare_revision" => map_value(item, :compare_revision),
        "scope_kind" => map_value(item, :scope_kind),
        "scope_id" => map_value(item, :scope_id),
        "resource_id" => map_value(item, :resource_id),
        "spacecraft_id" => map_value(item, :spacecraft_id),
        "contact_id" => map_value(item, :contact_id),
        "transport_id" => map_value(item, :transport_id),
        "source_endpoint_id" => map_value(item, :source_endpoint_id),
        "ground_station_id" => map_value(item, :ground_station_id),
        "scope_link_id" => map_value(item, :scope_link_id),
        "primary_data_view" =>
          map_value(item, :primary_data_view) || map_value(item, :primary_view),
        "compare_data_view" =>
          map_value(item, :compare_data_view) || map_value(item, :compare_view),
        "primary_data_management" => map_value(item, :primary_data_management),
        "compare_data_management" => map_value(item, :compare_data_management),
        "selection_query" => selection_query(item),
        "selection_path" => selection_path(current_path, item),
        "primary_data_link" => link_ref(map_value(item, :primary_data_link)),
        "compare_data_link" => link_ref(map_value(item, :compare_data_link))
      }
      |> compact()
    end)
  end

  defp items(_items, _current_path), do: []

  defp normalize_items(items, current_path) when is_list(items), do: items(items, current_path)
  defp normalize_items(_items, _current_path), do: []

  defp selection_query(item) when is_map(item) do
    %{
      "panel" => "data_link",
      "selected_target" => "comparison_finding",
      "selected_id" => map_value(item, :placement_id),
      "selected_placement" => map_value(item, :placement_id),
      "selected_widget" => map_value(item, :widget_id),
      "selected_widget_title" => map_value(item, :title),
      "selected_widget_type" => map_value(item, :widget_type),
      "selected_widget_source" => map_value(item, :widget_source),
      "selected_primary_kind" => map_value(item, :primary_kind),
      "selected_compare_kind" => map_value(item, :compare_kind),
      "selected_primary_observables" =>
        item |> map_value(:primary_observable_ids) |> string_list_text(),
      "selected_compare_observables" =>
        item |> map_value(:compare_observable_ids) |> string_list_text(),
      "selected_comparison_state" => map_value(item, :state),
      "selected_comparison_delta" => map_value(item, :delta),
      "selected_primary_sample" => map_value(item, :primary_sample_id),
      "selected_compare_sample" => map_value(item, :compare_sample_id),
      "selected_observation_identity" => map_value(item, :observation_identity_id),
      "selected_primary_observation_identity" =>
        map_value(item, :primary_observation_identity_id),
      "selected_compare_observation_identity" =>
        map_value(item, :compare_observation_identity_id),
      "selected_primary_observation" => map_value(item, :primary_observation_id),
      "selected_compare_observation" => map_value(item, :compare_observation_id),
      "selected_primary_revision" => map_value(item, :primary_revision),
      "selected_compare_revision" => map_value(item, :compare_revision),
      "selected_primary_data_view" =>
        map_value(item, :primary_data_view) || map_value(item, :primary_view),
      "selected_compare_data_view" =>
        map_value(item, :compare_data_view) || map_value(item, :compare_view),
      "selected_primary_data_management" =>
        data_management_codes(map_value(item, :primary_data_management)),
      "selected_compare_data_management" =>
        data_management_codes(map_value(item, :compare_data_management)),
      "selected_primary_count" => map_value(item, :primary_count),
      "selected_compare_count" => map_value(item, :compare_count),
      "selected_scope_kind" => map_value(item, :scope_kind),
      "selected_scope_id" => map_value(item, :scope_id),
      "selected_resource_id" => map_value(item, :resource_id),
      "selected_spacecraft_id" => map_value(item, :spacecraft_id),
      "selected_contact_id" => map_value(item, :contact_id),
      "selected_transport_id" => map_value(item, :transport_id),
      "selected_source_endpoint_id" => map_value(item, :source_endpoint_id),
      "selected_ground_station_id" => map_value(item, :ground_station_id),
      "selected_scope_link_id" => map_value(item, :scope_link_id)
    }
    |> compact()
  end

  defp selection_path(current_path, item) when is_binary(current_path) and is_map(item) do
    query = selection_query(item)

    if query == %{} do
      nil
    else
      merge_query(current_path, query)
    end
  end

  defp selection_path(_current_path, _item), do: nil

  defp merge_query(path, query) do
    [path_without_fragment, fragment] = String.split(path, "#", parts: 2) |> pad_split()

    [base_path, existing_query] =
      String.split(path_without_fragment, "?", parts: 2) |> pad_split()

    merged_query =
      existing_query
      |> decode_query()
      |> Map.merge(query)
      |> compact()

    query_path =
      case merged_query do
        empty when empty == %{} -> base_path
        merged_query -> base_path <> "?" <> URI.encode_query(merged_query)
      end

    if fragment, do: query_path <> "#" <> fragment, else: query_path
  end

  defp pad_split([first]), do: [first, nil]
  defp pad_split([first, second]), do: [first, second]

  defp decode_query(nil), do: %{}
  defp decode_query(""), do: %{}
  defp decode_query(query), do: URI.decode_query(query)

  defp data_management_codes(value) when is_binary(value), do: present_text(value)

  defp data_management_codes(%{badges: badges}) when is_list(badges) do
    badges
    |> Enum.map(&data_management_badge_value/1)
    |> Enum.reject(&is_nil/1)
    |> Enum.uniq()
    |> Enum.join(",")
    |> present_text()
  end

  defp data_management_codes(%{"badges" => badges}) when is_list(badges) do
    data_management_codes(%{badges: badges})
  end

  defp data_management_codes(_value), do: nil

  defp data_management_badge_value(%{value: value}), do: present_text(value)
  defp data_management_badge_value(%{"value" => value}), do: present_text(value)
  defp data_management_badge_value(_badge), do: nil

  defp link_ref(link) when is_map(link) do
    %{
      "link_id" => map_value(link, :link_id),
      "target" => map_value(link, :target),
      "target_text" => map_value(link, :target_text),
      "target_id" => map_value(link, :target_id),
      "context" => map_value(link, :context, %{})
    }
    |> compact()
  end

  defp link_ref(_link), do: nil

  defp placement_ids(value) when is_binary(value) do
    value
    |> String.split(",", trim: true)
  end

  defp placement_ids(value) when is_list(value), do: value
  defp placement_ids(_value), do: []

  defp string_list(value) when is_list(value) do
    value
    |> Enum.map(&present_text/1)
    |> Enum.reject(&is_nil/1)
    |> Enum.uniq()
  end

  defp string_list(value) do
    case present_text(value) do
      nil -> []
      value -> [value]
    end
  end

  defp string_list_text(value) do
    value
    |> string_list()
    |> Enum.join(",")
    |> present_text()
  end

  defp dashboard_id(document) when is_map(document),
    do: Map.get(document, :dashboard_id, Map.get(document, "dashboard_id"))

  defp dashboard_id(_document), do: nil

  defp mission_id(mission) when is_map(mission),
    do: Map.get(mission, :mission_id, Map.get(mission, "mission_id"))

  defp mission_id(_mission), do: nil

  defp map_value(map, key, default \\ nil) when is_map(map),
    do: Map.get(map, key, Map.get(map, Atom.to_string(key), default))

  defp compact(map) when is_map(map) do
    map
    |> Enum.reject(fn {_key, value} -> value in [nil, "", []] end)
    |> Map.new()
  end

  defp json_safe(%DateTime{} = value), do: DateTime.to_iso8601(value)

  defp json_safe(value) when is_map(value) do
    value
    |> Enum.map(fn {key, value} -> {to_string(key), json_safe(value)} end)
    |> Map.new()
  end

  defp json_safe(value) when is_list(value), do: Enum.map(value, &json_safe/1)
  defp json_safe(value) when is_atom(value), do: Atom.to_string(value)
  defp json_safe(value), do: value

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
