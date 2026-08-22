defmodule CadenceWeb.OpsDashboardShowLive.DataLinkIndex do
  @moduledoc false

  alias Cadence.Dashboards.{DataLink, Frame, PlacementFrames}
  alias CadenceWeb.OpsDashboardShowLive.DataLinkSelection
  alias CadenceWeb.OpsDashboardShowLive.RuntimeResult
  alias CadenceWeb.OpsDashboardShowLive.SelectionQuery

  def find_link(links, link_id) when is_binary(link_id) and link_id != "" do
    Enum.find(links, &(&1.link_id == link_id))
  end

  def find_link(_links, _link_id), do: nil

  def find_link_from_query(index, %SelectionQuery{} = query) do
    find_link_from_query(index, SelectionQuery.to_params(query))
  end

  def find_link_from_query(index, %{"selected_link" => link_id} = query)
      when is_binary(link_id) and link_id != "" do
    find_link_in_query_placement(index, link_id, query) ||
      find_link(all_links(index), link_id) ||
      find_link_by_target(index, query) ||
      DataLinkSelection.synthetic_link_from_query(query)
  end

  def find_link_from_query(index, query) do
    find_link_by_target(index, query) || DataLinkSelection.synthetic_link_from_query(query)
  end

  def all_links(index) when is_map(index) do
    panel_links(Map.get(index, :panel)) ++
      engine_result_links(Map.get(index, :engine_result)) ++
      frames_by_placement_links(Map.get(index, :frames_by_placement))
  end

  def placement_links_from_index(index, placement_id)
      when is_map(index) and is_binary(placement_id) and placement_id != "" do
    index
    |> Map.get(:frames_by_placement)
    |> case do
      frames_by_placement when is_map(frames_by_placement) ->
        frames_by_placement
        |> Map.get(placement_id)
        |> placement_links()

      _other ->
        []
    end
  end

  def placement_links_from_index(_index, _placement_id), do: []

  def engine_result_links(nil), do: []

  def engine_result_links(engine_result) do
    warnings = RuntimeResult.dashboard_warnings(engine_result)
    frames_by_placement = RuntimeResult.frames_by_placement(engine_result)

    placement_links =
      frames_by_placement
      |> Map.values()
      |> Enum.flat_map(&placement_links/1)

    warning_links(warnings) ++ placement_links
  end

  def frames_by_placement_links(frames_by_placement) when is_map(frames_by_placement) do
    frames_by_placement
    |> Map.values()
    |> Enum.flat_map(&placement_links/1)
  end

  def frames_by_placement_links(_frames_by_placement), do: []

  def placement_links(%PlacementFrames{} = placement_frames) do
    frame_links =
      (placement_frames.primary ++ overlay_frames(placement_frames.overlays))
      |> Enum.flat_map(&frame_links/1)

    warning_links(placement_frames.warnings) ++ frame_links
  end

  def placement_links(_placement_frames), do: []

  def panel_links({:data_link, %{related_links: links}}) when is_list(links) do
    Enum.filter(links, &match?(%DataLink{}, &1))
  end

  def panel_links(_panel), do: []

  defp find_link_in_query_placement(index, link_id, query) do
    placement_id = Map.get(query, "selected_placement")

    if placement_id in [nil, ""] do
      nil
    else
      index
      |> placement_links_from_index(placement_id)
      |> find_link(link_id)
    end
  end

  defp find_link_by_target(index, query) do
    target = Map.get(query, "selected_target")
    target_id = Map.get(query, "selected_id")
    placement_id = Map.get(query, "selected_placement")

    if target in [nil, ""] or target_id in [nil, ""] do
      nil
    else
      links =
        case placement_id do
          value when value in [nil, ""] -> all_links(index)
          value -> placement_links_from_index(index, value) ++ all_links(index)
        end

      Enum.find(links, &(data_ref_text(&1.target) == target and &1.target_id == target_id))
    end
  end

  defp overlay_frames(overlays) when is_map(overlays) do
    overlays
    |> Map.values()
    |> List.flatten()
  end

  defp overlay_frames(_overlays), do: []

  defp frame_links(%Frame{} = frame) do
    links_from_map(frame.meta) ++
      Enum.flat_map(frame.fields, &links_from_map(&1.metadata))
  end

  defp frame_links(_frame), do: []

  defp warning_links(warnings) when is_list(warnings) do
    Enum.flat_map(warnings, &links_from_map/1)
  end

  defp warning_links(_warnings), do: []

  defp links_from_map(%{links: links}) when is_list(links),
    do: Enum.filter(links, &match?(%DataLink{}, &1))

  defp links_from_map(%{} = map) do
    map
    |> Map.get("links", [])
    |> Enum.filter(&match?(%DataLink{}, &1))
  end

  defp links_from_map(_container), do: []

  defp data_ref_text(nil), do: nil
  defp data_ref_text(value) when is_atom(value), do: Atom.to_string(value)
  defp data_ref_text(value) when is_binary(value), do: value
  defp data_ref_text(value), do: to_string(value)
end
