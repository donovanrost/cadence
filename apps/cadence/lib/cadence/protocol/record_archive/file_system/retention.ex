defmodule Cadence.Protocol.RecordArchive.FileSystem.Retention do
  @moduledoc """
  Retention for the filesystem protocol archive (#694): a segment lives `protocol_archive_days`
  (`Cadence.Persistence.Retention`), and with it its summary row, its identity rows and its file.

  **Rows, then files.** A chunk takes the first `chunk_segments` segments whose *last* receipt time
  is past the cutoff (a segment is wholly expired only then, so no unexpired record loses its
  file; the summary row keeps both ends, so this needs no scan of the identities) and deletes
  their rows. The identity rows go with them by the foreign key's cascade, in the same short
  transaction. Once that commits, the files are removed. A crash between the two leaves an orphan
  file, never an index row pointing at a missing one.

  **Orphans.** When no expired segment is left, the rule walks the day directories more than a day
  older than the cutoff (a segment's path carries the receipt day of its first entry) and removes
  a `*.bin` file no segment row names: the leftover of a crash between a chunk's commit and its
  file removal, or of an archive write that never got indexed. A file with a row is never touched.
  A day directory left empty is removed.

  Only the configured filesystem archive is swept (`:protocol_record_archive`'s `base_path` and the
  `filesystem` backend); named instances of the archive keep their rows. The age query rides a BRIN
  index on `last_receipt_time` (segments arrive in time order, so it is tiny). Identity rows are
  cascaded, never queried by age, so a chunk's cost is its segments' record count.
  """

  @behaviour Cadence.Persistence.Retention.Rule

  require Logger

  alias Cadence.Persistence.Retention
  alias Cadence.Repo

  @archive_backend "filesystem"
  @file_system Cadence.Protocol.RecordArchive.FileSystem
  @day_margin 1

  @impl true
  def name, do: :protocol_archive

  @impl true
  def enabled?(_settings), do: file_system?() and is_binary(base_path())

  @impl true
  def initial_cursor, do: nil

  @impl true
  def sweep_chunk(nil, %DateTime{} = now, settings) do
    cutoff = now |> Retention.cutoff(Retention.protocol_archive_days(settings)) |> naive()
    limit = Keyword.fetch!(settings, :chunk_segments)

    %{rows: rows} =
      Repo.query!(
        """
        DELETE FROM protocol_archive_segments
        WHERE id IN (
          SELECT id FROM protocol_archive_segments
          WHERE archive_backend = $1 AND last_receipt_time < $2
          LIMIT $3
          FOR UPDATE SKIP LOCKED
        )
        RETURNING object_key
        """,
        [@archive_backend, cutoff, limit]
      )

    keys = List.flatten(rows)
    next = if length(keys) < limit, do: {:orphans, nil}, else: nil
    {:more, length(keys), next, fn -> remove_files(keys) end}
  end

  def sweep_chunk({:orphans, position}, %DateTime{} = now, settings) do
    cutoff_date = now |> Retention.cutoff(Retention.protocol_archive_days(settings)) |> date()
    limit = Keyword.fetch!(settings, :chunk_rows)

    case orphan_chunk(position, Date.add(cutoff_date, -@day_margin), limit) do
      {:done, orphans} -> {:done, 0, nil, fn -> remove_files(orphans) end}
      {:more, orphans, next} -> {:more, 0, {:orphans, next}, fn -> remove_files(orphans) end}
    end
  end

  # The orphans among the next `limit` files of the expired day directories, from `position`
  # (`{directory, last file name seen}`), and where the walk goes next.
  defp orphan_chunk(position, newest_day, limit) do
    case next_files(expired_directories(newest_day), position, limit) do
      {[], _next} ->
        {:done, []}

      {files, next} ->
        orphans = unindexed(files)
        if next == :done, do: {:done, orphans}, else: {:more, orphans, next}
    end
  end

  # Up to `limit` file keys from the first directory at or after `position` that has any left, and
  # the position after them (`:done` past the last directory).
  defp next_files(dirs, position, limit) do
    dirs =
      case position do
        {dir, _name} -> Enum.drop_while(dirs, &(&1 < dir))
        nil -> dirs
      end

    walk(dirs, position, limit)
  end

  defp walk([], _position, _limit), do: {[], :done}

  defp walk([dir | rest], position, limit) do
    after_name =
      case position do
        {^dir, name} when is_binary(name) -> name
        _ -> nil
      end

    names =
      dir
      |> list_bin_files()
      |> Enum.filter(&(is_nil(after_name) or &1 > after_name))
      |> Enum.take(limit)

    cond do
      names == [] ->
        # Empty (or only what an earlier chunk kept): remove the directory if nothing is left.
        _ = File.rmdir(Path.join(base_path(), dir))
        walk(rest, nil, limit)

      length(names) < limit ->
        {Enum.map(names, &Path.join(dir, &1)), next_position(rest)}

      true ->
        {Enum.map(names, &Path.join(dir, &1)), {dir, List.last(names)}}
    end
  end

  defp next_position([]), do: :done
  defp next_position([dir | _]), do: {dir, nil}

  defp unindexed(keys) do
    %{rows: rows} =
      Repo.query!(
        "SELECT object_key FROM protocol_archive_segments WHERE object_key = ANY($1)",
        [keys]
      )

    indexed = rows |> List.flatten() |> MapSet.new()
    Enum.reject(keys, &MapSet.member?(indexed, &1))
  end

  # `mission/YYYY-MM-DD` directories with a day at or before `newest_day`, sorted.
  defp expired_directories(newest_day) do
    base = base_path()

    for mission <- list_dir(base),
        File.dir?(Path.join(base, mission)),
        day <- list_dir(Path.join(base, mission)),
        {:ok, date} <- [Date.from_iso8601(day)],
        Date.compare(date, newest_day) != :gt,
        do: Path.join(mission, day)
  end

  defp list_bin_files(dir) do
    dir |> Path.expand(base_path()) |> list_dir() |> Enum.filter(&String.ends_with?(&1, ".bin"))
  end

  defp list_dir(path) do
    case File.ls(path) do
      {:ok, names} -> Enum.sort(names)
      {:error, _reason} -> []
    end
  end

  defp remove_files(keys) do
    base = base_path()

    Enum.each(keys, fn key ->
      path = Path.join(base, key)

      case File.rm(path) do
        :ok ->
          :ok

        {:error, :enoent} ->
          :ok

        {:error, reason} ->
          Logger.warning(
            "protocol archive retention: could not remove #{key}: #{inspect(reason)}"
          )
      end
    end)

    remove_empty_directories(keys, base)
  end

  # A day directory left empty goes (`rmdir` refuses a directory with anything in it). The days
  # are old ones, so no live write is racing it.
  defp remove_empty_directories(keys, base) do
    keys
    |> Enum.map(&Path.dirname/1)
    |> Enum.uniq()
    |> Enum.each(&File.rmdir(Path.join(base, &1)))
  end

  defp config, do: Application.get_env(:cadence, :protocol_record_archive, [])
  defp file_system?, do: Keyword.get(config(), :module) == @file_system
  defp base_path, do: Keyword.get(config(), :base_path)

  defp naive(%DateTime{} = at), do: at |> DateTime.shift_zone!("Etc/UTC") |> DateTime.to_naive()
  defp date(%DateTime{} = at), do: at |> DateTime.shift_zone!("Etc/UTC") |> DateTime.to_date()
end
