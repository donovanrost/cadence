defmodule Cadence.Repo.Migrations.CreateContactRequirements do
  use Ecto.Migration

  def up do
    create table(:contact_requirements, primary_key: false) do
      add(:contact_requirement_id, :string, primary_key: true)
      add(:organization_id, :string, null: false)
      add(:mission_id, :string, null: false)
      add(:current_version, :integer, null: false)
      add(:lifecycle_state, :string, null: false)
      add(:created_by, :string, null: false)
      add(:lifecycle_changed_by, :string, null: false)
      add(:lifecycle_changed_at, :utc_datetime_usec, null: false)
      add(:lifecycle_reason, :text, null: false, default: "")

      timestamps(type: :utc_datetime_usec)
    end

    create(
      unique_index(
        :contact_requirements,
        [:organization_id, :mission_id, :contact_requirement_id],
        name: :contact_requirements_scope_idx
      )
    )

    create(
      index(:contact_requirements, [:organization_id, :mission_id, :lifecycle_state],
        name: :contact_requirements_mission_state_idx
      )
    )

    create(
      constraint(:contact_requirements, :contact_requirements_current_version_positive,
        check: "current_version > 0"
      )
    )

    create(
      constraint(:contact_requirements, :contact_requirements_lifecycle_state_check,
        check: "lifecycle_state IN ('active', 'closed', 'canceled')"
      )
    )

    execute("""
    ALTER TABLE contact_requirements
    ADD CONSTRAINT contact_requirements_scope_uniq
    UNIQUE USING INDEX contact_requirements_scope_idx
    """)

    execute("""
    ALTER TABLE contact_requirements
    ADD CONSTRAINT contact_requirements_mission_fk
    FOREIGN KEY (organization_id, mission_id)
    REFERENCES missions (organization_id, mission_id)
    """)

    create table(:contact_requirement_versions, primary_key: false) do
      add(:contact_requirement_version_id, :string, primary_key: true)
      add(:contact_requirement_id, :string, null: false)
      add(:organization_id, :string, null: false)
      add(:mission_id, :string, null: false)
      add(:version, :integer, null: false)
      add(:spacecraft_id, :string, null: false)
      add(:service_direction, :string, null: false)
      add(:contact_intent, :string, null: false)
      add(:earliest_start, :utc_datetime_usec, null: false)
      add(:latest_end, :utc_datetime_usec, null: false)
      add(:success_measure, :string, null: false)
      add(:minimum_duration_seconds, :integer)
      add(:preferred_duration_seconds, :integer)
      add(:minimum_data_volume_bytes, :bigint)
      add(:contact_count, :integer, null: false, default: 1)
      add(:minimum_separation_seconds, :integer, null: false, default: 0)
      add(:priority, :string, null: false, default: "routine")
      add(:provider_constraints_document, :map, null: false, default: %{})
      add(:station_constraints_document, :map, null: false, default: %{})
      add(:policy_constraints_document, :map, null: false, default: %{})
      add(:approval_policy_document, :map, null: false, default: %{"mode" => "manual"})
      add(:rationale, :text, null: false, default: "")
      add(:metadata, :map, null: false, default: %{})
      add(:content_sha256, :string, null: false)
      add(:created_by, :string, null: false)
      add(:created_at, :utc_datetime_usec, null: false)
    end

    create(
      unique_index(
        :contact_requirement_versions,
        [:organization_id, :mission_id, :contact_requirement_id, :version],
        name: :contact_requirement_versions_scope_idx
      )
    )

    create(
      index(
        :contact_requirement_versions,
        [:organization_id, :mission_id, :spacecraft_id, :earliest_start, :latest_end],
        name: :contact_requirement_versions_horizon_idx
      )
    )

    create(
      constraint(
        :contact_requirement_versions,
        :contact_requirement_versions_positive_values,
        check:
          "version > 0 AND contact_count > 0 AND minimum_separation_seconds >= 0 AND " <>
            "(minimum_duration_seconds IS NULL OR minimum_duration_seconds > 0) AND " <>
            "(preferred_duration_seconds IS NULL OR preferred_duration_seconds > 0) AND " <>
            "(minimum_data_volume_bytes IS NULL OR minimum_data_volume_bytes > 0)"
      )
    )

    create(
      constraint(
        :contact_requirement_versions,
        :contact_requirement_versions_time_range,
        check: "earliest_start < latest_end"
      )
    )

    create(
      constraint(
        :contact_requirement_versions,
        :contact_requirement_versions_duration_order,
        check:
          "preferred_duration_seconds IS NULL OR minimum_duration_seconds IS NULL OR " <>
            "preferred_duration_seconds >= minimum_duration_seconds"
      )
    )

    create(
      constraint(
        :contact_requirement_versions,
        :contact_requirement_versions_direction_check,
        check: "service_direction IN ('downlink', 'uplink', 'bidirectional', 'tracking')"
      )
    )

    create(
      constraint(
        :contact_requirement_versions,
        :contact_requirement_versions_success_measure_check,
        check:
          "success_measure IN ('any_contact', 'minimum_duration', 'minimum_data_volume', 'contact_count') AND " <>
            "(success_measure <> 'minimum_duration' OR minimum_duration_seconds IS NOT NULL) AND " <>
            "(success_measure <> 'minimum_data_volume' OR minimum_data_volume_bytes IS NOT NULL)"
      )
    )

    create(
      constraint(:contact_requirement_versions, :contact_requirement_versions_priority_check,
        check: "priority IN ('routine', 'high', 'critical')"
      )
    )

    execute("""
    ALTER TABLE contact_requirement_versions
    ADD CONSTRAINT contact_requirement_versions_scope_uniq
    UNIQUE USING INDEX contact_requirement_versions_scope_idx
    """)

    execute("""
    ALTER TABLE contact_requirement_versions
    ADD CONSTRAINT contact_requirement_versions_requirement_fk
    FOREIGN KEY (organization_id, mission_id, contact_requirement_id)
    REFERENCES contact_requirements (organization_id, mission_id, contact_requirement_id)
    """)

    execute("""
    ALTER TABLE contact_requirement_versions
    ADD CONSTRAINT contact_requirement_versions_spacecraft_fk
    FOREIGN KEY (organization_id, mission_id, spacecraft_id)
    REFERENCES mission_spacecraft (organization_id, mission_id, spacecraft_id)
    """)

    execute("""
    ALTER TABLE contact_requirements
    ADD CONSTRAINT contact_requirements_current_version_fk
    FOREIGN KEY (organization_id, mission_id, contact_requirement_id, current_version)
    REFERENCES contact_requirement_versions (
      organization_id, mission_id, contact_requirement_id, version
    )
    DEFERRABLE INITIALLY DEFERRED
    """)
  end

  def down do
    execute("""
    ALTER TABLE contact_requirements
    DROP CONSTRAINT IF EXISTS contact_requirements_current_version_fk
    """)

    drop(table(:contact_requirement_versions))
    drop(table(:contact_requirements))
  end
end
