defmodule Cadence.Protocol.RecordArchive.Quarantine.Retention do
  @moduledoc """
  Retention for the protocol-archive quarantine (#791, #694; DECISIONS #88). Entries that can never
  be indexed wait here for an operator; nothing else removes them but a discard or a successful
  retry, so each poisoned entry used to stay for good.

  **An entry** is kept for the protocol archive's retention plus a review margin
  (`Retention.quarantine_entry_days/1`: `protocol_archive_days` + `quarantine_review_days`),
  counted from its record's `receipt_time` (its first sighting when it has none). Past the
  archive's retention, indexing it would only expire it at once, so a retry is no longer useful;
  the margin is the operators' time to decide. The quarantine's console item shows when its last
  entry expires (`expires_at`).

  **An item that expires is closed, not dropped:** when a chunk removes the last entry of an
  item (a realized contact and an error code) it records a resolution, action `expired`, so
  "recently resolved" says what happened to it, with the counts of what that chunk removed.

  **Resolutions** (the record of retried, discarded and expired items) are kept
  `quarantine_resolution_days`, counted from `resolved_at`.

  Each chunk is a short transaction over the oldest `chunk_rows` expired rows by that timestamp
  (expression index `protocol_archive_quarantine_expiry_idx`), skipping rows another transaction
  holds, so a retry or discard in progress is never waited on and never skipped for a pass.
  """

  @behaviour Cadence.Persistence.Retention.Rule

  alias Cadence.Persistence.Retention
  alias Cadence.Protocol.RecordArchive.Quarantine
  alias Cadence.Repo

  @system %{"kind" => "system", "id" => "quarantine_retention", "name" => "Cadence"}

  @impl true
  def name, do: :protocol_archive_quarantine

  @impl true
  def enabled?(_settings), do: true

  # `nil`: the entries; `:resolutions`: their record, once no entry is left to expire.
  @impl true
  def initial_cursor, do: nil

  @impl true
  def sweep_chunk(nil, now, settings) do
    limit = Keyword.fetch!(settings, :chunk_rows)
    cutoff = Retention.cutoff(now, Retention.quarantine_entry_days(settings))
    deleted = expire_entries(cutoff, limit, now)

    if deleted < limit,
      do: {:more, deleted, :resolutions, fn -> :ok end},
      else: {:more, deleted, nil, fn -> :ok end}
  end

  def sweep_chunk(:resolutions, now, settings) do
    limit = Keyword.fetch!(settings, :chunk_rows)
    cutoff = Retention.cutoff(now, Retention.quarantine_resolution_days(settings))

    %{num_rows: deleted} =
      Repo.query!(
        """
        WITH doomed AS (
          SELECT resolution_id FROM protocol_archive_quarantine_resolutions
          WHERE resolved_at < $1
          ORDER BY resolved_at
          LIMIT $2
          FOR UPDATE SKIP LOCKED
        )
        DELETE FROM protocol_archive_quarantine_resolutions r USING doomed d
        WHERE r.resolution_id = d.resolution_id
        """,
        [cutoff, limit]
      )

    {if(deleted < limit, do: :done, else: :more), deleted, :resolutions, fn -> :ok end}
  end

  # Deletes up to `limit` expired entries; records an `expired` resolution for each item the chunk
  # left with no entry. Returns how many entries it deleted.
  defp expire_entries(cutoff, limit, now) do
    %{rows: rows} =
      Repo.query!(
        """
        WITH doomed AS (
          SELECT quarantine_entry_id FROM protocol_archive_quarantine
          WHERE coalesce(receipt_time, first_seen_at) < $1
          ORDER BY coalesce(receipt_time, first_seen_at)
          LIMIT $2
          FOR UPDATE SKIP LOCKED
        ), gone AS (
          DELETE FROM protocol_archive_quarantine q USING doomed d
          WHERE q.quarantine_entry_id = d.quarantine_entry_id
          RETURNING q.mission_id, q.realized_contact_id, q.spacecraft_id, q.error_code,
                    q.record_kind
        )
        SELECT g.mission_id, g.realized_contact_id, g.error_code, max(g.spacecraft_id),
               count(*), count(*) FILTER (WHERE g.record_kind = 'transfer_frame_record'),
               count(*) FILTER (WHERE g.record_kind = 'packet_record')
        FROM gone g
        GROUP BY g.mission_id, g.realized_contact_id, g.error_code
        """,
        [cutoff, limit]
      )

    open = still_open(rows)

    for [mission, contact, code, spacecraft, entries, frames, packets] <- rows,
        not MapSet.member?(open, {mission, contact, code}) do
      Quarantine.record_resolution(%{
        mission_id: mission,
        item_id: Quarantine.item_id(contact, code),
        realized_contact_id: contact,
        spacecraft_id: spacecraft,
        error_code: code,
        action: "expired",
        actor: @system,
        note: nil,
        counts: %{entries: entries, frames: frames, packets: packets},
        resolved_at: now
      })
    end

    rows |> Enum.map(&Enum.at(&1, 4)) |> Enum.sum()
  end

  # Which of the chunk's items still have an entry (the delete has applied: this is a new statement).
  defp still_open([]), do: MapSet.new()

  defp still_open(rows) do
    {missions, contacts, codes} =
      rows
      |> Enum.map(fn [mission, contact, code | _rest] -> {mission, contact, code} end)
      |> Enum.reduce({[], [], []}, fn {m, c, e}, {ms, cs, es} ->
        {[m | ms], [c | cs], [e | es]}
      end)

    %{rows: open} =
      Repo.query!(
        """
        SELECT g.m, g.c, g.e
        FROM unnest($1::text[], $2::text[], $3::text[]) AS g(m, c, e)
        WHERE EXISTS (
          SELECT 1 FROM protocol_archive_quarantine r
          WHERE r.mission_id = g.m AND r.error_code = g.e
            AND (r.realized_contact_id = g.c OR (g.c IS NULL AND r.realized_contact_id IS NULL)))
        """,
        [missions, contacts, codes]
      )

    MapSet.new(open, fn [m, c, e] -> {m, c, e} end)
  end
end
