defmodule Cadence.Telemetry.LogSource.File do
  @moduledoc """
  Subscriber-based source paired with the file sink.

  Delivers live batches via in-memory notifications; replay from disk can be
  added later.
  """

  @behaviour Cadence.Telemetry.LogSource

  alias Cadence.Runtime.Telemetry.Lanes.LaneConfig
  alias Cadence.Telemetry.{LogEnvelope, LogStore}

  @default_base_dir Path.join([File.cwd!(), "priv", "telemetry_logs"])
  @default_batch_size 100

  @impl true
  def subscribe(shard_id, opts \\ []) do
    base_dir = Keyword.get(opts, :base_dir) || @default_base_dir
    group = Keyword.get(opts, :group)
    start_from = Keyword.get(opts, :start_from)
    mission_id = Keyword.get(opts, :mission_id)
    lane = Keyword.get(opts, :lane, :payload)

    LogStore.register_subscriber(shard_id, self())

    effective_start = resolve_start_offset(start_from, group, shard_id, base_dir)

    # Stream historical records asynchronously
    maybe_stream_from_disk(
      effective_start,
      shard_id,
      base_dir,
      mission_id,
      lane,
      Keyword.get(opts, :batch_size)
    )

    meta = %{
      shard_id: shard_id,
      group: group,
      start_from: effective_start
    }

    {:ok, self(), meta}
  end

  @impl true
  def ack(shard_id, offset, opts) do
    group = Keyword.get(opts, :group)
    base_dir = Keyword.get(opts, :base_dir) || @default_base_dir

    if group do
      LogStore.persist_consumer_offset(shard_id, group, offset, base_dir: base_dir)
    end

    :ok
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

  @impl true
  def handle_batch(pid, records, opts \\ []) do
    send(pid, {:log_batch, Keyword.get(opts, :shard_id), records, %{}})
  end

  defp stream_from_disk(subscriber, shard_id, start_from, base_dir, mission_id, lane, batch_size) do
    paths = build_paths(base_dir, mission_id, lane, shard_id)

    if paths != [] do
      paths
      |> Stream.flat_map(&File.stream!/1)
      |> Stream.with_index(1)
      |> drop_prefix(start_from)
      |> Stream.map(fn {line, _idx} -> decode_line(line) end)
      |> Stream.chunk_every(
        batch_size || @default_batch_size,
        batch_size || @default_batch_size,
        []
      )
      |> Enum.each(fn chunk ->
        send(subscriber, {:log_batch, shard_id, chunk, %{replay: true}})
      end)
    end
  end

  defp drop_prefix(stream, :head), do: stream
  defp drop_prefix(stream, {:offset, n}), do: Stream.drop(stream, max(n - 1, 0))
  defp drop_prefix(stream, _), do: Stream.drop(stream, 0)

  defp resolve_start_offset(start_from, group, shard_id, base_dir) do
    stored = group && LogStore.consumer_offset(shard_id, group, base_dir: base_dir)

    case {start_from, stored} do
      {{:offset, _} = offset, _} -> offset
      {:head, _} -> :head
      {:origin, _} -> :head
      {:tail, _} -> :tail
      {_, stored_offset} when is_integer(stored_offset) -> {:offset, stored_offset + 1}
      _ -> :tail
    end
  end

  defp maybe_stream_from_disk(:tail, _shard_id, _base_dir, _mission_id, _lane, _batch_size),
    do: :ok

  defp maybe_stream_from_disk(effective_start, shard_id, base_dir, mission_id, lane, batch_size) do
    subscriber = self()

    Task.start(fn ->
      stream_from_disk(
        subscriber,
        shard_id,
        effective_start,
        base_dir,
        mission_id,
        lane,
        batch_size
      )
    end)
  end

  defp decode_line(line) do
    line
    |> String.trim_trailing()
    |> Base.decode64!()
    |> :erlang.binary_to_term()
    |> normalize_envelope()
  end

  defp normalize_envelope(%LogEnvelope{} = env), do: env
  defp normalize_envelope(term), do: struct(LogEnvelope, Map.from_struct(term))

  defp build_paths(base_dir, mission_id, lane, shard_id) do
    base_path = Path.join([base_dir, resolve_mission(base_dir, mission_id), Atom.to_string(lane)])

    segment_paths =
      base_path
      |> Path.join("#{shard_id}-*.log")
      |> Path.wildcard()
      |> Enum.sort()

    if segment_paths != [] do
      segment_paths
    else
      path = Path.join(base_path, "#{shard_id}.log")

      if File.exists?(path) do
        [path]
      else
        []
      end
    end
  end

  defp resolve_mission(_base_dir, mission_id) when is_binary(mission_id), do: mission_id

  defp resolve_mission(base_dir, _mission_id) do
    case File.ls(base_dir) do
      {:ok, [mission_dir | _]} -> mission_dir
      _ -> "default"
    end
  end
end
