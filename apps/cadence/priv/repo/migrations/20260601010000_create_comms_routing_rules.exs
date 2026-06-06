defmodule Cadence.Repo.Migrations.CreateCommsRoutingRules do
  use Ecto.Migration

  def up do
    create table(:comms_routing_rules, primary_key: false) do
      add(:routing_rule_id, :string, null: false)
      add(:organization_id, :string)
      add(:mission_id, :string, null: false)
      add(:spacecraft_id, :string, null: false)
      add(:lifecycle_state, :string, null: false)
      add(:display_name, :string, null: false)
      add(:purpose_label, :string, null: false)
      add(:direction, :string, null: false)
      add(:transport_id, :string, null: false)
      add(:transport_version, :integer, null: false)
      add(:runtime_identity_policy, :string, null: false)
      add(:provider_path_ref, :string)
      add(:role, :string, null: false)
      add(:enabled, :boolean, null: false, default: true)
      add(:materialized_link_assignment_id, :string)
      add(:metadata, :map, null: false, default: %{})

      timestamps(type: :utc_datetime_usec)
    end

    create(
      unique_index(:comms_routing_rules, [:mission_id, :routing_rule_id],
        name: :comms_routing_rules_scope_idx
      )
    )

    create(
      index(:comms_routing_rules, [:organization_id, :mission_id],
        name: :comms_routing_rules_org_mission_idx
      )
    )

    create(
      index(:comms_routing_rules, [:organization_id, :mission_id, :spacecraft_id],
        name: :comms_routing_rules_spacecraft_idx
      )
    )

    create(
      index(:comms_routing_rules, [:organization_id, :mission_id, :transport_id],
        name: :comms_routing_rules_transport_idx
      )
    )

    execute("""
    ALTER TABLE comms_routing_rules
    ADD CONSTRAINT comms_routing_rules_org_mission_fk
    FOREIGN KEY (organization_id, mission_id)
    REFERENCES missions (organization_id, mission_id)
    """)

    execute("""
    CREATE TRIGGER sync_organization_id_from_mission
    BEFORE INSERT OR UPDATE OF mission_id, organization_id ON comms_routing_rules
    FOR EACH ROW
    EXECUTE FUNCTION cadence_sync_organization_id_from_mission()
    """)

    create table(:comms_routing_rule_events, primary_key: false) do
      add(:routing_rule_event_id, :string, null: false, primary_key: true)
      add(:organization_id, :string)
      add(:mission_id, :string, null: false)
      add(:routing_rule_id, :string, null: false)
      add(:event_type, :string, null: false)
      add(:actor_id, :string)
      add(:occurred_at, :utc_datetime_usec, null: false)
      add(:payload, :map, null: false, default: %{})
    end

    create(
      index(:comms_routing_rule_events, [:organization_id, :mission_id, :routing_rule_id],
        name: :comms_routing_rule_events_rule_idx
      )
    )

    execute("""
    ALTER TABLE comms_routing_rule_events
    ADD CONSTRAINT comms_routing_rule_events_org_mission_fk
    FOREIGN KEY (organization_id, mission_id)
    REFERENCES missions (organization_id, mission_id)
    """)

    execute("""
    CREATE TRIGGER sync_organization_id_from_mission
    BEFORE INSERT OR UPDATE OF mission_id, organization_id ON comms_routing_rule_events
    FOR EACH ROW
    EXECUTE FUNCTION cadence_sync_organization_id_from_mission()
    """)
  end

  def down do
    execute("""
    DROP TRIGGER IF EXISTS sync_organization_id_from_mission ON comms_routing_rule_events
    """)

    execute("""
    ALTER TABLE comms_routing_rule_events
    DROP CONSTRAINT IF EXISTS comms_routing_rule_events_org_mission_fk
    """)

    drop_if_exists(
      index(:comms_routing_rule_events, [:organization_id, :mission_id, :routing_rule_id],
        name: :comms_routing_rule_events_rule_idx
      )
    )

    drop(table(:comms_routing_rule_events))

    execute("""
    DROP TRIGGER IF EXISTS sync_organization_id_from_mission ON comms_routing_rules
    """)

    execute("""
    ALTER TABLE comms_routing_rules
    DROP CONSTRAINT IF EXISTS comms_routing_rules_org_mission_fk
    """)

    drop_if_exists(
      index(:comms_routing_rules, [:organization_id, :mission_id, :transport_id],
        name: :comms_routing_rules_transport_idx
      )
    )

    drop_if_exists(
      index(:comms_routing_rules, [:organization_id, :mission_id, :spacecraft_id],
        name: :comms_routing_rules_spacecraft_idx
      )
    )

    drop_if_exists(
      index(:comms_routing_rules, [:organization_id, :mission_id],
        name: :comms_routing_rules_org_mission_idx
      )
    )

    drop_if_exists(
      index(:comms_routing_rules, [:mission_id, :routing_rule_id],
        name: :comms_routing_rules_scope_idx
      )
    )

    drop(table(:comms_routing_rules))
  end
end
