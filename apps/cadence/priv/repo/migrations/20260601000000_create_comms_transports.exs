defmodule Cadence.Repo.Migrations.CreateCommsTransports do
  use Ecto.Migration

  def up do
    create table(:comms_transports, primary_key: false) do
      add(:transport_id, :string, null: false)
      add(:organization_id, :string)
      add(:mission_id, :string, null: false)
      add(:version, :integer, null: false)
      add(:lifecycle_state, :string, null: false)
      add(:display_name, :string, null: false)
      add(:transport_kind, :string, null: false)
      add(:direction_capability, :string, null: false)
      add(:adapter_key, :string, null: false)
      add(:configuration, :map, null: false, default: %{})
      add(:materialized_provider_profile_id, :string)
      add(:metadata, :map, null: false, default: %{})

      timestamps(type: :utc_datetime_usec, updated_at: false)
    end

    create(
      unique_index(:comms_transports, [:mission_id, :transport_id, :version],
        name: :comms_transports_scope_idx
      )
    )

    create(
      index(:comms_transports, [:organization_id, :mission_id],
        name: :comms_transports_org_mission_idx
      )
    )

    create(
      index(:comms_transports, [:mission_id, :materialized_provider_profile_id],
        name: :comms_transports_provider_profile_idx
      )
    )

    execute("""
    ALTER TABLE comms_transports
    ADD CONSTRAINT comms_transports_org_mission_fk
    FOREIGN KEY (organization_id, mission_id)
    REFERENCES missions (organization_id, mission_id)
    """)

    execute("""
    CREATE TRIGGER sync_organization_id_from_mission
    BEFORE INSERT OR UPDATE OF mission_id, organization_id ON comms_transports
    FOR EACH ROW
    EXECUTE FUNCTION cadence_sync_organization_id_from_mission()
    """)
  end

  def down do
    execute("""
    DROP TRIGGER IF EXISTS sync_organization_id_from_mission ON comms_transports
    """)

    execute("""
    ALTER TABLE comms_transports
    DROP CONSTRAINT IF EXISTS comms_transports_org_mission_fk
    """)

    drop_if_exists(
      index(:comms_transports, [:mission_id, :materialized_provider_profile_id],
        name: :comms_transports_provider_profile_idx
      )
    )

    drop_if_exists(
      index(:comms_transports, [:organization_id, :mission_id],
        name: :comms_transports_org_mission_idx
      )
    )

    drop_if_exists(
      index(:comms_transports, [:mission_id, :transport_id, :version],
        name: :comms_transports_scope_idx
      )
    )

    drop(table(:comms_transports))
  end
end
