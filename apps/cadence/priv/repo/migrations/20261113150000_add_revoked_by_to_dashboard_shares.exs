defmodule Cadence.Repo.Migrations.AddRevokedByToDashboardShares do
  use Ecto.Migration

  # D20: who revoked a share ("Revoked by Mira K."). Null for shares revoked before this.
  def change do
    execute("SET LOCAL lock_timeout = '5s'", "SET LOCAL lock_timeout = '5s'")

    alter table(:dashboard_shares) do
      add(:revoked_by, :string, null: true)
    end
  end
end
