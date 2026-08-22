defmodule Cadence.Repo.Migrations.CreateChannelTargets do
  use Ecto.Migration

  def change do
    create table(:channel_targets, primary_key: false) do
      add :id, :binary_id, primary_key: true

      add :organization_id, references(:organizations, type: :binary_id, on_delete: :delete_all),
        null: false

      add :mission_id, references(:missions, type: :binary_id, on_delete: :delete_all),
        null: false

      add :target_id, :string, null: false
      add :scid, :integer, null: false
      add :vcid, :integer, null: false, default: 0
      add :map_id, :integer
      add :purpose, :string

      timestamps(type: :utc_datetime)
    end

    create index(:channel_targets, [:mission_id])
    create index(:channel_targets, [:target_id])

    create unique_index(
             :channel_targets,
             [:organization_id, :mission_id, :target_id, :scid, :vcid],
             where: "map_id IS NULL AND purpose IS NULL",
             name: :channel_targets_null_map_null_purpose_index
           )

    create unique_index(
             :channel_targets,
             [:organization_id, :mission_id, :target_id, :scid, :vcid, :map_id],
             where: "map_id IS NOT NULL AND purpose IS NULL",
             name: :channel_targets_map_null_purpose_index
           )

    create unique_index(
             :channel_targets,
             [:organization_id, :mission_id, :target_id, :scid, :vcid, :purpose],
             where: "map_id IS NULL AND purpose IS NOT NULL",
             name: :channel_targets_null_map_with_purpose_index
           )

    create unique_index(
             :channel_targets,
             [:organization_id, :mission_id, :target_id, :scid, :vcid, :map_id, :purpose],
             where: "map_id IS NOT NULL AND purpose IS NOT NULL",
             name: :channel_targets_map_with_purpose_index
           )
  end
end
