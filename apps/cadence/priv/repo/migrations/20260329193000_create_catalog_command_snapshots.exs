defmodule Cadence.Repo.Migrations.CreateCatalogCommandSnapshots do
  use Ecto.Migration

  def change do
    create table(:catalog_command_snapshots, primary_key: false) do
      add(:snapshot_id, :string, primary_key: true)
      add(:organization_id, :string)
      add(:mission_id, references(:missions, column: :mission_id, type: :string), null: false)

      add(:artifact_id, references(:catalog_artifacts, column: :artifact_id, type: :string),
        null: false
      )

      add(
        :import_run_id,
        references(:catalog_import_runs, column: :import_run_id, type: :string),
        null: false
      )

      add(:importer_key, :string, null: false)
      add(:snapshot_name, :string, null: false)
      add(:snapshot_version, :string)
      add(:description, :string)
      add(:published_at, :utc_datetime_usec)
      add(:superseded_at, :utc_datetime_usec)
      add(:command_count, :integer, null: false, default: 0)
      add(:argument_count, :integer, null: false, default: 0)
      add(:argument_type_count, :integer, null: false, default: 0)
      add(:encoding_layout_count, :integer, null: false, default: 0)
      add(:snapshot_document, :map, null: false, default: %{"value" => %{}})

      timestamps(type: :utc_datetime_usec, updated_at: false)
    end

    create(unique_index(:catalog_command_snapshots, [:import_run_id]))
    create(index(:catalog_command_snapshots, [:organization_id, :mission_id]))
    create(index(:catalog_command_snapshots, [:mission_id, :artifact_id, :inserted_at]))
    create(index(:catalog_command_snapshots, [:mission_id, :snapshot_name, :inserted_at]))

    create table(:catalog_revisions, primary_key: false) do
      add(:catalog_revision_id, :string, primary_key: true)
      add(:organization_id, :string)
      add(:mission_id, references(:missions, column: :mission_id, type: :string), null: false)

      add(
        :catalog_database_id,
        references(:catalog_databases, column: :catalog_database_id, type: :string),
        null: false
      )

      add(:revision_number, :integer, null: false)
      add(:revision_label, :string, null: false)
      add(:catalog_family, :string, null: false)

      add(
        :artifact_id,
        references(:catalog_artifacts, column: :artifact_id, type: :string),
        null: false
      )

      add(
        :import_run_id,
        references(:catalog_import_runs, column: :import_run_id, type: :string),
        null: false
      )

      add(
        :telemetry_snapshot_id,
        references(:catalog_telemetry_snapshots, column: :snapshot_id, type: :string)
      )

      add(
        :command_snapshot_id,
        references(:catalog_command_snapshots, column: :snapshot_id, type: :string)
      )

      add(:content_sha256, :string, null: false)
      add(:created_by, :map, null: false, default: %{})
      add(:notes, :string)
      add(:metadata, :map, null: false, default: %{})

      timestamps(type: :utc_datetime_usec, updated_at: false)
    end

    create(index(:catalog_revisions, [:organization_id, :mission_id, :catalog_database_id]))
    create(index(:catalog_revisions, [:artifact_id]))

    create(
      unique_index(:catalog_revisions, [:import_run_id], name: :catalog_revisions_import_run_idx)
    )

    create(
      unique_index(:catalog_revisions, [:catalog_database_id, :revision_number],
        name: :catalog_revisions_database_number_idx
      )
    )

    create(
      unique_index(:catalog_revisions, [:catalog_database_id, :revision_label],
        name: :catalog_revisions_database_label_idx
      )
    )
  end
end
