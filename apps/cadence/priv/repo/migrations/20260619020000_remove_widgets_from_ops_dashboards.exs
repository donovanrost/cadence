defmodule Cadence.Repo.Migrations.RemoveWidgetsFromOpsDashboards do
  use Ecto.Migration

  def change do
    alter table(:ops_dashboards) do
      remove(:widgets, :map, null: false, default: %{})
    end
  end
end
