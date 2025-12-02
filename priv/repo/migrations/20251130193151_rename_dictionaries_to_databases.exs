defmodule Cadence.Repo.Migrations.RenameDictionariesToDatabases do
  use Ecto.Migration

  @moduledoc """
  Renames Dictionary -> Database and restructures the model:
  - dictionaries table -> databases table
  - organization_id -> mission_id (now mission-scoped)
  - dictionary_id -> database_id on definition_sets
  - Removes mission_id from definition_sets (no more legacy mission-scoped definitions)

  This is a breaking change - no backward compatibility.
  """

  def up do
    # 1. Rename the table
    rename table(:dictionaries), to: table(:databases)

    # 2. Add mission_id column to databases
    alter table(:databases) do
      add :mission_id, references(:missions, type: :binary_id, on_delete: :delete_all)
    end

    # 3. Migrate data: set mission_id from associated definition_sets
    # (Find a definition_set for each database and get its mission_id)
    execute """
    UPDATE databases d
    SET mission_id = (
      SELECT ds.mission_id
      FROM mdb_definition_sets ds
      WHERE ds.dictionary_id = d.id
      LIMIT 1
    )
    """

    # 4. Make mission_id required and drop organization_id
    alter table(:databases) do
      modify :mission_id, :binary_id, null: false
    end

    # Drop old organization constraint and index (use explicit old names since table was renamed)
    drop constraint(:databases, "dictionaries_organization_id_fkey")
    drop_if_exists index(:databases, [:organization_id], name: :dictionaries_organization_id_index)
    drop_if_exists index(:databases, [:organization_id, :slug], name: :dictionaries_organization_id_slug_index)

    alter table(:databases) do
      remove :organization_id
    end

    # Create new indexes
    create index(:databases, [:mission_id])
    create unique_index(:databases, [:mission_id, :slug])

    # 5. Rename dictionary_id -> database_id on definition_sets
    # First drop the old constraint and index
    drop constraint(:mdb_definition_sets, "mdb_definition_sets_dictionary_id_fkey")
    drop index(:mdb_definition_sets, [:dictionary_id])
    drop index(:mdb_definition_sets, [:dictionary_id, :version], name: :mdb_definition_sets_dictionary_version_index)

    rename table(:mdb_definition_sets), :dictionary_id, to: :database_id

    # Re-add constraint and indexes with new name
    alter table(:mdb_definition_sets) do
      modify :database_id, references(:databases, type: :binary_id, on_delete: :delete_all), null: false
    end

    create index(:mdb_definition_sets, [:database_id])
    create unique_index(:mdb_definition_sets, [:database_id, :version],
             name: :mdb_definition_sets_database_version_index)

    # 6. Remove mission_id from definition_sets (no longer needed - get via database.mission_id)
    drop index(:mdb_definition_sets, [:mission_id])

    alter table(:mdb_definition_sets) do
      remove :mission_id
    end
  end

  def down do
    # Restore mission_id to definition_sets
    alter table(:mdb_definition_sets) do
      add :mission_id, references(:missions, type: :binary_id, on_delete: :delete_all)
    end

    create index(:mdb_definition_sets, [:mission_id])

    # Populate mission_id from database
    execute """
    UPDATE mdb_definition_sets ds
    SET mission_id = (
      SELECT d.mission_id
      FROM databases d
      WHERE d.id = ds.database_id
    )
    """

    # Rename database_id -> dictionary_id
    drop constraint(:mdb_definition_sets, "mdb_definition_sets_database_id_fkey")
    drop index(:mdb_definition_sets, [:database_id])
    drop index(:mdb_definition_sets, [:database_id, :version], name: :mdb_definition_sets_database_version_index)

    rename table(:mdb_definition_sets), :database_id, to: :dictionary_id

    alter table(:mdb_definition_sets) do
      modify :dictionary_id, references(:databases, type: :binary_id, on_delete: :delete_all)
    end

    create index(:mdb_definition_sets, [:dictionary_id])
    create unique_index(:mdb_definition_sets, [:dictionary_id, :version],
             name: :mdb_definition_sets_dictionary_version_index)

    # Add organization_id back to databases
    alter table(:databases) do
      add :organization_id, references(:organizations, type: :binary_id, on_delete: :delete_all)
    end

    # Populate organization_id from mission
    execute """
    UPDATE databases d
    SET organization_id = (
      SELECT m.organization_id
      FROM missions m
      WHERE m.id = d.mission_id
    )
    """

    alter table(:databases) do
      modify :organization_id, :binary_id, null: false
      remove :mission_id
    end

    drop index(:databases, [:mission_id])
    drop index(:databases, [:mission_id, :slug])

    create index(:databases, [:organization_id])
    create unique_index(:databases, [:organization_id, :slug])

    # Rename table back
    rename table(:databases), to: table(:dictionaries)
  end
end
