defmodule Cadence.Telemetry.LogSink.File do
  @moduledoc """
  File-based sink that appends envelopes per shard and notifies subscribers.

  Writes one line per record (base64-encoded term) to
  `<base_dir>/<mission>/<lane>/<shard>.log`.
  """

  @behaviour Cadence.Telemetry.LogSink

  alias Cadence.Runtime.Telemetry.Lanes.LaneConfig
  alias Cadence.Telemetry.LogStore

  @impl true
  def append(_shard_id, [], _opts), do: {:ok, %{first_offset: 0, last_offset: 0}}

  def append(shard_id, records, opts) when is_list(records) do
    base_dir = Keyword.get(opts, :base_dir, default_base_dir())
    mission_id = records |> List.first() |> Map.fetch!(:mission_id)
    lane = records |> List.first() |> Map.fetch!(:lane)
    segment_bytes = Keyword.get(opts, :segment_bytes)
    max_segments = Keyword.get(opts, :max_segments)
    max_total_bytes = Keyword.get(opts, :max_total_bytes)

    path = Path.join([base_dir, mission_id, Atom.to_string(lane)])
    File.mkdir_p!(path)

    encoded =
      Enum.map(records, fn record ->
        encoded = record |> :erlang.term_to_binary() |> Base.encode64()
        [encoded, "\n"]
      end)

    bytes_to_write = IO.iodata_length(encoded)

    file_path =
      if is_integer(segment_bytes) and segment_bytes > 0 do
        ensure_segment(path, shard_id, segment_bytes, bytes_to_write)
      else
        Path.join(path, "#{shard_id}.log")
      end

    {:ok, file} =
      File.open(file_path, [:append, :binary, :raw, {:delayed_write, 64_000, 100}])

    IO.binwrite(file, encoded)
    File.close(file)

    maybe_apply_retention(path, shard_id, max_segments, max_total_bytes)

    {first_offset, last_offset} = LogStore.next_offsets(shard_id, length(records))
    broadcast(shard_id, records, first_offset, last_offset)

    {:ok, %{first_offset: first_offset, last_offset: last_offset}}
  rescue
    error -> {:error, error}
  end

  @impl true
  def partitions do
    shard_count =
      LaneConfig.lane_shard_count(
        Application.get_env(:cadence, :pipeline_lanes),
        :payload,
        Application.get_env(:cadence, :pipeline_lane_shards, 0)
      )

    if is_integer(shard_count) and shard_count > 0 do
      {:ok, Enum.to_list(0..(shard_count - 1))}
    else
      {:error, :unknown_partitions}
    end
  end

  @impl true
  def health, do: {:ok, %{status: :ok}}

  defp default_base_dir do
    Path.join([File.cwd!(), "priv", "telemetry_logs"])
  end

  defp ensure_segment(path, shard_id, segment_bytes, bytes_to_write) do
    manifest_path = Path.join(path, "#{shard_id}.manifest")
    current_segment = read_segment_index(manifest_path)
    segment_path = Path.join(path, "#{shard_id}-#{current_segment}.log")

    current_size =
      case File.stat(segment_path) do
        {:ok, stat} -> stat.size
        _ -> 0
      end

    if current_size > 0 and current_size + bytes_to_write > segment_bytes do
      next_segment = current_segment + 1
      File.write!(manifest_path, Integer.to_string(next_segment))
      Path.join(path, "#{shard_id}-#{next_segment}.log")
    else
      if current_size == 0 do
        File.write!(manifest_path, Integer.to_string(current_segment))
      end

      segment_path
    end
  end

  defp maybe_apply_retention(_path, _shard_id, nil, nil), do: :ok

  defp maybe_apply_retention(path, shard_id, max_segments, max_total_bytes) do
    segment_paths =
      path
      |> Path.join("#{shard_id}-*.log")
      |> Path.wildcard()
      |> Enum.sort()

    segment_paths
    |> enforce_max_segments(max_segments)
    |> enforce_max_total_bytes(max_total_bytes)

    :ok
  end

  defp enforce_max_segments(paths, max_segments)
       when is_integer(max_segments) and max_segments > 0 do
    overflow = max(length(paths) - max_segments, 0)

    paths
    |> Enum.take(overflow)
    |> Enum.each(&File.rm/1)

    Enum.drop(paths, overflow)
  end

  defp enforce_max_segments(paths, _), do: paths

  defp enforce_max_total_bytes(paths, max_total_bytes)
       when is_integer(max_total_bytes) and max_total_bytes > 0 do
    total_bytes = sum_bytes(paths)

    if total_bytes > max_total_bytes do
      :ok = trim_to_bytes(paths, total_bytes, max_total_bytes)
    else
      paths
    end
  end

  defp enforce_max_total_bytes(paths, _), do: paths

  defp sum_bytes(paths) do
    Enum.reduce(paths, 0, fn path, acc ->
      case File.stat(path) do
        {:ok, stat} -> acc + stat.size
        _ -> acc
      end
    end)
  end

  defp trim_to_bytes(paths, total_bytes, max_total_bytes) do
    _remaining =
      Enum.reduce_while(paths, total_bytes, fn path, current_bytes ->
        drop_path(path, current_bytes, max_total_bytes)
      end)

    :ok
  end

  defp drop_path(_path, current_bytes, max_total_bytes) when current_bytes <= max_total_bytes do
    {:halt, current_bytes}
  end

  defp drop_path(path, current_bytes, _max_total_bytes) do
    case File.stat(path) do
      {:ok, stat} ->
        _ = File.rm(path)
        {:cont, current_bytes - stat.size}

      _ ->
        {:cont, current_bytes}
    end
  end

  defp read_segment_index(manifest_path) do
    case File.read(manifest_path) do
      {:ok, contents} ->
        contents |> String.trim() |> String.to_integer()

      _ ->
        0
    end
  end

  defp broadcast(shard_id, records, first_offset, last_offset) do
    meta = %{start_offset: first_offset, end_offset: last_offset}

    LogStore.subscribers(shard_id)
    |> Enum.each(fn pid ->
      send(pid, {:log_batch, shard_id, records, meta})
    end)
  end
end
