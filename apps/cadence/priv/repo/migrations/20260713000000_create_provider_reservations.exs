defmodule Cadence.Repo.Migrations.CreateProviderReservations do
  use Ecto.Migration

  def change do
    create table(:provider_reservations, primary_key: false) do
      add(:provider_reservation_id, :string, primary_key: true)
      add(:organization_id, :string, null: false)
      add(:mission_id, :string, null: false)
      add(:provider_profile_id, :string, null: false)
      add(:provider_profile_version, :integer, null: false)
      add(:scheduled_contact_id, :string, null: false)
      add(:provider_opportunity_ref, :string, null: false)
      add(:provider_contact_ref, :string)
      add(:idempotency_key, :string, null: false)
      add(:lifecycle_state, :string, null: false)
      add(:provider_status, :string)
      add(:spacecraft_id, :string, null: false)
      add(:provider_spacecraft_ref, :string, null: false)
      add(:source_endpoint_refs, {:array, :string}, null: false, default: [])
      add(:path_template_ids, {:array, :string}, null: false, default: [])
      add(:starts_at, :utc_datetime_usec, null: false)
      add(:ends_at, :utc_datetime_usec, null: false)
      add(:request_document, :map, null: false, default: %{})
      add(:response_document, :map, null: false, default: %{})
      add(:last_error_document, :map, null: false, default: %{})
      add(:attempt_count, :integer, null: false, default: 0)
      add(:last_reconciled_at, :utc_datetime_usec)
      add(:metadata, :map, null: false, default: %{})

      timestamps(type: :utc_datetime_usec)
    end

    create(
      unique_index(:provider_reservations, [:mission_id, :provider_reservation_id],
        name: :provider_reservations_scope_idx
      )
    )

    create(
      unique_index(
        :provider_reservations,
        [:mission_id, :provider_profile_id, :idempotency_key],
        name: :provider_reservations_idempotency_idx
      )
    )

    create(
      unique_index(:provider_reservations, [:mission_id, :provider_contact_ref],
        name: :provider_reservations_provider_ref_idx,
        where: "provider_contact_ref IS NOT NULL"
      )
    )

    create(
      index(
        :provider_reservations,
        [:organization_id, :mission_id, :lifecycle_state, :last_reconciled_at],
        name: :provider_reservations_reconciliation_idx
      )
    )

    create(
      index(
        :provider_reservations,
        [:organization_id, :mission_id, :scheduled_contact_id],
        name: :provider_reservations_contact_idx
      )
    )
  end
end
