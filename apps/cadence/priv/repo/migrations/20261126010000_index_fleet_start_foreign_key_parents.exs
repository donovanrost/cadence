defmodule Cadence.Repo.Migrations.IndexFleetStartForeignKeyParents do
  use Ecto.Migration

  def up do
    drop(
      index(:contact_requirements, [:organization_id, :mission_id, :lifecycle_state],
        name: :contact_requirements_mission_state_idx
      )
    )

    create(
      index(:contact_requirements, [:organization_id, :mission_id],
        name: :contact_requirements_active_mission_idx,
        where: "lifecycle_state = 'active'"
      )
    )

    create(
      index(:contact_requirements, [:organization_id, :mission_id, :lifecycle_state],
        name: :contact_requirements_inactive_mission_state_idx,
        where: "lifecycle_state <> 'active'"
      )
    )

    drop(
      index(
        :contact_requirement_versions,
        [:organization_id, :mission_id, :spacecraft_id, :earliest_start, :latest_end],
        name: :contact_requirement_versions_horizon_idx
      )
    )

    create(
      index(
        :contact_requirement_versions,
        [:spacecraft_id, :organization_id, :mission_id, :earliest_start, :latest_end],
        name: :contact_requirement_versions_spacecraft_horizon_idx
      )
    )

    create(
      index(
        :contact_requirement_versions,
        [:organization_id, :mission_id, :earliest_start, :latest_end],
        name: :contact_requirement_versions_mission_horizon_idx,
        # Horizon reads imply this predicate; RI checks do not. Even though the column is
        # required, the predicate keeps this broad index out of cached FK lookup plans.
        where: "earliest_start IS NOT NULL"
      )
    )

    create(
      index(:contact_requirement_versions, [:contact_requirement_id, :version],
        name: :contact_requirement_versions_requirement_version_idx
      )
    )
  end

  def down do
    drop(
      index(:contact_requirement_versions, [:contact_requirement_id, :version],
        name: :contact_requirement_versions_requirement_version_idx
      )
    )

    drop(
      index(
        :contact_requirement_versions,
        [:organization_id, :mission_id, :earliest_start, :latest_end],
        name: :contact_requirement_versions_mission_horizon_idx,
        where: "earliest_start IS NOT NULL"
      )
    )

    drop(
      index(
        :contact_requirement_versions,
        [:spacecraft_id, :organization_id, :mission_id, :earliest_start, :latest_end],
        name: :contact_requirement_versions_spacecraft_horizon_idx
      )
    )

    create(
      index(
        :contact_requirement_versions,
        [:organization_id, :mission_id, :spacecraft_id, :earliest_start, :latest_end],
        name: :contact_requirement_versions_horizon_idx
      )
    )

    drop(
      index(:contact_requirements, [:organization_id, :mission_id, :lifecycle_state],
        name: :contact_requirements_inactive_mission_state_idx
      )
    )

    drop(
      index(:contact_requirements, [:organization_id, :mission_id],
        name: :contact_requirements_active_mission_idx
      )
    )

    create(
      index(:contact_requirements, [:organization_id, :mission_id, :lifecycle_state],
        name: :contact_requirements_mission_state_idx
      )
    )
  end
end
