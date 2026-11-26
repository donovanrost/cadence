defmodule Cadence.IngressArchive.Retention do
  @moduledoc """
  Retention for the filesystem ingress archive (#694): an index row lives as long as its segment,
  and a segment lives `ingress_archive_days` (`Cadence.Persistence.Retention`).

  A segment is written in a moment, so it has one age. A chunk takes the first `chunk_segments`
  object keys with an expired row, keeps those whose rows are *all* expired (a segment that
  straddles the cutoff waits for the next sweep, so no unexpired evidence loses its file), deletes
  their index rows, and, once that commits, their files. Rows go first: a crash leaves an orphan
  file, never an index row that points at a missing one. A file already gone is fine.

  Only the configured filesystem archive (`:ingress_archive`'s `base_path`) is swept; named
  instances of the archive keep their rows. The age query rides a BRIN index on `receipt_time`
  (rows arrive in time order, so it is tiny).
  """

  @behaviour Cadence.Persistence.Retention.Rule

  require Logger

  alias Cadence.Persistence.Retention
  alias Cadence.Repo

  @archive_backend "filesystem"

  @impl true
  def name, do: :ingress_archive

  @impl true
  def enabled?(_settings), do: is_binary(base_path())

  @impl true
  def initial_cursor, do: nil

  @impl true
  def sweep_chunk(_cursor, %DateTime{} = now, settings) do
    cutoff = now |> Retention.cutoff(Retention.ingress_archive_days(settings)) |> naive()
    limit = Keyword.fetch!(settings, :chunk_segments)
    keys = whole_segments(cutoff, limit)

    %{num_rows: deleted} =
      Repo.query!(
        "DELETE FROM ingress_archive_evidence_entries WHERE archive_backend = $1 AND object_key = ANY($2)",
        [@archive_backend, keys]
      )

    # Done when nothing was deleted (what is left straddles the cutoff, or the rest waits) or no
    # expired row is left.
    status = if deleted == 0 or candidates(cutoff, 1) == [], do: :done, else: :more
    {status, deleted, nil, fn -> remove_files(keys) end}
  end

  # The object keys with an expired row (at most `limit`), narrowed to those with no unexpired one.
  defp whole_segments(cutoff, limit) do
    keys = candidates(cutoff, limit)

    %{rows: rows} =
      Repo.query!(
        """
        SELECT object_key FROM ingress_archive_evidence_entries
        WHERE archive_backend = $1 AND object_key = ANY($2)
        GROUP BY object_key HAVING max(receipt_time) < $3
        """,
        [@archive_backend, keys, cutoff]
      )

    List.flatten(rows)
  end

  defp candidates(cutoff, limit) do
    %{rows: rows} =
      Repo.query!(
        """
        SELECT DISTINCT object_key FROM (
          SELECT object_key FROM ingress_archive_evidence_entries
          WHERE archive_backend = $1 AND receipt_time < $2
          LIMIT $3
        ) expired
        """,
        [@archive_backend, cutoff, limit * 50]
      )

    rows |> List.flatten() |> Enum.take(limit)
  end

  defp remove_files(keys) do
    base = base_path()

    Enum.each(keys, fn key ->
      case File.rm(Path.join(base, key)) do
        :ok ->
          :ok

        {:error, :enoent} ->
          :ok

        {:error, reason} ->
          Logger.warning("ingress archive retention: could not remove #{key}: #{inspect(reason)}")
      end
    end)
  end

  defp base_path do
    :cadence |> Application.get_env(:ingress_archive, []) |> Keyword.get(:base_path)
  end

  defp naive(%DateTime{} = at), do: at |> DateTime.shift_zone!("Etc/UTC") |> DateTime.to_naive()
end
