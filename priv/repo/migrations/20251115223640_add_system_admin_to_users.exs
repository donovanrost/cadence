defmodule Cadence.Repo.Migrations.AddSystemAdminToUsers do
  use Ecto.Migration

  def change do
    alter table(:users) do
      add :system_admin, :boolean, default: false, null: false
    end

    # Make organization_id nullable since system admins don't belong to a single org
    # First drop the existing constraint, then modify the column
    execute "ALTER TABLE users DROP CONSTRAINT IF EXISTS users_organization_id_fkey"

    alter table(:users) do
      modify :organization_id, :binary_id, null: true, from: {:binary_id, null: false}
    end

    # Re-add the constraint with nilify_all
    execute """
    ALTER TABLE users
    ADD CONSTRAINT users_organization_id_fkey
    FOREIGN KEY (organization_id)
    REFERENCES organizations(id)
    ON DELETE SET NULL
    """
  end
end
