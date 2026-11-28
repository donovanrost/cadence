defmodule Cadence.Repo.Migrations.ChangeSetLanes do
  use Ecto.Migration

  # ADR-020 P3 slice L (#451; the addendum's change-set lanes, DECISIONS #93 c; ux U108): change
  # sets run in lanes. Configuration keeps one active set per mission (open or in review, frozen in
  # review). Monitoring has one OPEN set per mission; its sets in review don't count, so review
  # never closes the lane. Every existing set is a configuration set.
  def up do
    alter table(:mission_config_change_sets) do
      add(:lane, :string, null: false, default: "configuration", collation: "C")
    end

    create(
      constraint(:mission_config_change_sets, :mission_config_change_sets_lane,
        check: "lane IN ('configuration', 'monitoring')"
      )
    )

    drop(
      index(:mission_config_change_sets, [:mission_id],
        name: :mission_config_change_sets_one_open_idx
      )
    )

    create(
      unique_index(:mission_config_change_sets, [:mission_id],
        name: :mission_config_change_sets_one_active_configuration_idx,
        where: "lane = 'configuration' AND state IN ('open', 'in_review')"
      )
    )

    create(
      unique_index(:mission_config_change_sets, [:mission_id],
        name: :mission_config_change_sets_one_open_monitoring_idx,
        where: "lane = 'monitoring' AND state = 'open'"
      )
    )
  end

  def down do
    drop(
      index(:mission_config_change_sets, [:mission_id],
        name: :mission_config_change_sets_one_open_monitoring_idx
      )
    )

    drop(
      index(:mission_config_change_sets, [:mission_id],
        name: :mission_config_change_sets_one_active_configuration_idx
      )
    )

    execute("DELETE FROM mission_config_change_sets WHERE lane = 'monitoring'")

    create(
      unique_index(:mission_config_change_sets, [:mission_id],
        name: :mission_config_change_sets_one_open_idx,
        where: "state IN ('open', 'in_review')"
      )
    )

    drop(constraint(:mission_config_change_sets, :mission_config_change_sets_lane))

    alter table(:mission_config_change_sets) do
      remove(:lane)
    end
  end
end
