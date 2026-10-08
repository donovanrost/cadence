defmodule Cadence.Repo.Migrations.CreateContactScheduleOperations do
  use Ecto.Migration

  def change do
    create table(:contact_schedule_operations, primary_key: false) do
      add(:operation_id, :uuid, primary_key: true)
      add(:organization_id, :string, null: false)
      add(:user_id, :string, null: false)
      add(:mission_id, :string, null: false)
      add(:action, :string, null: false)
      add(:input, :map, null: false)
      add(:reservation_id, :string, null: false)
      add(:status, :string, null: false)
      add(:revision, :integer, null: false)
      add(:result, :map)
      add(:admin_mode, :boolean, null: false, default: false)
      timestamps(type: :utc_datetime_usec)
    end

    create(
      index(:contact_schedule_operations, [:organization_id, :user_id, :mission_id, :inserted_at])
    )

    create(
      unique_index(:contact_schedule_operations, [:organization_id, :mission_id, :reservation_id],
        name: :contact_schedule_unresolved_reservation,
        where: "status IN ('accepted', 'unconfirmed')"
      )
    )

    create(
      constraint(:contact_schedule_operations, :contact_schedule_operation_state,
        check:
          "status IN ('accepted', 'unconfirmed', 'completed', 'rejected') AND revision > 0 AND action IN ('reserve', 'cancel')"
      )
    )
  end
end
