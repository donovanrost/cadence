defmodule Cadence.Telemetry.LogStore do
  @moduledoc false
  # Lightweight registry for sink/source coordination (offsets + subscribers).

  @table :cadence_log_store
  @default_base_dir Path.join([File.cwd!(), "priv", "telemetry_logs"])

  def ensure_table do
    case :ets.whereis(@table) do
      :undefined ->
        :ets.new(@table, [:set, :named_table, :public, read_concurrency: true])

      _ ->
        :ok
    end
  end

  def next_offsets(shard_id, count) when is_integer(count) and count >= 0 do
    ensure_table()

    key = {:offset, shard_id}

    current =
      case :ets.lookup(@table, key) do
        [{^key, val}] -> val
        [] -> 0
      end

    new = current + count
    :ets.insert(@table, {key, new})
    {current + 1, new}
  end

  def register_subscriber(shard_id, pid) when is_pid(pid) do
    ensure_table()
    key = {:subscribers, shard_id}

    subs =
      case :ets.lookup(@table, key) do
        [] -> []
        [{^key, list}] -> Enum.filter(list, &Process.alive?/1)
      end

    updated = Enum.uniq([pid | subs])
    :ets.insert(@table, {key, updated})
    :ok
  end

  def subscribers(shard_id) do
    ensure_table()
    key = {:subscribers, shard_id}

    case :ets.lookup(@table, key) do
      [] -> []
      [{^key, list}] -> Enum.filter(list, &Process.alive?/1)
    end
  end

  def consumer_offset(shard_id, group, opts \\ []) do
    ensure_table()
    base_dir = Keyword.get(opts, :base_dir) || @default_base_dir
    key = {:consumer_offset, shard_id, group}

    case :ets.lookup(@table, key) do
      [{^key, offset}] ->
        offset

      [] ->
        offset_from_disk(shard_id, group, base_dir)
    end
  end

  def persist_consumer_offset(shard_id, group, offset, opts \\ []) do
    ensure_table()
    base_dir = Keyword.get(opts, :base_dir) || @default_base_dir
    key = {:consumer_offset, shard_id, group}

    :ets.insert(@table, {key, offset})
    dir = offset_dir(base_dir, group)
    File.mkdir_p!(dir)
    File.write!(Path.join(dir, "#{shard_id}.offset"), Integer.to_string(offset))
    :ok
  end

  defp offset_from_disk(shard_id, group, base_dir) do
    path = Path.join(offset_dir(base_dir, group), "#{shard_id}.offset")

    case File.read(path) do
      {:ok, contents} ->
        contents
        |> String.trim()
        |> parse_offset()

      _ ->
        nil
    end
  end

  defp parse_offset(""), do: nil

  defp parse_offset(value) do
    case Integer.parse(value) do
      {offset, ""} -> offset
      _ -> nil
    end
  end

  defp offset_dir(base_dir, group) do
    Path.join([base_dir, "offsets", encode_group(group)])
  end

  defp encode_group(nil), do: "default"
  defp encode_group(atom) when is_atom(atom), do: Atom.to_string(atom)
  defp encode_group(term), do: :erlang.phash2(term) |> Integer.to_string()
end
