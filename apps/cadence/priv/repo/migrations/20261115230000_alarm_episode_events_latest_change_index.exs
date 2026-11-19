defmodule Cadence.Repo.Migrations.AlarmEpisodeEventsLatestChangeIndex do
  use Ecto.Migration

  # U69 A6 (ux, fe-ops): the alarm-episode summary names the mission's latest state change
  # (raised, escalated, deescalated, cleared), newest first. Partial on those kinds, so the
  # summary reads one index entry instead of the mission's events. Concurrent and
  # if-not-exists: safe in a qa slot, or built by hand ahead of a restart with the same name.
  @disable_ddl_transaction true
  @disable_migration_lock true

  def change do
    create_if_not_exists(
      index(:alarm_episode_events, [:mission_id, "at DESC", "event_id DESC"],
        name: :alarm_episode_events_latest_change_idx,
        where: "kind IN ('raised', 'escalated', 'deescalated', 'cleared')",
        concurrently: true
      )
    )
  end
end
