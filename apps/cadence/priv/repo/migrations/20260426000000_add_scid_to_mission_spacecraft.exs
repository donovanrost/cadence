defmodule Cadence.Repo.Migrations.AddScidToMissionSpacecraft do
  use Ecto.Migration

  def change do
    alter table(:mission_spacecraft) do
      add(:scid, :integer)
    end

    create(
      unique_index(:mission_spacecraft, [:organization_id, :mission_id, :scid],
        name: :mission_spacecraft_org_mission_scid_idx,
        where: "scid IS NOT NULL"
      )
    )
  end
end
