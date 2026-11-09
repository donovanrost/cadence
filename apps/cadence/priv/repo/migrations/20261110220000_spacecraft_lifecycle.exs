defmodule Cadence.Repo.Migrations.SpacecraftLifecycle do
  use Ecto.Migration

  # #49/#50: spacecraft can be archived (rollback of a creation with traffic). Additive: every
  # existing spacecraft is active.
  def change do
    alter table(:mission_spacecraft) do
      add(:lifecycle_state, :string, null: false, default: "active")
      add(:archived_at, :utc_datetime_usec)
      add(:archived_by, :map)
    end

    create(index(:mission_spacecraft, [:mission_id, :lifecycle_state]))

    create(
      constraint(:mission_spacecraft, :mission_spacecraft_lifecycle_check,
        check: "lifecycle_state IN ('active','archived')"
      )
    )
  end
end
