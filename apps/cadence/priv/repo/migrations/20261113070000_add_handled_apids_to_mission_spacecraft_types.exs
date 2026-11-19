defmodule Cadence.Repo.Migrations.AddHandledApidsToMissionSpacecraftTypes do
  use Ecto.Migration

  # L22: a profile's handled APIDs, next to its catalog. Null (every existing profile) means
  # "all of the catalog's APIDs", expanded at apply; a change it causes is shown as a HOLD.
  def change do
    # Profiles are read on every fleet build; fail fast rather than queue readers (qa).
    execute("SET LOCAL lock_timeout = '5s'", "SET LOCAL lock_timeout = '5s'")

    alter table(:mission_spacecraft_types) do
      add(:handled_apids, {:array, :integer}, null: true)
    end
  end
end
