defmodule Cadence.Repo.Migrations.CreateBookingResolutions do
  use Ecto.Migration

  # DECISIONS #53/#54: an operator's resolution of an unconfirmed booking (one per plan item),
  # which is also its audit entry, plus an open-conflict state that feeds the attention read.
  # Pass fields are copied from the reservation so the read needs no joins.
  def change do
    create table(:booking_resolutions, primary_key: false) do
      add(:booking_resolution_id, :string, primary_key: true)
      add(:organization_id, :string, null: false)
      add(:mission_id, :string, null: false)
      add(:contact_plan_id, :string, null: false)
      add(:contact_plan_version, :integer, null: false)
      add(:contact_plan_execution_item_id, :string, null: false)
      add(:provider_reservation_id, :string, null: false)
      add(:provider_contact_ref, :string)
      add(:scheduled_contact_id, :string)
      add(:spacecraft_id, :string, null: false)
      add(:ground_station_ref, :string)
      add(:provider_id, :string, null: false)
      add(:starts_at, :utc_datetime_usec, null: false)
      add(:ends_at, :utc_datetime_usec, null: false)
      add(:action, :string, null: false)
      add(:outcome, :string, null: false)
      add(:provider_reference, :string)
      add(:note, :text, null: false)
      add(:actor_document, :map, null: false)
      add(:provider_answer_document, :map, null: false, default: %{})
      add(:conflict, :string)
      add(:conflict_state, :string)
      add(:conflict_document, :map, null: false, default: %{})
      add(:conflict_raised_at, :utc_datetime_usec)
      add(:conflict_acknowledged_at, :utc_datetime_usec)
      add(:conflict_acknowledged_by, :map)
      add(:conflict_resolved_at, :utc_datetime_usec)
      add(:conflict_resolved_by, :map)
      add(:conflict_resolution_action, :string)
      timestamps(type: :utc_datetime_usec)
    end

    create(unique_index(:booking_resolutions, [:contact_plan_execution_item_id]))

    create(index(:booking_resolutions, [:organization_id, :mission_id, :provider_reservation_id]))

    create(
      index(:booking_resolutions, [:organization_id, :mission_id, :starts_at],
        where: "conflict_state IN ('open', 'acknowledged')",
        name: :booking_resolutions_conflicts_idx
      )
    )
  end
end
