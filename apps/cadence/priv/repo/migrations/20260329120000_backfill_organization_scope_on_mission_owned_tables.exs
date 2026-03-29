defmodule Cadence.Repo.Migrations.BackfillOrganizationScopeOnMissionOwnedTables do
  use Ecto.Migration

  @mission_owned_tables [
    :mission_active_binding_sets,
    :background_jobs,
    :mission_binding_set_activations,
    :governed_binding_sets,
    :combined_downlink_records,
    :contact_actions,
    :derived_telemetry_evaluation_runs,
    :derived_telemetry_latest_value_rebuild_runs,
    :derived_telemetry_latest_values,
    :derived_telemetry_samples,
    :downlink_diagnostics,
    :downlink_observations,
    :governed_derived_telemetry_definitions,
    :governed_limit_definitions,
    :governed_packet_definitions,
    :managed_action_requests,
    :managed_capability_records,
    :managed_timer_events,
    :mission_event_rebuild_runs,
    :mission_events,
    :protocol_packet_records,
    :ingress_raw_evidence,
    :realized_contacts,
    :replay_managed_action_requests,
    :replay_managed_capability_records,
    :replay_managed_timer_events,
    :replay_runs,
    :replay_telemetry_samples,
    :scheduled_contacts,
    :mission_source_endpoints,
    :telemetry_latest_limit_state_rebuild_runs,
    :telemetry_latest_limit_states,
    :telemetry_latest_value_rebuild_runs,
    :telemetry_latest_values,
    :telemetry_limit_evaluation_runs,
    :telemetry_limit_events,
    :telemetry_samples,
    :transport_action_requests,
    :transport_capability_records,
    :transport_timer_events
  ]

  def up do
    create(
      unique_index(:missions, [:organization_id, :mission_id], name: :missions_org_mission_idx)
    )

    flush()

    execute("""
    CREATE OR REPLACE FUNCTION cadence_sync_organization_id_from_mission()
    RETURNS trigger AS $$
    BEGIN
      IF NEW.mission_id IS NULL OR NEW.organization_id IS NOT NULL THEN
        RETURN NEW;
      END IF;

      SELECT missions.organization_id
      INTO NEW.organization_id
      FROM missions
      WHERE missions.mission_id = NEW.mission_id;

      RETURN NEW;
    END;
    $$ LANGUAGE plpgsql;
    """)

    Enum.each(@mission_owned_tables, fn table ->
      alter table(table) do
        add(:organization_id, :string)
      end
    end)

    flush()

    Enum.each(@mission_owned_tables, fn table ->
      execute("""
      UPDATE #{table}
      SET organization_id = missions.organization_id
      FROM missions
      WHERE #{table}.mission_id = missions.mission_id
        AND #{table}.organization_id IS NULL
      """)

      execute("""
      ALTER TABLE #{table}
      ADD CONSTRAINT #{org_mission_fk_name(table)}
      FOREIGN KEY (organization_id, mission_id)
      REFERENCES missions (organization_id, mission_id)
      """)

      execute("""
      CREATE TRIGGER sync_organization_id_from_mission
      BEFORE INSERT OR UPDATE OF mission_id, organization_id ON #{table}
      FOR EACH ROW
      EXECUTE FUNCTION cadence_sync_organization_id_from_mission()
      """)
    end)

    execute("""
    ALTER TABLE service_identities
    ADD CONSTRAINT #{org_mission_fk_name(:service_identities)}
    FOREIGN KEY (organization_id, mission_id)
    REFERENCES missions (organization_id, mission_id)
    """)
  end

  def down do
    execute("""
    ALTER TABLE service_identities
    DROP CONSTRAINT IF EXISTS #{org_mission_fk_name(:service_identities)}
    """)

    Enum.each(@mission_owned_tables, fn table ->
      execute("""
      DROP TRIGGER IF EXISTS sync_organization_id_from_mission ON #{table}
      """)

      execute("""
      ALTER TABLE #{table}
      DROP CONSTRAINT IF EXISTS #{org_mission_fk_name(table)}
      """)
    end)

    Enum.each(@mission_owned_tables, fn table ->
      alter table(table) do
        remove(:organization_id)
      end
    end)

    flush()

    execute("DROP FUNCTION IF EXISTS cadence_sync_organization_id_from_mission()")

    drop_if_exists(
      index(:missions, [:organization_id, :mission_id], name: :missions_org_mission_idx)
    )
  end

  defp org_mission_fk_name(table) do
    "#{table}_org_mission_fk"
  end
end
