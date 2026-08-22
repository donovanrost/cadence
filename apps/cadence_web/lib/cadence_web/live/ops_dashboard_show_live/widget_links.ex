defmodule CadenceWeb.OpsDashboardShowLive.WidgetLinks do
  @moduledoc false

  alias Cadence.Dashboards.{DataLink, Frame, PlacementFrames}
  alias CadenceWeb.OpsDashboardShowLive.EvidencePresentation

  @widget_link_targets [
    :limit_event,
    :limit_definition,
    :telemetry_sample,
    :telemetry_point,
    :mission_event,
    :operational_event,
    :source_health_event,
    :source_watermark_event,
    :telemetry_revision_decision_event,
    :telemetry_backfill_lifecycle_event,
    :contact,
    :link,
    :transport,
    :source_endpoint,
    :ground_station
  ]

  @spec widget_data_links(Frame.t(), PlacementFrames.t() | term()) :: [map()]
  def widget_data_links(%Frame{} = telemetry_frame, %PlacementFrames{} = placement_frames) do
    timestamps_by_sample_id = sample_timestamps_by_id(telemetry_frame)

    telemetry_frame
    |> data_links()
    |> Kernel.++(limit_overlay_links(placement_frames))
    |> filter_widget_links(timestamps_by_sample_id)
  end

  def widget_data_links(%Frame{} = telemetry_frame, _placement_frames) do
    timestamps_by_sample_id = sample_timestamps_by_id(telemetry_frame)

    telemetry_frame
    |> data_links()
    |> filter_widget_links(timestamps_by_sample_id)
  end

  @spec filter_widget_links([DataLink.t()]) :: [map()]
  def filter_widget_links(links, timestamps_by_sample_id \\ %{}) do
    links
    |> Enum.filter(&(&1.target in @widget_link_targets))
    |> uniq_widget_links()
    |> Enum.map(&link_summary(&1, timestamps_by_sample_id))
  end

  @spec uniq_link_summaries([map()]) :: [map()]
  def uniq_link_summaries(links) do
    links
    |> Enum.uniq_by(&(&1.link_id || {&1.target, &1.target_id}))
    |> Enum.sort_by(&summary_link_sort_key/1)
  end

  @spec limit_links(map() | term()) :: [map()]
  def limit_links(%{links: links}) when is_list(links), do: filter_widget_links(links)
  def limit_links(_limit), do: []

  @spec data_links(Frame.t() | map() | term()) :: [DataLink.t()]
  def data_links(%Frame{} = frame) do
    data_links(frame.meta) ++ Enum.flat_map(frame.fields, &data_links(&1.metadata))
  end

  def data_links(%{links: links}) when is_list(links),
    do: DataLink.normalize_many(links)

  def data_links(%{} = map) do
    map
    |> Map.get("links", [])
    |> DataLink.normalize_many()
  end

  def data_links(_container), do: []

  defp limit_overlay_links(%PlacementFrames{overlays: %{limits: [%Frame{} = limit_frame | _]}}) do
    data_links(limit_frame)
  end

  defp limit_overlay_links(_placement_frames), do: []

  defp uniq_widget_links(links) do
    links
    |> Enum.uniq_by(&(&1.link_id || {&1.target, &1.target_id}))
    |> Enum.sort_by(&widget_link_sort_key/1)
  end

  defp widget_link_sort_key(%DataLink{target: target}) do
    Enum.find_index(@widget_link_targets, &(&1 == target)) || length(@widget_link_targets)
  end

  defp summary_link_sort_key(%{target: target}) when is_binary(target) do
    target_atom = Enum.find(@widget_link_targets, &(Atom.to_string(&1) == target))
    Enum.find_index(@widget_link_targets, &(&1 == target_atom)) || length(@widget_link_targets)
  end

  defp summary_link_sort_key(%{target: target}) when is_atom(target) do
    Enum.find_index(@widget_link_targets, &(&1 == target)) || length(@widget_link_targets)
  end

  defp summary_link_sort_key(_link), do: length(@widget_link_targets)

  defp link_summary(%DataLink{target: :telemetry_sample, target_id: sample_id} = link, timestamps)
       when is_binary(sample_id) and is_map(timestamps) do
    link
    |> EvidencePresentation.link_summary()
    |> maybe_put_timestamp_ms(Map.get(timestamps, sample_id))
  end

  defp link_summary(%DataLink{} = link, _timestamps), do: EvidencePresentation.link_summary(link)

  defp maybe_put_timestamp_ms(summary, timestamp_ms) when is_integer(timestamp_ms),
    do: Map.put(summary, :timestamp_ms, timestamp_ms)

  defp maybe_put_timestamp_ms(summary, _timestamp_ms), do: summary

  defp sample_timestamps_by_id(%Frame{fields: fields}) when is_list(fields) do
    times = frame_times(fields)

    fields
    |> Enum.flat_map(fn field ->
      field
      |> metadata_values(:sample_ids)
      |> Enum.zip(times)
    end)
    |> Enum.reduce(%{}, fn
      {sample_id, %DateTime{} = timestamp}, acc when is_binary(sample_id) and sample_id != "" ->
        Map.put_new(acc, sample_id, DateTime.to_unix(timestamp, :millisecond))

      _entry, acc ->
        acc
    end)
  end

  defp sample_timestamps_by_id(%Frame{}), do: %{}

  defp frame_times(fields) do
    fields
    |> Enum.find(&(&1.name in ["time", "bucket_start"]))
    |> case do
      %{values: values} when is_list(values) -> values
      _missing -> []
    end
  end

  defp metadata_values(%{metadata: metadata}, key), do: metadata_values(metadata, key)

  defp metadata_values(metadata, key) when is_map(metadata) and is_atom(key) do
    metadata
    |> Map.get(key, Map.get(metadata, Atom.to_string(key), []))
    |> List.wrap()
  end

  defp metadata_values(_metadata, _key), do: []
end
