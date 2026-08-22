defmodule Cadence.Repo.Migrations.CreateProcedures do
  use Ecto.Migration

  def change do
    create table(:procedures, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :name, :string, null: false
      add :description, :text
      add :type, :string, null: false, default: "sequence"

      add :organization_id, references(:organizations, type: :binary_id, on_delete: :delete_all),
        null: false

      add :mission_id, references(:missions, type: :binary_id, on_delete: :delete_all)

      # current_version_id added after procedure_versions table exists
      timestamps(type: :utc_datetime)
    end

    create index(:procedures, [:organization_id])
    create index(:procedures, [:mission_id])

    create unique_index(:procedures, [:organization_id, :mission_id, :name],
             name: :procedures_org_mission_name_index
           )
  end
end
