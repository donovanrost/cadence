defmodule Cadence.Repo.Migrations.CreateFleetAlarmSummaries do
  use Ecto.Migration

  # #871. One row per spacecraft summarizing its ACTIVE live monitoring alarms (worst severity, how
  # many are active, newest receipt, the worst alarm's state row), recomputed by the writer of
  # `semantic_latest_alarm_states` in the same transaction, once per spacecraft per batch that
  # transitions anything. Reading the aggregate instead cost what the active alarms do (58 ms p99 at
  # 3% of 200,000 rows active, 800 ms in a mass event); the fleet read is one row per spacecraft.
  # The identity columns are bytewise (COLLATE "C"), as #949 requires of every id/key column.
  def up do
    create table(:semantic_fleet_alarm_summaries, primary_key: false) do
      add(:organization_id, :string, null: false, primary_key: true, collation: "C")
      add(:mission_id, :string, null: false, primary_key: true, collation: "C")
      add(:spacecraft_id, :string, null: false, primary_key: true, collation: "C")
      add(:worst_rank, :smallint, null: false)
      add(:active, :integer, null: false)
      add(:last_received_at, :utc_datetime_usec, null: false)
      add(:worst_state_id, :bigint, null: false)
    end

    execute("""
    ALTER TABLE semantic_fleet_alarm_summaries
      ADD CONSTRAINT semantic_fleet_alarm_summaries_org_mission_fk
      FOREIGN KEY (organization_id, mission_id) REFERENCES missions (organization_id, mission_id)
    """)

    execute("""
    INSERT INTO semantic_fleet_alarm_summaries
      (organization_id, mission_id, spacecraft_id, worst_rank, active, last_received_at, worst_state_id)
    SELECT organization_id, mission_id, spacecraft_id,
      max(CASE WHEN effective_state IN ('distress', 'critical', 'severe') THEN 2 ELSE 1 END),
      count(*), max(receipt_time),
      (array_agg(id ORDER BY (CASE WHEN effective_state IN ('distress', 'critical', 'severe') THEN 2 ELSE 1 END) DESC,
                 receipt_time DESC, id DESC))[1]
    FROM semantic_latest_alarm_states
    WHERE effective_state IN ('watch', 'warning', 'distress', 'critical', 'severe')
      AND spacecraft_id IS NOT NULL AND organization_id IS NOT NULL
    GROUP BY organization_id, mission_id, spacecraft_id
    """)
  end

  def down, do: drop(table(:semantic_fleet_alarm_summaries))
end
