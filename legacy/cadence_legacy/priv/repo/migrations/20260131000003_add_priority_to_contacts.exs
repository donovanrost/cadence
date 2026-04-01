defmodule Cadence.Repo.Migrations.AddPriorityToContacts do
  use Ecto.Migration

  def change do
    alter table(:contacts) do
      add :priority, :integer, null: false, default: 0
    end

    create index(:contacts, [:mission_id, :ground_station_target_id, :antenna_id, :start_time])
    create index(:contacts, [:mission_id, :spacecraft_target_id, :start_time])
  end
end
