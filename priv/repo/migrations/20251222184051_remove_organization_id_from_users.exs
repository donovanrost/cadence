defmodule Cadence.Repo.Migrations.RemoveOrganizationIdFromUsers do
  @moduledoc """
  Removes the deprecated organization_id field from users.

  Users now belong to organizations via organization_memberships table,
  which supports multi-org membership. This migration removes the legacy
  single-org field.
  """
  use Ecto.Migration

  def change do
    drop index(:users, [:organization_id])
    drop index(:users, [:organization_id, :role])

    alter table(:users) do
      remove :organization_id, references(:organizations, type: :binary_id)
    end
  end
end
