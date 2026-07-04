defmodule Cadence.Repo.Migrations.AddLockVersionToOpsDashboards do
  use Ecto.Migration

  def change do
    alter table(:ops_dashboards) do
      add(:lock_version, :integer, null: false, default: 1)
    end
  end
end
