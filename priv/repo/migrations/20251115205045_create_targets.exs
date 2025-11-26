defmodule Cadence.Repo.Migrations.CreateTargets do
  use Ecto.Migration

  def change do
    create table(:targets, primary_key: false) do
      add :id, :binary_id, primary_key: true

      add :mission_id, references(:missions, type: :binary_id, on_delete: :delete_all),
        null: false

      add :name, :string, null: false
      add :identifier, :string, null: false
      add :type, :string, null: false
      add :status, :string, null: false, default: "offline"

      # Target-specific configuration
      add :config, :map, default: %{}
      add :metadata, :map, default: %{}

      # Command safety
      add :circuit_breaker_status, :string, default: "closed"
      add :circuit_breaker_failures, :integer, default: 0
      add :circuit_breaker_opened_at, :utc_datetime

      timestamps(type: :utc_datetime)
    end

    create index(:targets, [:mission_id])
    create unique_index(:targets, [:mission_id, :identifier])
    create index(:targets, [:status])
    create index(:targets, [:circuit_breaker_status])
  end
end
