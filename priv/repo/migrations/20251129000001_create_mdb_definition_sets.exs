defmodule Cadence.Repo.Migrations.CreateMdbDefinitionSets do
  use Ecto.Migration

  def change do
    create table(:mdb_definition_sets, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :organization_id, references(:organizations, type: :binary_id, on_delete: :delete_all), null: false
      add :mission_id, references(:missions, type: :binary_id, on_delete: :delete_all), null: false

      add :name, :string
      add :version, :string, null: false
      add :description, :text

      # Source tracking
      add :source_format, :string, null: false
      add :source_filename, :string
      add :source_hash, :string

      # Lifecycle
      add :published_at, :utc_datetime
      add :superseded_at, :utc_datetime

      # Extensions for format-specific metadata
      add :extensions, :map, default: %{}

      timestamps(type: :utc_datetime)
    end

    create index(:mdb_definition_sets, [:organization_id])
    create index(:mdb_definition_sets, [:mission_id])
    create unique_index(:mdb_definition_sets, [:mission_id, :version], name: :mdb_definition_sets_mission_version_index)
    create index(:mdb_definition_sets, [:mission_id, :published_at, :superseded_at], name: :mdb_definition_sets_active_index)
  end
end
