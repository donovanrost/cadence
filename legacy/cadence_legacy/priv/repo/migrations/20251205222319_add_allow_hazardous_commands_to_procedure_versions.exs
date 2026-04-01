defmodule Cadence.Repo.Migrations.AddAllowHazardousCommandsToProcedureVersions do
  use Ecto.Migration

  def change do
    alter table(:procedure_versions) do
      add :allow_hazardous_commands, :boolean, default: false, null: false
    end
  end
end
