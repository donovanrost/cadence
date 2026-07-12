defmodule CadenceWeb.OpsDashboardShowLive.SelectionQuery do
  @moduledoc false

  alias Cadence.Dashboards.DataLink
  alias CadenceWeb.OpsDashboardShowLive.SelectedDataRef

  defstruct params: %{}

  @type params :: %{optional(binary()) => binary() | integer()}
  @type t :: %__MODULE__{params: params()}

  @selection_keys [
    "selected_link",
    "selected_target",
    "selected_id",
    "selected_placement",
    "selected_time",
    "selected_data_view",
    "selected_series_role",
    "selected_compare_of",
    "selected_comparison_state",
    "selected_comparison_delta",
    "selected_primary_sample",
    "selected_compare_sample",
    "selected_primary_data_view",
    "selected_compare_data_view",
    "selected_primary_data_management",
    "selected_compare_data_management",
    "selected_primary_count",
    "selected_compare_count",
    "selected_widget",
    "selected_widget_title",
    "selected_widget_type",
    "selected_widget_source",
    "selected_primary_kind",
    "selected_compare_kind",
    "selected_primary_observables",
    "selected_compare_observables",
    "selected_scope_kind",
    "selected_scope_id",
    "selected_scope_ids",
    "selected_resource_id",
    "selected_spacecraft_id",
    "selected_contact_id",
    "selected_contact_ids",
    "selected_transport_id",
    "selected_source_endpoint_id",
    "selected_ground_station_id",
    "selected_scope_link_id",
    "realm",
    "data_source_id",
    "source_binding_id",
    "time_mode",
    "time_axis",
    "replay_run_id",
    "limit_mode",
    "nav_from_link_id",
    "nav_from_target",
    "nav_from_target_id",
    "nav_from_label",
    "nav_from_relationship_kind",
    "nav_from_relationship_label",
    "nav_trail"
  ]

  @spec from_params(map(), atom() | nil) :: t() | nil
  def from_params(params, :evidence) when is_map(params), do: nil

  def from_params(params, panel_query)
      when is_map(params) and panel_query not in [nil, :data_link],
      do: nil

  def from_params(params, _panel_query) when is_map(params) do
    %{
      "selected_link" => text_param(params["selected_link"]),
      "selected_target" => text_param(params["selected_target"]),
      "selected_id" => text_param(params["selected_id"]),
      "selected_placement" => text_param(params["selected_placement"]),
      "selected_time" => integer_param(params, "selected_time"),
      "selected_data_view" => text_param(params["selected_data_view"]),
      "selected_series_role" => text_param(params["selected_series_role"]),
      "selected_compare_of" => text_param(params["selected_compare_of"]),
      "selected_comparison_state" => text_param(params["selected_comparison_state"]),
      "selected_comparison_delta" => text_param(params["selected_comparison_delta"]),
      "selected_primary_sample" => text_param(params["selected_primary_sample"]),
      "selected_compare_sample" => text_param(params["selected_compare_sample"]),
      "selected_primary_data_view" => text_param(params["selected_primary_data_view"]),
      "selected_compare_data_view" => text_param(params["selected_compare_data_view"]),
      "selected_primary_data_management" =>
        text_param(params["selected_primary_data_management"]),
      "selected_compare_data_management" =>
        text_param(params["selected_compare_data_management"]),
      "selected_primary_count" => integer_param(params, "selected_primary_count"),
      "selected_compare_count" => integer_param(params, "selected_compare_count"),
      "selected_widget" => text_param(params["selected_widget"]),
      "selected_widget_title" => text_param(params["selected_widget_title"]),
      "selected_widget_type" => text_param(params["selected_widget_type"]),
      "selected_widget_source" => text_param(params["selected_widget_source"]),
      "selected_primary_kind" => text_param(params["selected_primary_kind"]),
      "selected_compare_kind" => text_param(params["selected_compare_kind"]),
      "selected_primary_observables" => text_param(params["selected_primary_observables"]),
      "selected_compare_observables" => text_param(params["selected_compare_observables"]),
      "selected_scope_kind" => text_param(params["selected_scope_kind"]),
      "selected_scope_id" => text_param(params["selected_scope_id"]),
      "selected_scope_ids" => text_param(params["selected_scope_ids"]),
      "selected_resource_id" => text_param(params["selected_resource_id"]),
      "selected_spacecraft_id" => text_param(params["selected_spacecraft_id"]),
      "selected_contact_id" => text_param(params["selected_contact_id"]),
      "selected_contact_ids" => text_param(params["selected_contact_ids"]),
      "selected_transport_id" => text_param(params["selected_transport_id"]),
      "selected_source_endpoint_id" => text_param(params["selected_source_endpoint_id"]),
      "selected_ground_station_id" => text_param(params["selected_ground_station_id"]),
      "selected_scope_link_id" => text_param(params["selected_scope_link_id"]),
      "realm" => text_param(params["realm"]),
      "data_source_id" => text_param(params["data_source_id"]),
      "source_binding_id" => text_param(params["source_binding_id"]),
      "time_mode" => text_param(params["time_mode"]),
      "time_axis" => text_param(params["time_axis"]),
      "replay_run_id" => text_param(params["replay_run_id"]),
      "limit_mode" => text_param(params["limit_mode"]),
      "nav_from_link_id" => text_param(params["nav_from_link_id"]),
      "nav_from_target" => text_param(params["nav_from_target"]),
      "nav_from_target_id" => text_param(params["nav_from_target_id"]),
      "nav_from_label" => text_param(params["nav_from_label"]),
      "nav_from_relationship_kind" => text_param(params["nav_from_relationship_kind"]),
      "nav_from_relationship_label" => text_param(params["nav_from_relationship_label"]),
      "nav_trail" => text_param(params["nav_trail"])
    }
    |> compact_flat()
    |> case do
      query when map_size(query) == 0 ->
        nil

      %{"selected_target" => target_value} = query when not is_nil(target_value) ->
        if is_map_key(query, "selected_link") or target(target_value), do: new(query)

      query
      when not is_map_key(query, "selected_target") and not is_map_key(query, "selected_link") ->
        nil

      query ->
        new(query)
    end
  end

  def from_params(_params, _panel_query), do: nil

  @spec from_ref(map() | nil) :: t() | nil
  def from_ref(nil), do: nil

  def from_ref(selected_ref) when is_map(selected_ref) do
    selected_ref
    |> selected_ref_params()
    |> new()
  end

  def from_ref(_selected_ref), do: nil

  @spec new(params() | t() | nil) :: t()
  def new(%__MODULE__{} = query), do: query
  def new(params) when is_map(params), do: %__MODULE__{params: compact_flat(params)}
  def new(_params), do: %__MODULE__{}

  @spec to_params(t() | params() | nil) :: params()
  def to_params(%__MODULE__{params: params}), do: params

  def to_params(params) when is_map(params) do
    params
    |> Map.take(@selection_keys)
    |> compact_flat()
  end

  def to_params(_query), do: %{}

  @spec to_event_params(t() | params() | nil) :: map()
  def to_event_params(query) do
    query = to_params(query)

    %{
      "timestamp-ms" => Map.get(query, "selected_time"),
      "placement-id" => Map.get(query, "selected_placement"),
      "data-view" => Map.get(query, "selected_data_view"),
      "series-role" => Map.get(query, "selected_series_role"),
      "compare-of" => Map.get(query, "selected_compare_of"),
      "comparison-state" => Map.get(query, "selected_comparison_state"),
      "comparison-delta" => Map.get(query, "selected_comparison_delta"),
      "primary-sample-id" => Map.get(query, "selected_primary_sample"),
      "compare-sample-id" => Map.get(query, "selected_compare_sample"),
      "primary-data-view" => Map.get(query, "selected_primary_data_view"),
      "compare-data-view" => Map.get(query, "selected_compare_data_view"),
      "primary-data-management" => Map.get(query, "selected_primary_data_management"),
      "compare-data-management" => Map.get(query, "selected_compare_data_management"),
      "primary-count" => Map.get(query, "selected_primary_count"),
      "compare-count" => Map.get(query, "selected_compare_count"),
      "widget-id" => Map.get(query, "selected_widget"),
      "widget-title" => Map.get(query, "selected_widget_title"),
      "widget-type" => Map.get(query, "selected_widget_type"),
      "widget-source" => Map.get(query, "selected_widget_source"),
      "primary-kind" => Map.get(query, "selected_primary_kind"),
      "compare-kind" => Map.get(query, "selected_compare_kind"),
      "primary-observables" => Map.get(query, "selected_primary_observables"),
      "compare-observables" => Map.get(query, "selected_compare_observables"),
      "scope-kind" => Map.get(query, "selected_scope_kind"),
      "scope-id" => Map.get(query, "selected_scope_id"),
      "scope-ids" => Map.get(query, "selected_scope_ids"),
      "resource-id" => Map.get(query, "selected_resource_id"),
      "spacecraft-id" => Map.get(query, "selected_spacecraft_id"),
      "contact-id" => Map.get(query, "selected_contact_id"),
      "contact-ids" => Map.get(query, "selected_contact_ids"),
      "transport-id" => Map.get(query, "selected_transport_id"),
      "source-endpoint-id" => Map.get(query, "selected_source_endpoint_id"),
      "ground-station-id" => Map.get(query, "selected_ground_station_id"),
      "scope-link-id" => Map.get(query, "selected_scope_link_id"),
      "realm" => Map.get(query, "realm"),
      "data-source-id" => Map.get(query, "data_source_id"),
      "source-binding-id" => Map.get(query, "source_binding_id"),
      "time-mode" => Map.get(query, "time_mode"),
      "time-axis" => Map.get(query, "time_axis"),
      "replay-run-id" => Map.get(query, "replay_run_id"),
      "limit-mode" => Map.get(query, "limit_mode"),
      "nav-from-link-id" => Map.get(query, "nav_from_link_id"),
      "nav-from-target" => Map.get(query, "nav_from_target"),
      "nav-from-target-id" => Map.get(query, "nav_from_target_id"),
      "nav-from-label" => Map.get(query, "nav_from_label"),
      "nav-from-relationship-kind" => Map.get(query, "nav_from_relationship_kind"),
      "nav-from-relationship-label" => Map.get(query, "nav_from_relationship_label"),
      "nav-trail" => Map.get(query, "nav_trail")
    }
    |> compact_flat()
  end

  @spec value(t() | params() | nil, binary()) :: binary() | integer() | nil
  def value(query, key), do: query |> to_params() |> Map.get(key)

  @spec query?(t() | params() | nil) :: boolean()
  def query?(query) do
    query = to_params(query)

    present?(Map.get(query, "selected_target")) or
      present?(Map.get(query, "selected_link")) or
      present?(Map.get(query, "selected_id"))
  end

  @spec missing_selected_link_id(t() | params() | nil) :: binary() | nil
  def missing_selected_link_id(query) do
    case value(query, "selected_link") do
      link_id when is_binary(link_id) and link_id != "" -> link_id
      _other -> nil
    end
  end

  @spec clear_query() :: %{binary() => nil}
  def clear_query do
    %{
      "selected_link" => nil,
      "selected_target" => nil,
      "selected_id" => nil,
      "selected_placement" => nil,
      "selected_time" => nil,
      "selected_data_view" => nil,
      "selected_series_role" => nil,
      "selected_compare_of" => nil,
      "selected_comparison_state" => nil,
      "selected_comparison_delta" => nil,
      "selected_primary_sample" => nil,
      "selected_compare_sample" => nil,
      "selected_primary_data_view" => nil,
      "selected_compare_data_view" => nil,
      "selected_primary_data_management" => nil,
      "selected_compare_data_management" => nil,
      "selected_primary_count" => nil,
      "selected_compare_count" => nil,
      "selected_widget" => nil,
      "selected_widget_title" => nil,
      "selected_widget_type" => nil,
      "selected_widget_source" => nil,
      "selected_primary_kind" => nil,
      "selected_compare_kind" => nil,
      "selected_primary_observables" => nil,
      "selected_compare_observables" => nil,
      "selected_scope_kind" => nil,
      "selected_scope_id" => nil,
      "selected_scope_ids" => nil,
      "selected_resource_id" => nil,
      "selected_spacecraft_id" => nil,
      "selected_contact_id" => nil,
      "selected_contact_ids" => nil,
      "selected_transport_id" => nil,
      "selected_source_endpoint_id" => nil,
      "selected_ground_station_id" => nil,
      "selected_scope_link_id" => nil,
      "time_axis" => nil,
      "nav_from_link_id" => nil,
      "nav_from_target" => nil,
      "nav_from_target_id" => nil,
      "nav_from_label" => nil,
      "nav_from_relationship_kind" => nil,
      "nav_from_relationship_label" => nil,
      "nav_trail" => nil
    }
  end

  defp target(target_value), do: DataLink.parse_resolvable_target(target_value)

  defp selected_ref_params(selected_ref) do
    %{
      "selected_link" => SelectedDataRef.value(selected_ref, "link_id"),
      "selected_target" => SelectedDataRef.value(selected_ref, "target"),
      "selected_id" => SelectedDataRef.value(selected_ref, "target_id"),
      "selected_placement" => SelectedDataRef.value(selected_ref, "placement_id"),
      "selected_time" => SelectedDataRef.value(selected_ref, "timestamp_ms"),
      "selected_data_view" => SelectedDataRef.value(selected_ref, "data_view"),
      "selected_series_role" => SelectedDataRef.value(selected_ref, "series_role"),
      "selected_compare_of" => SelectedDataRef.value(selected_ref, "compare_of"),
      "selected_comparison_state" => SelectedDataRef.value(selected_ref, "comparison_state"),
      "selected_comparison_delta" => SelectedDataRef.value(selected_ref, "comparison_delta"),
      "selected_primary_sample" => SelectedDataRef.value(selected_ref, "primary_sample_id"),
      "selected_compare_sample" => SelectedDataRef.value(selected_ref, "compare_sample_id"),
      "selected_primary_data_view" => SelectedDataRef.value(selected_ref, "primary_data_view"),
      "selected_compare_data_view" => SelectedDataRef.value(selected_ref, "compare_data_view"),
      "selected_primary_data_management" =>
        SelectedDataRef.value(selected_ref, "primary_data_management"),
      "selected_compare_data_management" =>
        SelectedDataRef.value(selected_ref, "compare_data_management"),
      "selected_primary_count" => SelectedDataRef.value(selected_ref, "primary_count"),
      "selected_compare_count" => SelectedDataRef.value(selected_ref, "compare_count"),
      "selected_widget" => SelectedDataRef.value(selected_ref, "widget_id"),
      "selected_widget_title" => SelectedDataRef.value(selected_ref, "widget_title"),
      "selected_widget_type" => SelectedDataRef.value(selected_ref, "widget_type"),
      "selected_widget_source" => SelectedDataRef.value(selected_ref, "widget_source"),
      "selected_primary_kind" => SelectedDataRef.value(selected_ref, "primary_kind"),
      "selected_compare_kind" => SelectedDataRef.value(selected_ref, "compare_kind"),
      "selected_primary_observables" =>
        SelectedDataRef.value(selected_ref, "primary_observables"),
      "selected_compare_observables" =>
        SelectedDataRef.value(selected_ref, "compare_observables"),
      "selected_scope_kind" => SelectedDataRef.value(selected_ref, "scope_kind"),
      "selected_scope_id" => SelectedDataRef.value(selected_ref, "scope_id"),
      "selected_scope_ids" => SelectedDataRef.value(selected_ref, "scope_ids"),
      "selected_resource_id" => SelectedDataRef.value(selected_ref, "resource_id"),
      "selected_spacecraft_id" => SelectedDataRef.value(selected_ref, "spacecraft_id"),
      "selected_contact_id" => SelectedDataRef.value(selected_ref, "contact_id"),
      "selected_contact_ids" => SelectedDataRef.value(selected_ref, "contact_ids"),
      "selected_transport_id" => SelectedDataRef.value(selected_ref, "transport_id"),
      "selected_source_endpoint_id" => SelectedDataRef.value(selected_ref, "source_endpoint_id"),
      "selected_ground_station_id" => SelectedDataRef.value(selected_ref, "ground_station_id"),
      "selected_scope_link_id" => SelectedDataRef.value(selected_ref, "scope_link_id"),
      "realm" => SelectedDataRef.value(selected_ref, "realm"),
      "data_source_id" => SelectedDataRef.value(selected_ref, "data_source_id"),
      "source_binding_id" => SelectedDataRef.value(selected_ref, "source_binding_id"),
      "time_mode" => SelectedDataRef.value(selected_ref, "time_mode"),
      "time_axis" => SelectedDataRef.value(selected_ref, "time_axis"),
      "replay_run_id" => SelectedDataRef.value(selected_ref, "replay_run_id"),
      "limit_mode" => SelectedDataRef.value(selected_ref, "limit_mode"),
      "nav_from_link_id" => SelectedDataRef.value(selected_ref, "nav_from_link_id"),
      "nav_from_target" => SelectedDataRef.value(selected_ref, "nav_from_target"),
      "nav_from_target_id" => SelectedDataRef.value(selected_ref, "nav_from_target_id"),
      "nav_from_label" => SelectedDataRef.value(selected_ref, "nav_from_label"),
      "nav_from_relationship_kind" =>
        SelectedDataRef.value(selected_ref, "nav_from_relationship_kind"),
      "nav_from_relationship_label" =>
        SelectedDataRef.value(selected_ref, "nav_from_relationship_label"),
      "nav_trail" => SelectedDataRef.value(selected_ref, "nav_trail")
    }
  end

  defp compact_flat(map) when is_map(map) do
    map
    |> Enum.reject(fn {_key, value} -> value in [nil, ""] end)
    |> Map.new()
  end

  defp text_param(value) when is_binary(value) do
    value = String.trim(value)
    if value == "", do: nil, else: value
  end

  defp text_param(_value), do: nil

  defp integer_param(params, key) do
    case Map.get(params, key) do
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

  defp present?(value), do: value not in [nil, ""]
end
