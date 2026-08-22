defmodule Cadence.Repo.Migrations.AddDocumentToOpsDashboards do
  use Ecto.Migration

  def change do
    alter table(:ops_dashboards) do
      add(:document, :map, null: false, default: %{})
    end
  end
end
