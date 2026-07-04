defmodule Cadence.Repo.Migrations.AddDashboardPointersToOpsDashboards do
  use Ecto.Migration

  def change do
    alter table(:ops_dashboards) do
      add(:latest_version, :integer)
      add(:draft_version, :integer)
      add(:published_version, :integer)
      add(:lifecycle_state, :string, null: false, default: "active")
      add(:published_at, :utc_datetime_usec)
      add(:published_by, :string)
    end
  end
end
