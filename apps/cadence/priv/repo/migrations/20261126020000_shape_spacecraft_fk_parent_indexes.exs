defmodule Cadence.Repo.Migrations.ShapeSpacecraftForeignKeyParentIndexes do
  use Ecto.Migration

  def up do
    drop(
      index(:mission_spacecraft, [:organization_id, :mission_id],
        name: :mission_spacecraft_org_mission_idx
      )
    )

    drop(index(:mission_spacecraft, [:mission_id, :lifecycle_state]))

    create(
      index(:mission_spacecraft, [:mission_id],
        name: :mission_spacecraft_active_mission_idx,
        where: "lifecycle_state = 'active'"
      )
    )
  end

  def down do
    drop(index(:mission_spacecraft, [:mission_id], name: :mission_spacecraft_active_mission_idx))

    create(index(:mission_spacecraft, [:mission_id, :lifecycle_state]))

    create(
      index(:mission_spacecraft, [:organization_id, :mission_id],
        name: :mission_spacecraft_org_mission_idx
      )
    )
  end
end
