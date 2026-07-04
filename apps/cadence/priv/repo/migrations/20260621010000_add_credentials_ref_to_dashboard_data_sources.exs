defmodule Cadence.Repo.Migrations.AddCredentialsRefToDashboardDataSources do
  use Ecto.Migration

  def change do
    alter table(:dashboard_data_sources) do
      add(:credentials_ref, :string)
    end
  end
end
