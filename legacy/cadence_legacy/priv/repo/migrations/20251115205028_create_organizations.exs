defmodule Cadence.Repo.Migrations.CreateOrganizations do
  use Ecto.Migration

  def change do
    create table(:organizations, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :name, :string, null: false
      add :slug, :string, null: false
      add :status, :string, null: false, default: "active"
      add :subscription_tier, :string, null: false, default: "free"

      # Quotas and limits
      add :max_missions, :integer, default: 5
      add :max_targets_per_mission, :integer, default: 10
      add :max_users, :integer, default: 10
      add :storage_quota_gb, :integer, default: 10

      # Metadata
      add :settings, :map, default: %{}
      add :metadata, :map, default: %{}

      timestamps(type: :utc_datetime)
    end

    create unique_index(:organizations, [:slug])
    create index(:organizations, [:status])
  end
end
