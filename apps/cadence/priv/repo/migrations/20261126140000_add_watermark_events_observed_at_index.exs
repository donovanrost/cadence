defmodule Cadence.Repo.Migrations.AddWatermarkEventsObservedAtIndex do
  use Ecto.Migration

  # Retention (#694) finds the expired end of the history by age alone, and every other index on
  # the table leads with a key or a scope. It also skips the event each status names, which wants
  # an index on the status side: without it the planner hashes the whole backlog and sorts it on
  # every chunk (measured at 500k events: 242 ms a chunk, 19 ms with both indexes).
  def change do
    create(
      index(:data_source_watermark_events, [:observed_at],
        name: :data_source_watermark_events_observed_idx
      )
    )

    create(
      index(:data_source_watermark_statuses, [:source_watermark_event_id],
        name: :data_source_watermark_statuses_event_idx
      )
    )
  end
end
