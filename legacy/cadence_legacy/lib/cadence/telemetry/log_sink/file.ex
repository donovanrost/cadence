defmodule Cadence.Telemetry.LogSink.File do
  @moduledoc """
  File-based sink that appends envelopes per shard and notifies subscribers.

  Writes one line per record (base64-encoded term) to
  `<base_dir>/<mission>/<lane>/<shard>.log`.
  """

  @behaviour Cadence.Telemetry.LogSink

  alias Cadence.Runtime.Telemetry.Lanes.LaneConfig
  alias Cadence.Telemetry.LogStore

  @state_prefix {__MODULE__, :state}
  @default_base_dir Path.join([File.cwd!(), "priv", "telemetry_logs"])

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
    state_key = sink_state_key(base_dir, mission_id, lane, shard_id)

    try do
      state = load_state(state_key, path, shard_id, segment_bytes, max_segments, max_total_bytes)

      encoded =
        Enum.map(records, fn record ->
          encoded = record |> :erlang.term_to_binary() |> Base.encode64()
          [encoded, "\n"]
        end)

      bytes_to_write = IO.iodata_length(encoded)
      state = write_records(state, encoded, bytes_to_write)
      store_state(state_key, state)

      {first_offset, last_offset} = LogStore.next_offsets(shard_id, length(records))
      broadcast(shard_id, records, first_offset, last_offset)

      {:ok, %{first_offset: first_offset, last_offset: last_offset}}
    rescue
      error ->
        clear_state(state_key)
        {:error, error}
    end
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
    @default_base_dir
  end

  defp load_state(state_key, path, shard_id, segment_bytes, max_segments, max_total_bytes) do
    case Process.get(state_key) do
      %{
        path: ^path,
        shard_id: ^shard_id,
        segment_bytes: ^segment_bytes,
        max_segments: ^max_segments,
        max_total_bytes: ^max_total_bytes
      } = state ->
        state

      existing ->
        maybe_close_file(existing)
        init_state(path, shard_id, segment_bytes, max_segments, max_total_bytes)
    end
  end

  defp init_state(path, shard_id, segment_bytes, max_segments, max_total_bytes) do
    File.mkdir_p!(path)
    segmented? = is_integer(segment_bytes) and segment_bytes > 0

    state =
      if segmented? do
        manifest_path = Path.join(path, "#{shard_id}.manifest")
        current_segment = read_segment_index(path, shard_id, manifest_path)
        current_path = segment_path(path, shard_id, current_segment)
        segments = load_segment_entries(path, shard_id)
        current_size = file_size(current_path)

        %{
          path: path,
          shard_id: shard_id,
          segmented?: true,
          segment_bytes: segment_bytes,
          max_segments: max_segments,
          max_total_bytes: max_total_bytes,
          manifest_path: manifest_path,
          current_segment: current_segment,
          current_path: current_path,
          current_size: current_size,
          current_file: nil,
          segments: ensure_current_segment(segments, current_path, current_segment, current_size),
          total_bytes: total_bytes(segments, current_path, current_segment, current_size)
        }
      else
        current_path = Path.join(path, "#{shard_id}.log")
        current_size = file_size(current_path)

        %{
          path: path,
          shard_id: shard_id,
          segmented?: false,
          segment_bytes: segment_bytes,
          max_segments: max_segments,
          max_total_bytes: max_total_bytes,
          manifest_path: nil,
          current_segment: nil,
          current_path: current_path,
          current_size: current_size,
          current_file: nil,
          segments: [%{path: current_path, index: nil, size: current_size}],
          total_bytes: current_size
        }
      end

    apply_retention(state)
  end

  defp write_records(state, encoded, bytes_to_write) do
    state =
      state
      |> maybe_roll_segment(bytes_to_write)
      |> ensure_file_open()

    IO.binwrite(state.current_file, encoded)

    state
    |> update_current_size(bytes_to_write)
    |> apply_retention()
  end

  defp maybe_roll_segment(
         %{segmented?: true, current_size: current_size, segment_bytes: segment_bytes} = state,
         bytes_to_write
       )
       when current_size > 0 and current_size + bytes_to_write > segment_bytes do
    next_segment = state.current_segment + 1
    next_path = segment_path(state.path, state.shard_id, next_segment)
    write_segment_index!(state.manifest_path, next_segment)

    state
    |> close_current_file()
    |> Map.merge(%{
      current_segment: next_segment,
      current_path: next_path,
      current_size: 0,
      segments: state.segments ++ [%{path: next_path, index: next_segment, size: 0}]
    })
  end

  defp maybe_roll_segment(state, _bytes_to_write), do: state

  defp ensure_file_open(%{current_file: nil, current_path: current_path} = state) do
    {:ok, file} = File.open(current_path, [:append, :binary, :raw])
    %{state | current_file: file}
  end

  defp ensure_file_open(state), do: state

  defp update_current_size(%{segments: segments} = state, bytes_to_write) do
    updated_segments =
      case Enum.reverse(segments) do
        [%{size: size} = current | rest] ->
          Enum.reverse([%{current | size: size + bytes_to_write} | rest])

        [] ->
          []
      end

    %{
      state
      | current_size: state.current_size + bytes_to_write,
        segments: updated_segments,
        total_bytes: state.total_bytes + bytes_to_write
    }
  end

  defp apply_retention(state) do
    state
    |> enforce_max_segments()
    |> enforce_max_total_bytes()
  end

  defp enforce_max_segments(%{segmented?: true, max_segments: max_segments} = state)
       when is_integer(max_segments) and max_segments > 0 do
    trim_segments_while(state, fn current_state ->
      length(current_state.segments) > max_segments
    end)
  end

  defp enforce_max_segments(state), do: state

  defp enforce_max_total_bytes(%{max_total_bytes: max_total_bytes} = state)
       when is_integer(max_total_bytes) and max_total_bytes > 0 do
    trim_segments_while(state, fn current_state ->
      current_state.total_bytes > max_total_bytes
    end)
  end

  defp enforce_max_total_bytes(state), do: state

  defp trim_segments_while(state, predicate) do
    do_trim_segments(state, predicate)
  end

  defp do_trim_segments(%{segments: []} = state, _predicate), do: state

  defp do_trim_segments(state, predicate) do
    if predicate.(state) and trimmable?(state) do
      [%{path: path, size: size} | rest] = state.segments
      _ = File.rm(path)

      state
      |> Map.put(:segments, rest)
      |> Map.put(:total_bytes, max(state.total_bytes - size, 0))
      |> do_trim_segments(predicate)
    else
      state
    end
  end

  defp trimmable?(%{segments: [%{path: current_path} | _], current_path: current_path}), do: false
  defp trimmable?(%{segments: [_oldest, _next | _rest]}), do: true
  defp trimmable?(_state), do: false

  defp maybe_close_file(%{current_file: file}) when file != nil do
    _ = File.close(file)
    :ok
  end

  defp maybe_close_file(_state), do: :ok

  defp close_current_file(%{current_file: nil} = state), do: state

  defp close_current_file(%{current_file: file} = state) do
    _ = File.close(file)
    %{state | current_file: nil}
  end

  defp sink_state_key(base_dir, mission_id, lane, shard_id) do
    {@state_prefix, base_dir, mission_id, lane, shard_id}
  end

  defp store_state(state_key, state), do: Process.put(state_key, state)

  defp clear_state(state_key) do
    case Process.delete(state_key) do
      nil -> :ok
      state -> maybe_close_file(state)
    end
  end

  defp load_segment_entries(path, shard_id) do
    path
    |> Path.join("#{shard_id}-*.log")
    |> Path.wildcard()
    |> Enum.map(fn segment_path ->
      %{
        path: segment_path,
        index: segment_index(segment_path, shard_id),
        size: file_size(segment_path)
      }
    end)
    |> Enum.sort_by(& &1.index)
  end

  defp ensure_current_segment(segments, current_path, current_segment, current_size) do
    case Enum.any?(segments, &(&1.path == current_path)) do
      true ->
        segments

      false ->
        segments ++ [%{path: current_path, index: current_segment, size: current_size}]
    end
  end

  defp total_bytes(segments, current_path, current_segment, current_size) do
    segments
    |> ensure_current_segment(current_path, current_segment, current_size)
    |> Enum.reduce(0, fn %{size: size}, total -> total + size end)
  end

  defp file_size(path) do
    case File.stat(path) do
      {:ok, stat} -> stat.size
      _ -> 0
    end
  end

  defp segment_path(path, shard_id, segment), do: Path.join(path, "#{shard_id}-#{segment}.log")

  defp read_segment_index(path, shard_id, manifest_path) do
    case File.read(manifest_path) do
      {:ok, contents} ->
        parse_segment_index(contents, path, shard_id, manifest_path)

      _ ->
        recover_segment_index(path, shard_id, manifest_path)
    end
  end

  defp parse_segment_index(contents, path, shard_id, manifest_path) do
    case Integer.parse(String.trim(contents)) do
      {index, ""} when index >= 0 ->
        index

      _ ->
        recover_segment_index(path, shard_id, manifest_path)
    end
  end

  defp recover_segment_index(path, shard_id, manifest_path) do
    index = latest_segment_index(path, shard_id)
    write_segment_index!(manifest_path, index)
    index
  end

  defp latest_segment_index(path, shard_id) do
    path
    |> Path.join("#{shard_id}-*.log")
    |> Path.wildcard()
    |> Enum.reduce(0, fn segment_path, max_index ->
      max(max_index, segment_index(segment_path, shard_id))
    end)
  end

  defp segment_index(segment_path, shard_id) do
    shard_prefix = "#{shard_id}-"
    shard_suffix = ".log"

    case Path.basename(segment_path) do
      <<^shard_prefix::binary, rest::binary>> ->
        rest
        |> String.trim_trailing(shard_suffix)
        |> parse_segment_suffix()

      _ ->
        0
    end
  end

  defp parse_segment_suffix(value) do
    case Integer.parse(value) do
      {index, ""} when index >= 0 -> index
      _ -> 0
    end
  end

  defp write_segment_index!(manifest_path, index) do
    tmp_path = manifest_path <> ".tmp"
    File.write!(tmp_path, Integer.to_string(index) <> "\n")
    File.rename!(tmp_path, manifest_path)
  end

  defp broadcast(shard_id, records, first_offset, last_offset) do
    meta = %{start_offset: first_offset, end_offset: last_offset}

    LogStore.subscribers(shard_id)
    |> Enum.each(fn pid ->
      send(pid, {:log_batch, shard_id, records, meta})
    end)
  end
end
