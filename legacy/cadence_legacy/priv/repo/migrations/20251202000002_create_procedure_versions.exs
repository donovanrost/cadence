defmodule Cadence.Repo.Migrations.CreateProcedureVersions do
  use Ecto.Migration

  def change do
    create table(:procedure_versions, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :version_number, :integer, null: false
      add :source, :map, null: false
      add :parameters_schema, :map, default: %{}
      add :status, :string, null: false, default: "draft"
      add :change_summary, :text

      add :approved_at, :utc_datetime

      add :procedure_id, references(:procedures, type: :binary_id, on_delete: :delete_all),
        null: false

      add :created_by_id, references(:users, type: :binary_id, on_delete: :nilify_all)
      add :approved_by_id, references(:users, type: :binary_id, on_delete: :nilify_all)

      timestamps(type: :utc_datetime)
    end

    create index(:procedure_versions, [:procedure_id])
    create index(:procedure_versions, [:status])

    create unique_index(:procedure_versions, [:procedure_id, :version_number],
             name: :procedure_versions_procedure_version_index
           )

    # Now add the current_version_id FK to procedures
    alter table(:procedures) do
      add :current_version_id,
          references(:procedure_versions, type: :binary_id, on_delete: :nilify_all)
    end

    create index(:procedures, [:current_version_id])
  end
end
