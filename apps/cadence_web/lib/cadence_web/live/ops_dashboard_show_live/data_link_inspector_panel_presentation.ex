defmodule CadenceWeb.OpsDashboardShowLive.DataLinkInspectorPanelPresentation do
  @moduledoc false

  alias CadenceWeb.OpsDashboardShowLive.DashboardActionPresentation
  alias CadenceWeb.OpsDashboardShowLive.DataLinkActionOutcomePresentation
  alias CadenceWeb.OpsDashboardShowLive.DataLinkPresentation

  @empty_panel_attrs %{
    target: "",
    target_id: "",
    status: "",
    selected_link: "",
    selected_realm: "",
    selected_data_view: "",
    selected_data_source_id: "",
    selected_source_binding_id: "",
    selected_time_mode: "",
    selected_time_axis: "",
    selected_replay_run_id: ""
  }

  def build(inspector, mission_id, dashboard_document, action_outcome \\ nil) do
    panel = DataLinkPresentation.panel(inspector)

    %{
      panel: panel,
      panel_attrs: panel_attrs(inspector, panel),
      data_link_actions:
        DashboardActionPresentation.for_inspector(
          inspector,
          mission_id,
          :data_link_panel,
          dashboard_document
        ),
      action_outcome: DataLinkActionOutcomePresentation.build(action_outcome)
    }
  end

  def panel_attrs(inspector, panel) when is_map(inspector) and is_map(panel) do
    selection_summary = map_value(panel, :selection_summary) || %{}

    %{
      target: attr_text(inspector_value(inspector, :target)),
      target_id: attr_text(inspector_value(inspector, :target_id)),
      status: attr_text(inspector_value(inspector, :status_text)),
      selected_link: attr_text(map_value(selection_summary, :link_id)),
      selected_realm: attr_text(map_value(selection_summary, :realm)),
      selected_data_view: attr_text(map_value(selection_summary, :data_view)),
      selected_data_source_id: attr_text(map_value(selection_summary, :data_source_id)),
      selected_source_binding_id: attr_text(map_value(selection_summary, :source_binding_id)),
      selected_time_mode: attr_text(map_value(selection_summary, :time_mode)),
      selected_time_axis: attr_text(map_value(selection_summary, :time_axis)),
      selected_replay_run_id: attr_text(map_value(selection_summary, :replay_run_id))
    }
  end

  def panel_attrs(_inspector, _panel), do: @empty_panel_attrs

  def relationship_kind_text(nil), do: nil
  def relationship_kind_text(kind) when is_atom(kind), do: Atom.to_string(kind)
  def relationship_kind_text(kind) when is_binary(kind), do: kind
  def relationship_kind_text(_kind), do: nil

  def bool_attr(true), do: "true"
  def bool_attr(_value), do: "false"

  def present_text?(value), do: is_binary(value) and value != ""

  defp inspector_value(inspector, key) do
    map_value(inspector, key)
  end

  defp map_value(map, key) when is_map(map) do
    Map.get(map, key, Map.get(map, Atom.to_string(key)))
  end

  defp map_value(_map, _key), do: nil

  defp attr_text(nil), do: ""
  defp attr_text(value) when is_atom(value), do: Atom.to_string(value)
  defp attr_text(value) when is_integer(value), do: Integer.to_string(value)
  defp attr_text(value) when is_binary(value), do: value
  defp attr_text(_value), do: ""
end
