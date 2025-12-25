defmodule Cadence.Repo.Migrations.AddConfigGenerationToMissions do
  use Ecto.Migration

  def change do
    alter table(:missions) do
      add :config_generation, :integer, default: 1, null: false
    end

    # Create index for efficient lookup of missions by generation
    create index(:missions, [:config_generation])
  end
end
