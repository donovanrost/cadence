defmodule Cadence.Repo.Migrations.AddRetiredToDerivedTelemetryDefinitions do
  use Ecto.Migration

  # #77 stage 1: a derived point is retired, never deleted. Retiring appends a final version
  # marked retired; versions stay for history. Null (every existing row) is live.
  def change do
    # Evaluation reads these each run; fail fast rather than queue readers (qa).
    execute("SET LOCAL lock_timeout = '5s'", "SET LOCAL lock_timeout = '5s'")

    alter table(:governed_derived_telemetry_definitions) do
      add(:retired_at, :utc_datetime_usec, null: true)
      add(:retired_by, :string, null: true)
    end
  end
end
