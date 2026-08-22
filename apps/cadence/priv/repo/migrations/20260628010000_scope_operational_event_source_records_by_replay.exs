defmodule Cadence.Repo.Migrations.ScopeOperationalEventSourceRecordsByReplay do
  use Ecto.Migration

  def up do
    drop_if_exists(index(:operational_events, [], name: :operational_events_source_record_idx))

    create(
      unique_index(:operational_events, [:mission_id, :source_record_kind, :source_record_id],
        name: :operational_events_source_record_idx,
        where:
          "source_record_kind IS NOT NULL AND source_record_id IS NOT NULL AND replay_run_id IS NULL"
      )
    )

    create(
      unique_index(
        :operational_events,
        [:mission_id, :source_record_kind, :source_record_id, :replay_run_id],
        name: :operational_events_source_record_replay_idx,
        where:
          "source_record_kind IS NOT NULL AND source_record_id IS NOT NULL AND replay_run_id IS NOT NULL"
      )
    )
  end

  def down do
    drop_if_exists(
      index(:operational_events, [], name: :operational_events_source_record_replay_idx)
    )

    drop_if_exists(index(:operational_events, [], name: :operational_events_source_record_idx))

    create(
      unique_index(:operational_events, [:mission_id, :source_record_kind, :source_record_id],
        name: :operational_events_source_record_idx,
        where: "source_record_kind IS NOT NULL AND source_record_id IS NOT NULL"
      )
    )
  end
end
