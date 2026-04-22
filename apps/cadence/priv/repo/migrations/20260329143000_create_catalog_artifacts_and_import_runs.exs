defmodule Cadence.Repo.Migrations.CreateCatalogArtifactsAndImportRuns do
  use Ecto.Migration

  def change do
    create table(:catalog_databases, primary_key: false) do
      add(:catalog_database_id, :string, primary_key: true)
      add(:organization_id, :string)
      add(:mission_id, references(:missions, column: :mission_id, type: :string), null: false)
      add(:name, :string, null: false)
      add(:slug, :string, null: false)
      add(:description, :string)
      add(:catalog_family, :string, null: false)
      add(:default_importer_key, :string)
      add(:created_by, :map, null: false, default: %{})
      add(:metadata, :map, null: false, default: %{})

      timestamps(type: :utc_datetime_usec)
    end

    create(index(:catalog_databases, [:organization_id, :mission_id]))

    create(
      unique_index(:catalog_databases, [:organization_id, :mission_id, :slug],
        name: :catalog_databases_mission_slug_idx
      )
    )

    create(index(:catalog_databases, [:organization_id, :mission_id, :catalog_family]))

    create table(:catalog_artifacts, primary_key: false) do
      add(:artifact_id, :string, primary_key: true)
      add(:organization_id, :string)
      add(:mission_id, references(:missions, column: :mission_id, type: :string), null: false)

      add(
        :catalog_database_id,
        references(:catalog_databases, column: :catalog_database_id, type: :string)
      )

      add(:catalog_family, :string, null: false)
      add(:artifact_name, :string, null: false)
      add(:format_key, :string, null: false)
      add(:format_version, :string)
      add(:media_type, :string)
      add(:source_artifact, :map, null: false)
      add(:content_sha256, :string, null: false)
      add(:uploaded_by, :map, null: false, default: %{})
      add(:uploaded_at, :utc_datetime_usec, null: false)
      add(:metadata, :map, null: false, default: %{})

      timestamps(type: :utc_datetime_usec, updated_at: false)
    end

    create(index(:catalog_artifacts, [:organization_id, :mission_id]))
    create(index(:catalog_artifacts, [:mission_id, :catalog_database_id]))
    create(index(:catalog_artifacts, [:mission_id, :catalog_family, :uploaded_at]))
    create(index(:catalog_artifacts, [:mission_id, :content_sha256]))

    create table(:catalog_import_runs, primary_key: false) do
      add(:import_run_id, :string, primary_key: true)
      add(:organization_id, :string)
      add(:mission_id, references(:missions, column: :mission_id, type: :string), null: false)

      add(
        :catalog_database_id,
        references(:catalog_databases, column: :catalog_database_id, type: :string)
      )

      add(:artifact_id, references(:catalog_artifacts, column: :artifact_id, type: :string),
        null: false
      )

      add(:catalog_family, :string, null: false)
      add(:importer_key, :string, null: false)
      add(:status, :string, null: false)
      add(:imported_definition_count, :integer, null: false, default: 0)
      add(:diagnostics, :map, null: false, default: %{"items" => []})
      add(:result_document, :map, null: false, default: %{"value" => %{}})
      add(:failure_reason, :map)
      add(:requested_by, :map, null: false, default: %{})
      add(:metadata, :map, null: false, default: %{})
      add(:started_at, :utc_datetime_usec, null: false)
      add(:completed_at, :utc_datetime_usec)

      timestamps(type: :utc_datetime_usec, updated_at: false)
    end

    create(index(:catalog_import_runs, [:organization_id, :mission_id]))
    create(index(:catalog_import_runs, [:mission_id, :catalog_database_id, :started_at]))
    create(index(:catalog_import_runs, [:mission_id, :artifact_id, :started_at]))
    create(index(:catalog_import_runs, [:mission_id, :status, :started_at]))
    create(index(:catalog_import_runs, [:mission_id, :importer_key, :started_at]))
  end
end
