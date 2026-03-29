defmodule Cadence.Repo.Migrations.CreateCatalogCommandSnapshots do
  use Ecto.Migration

  def change do
    create table(:catalog_command_snapshots, primary_key: false) do
      add :snapshot_id, :string, primary_key: true
      add :organization_id, :string
      add :mission_id, references(:missions, column: :mission_id, type: :string), null: false
      add :artifact_id, references(:catalog_artifacts, column: :artifact_id, type: :string),
        null: false

      add :import_run_id,
          references(:catalog_import_runs, column: :import_run_id, type: :string),
          null: false

      add :importer_key, :string, null: false
      add :snapshot_name, :string, null: false
      add :snapshot_version, :string
      add :description, :string
      add :published_at, :utc_datetime_usec
      add :superseded_at, :utc_datetime_usec
      add :command_count, :integer, null: false, default: 0
      add :argument_count, :integer, null: false, default: 0
      add :argument_type_count, :integer, null: false, default: 0
      add :encoding_layout_count, :integer, null: false, default: 0
      add :snapshot_document, :map, null: false, default: %{"value" => %{}}

      timestamps(type: :utc_datetime_usec, updated_at: false)
    end

    create unique_index(:catalog_command_snapshots, [:import_run_id])
    create index(:catalog_command_snapshots, [:organization_id, :mission_id])
    create index(:catalog_command_snapshots, [:mission_id, :artifact_id, :inserted_at])
    create index(:catalog_command_snapshots, [:mission_id, :snapshot_name, :inserted_at])
  end
end
