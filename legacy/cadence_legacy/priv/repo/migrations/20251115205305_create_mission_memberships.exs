defmodule Cadence.Repo.Migrations.CreateMissionMemberships do
  use Ecto.Migration

  def change do
    create table(:mission_memberships, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :user_id, references(:users, type: :binary_id, on_delete: :delete_all), null: false

      add :mission_id, references(:missions, type: :binary_id, on_delete: :delete_all),
        null: false

      add :role, :string, null: false, default: "viewer"

      timestamps(type: :utc_datetime)
    end

    create index(:mission_memberships, [:user_id])
    create index(:mission_memberships, [:mission_id])
    create unique_index(:mission_memberships, [:user_id, :mission_id])
  end
end
