defmodule Cadence.Repo.Migrations.AddOrganizationToUsers do
  use Ecto.Migration

  def change do
    alter table(:users) do
      add :organization_id, references(:organizations, type: :binary_id, on_delete: :delete_all),
        null: false

      add :role, :string, null: false, default: "member"
    end

    create index(:users, [:organization_id])
    create index(:users, [:organization_id, :role])
  end
end
