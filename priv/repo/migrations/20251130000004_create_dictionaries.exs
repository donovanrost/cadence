defmodule Cadence.Repo.Migrations.CreateDictionaries do
  use Ecto.Migration

  def change do
    # Create the dictionaries catalog table
    create table(:dictionaries, primary_key: false) do
      add :id, :binary_id, primary_key: true

      add :organization_id, references(:organizations, type: :binary_id, on_delete: :delete_all),
        null: false

      add :name, :string, null: false
      add :slug, :string, null: false
      add :description, :text
      add :metadata, :map, default: %{}

      timestamps(type: :utc_datetime)
    end

    create index(:dictionaries, [:organization_id])
    create unique_index(:dictionaries, [:organization_id, :slug])

    # Add dictionary_id to definition_sets, make mission_id optional
    alter table(:mdb_definition_sets) do
      add :dictionary_id, references(:dictionaries, type: :binary_id, on_delete: :delete_all)
      modify :mission_id, :binary_id, null: true
    end

    create index(:mdb_definition_sets, [:dictionary_id])

    # Update unique constraint: version unique per dictionary, not per mission
    drop_if_exists unique_index(:mdb_definition_sets, [:mission_id, :version],
                     name: :mdb_definition_sets_mission_version_index
                   )

    create unique_index(:mdb_definition_sets, [:dictionary_id, :version],
             name: :mdb_definition_sets_dictionary_version_index
           )

    # Add definition_set_id to targets
    alter table(:targets) do
      add :definition_set_id,
          references(:mdb_definition_sets, type: :binary_id, on_delete: :nilify_all)
    end

    create index(:targets, [:definition_set_id])
  end
end
