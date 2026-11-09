defmodule Cadence.Repo.Migrations.ProfileRouting do
  use Ecto.Migration

  # Profile-level routing (docs/apogee/domain/profile-routing.md, DECISIONS #3). Schema only:
  # existing per-spacecraft rules are marked `legacy` and are lifted into profile rules by a
  # reviewable change set, not by this migration.
  def up do
    alter table(:comms_ground_stations) do
      add(:code, :string)
    end

    # Short station codes from the name ("Svalbard (Demo)" -> "SVA"), de-duplicated per mission.
    execute("""
    WITH base AS (
      SELECT ground_station_id, mission_id,
             upper(left(regexp_replace(display_name, '[^A-Za-z]', '', 'g'), 3)) AS stem
      FROM comms_ground_stations
    ), numbered AS (
      SELECT ground_station_id, mission_id, stem,
             row_number() OVER (PARTITION BY mission_id, stem ORDER BY ground_station_id) AS n
      FROM base
    )
    UPDATE comms_ground_stations s
    SET code = CASE WHEN numbered.n = 1 THEN numbered.stem ELSE numbered.stem || numbered.n END
    FROM numbered
    WHERE s.ground_station_id = numbered.ground_station_id AND s.mission_id = numbered.mission_id
      AND numbered.stem <> ''
    """)

    create(
      unique_index(:comms_ground_stations, [:mission_id, :code],
        where: "code IS NOT NULL AND lifecycle_state = 'active'",
        name: :comms_ground_stations_code_idx
      )
    )

    alter table(:comms_transports) do
      add(:ground_station_id, :string)
    end

    execute("""
    UPDATE comms_transports
    SET ground_station_id = metadata->'value'->>'ground_station_id'
    WHERE metadata->'value'->>'ground_station_id' IS NOT NULL
    """)

    alter table(:mission_spacecraft_types) do
      add(:catalog_revision_id, :string)
      add(:routing_rules, {:array, :map}, null: false, default: [])
    end

    create table(:spacecraft_config_overrides, primary_key: false) do
      add(:mission_id, :string, primary_key: true)
      add(:spacecraft_id, :string, primary_key: true)
      add(:path, :string, primary_key: true)
      add(:organization_id, :string)
      add(:value, :map, null: false)
      add(:reason, :text)
      add(:set_by, :map)
      add(:set_in_revision, :integer)
      add(:set_at, :utc_datetime_usec, null: false)
    end

    execute("""
    ALTER TABLE spacecraft_config_overrides
    ADD CONSTRAINT spacecraft_config_overrides_org_mission_fk
    FOREIGN KEY (organization_id, mission_id) REFERENCES missions (organization_id, mission_id)
    """)

    execute("""
    CREATE TRIGGER sync_organization_id_from_mission
    BEFORE INSERT OR UPDATE OF mission_id, organization_id ON spacecraft_config_overrides
    FOR EACH ROW EXECUTE FUNCTION cadence_sync_organization_id_from_mission()
    """)

    alter table(:comms_routing_rules) do
      add(:id, :bigserial, primary_key: true)
      add(:origin, :string, null: false, default: "legacy")
      add(:profile_rule_id, :string)
      add(:spacecraft_type_id, :string)
      add(:spacecraft_type_version, :integer)
      add(:ground_station_id, :string)
      add(:leg_direction, :string)
    end

    create(
      unique_index(
        :comms_routing_rules,
        [:mission_id, :spacecraft_id, :profile_rule_id, :ground_station_id, :leg_direction],
        where: "origin = 'profile'",
        name: :comms_routing_rules_profile_route_idx
      )
    )
  end

  def down do
    drop_if_exists(index(:comms_routing_rules, [], name: :comms_routing_rules_profile_route_idx))

    alter table(:comms_routing_rules) do
      remove(:leg_direction)
      remove(:ground_station_id)
      remove(:spacecraft_type_version)
      remove(:spacecraft_type_id)
      remove(:profile_rule_id)
      remove(:origin)
      remove(:id)
    end

    drop(table(:spacecraft_config_overrides))

    alter table(:mission_spacecraft_types) do
      remove(:routing_rules)
      remove(:catalog_revision_id)
    end

    alter table(:comms_transports) do
      remove(:ground_station_id)
    end

    drop_if_exists(index(:comms_ground_stations, [], name: :comms_ground_stations_code_idx))

    alter table(:comms_ground_stations) do
      remove(:code)
    end
  end
end
