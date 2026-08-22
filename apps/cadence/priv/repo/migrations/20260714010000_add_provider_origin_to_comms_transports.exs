defmodule Cadence.Repo.Migrations.AddProviderOriginToCommsTransports do
  use Ecto.Migration

  def up do
    alter table(:comms_transports) do
      add(:origin, :string, null: false, default: "direct")
      add(:mission_provider_id, :string)
      add(:mission_provider_version, :integer)
      add(:service_profile_ref, :map)
      add(:delivery_profile_ref, :map)
      add(:provider_configuration_snapshot, :map, null: false, default: %{})
    end

    create(
      index(
        :comms_transports,
        [:mission_id, :mission_provider_id, :mission_provider_version],
        name: :comms_transports_mission_provider_idx
      )
    )

    execute("""
    ALTER TABLE comms_transports
    ADD CONSTRAINT comms_transports_mission_provider_fk
    FOREIGN KEY (mission_id, mission_provider_id, mission_provider_version)
    REFERENCES mission_providers (mission_id, provider_id, version)
    """)
  end

  def down do
    execute("""
    ALTER TABLE comms_transports
    DROP CONSTRAINT IF EXISTS comms_transports_mission_provider_fk
    """)

    drop_if_exists(
      index(
        :comms_transports,
        [:mission_id, :mission_provider_id, :mission_provider_version],
        name: :comms_transports_mission_provider_idx
      )
    )

    alter table(:comms_transports) do
      remove(:provider_configuration_snapshot)
      remove(:delivery_profile_ref)
      remove(:service_profile_ref)
      remove(:mission_provider_version)
      remove(:mission_provider_id)
      remove(:origin)
    end
  end
end
