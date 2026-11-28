defmodule Cadence.Repo.Migrations.AddSourceEndpointRelay do
  use Ecto.Migration

  def change do
    alter table(:mission_source_endpoints) do
      add(:relay, :map)
    end
  end
end
