defmodule Cadence.Repo.Migrations.AddOperationalEventSourceHistoryIndex do
  use Ecto.Migration

  @disable_ddl_transaction true
  @disable_migration_lock true

  def change do
    # Keep time ordering before the optional replay filter so generic prepared
    # plans can use this index for both binding and source-health history.
    create(
      index(
        :operational_events,
        [
          :organization_id,
          :mission_id,
          :source_record_kind,
          :occurred_at,
          :event_id,
          :replay_run_id
        ],
        name: :operational_events_source_history_idx,
        concurrently: true
      )
    )
  end
end
