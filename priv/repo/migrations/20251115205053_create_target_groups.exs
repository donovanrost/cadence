defmodule Cadence.Repo.Migrations.CreateTargetGroups do
  use Ecto.Migration

  def change do
    create table(:target_groups, primary_key: false) do
      add :id, :binary_id, primary_key: true

      add :mission_id, references(:missions, type: :binary_id, on_delete: :delete_all),
        null: false

      add :parent_id, references(:target_groups, type: :binary_id, on_delete: :delete_all)

      add :name, :string, null: false
      add :slug, :string, null: false
      add :description, :text
      add :group_type, :string, null: false

      # Metadata
      add :metadata, :map, default: %{}

      timestamps(type: :utc_datetime)
    end

    create table(:target_group_memberships, primary_key: false) do
      add :id, :binary_id, primary_key: true

      add :target_group_id, references(:target_groups, type: :binary_id, on_delete: :delete_all),
        null: false

      add :target_id, references(:targets, type: :binary_id, on_delete: :delete_all), null: false

      timestamps(type: :utc_datetime)
    end

    create index(:target_groups, [:mission_id])
    create index(:target_groups, [:parent_id])
    create unique_index(:target_groups, [:mission_id, :slug])

    create index(:target_group_memberships, [:target_group_id])
    create index(:target_group_memberships, [:target_id])
    create unique_index(:target_group_memberships, [:target_group_id, :target_id])
  end
end
