# Read-only durable checkpoints and complete record boundaries, including retired pods.
# A checkpoint can lag live processing. This does not establish exclusive ownership.
unless System.get_env("CADENCE_CHAOS_LAB") == "true" and
         System.get_env("POD_NAMESPACE") == "cadence-chaos",
       do: raise("Not the lab")

read_term = fn path ->
  case File.read(path) do
    {:ok, bytes} -> :erlang.binary_to_term(bytes, [:safe])
    {:error, :enoent} -> %{}
  end
end

scan = fn scan, file, position, size, tail ->
  case :file.pread(file, position, 70) do
    {:ok,
     <<"CIJR", 1::16, sequence::64, offset::64, _receipt::signed-64, payload_size::32,
       metadata_size::32, _checksum::binary-size(32)>>}
    when position + 70 + metadata_size + payload_size <= size ->
      scan.(scan, file, position + 70 + metadata_size + payload_size, size, %{
        next_offset: offset + payload_size,
        next_sequence: sequence + 1
      })

    _ ->
      Map.put(tail, :unscanned_bytes, size - position)
  end
end

streams =
  Path.wildcard("/data/journal/*/stream-*/stream.term")
  |> Enum.map(fn path ->
    directory = Path.dirname(path)
    metadata = read_term.(path)
    checkpoint = read_term.(Path.join(directory, "cursors.term"))

    tails =
      Path.wildcard(Path.join(directory, "*.cij"))
      |> Enum.map(fn segment ->
        {:ok, file} = :file.open(String.to_charlist(segment), [:read, :raw, :binary])

        try do
          scan.(scan, file, 0, File.stat!(segment).size, %{next_offset: 0, next_sequence: 0})
        after
          :file.close(file)
        end
      end)

    tail = Enum.max([Map.get(checkpoint, :next_offset, 0) | Enum.map(tails, & &1.next_offset)])

    %{
      pod_uid: directory |> Path.dirname() |> Path.basename(),
      stream_id: metadata.stream_id,
      context: metadata.context,
      complete_record_tail: tail,
      durable_checkpoint: checkpoint,
      bytes_after_checkpoint:
        Map.new(Map.get(checkpoint, :cursors, %{processing: 0, archive: 0}), fn {consumer, cursor} ->
          {consumer, max(tail - cursor, 0)}
        end),
      unscanned_bytes: Enum.sum(Enum.map(tails, & &1.unscanned_bytes))
    }
  end)

IO.puts("LAB_JOURNAL_SNAPSHOT=" <> Jason.encode!(%{at: DateTime.utc_now(), streams: streams}))
