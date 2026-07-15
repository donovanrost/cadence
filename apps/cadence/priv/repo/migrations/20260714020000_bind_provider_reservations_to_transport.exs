defmodule Cadence.Repo.Migrations.BindProviderReservationsToTransport do
  use Ecto.Migration

  def up do
    alter table(:provider_reservations) do
      add(:provider_id, :string)
      add(:provider_version, :integer)
      add(:transport_id, :string)
      add(:transport_version, :integer)
      add(:service_profile_ref, :map, null: false, default: %{})
      add(:delivery_profile_ref, :map, null: false, default: %{})
      add(:delivery_descriptor_document, :map, null: false, default: %{})
      add(:pass_phase, :string)
      add(:delivery_state, :string)
    end

    create(
      unique_index(
        :provider_reservations,
        [:mission_id, :provider_id, :idempotency_key],
        name: :provider_reservations_provider_idempotency_idx,
        where: "provider_id IS NOT NULL"
      )
    )

    create(
      index(
        :provider_reservations,
        [:mission_id, :transport_id, :transport_version],
        name: :provider_reservations_transport_idx
      )
    )

    execute("""
    ALTER TABLE provider_reservations
    ADD CONSTRAINT provider_reservations_mission_provider_fk
    FOREIGN KEY (mission_id, provider_id, provider_version)
    REFERENCES mission_providers (mission_id, provider_id, version)
    """)

    execute("""
    ALTER TABLE provider_reservations
    ADD CONSTRAINT provider_reservations_transport_fk
    FOREIGN KEY (mission_id, transport_id, transport_version)
    REFERENCES comms_transports (mission_id, transport_id, version)
    """)
  end

  def down do
    execute("""
    ALTER TABLE provider_reservations
    DROP CONSTRAINT IF EXISTS provider_reservations_transport_fk
    """)

    execute("""
    ALTER TABLE provider_reservations
    DROP CONSTRAINT IF EXISTS provider_reservations_mission_provider_fk
    """)

    drop_if_exists(
      index(
        :provider_reservations,
        [:mission_id, :transport_id, :transport_version],
        name: :provider_reservations_transport_idx
      )
    )

    drop_if_exists(
      index(
        :provider_reservations,
        [:mission_id, :provider_id, :idempotency_key],
        name: :provider_reservations_provider_idempotency_idx
      )
    )

    alter table(:provider_reservations) do
      remove(:delivery_state)
      remove(:pass_phase)
      remove(:delivery_descriptor_document)
      remove(:delivery_profile_ref)
      remove(:service_profile_ref)
      remove(:transport_version)
      remove(:transport_id)
      remove(:provider_version)
      remove(:provider_id)
    end
  end
end
