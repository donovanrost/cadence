defmodule Cadence.Repo.Migrations.CreateFleetLimitSummaries do
  use Ecto.Migration

  # #849. One row per spacecraft summarizing its latest limit states (worst severity, violating
  # count, newest receipt, the worst violating point's row), kept by the writers of
  # `telemetry_latest_limit_states` in the same transaction, so the fleet read is one query over a
  # row per spacecraft instead of an aggregate over every point. It replaces the violators index
  # #798 added for the aggregate's DISTINCT ON.
  def up do
    create table(:telemetry_fleet_limit_summaries, primary_key: false) do
      add(:organization_id, :string, null: false, primary_key: true)
      add(:mission_id, :string, null: false, primary_key: true)
      add(:spacecraft_id, :string, null: false, primary_key: true)
      add(:worst_rank, :smallint, null: false)
      add(:violating, :integer, null: false)
      add(:last_received_at, :utc_datetime_usec)
      add(:worst_state_id, :bigint)
    end

    execute("""
    ALTER TABLE telemetry_fleet_limit_summaries
      ADD CONSTRAINT telemetry_fleet_limit_summaries_org_mission_fk
      FOREIGN KEY (organization_id, mission_id) REFERENCES missions (organization_id, mission_id)
    """)

    execute("""
    INSERT INTO telemetry_fleet_limit_summaries
      (organization_id, mission_id, spacecraft_id, worst_rank, violating, last_received_at, worst_state_id)
    SELECT organization_id, mission_id, spacecraft_id,
      max(CASE normalized_state WHEN 'red' THEN 2 WHEN 'yellow' THEN 1 ELSE 0 END),
      count(*) FILTER (WHERE violation),
      max(receipt_time),
      (array_agg(id ORDER BY (CASE normalized_state WHEN 'red' THEN 2 WHEN 'yellow' THEN 1 ELSE 0 END) DESC,
                 receipt_time DESC, id DESC) FILTER (WHERE violation))[1]
    FROM telemetry_latest_limit_states
    WHERE spacecraft_id IS NOT NULL AND organization_id IS NOT NULL
    GROUP BY organization_id, mission_id, spacecraft_id
    """)

    drop(
      index(:telemetry_latest_limit_states, [],
        name: :telemetry_latest_limit_states_violators_idx
      )
    )
  end

  def down do
    execute("""
    CREATE INDEX telemetry_latest_limit_states_violators_idx ON telemetry_latest_limit_states
      (mission_id, organization_id, spacecraft_id,
       (CASE normalized_state WHEN 'red' THEN 2 WHEN 'yellow' THEN 1 ELSE 0 END) DESC, receipt_time DESC)
      WHERE violation AND spacecraft_id IS NOT NULL
    """)

    drop(table(:telemetry_fleet_limit_summaries))
  end
end
