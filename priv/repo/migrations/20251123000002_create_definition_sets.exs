defmodule Cadence.Repo.Migrations.CreateDefinitionSets do
  use Ecto.Migration

  def change do
    create table(:definition_sets, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :mission_id, references(:missions, type: :binary_id, on_delete: :delete_all), null: false

      add :version, :string, null: false
      add :description, :text

      # Source tracking
      add :source_format, :string, null: false
      add :source_filename, :string
      add :source_hash, :string

      # Lifecycle timestamps
      add :published_at, :utc_datetime
      add :superseded_at, :utc_datetime

      timestamps(type: :utc_datetime)
    end

    create index(:definition_sets, [:mission_id])
    create unique_index(:definition_sets, [:mission_id, :version])

    # Index for finding active version
    create index(:definition_sets, [:mission_id, :published_at, :superseded_at])

    # Add definition_set_id to packet_definitions
    alter table(:packet_definitions) do
      add :definition_set_id, references(:definition_sets, type: :binary_id, on_delete: :delete_all)
    end

    create index(:packet_definitions, [:definition_set_id])
    create unique_index(:packet_definitions, [:definition_set_id, :name])
  end
end
