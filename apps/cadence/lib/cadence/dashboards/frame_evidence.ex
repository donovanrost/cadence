defmodule Cadence.Dashboards.FrameEvidence do
  @moduledoc """
  Core frame-evidence aggregation for dashboard evidence inspectors.

  The web layer decides how to label and render frame evidence. This module owns
  the semantic aggregation across a placement's primary frame and relevant
  overlay frames: evidence refs, data links, and operator actions.
  """

  alias Cadence.Dashboards.{DashboardAction, DataLink, EvidenceRef, Frame, PlacementFrames}

  @type inspector :: %{
          required(:frame) => Frame.t(),
          required(:overlay_frames) => [Frame.t()],
          required(:frames) => [Frame.t()],
          required(:links) => [DataLink.t()],
          required(:evidence_refs) => [EvidenceRef.t()],
          required(:actions) => [DashboardAction.t()]
        }

  @spec inspect(PlacementFrames.t() | nil, binary() | nil) :: inspector() | nil
  def inspect(%PlacementFrames{} = placement_frames, observable_id) do
    case primary_frame_for_observable(placement_frames, observable_id) do
      %Frame{} = frame ->
        overlay_frames = relevant_overlay_frames(placement_frames, observable_id)
        frames = [frame | overlay_frames]

        %{
          frame: frame,
          overlay_frames: overlay_frames,
          frames: frames,
          links: frame_links(frames),
          evidence_refs: frame_evidence_refs(frames),
          actions: frame_actions(frames)
        }

      nil ->
        nil
    end
  end

  def inspect(_placement_frames, _observable_id), do: nil

  @spec frame_links([Frame.t()] | Frame.t()) :: [DataLink.t()]
  def frame_links(%Frame{} = frame), do: frame_links([frame])

  def frame_links(frames) when is_list(frames) do
    frames
    |> Enum.flat_map(&data_links/1)
    |> Enum.uniq_by(&(&1.link_id || {&1.target, &1.target_id}))
  end

  @spec frame_evidence_refs([Frame.t()] | Frame.t()) :: [EvidenceRef.t()]
  def frame_evidence_refs(%Frame{} = frame), do: frame_evidence_refs([frame])

  def frame_evidence_refs(frames) when is_list(frames) do
    frames
    |> Enum.flat_map(&evidence_refs/1)
    |> EvidenceRef.normalize_many()
    |> Enum.uniq_by(&evidence_identity/1)
  end

  @spec frame_actions([Frame.t()] | Frame.t()) :: [DashboardAction.t()]
  def frame_actions(%Frame{} = frame), do: frame_actions([frame])

  def frame_actions(frames) when is_list(frames) do
    frames
    |> Enum.flat_map(&dashboard_actions/1)
    |> Enum.uniq_by(& &1.action_id)
  end

  defp primary_frame_for_observable(%PlacementFrames{primary: frames}, observable_id)
       when is_list(frames) do
    Enum.find(frames, fn
      %Frame{} = frame ->
        observable_id in [nil, ""] or observable_id in observable_ids(frame)

      _other ->
        false
    end)
  end

  defp primary_frame_for_observable(_placement_frames, _observable_id), do: nil

  defp relevant_overlay_frames(%PlacementFrames{overlays: overlays}, observable_id)
       when is_map(overlays) do
    overlays
    |> Map.values()
    |> List.flatten()
    |> Enum.filter(fn
      %Frame{} = frame ->
        observable_ids = observable_ids(frame)
        observable_id in [nil, ""] or observable_ids == [] or observable_id in observable_ids

      _other ->
        false
    end)
  end

  defp relevant_overlay_frames(_placement_frames, _observable_id), do: []

  defp data_links(%Frame{} = frame) do
    data_links(frame.meta) ++ Enum.flat_map(frame.fields, &data_links(&1.metadata))
  end

  defp data_links(%{links: links}) when is_list(links),
    do: DataLink.normalize_many(links)

  defp data_links(%{} = map) do
    map
    |> Map.get("links", [])
    |> DataLink.normalize_many()
  end

  defp data_links(_container), do: []

  defp evidence_refs(%Frame{} = frame) do
    evidence_refs(frame.meta) ++ Enum.flat_map(frame.fields, &evidence_refs(&1.metadata))
  end

  defp evidence_refs(container) when is_map(container) do
    container
    |> evidence_ref_values()
  end

  defp evidence_refs(_container), do: []

  defp evidence_ref_values(container) do
    List.wrap(metadata_value(container, :evidence, [])) ++
      List.wrap(metadata_value(container, :evidence_refs, []))
  end

  defp dashboard_actions(%Frame{} = frame) do
    dashboard_actions(frame.meta) ++ Enum.flat_map(frame.fields, &dashboard_actions(&1.metadata))
  end

  defp dashboard_actions(%{actions: actions}), do: DashboardAction.normalize_many(actions)

  defp dashboard_actions(%{} = map) do
    map
    |> Map.get("actions", [])
    |> DashboardAction.normalize_many()
  end

  defp dashboard_actions(_container), do: []

  defp observable_ids(%Frame{meta: meta}) when is_map(meta) do
    cond do
      is_binary(metadata_value(meta, :observable_id)) ->
        [metadata_value(meta, :observable_id)]

      is_list(metadata_value(meta, :observable_ids)) ->
        metadata_value(meta, :observable_ids)

      true ->
        []
    end
  end

  defp observable_ids(%Frame{}), do: []

  defp metadata_value(map, key, default \\ nil) when is_map(map) and is_atom(key) do
    Map.get(map, key, Map.get(map, Atom.to_string(key), default))
  end

  defp evidence_identity(%EvidenceRef{} = ref), do: {ref.kind, ref.id}

  defp evidence_identity(ref) when is_map(ref) do
    {metadata_value(ref, :kind), metadata_value(ref, :id)}
  end

  defp evidence_identity(ref), do: ref
end
