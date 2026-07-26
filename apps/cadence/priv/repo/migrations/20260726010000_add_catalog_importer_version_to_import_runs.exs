defmodule Cadence.Repo.Migrations.AddCatalogImporterVersionToImportRuns do
  use Ecto.Migration

  def change do
    alter table(:catalog_import_runs) do
      add(:importer_version, :integer, null: false, default: 1)
    end
  end
end
