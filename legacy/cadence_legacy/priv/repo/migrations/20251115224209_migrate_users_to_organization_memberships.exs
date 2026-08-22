defmodule Cadence.Repo.Migrations.MigrateUsersToOrganizationMemberships do
  use Ecto.Migration
  import Ecto.Query

  def up do
    # For all existing non-system-admin users, create organization membership
    # based on their organization_id and role fields
    execute """
    INSERT INTO organization_memberships (id, user_id, organization_id, role, inserted_at, updated_at)
    SELECT
      gen_random_uuid() AS id,
      id AS user_id,
      organization_id,
      role,
      NOW() AS inserted_at,
      NOW() AS updated_at
    FROM users
    WHERE organization_id IS NOT NULL
    AND system_admin = false
    """
  end

  def down do
    # Remove all organization memberships
    execute "DELETE FROM organization_memberships"
  end
end
