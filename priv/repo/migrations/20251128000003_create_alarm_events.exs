defmodule Cadence.Repo.Migrations.CreateAlarmEvents do
  use Ecto.Migration

  def change do
    create table(:alarm_events, primary_key: false) do
      add :id, :binary_id, primary_key: true

      add :alarm_id, references(:alarms, type: :binary_id, on_delete: :delete_all),
        null: false

      # Who took action (nil for system-generated events)
      add :user_id, references(:users, type: :binary_id, on_delete: :nilify_all)

      # What happened
      add :event_type, :string, null: false
      # Types: "triggered", "escalated", "deescalated", "acknowledged",
      #        "cleared", "shelved", "unshelved", "value_updated"

      # State before and after (for audit trail)
      add :previous_state, :map
      add :new_state, :map

      # Optional note (e.g., acknowledgment reason)
      add :note, :text

      # The value that triggered this event (for telemetry alarms)
      add :trigger_value, :float

      timestamps(type: :utc_datetime)
    end

    create index(:alarm_events, [:alarm_id])
    create index(:alarm_events, [:user_id])
    create index(:alarm_events, [:event_type])
    create index(:alarm_events, [:inserted_at])

    # For querying event history for an alarm
    create index(:alarm_events, [:alarm_id, :inserted_at])
  end
end
