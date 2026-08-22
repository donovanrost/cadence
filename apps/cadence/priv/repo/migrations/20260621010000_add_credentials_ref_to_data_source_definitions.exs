defmodule Cadence.Repo.Migrations.AddCredentialsRefToDataSourceDefinitions do
  use Ecto.Migration

  def change do
    alter table(:data_source_definitions) do
      add(:credentials_ref, :string)
    end
  end
end
