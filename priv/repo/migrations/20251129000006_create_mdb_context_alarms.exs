defmodule Cadence.Repo.Migrations.CreateMdbContextAlarms do
  use Ecto.Migration

  def change do
    create table(:mdb_context_alarms, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :data_type_id, references(:mdb_data_types, type: :binary_id, on_delete: :delete_all), null: false

      # Condition that activates this alarm set (embedded JSON)
      add :match_criteria, :map, null: false

      # The alarm definition when this context is active (embedded JSON)
      # Same structure as DataType.default_alarm
      add :alarm_definition, :map, null: false

      # Priority (lower = higher priority, evaluated in order)
      add :priority, :integer, default: 0

      timestamps(type: :utc_datetime)
    end

    create index(:mdb_context_alarms, [:data_type_id])
  end
end
