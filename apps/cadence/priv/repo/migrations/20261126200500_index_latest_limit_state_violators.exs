defmodule Cadence.Repo.Migrations.IndexLatestLimitStateViolators do
  use Ecto.Migration

  @disable_ddl_transaction true
  @disable_migration_lock true

  # #798. The fleet read finds each spacecraft's worst violating point among the violating rows only
  # (a few percent of the mission's latest limit states), so those rows have their own small index.
  def change do
    create(
      index(
        :telemetry_latest_limit_states,
        [
          :mission_id,
          :organization_id,
          :spacecraft_id,
          "(CASE normalized_state WHEN 'red' THEN 2 WHEN 'yellow' THEN 1 ELSE 0 END) DESC",
          "receipt_time DESC"
        ],
        where: "violation AND spacecraft_id IS NOT NULL",
        name: :telemetry_latest_limit_states_violators_idx,
        concurrently: true
      )
    )
  end
end
