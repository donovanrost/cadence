defmodule Cadence.Repo.Migrations.CreateMissions do
  use Ecto.Migration

  def change do
    create table(:missions, primary_key: false) do
      add :id, :binary_id, primary_key: true

      add :organization_id, references(:organizations, type: :binary_id, on_delete: :delete_all),
        null: false

      add :name, :string, null: false
      add :slug, :string, null: false
      add :description, :text
      add :status, :string, null: false, default: "inactive"

      # Mission phase (planning, testing, operational, decommissioned)
      add :phase, :string, null: false, default: "planning"

      # Configuration
      add :config, :map, default: %{}
      add :metadata, :map, default: %{}

      # Operational windows
      add :start_date, :utc_datetime
      add :end_date, :utc_datetime

      timestamps(type: :utc_datetime)
    end

    create index(:missions, [:organization_id])
    create unique_index(:missions, [:organization_id, :slug])
    create index(:missions, [:status])
    create index(:missions, [:phase])
  end
end
