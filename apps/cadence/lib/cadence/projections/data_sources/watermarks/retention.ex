defmodule Cadence.Projections.DataSources.Watermarks.Retention do
  @moduledoc """
  Retention for `data_source_watermark_events` (#694): the history of every watermark transition,
  one row per change per source. Nothing else deletes it, and at constellation scale it grows with
  the number of sources and their transitions.

  An event lives `watermark_event_days` (`Cadence.Persistence.Retention`; the observation
  retention unless set), counted from `observed_at`. The current state of a source is its row in
  `data_source_watermark_statuses`, which this rule never touches, and the event that status names
  is kept however old it is, so the one an operator can link to for a quiet source never goes
  missing.

  A chunk deletes the oldest `chunk_rows` expired events by `observed_at` (the new index starts
  the scan at the old end), skipping rows another transaction holds.
  """

  @behaviour Cadence.Persistence.Retention.Rule

  alias Cadence.Persistence.Retention
  alias Cadence.Repo

  @impl true
  def name, do: :watermark_events

  @impl true
  def enabled?(_settings), do: true

  @impl true
  def initial_cursor, do: nil

  @impl true
  def sweep_chunk(_cursor, %DateTime{} = now, settings) do
    cutoff = now |> Retention.cutoff(Retention.watermark_event_days(settings))
    limit = Keyword.fetch!(settings, :chunk_rows)

    %{num_rows: deleted} =
      Repo.query!(
        """
        WITH doomed AS (
          SELECT e.source_watermark_event_id FROM data_source_watermark_events e
          WHERE e.observed_at < $1
            AND NOT EXISTS (
              SELECT 1 FROM data_source_watermark_statuses s
              WHERE s.source_watermark_event_id = e.source_watermark_event_id
            )
          ORDER BY e.observed_at
          LIMIT $2
          FOR UPDATE OF e SKIP LOCKED
        )
        DELETE FROM data_source_watermark_events e USING doomed d
        WHERE e.source_watermark_event_id = d.source_watermark_event_id
        """,
        [cutoff, limit]
      )

    {if(deleted < limit, do: :done, else: :more), deleted, nil, fn -> :ok end}
  end
end
