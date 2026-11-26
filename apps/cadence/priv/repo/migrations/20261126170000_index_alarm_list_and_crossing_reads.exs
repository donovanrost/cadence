defmodule Cadence.Repo.Migrations.IndexAlarmListAndCrossingReads do
  use Ecto.Migration

  @disable_ddl_transaction true
  @disable_migration_lock true

  # #794. The alarm list pages in SQL in the list's own order (severity rank, newest first,
  # spacecraft, point) over the ACTIVE rows, and the crossing time of a page's alarms is read from
  # each (spacecraft, point)'s newest events.
  def change do
    create(
      index(
        :telemetry_latest_limit_states,
        [
          :mission_id,
          "(CASE normalized_state WHEN 'red' THEN 0 WHEN 'yellow' THEN 1 WHEN 'blue' THEN 2 ELSE 3 END)",
          "receipt_time DESC",
          "(coalesce(spacecraft_id, ''))",
          :point_id
        ],
        where: "violation",
        name: :telemetry_latest_limit_states_active_order_idx,
        concurrently: true
      )
    )

    create(
      index(
        :telemetry_limit_events,
        [:mission_id, :spacecraft_id, :point_id, "receipt_time DESC", "limit_event_id DESC"],
        name: :telemetry_limit_events_crossing_idx,
        concurrently: true
      )
    )
  end
end
