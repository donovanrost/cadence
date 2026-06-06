defmodule Cadence.Repo.Migrations.AddSpacecraftTypeToMissionSpacecraft do
  use Ecto.Migration

  def change do
    alter table(:mission_spacecraft) do
      add(:spacecraft_type_id, :string)
      add(:spacecraft_type_version, :integer)
    end

    create(
      index(:mission_spacecraft, [:organization_id, :mission_id, :spacecraft_type_id],
        name: :mission_spacecraft_org_mission_type_idx,
        where: "spacecraft_type_id IS NOT NULL"
      )
    )
  end
end
