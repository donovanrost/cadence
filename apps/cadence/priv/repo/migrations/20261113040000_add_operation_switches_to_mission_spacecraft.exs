defmodule Cadence.Repo.Migrations.AddOperationSwitchesToMissionSpacecraft do
  use Ecto.Migration

  # L22: commanding and telemetry switches become change-set fields. Null (every existing row)
  # means "as the spacecraft's configuration has it"; once a change set sets one, the change set
  # is its one writer and the configuration is derived from it.
  def change do
    # mission_spacecraft is read constantly; fail fast (and retry) rather than queue every
    # reader behind the ALTER's lock (qa, 2026-11-13).
    execute("SET LOCAL lock_timeout = '5s'", "SET LOCAL lock_timeout = '5s'")

    alter table(:mission_spacecraft) do
      add(:commanding_enabled, :boolean, null: true)
      add(:telemetry_enabled, :boolean, null: true)
    end
  end
end
