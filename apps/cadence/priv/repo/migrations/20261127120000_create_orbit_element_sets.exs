defmodule Cadence.Repo.Migrations.CreateOrbitElementSets do
  use Ecto.Migration

  # #889 (slice 1 of #732, DECISIONS #114): each spacecraft's orbit as SGP4 mean elements, from an
  # OMM or a TLE. Rows are immutable and history is kept; the current set is the newest epoch. The
  # natural key (mission, spacecraft, epoch, content hash) makes a re-send idempotent. Identity
  # columns are bytewise (#949).
  def up do
    create table(:orbit_element_sets, primary_key: false) do
      add(:element_set_id, :text, primary_key: true, collation: "C")
      add(:organization_id, :text, null: false, collation: "C")
      add(:mission_id, :text, null: false, collation: "C")
      add(:spacecraft_id, :text, null: false, collation: "C")
      add(:format, :text, null: false)
      add(:source, :text, null: false)
      add(:raw, :text, null: false)
      add(:object_name, :text)
      add(:norad_id, :integer)
      add(:element_set_number, :integer)
      add(:epoch, :utc_datetime_usec, null: false)
      add(:mean_motion, :float, null: false)
      add(:eccentricity, :float, null: false)
      add(:inclination_deg, :float, null: false)
      add(:raan_deg, :float, null: false)
      add(:arg_perigee_deg, :float, null: false)
      add(:mean_anomaly_deg, :float, null: false)
      add(:bstar, :float, null: false)
      add(:mean_motion_dot, :float, null: false)
      add(:mean_motion_ddot, :float, null: false)
      add(:content_sha256, :text, null: false)
      add(:received_at, :utc_datetime_usec, null: false)
      add(:created_by, :map, null: false)
    end

    create(
      constraint(:orbit_element_sets, :orbit_element_sets_format_check,
        check: "format IN ('omm', 'tle')"
      )
    )

    create(
      constraint(:orbit_element_sets, :orbit_element_sets_source_check,
        check: "source IN ('manual', 'api')"
      )
    )

    create(
      constraint(:orbit_element_sets, :orbit_element_sets_elements_check,
        check: "eccentricity >= 0 AND eccentricity < 1 AND mean_motion > 0"
      )
    )

    create(
      unique_index(
        :orbit_element_sets,
        [:mission_id, :spacecraft_id, :epoch, :content_sha256],
        name: :orbit_element_sets_natural_key
      )
    )

    # History newest first, and the current set is its first row.
    execute("""
    CREATE INDEX orbit_element_sets_history_idx
    ON orbit_element_sets (mission_id, spacecraft_id, epoch DESC, element_set_id DESC)
    """)

    execute("""
    ALTER TABLE orbit_element_sets
    ADD CONSTRAINT orbit_element_sets_org_mission_fk
    FOREIGN KEY (organization_id, mission_id)
    REFERENCES missions (organization_id, mission_id)
    """)

    execute("""
    ALTER TABLE orbit_element_sets
    ADD CONSTRAINT orbit_element_sets_spacecraft_fk
    FOREIGN KEY (organization_id, mission_id, spacecraft_id)
    REFERENCES mission_spacecraft (organization_id, mission_id, spacecraft_id)
    ON DELETE CASCADE
    """)

    execute("""
    CREATE TRIGGER sync_organization_id_from_mission
    BEFORE INSERT OR UPDATE OF mission_id, organization_id ON orbit_element_sets
    FOR EACH ROW
    EXECUTE FUNCTION cadence_sync_organization_id_from_mission()
    """)
  end

  def down do
    drop(table(:orbit_element_sets))
  end
end
