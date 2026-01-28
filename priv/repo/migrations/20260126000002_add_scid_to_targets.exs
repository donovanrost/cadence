defmodule Cadence.Repo.Migrations.AddScidToTargets do
  use Ecto.Migration

  def change do
    alter table(:targets) do
      add :scid, :integer
    end

    create unique_index(:targets, [:mission_id, :scid],
             where: "scid IS NOT NULL",
             name: :targets_mission_scid_index
           )
  end
end
