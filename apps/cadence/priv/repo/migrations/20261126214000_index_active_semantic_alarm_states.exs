defmodule Cadence.Repo.Migrations.IndexActiveSemanticAlarmStates do
  use Ecto.Migration

  @disable_ddl_transaction true
  @disable_migration_lock true

  # #871. The fleet summary of a spacecraft's ACTIVE live alarms (watch, warning, distress,
  # critical, severe) is recomputed from this table by its writer on every transition batch. Only
  # the active rows are read, so they have their own small index (normal, unknown and disabled
  # rows, most of the table, are not in it) and the recompute costs what that spacecraft's active
  # alarms do.
  def change do
    create(
      index(
        :semantic_latest_alarm_states,
        [
          :organization_id,
          :mission_id,
          :spacecraft_id,
          "(CASE WHEN effective_state IN ('distress', 'critical', 'severe') THEN 2 ELSE 1 END) DESC",
          "receipt_time DESC"
        ],
        where:
          "effective_state IN ('watch', 'warning', 'distress', 'critical', 'severe') AND spacecraft_id IS NOT NULL",
        name: :semantic_latest_alarm_states_active_idx,
        concurrently: true
      )
    )
  end
end
