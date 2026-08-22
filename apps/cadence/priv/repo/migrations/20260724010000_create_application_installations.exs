defmodule Cadence.Repo.Migrations.CreateApplicationInstallations do
  use Ecto.Migration

  def up do
    alter table(:spacecraft_application_bindings) do
      add(:configuration_version, :integer, null: false, default: 1)
    end

    create(
      constraint(
        :spacecraft_application_bindings,
        :spacecraft_application_bindings_config_version_check,
        check: "configuration_version > 0"
      )
    )

    create table(:application_installations, primary_key: false) do
      add(:application_installation_id, :string, primary_key: true)
      add(:organization_id, :string, null: false)
      add(:mission_id, :string, null: false)
      add(:scope_kind, :string, null: false)
      add(:scope_id, :string, null: false)
      add(:spacecraft_id, :string)
      add(:application_key, :string, null: false)
      add(:application_version, :integer, null: false)
      add(:configuration_kind, :string)
      add(:configuration_id, :string)
      add(:configuration_version, :integer)
      add(:lifecycle_state, :string, null: false)
      add(:metadata, :map, null: false, default: %{})

      timestamps(type: :utc_datetime_usec)
    end

    create(
      unique_index(
        :application_installations,
        [:organization_id, :mission_id, :scope_kind, :scope_id, :application_key],
        name: :application_installations_scope_idx
      )
    )

    create(
      index(:application_installations, [:organization_id, :mission_id, :scope_kind, :scope_id],
        name: :application_installations_host_scope_idx
      )
    )

    create(
      constraint(:application_installations, :application_installations_scope_kind_check,
        check: "scope_kind IN ('mission', 'spacecraft')"
      )
    )

    create(
      constraint(:application_installations, :application_installations_scope_ref_check,
        check: """
        (scope_kind = 'mission' AND scope_id = mission_id AND spacecraft_id IS NULL)
        OR
        (scope_kind = 'spacecraft' AND scope_id = spacecraft_id AND spacecraft_id IS NOT NULL)
        """
      )
    )

    create(
      constraint(:application_installations, :application_installations_lifecycle_state_check,
        check: "lifecycle_state IN ('installed', 'disabled')"
      )
    )

    create(
      constraint(:application_installations, :application_installations_version_check,
        check: "application_version > 0"
      )
    )

    create(
      constraint(:application_installations, :application_installations_configuration_ref_check,
        check: """
        (configuration_kind IS NULL AND configuration_id IS NULL AND configuration_version IS NULL)
        OR
        (configuration_kind IS NOT NULL AND configuration_id IS NOT NULL AND configuration_version > 0)
        """
      )
    )

    execute("""
    ALTER TABLE application_installations
    ADD CONSTRAINT application_installations_mission_fk
    FOREIGN KEY (organization_id, mission_id)
    REFERENCES missions (organization_id, mission_id)
    ON DELETE CASCADE
    """)

    execute("""
    ALTER TABLE application_installations
    ADD CONSTRAINT application_installations_spacecraft_fk
    FOREIGN KEY (organization_id, mission_id, spacecraft_id)
    REFERENCES mission_spacecraft (organization_id, mission_id, spacecraft_id)
    ON DELETE CASCADE
    """)

    create table(:application_installation_events, primary_key: false) do
      add(:application_installation_event_id, :string, primary_key: true)
      add(:application_installation_id, :string, null: false)
      add(:organization_id, :string, null: false)
      add(:mission_id, :string, null: false)
      add(:scope_kind, :string, null: false)
      add(:scope_id, :string, null: false)
      add(:application_key, :string, null: false)
      add(:event_type, :string, null: false)
      add(:previous_lifecycle_state, :string)
      add(:current_lifecycle_state, :string, null: false)
      add(:previous_application_version, :integer)
      add(:current_application_version, :integer, null: false)
      add(:previous_configuration_version, :integer)
      add(:current_configuration_version, :integer)
      add(:actor_id, :string, null: false)
      add(:occurred_at, :utc_datetime_usec, null: false)
      add(:payload, :map, null: false, default: %{})

      timestamps(type: :utc_datetime_usec, updated_at: false)
    end

    create(
      index(:application_installation_events, [:application_installation_id, :occurred_at],
        name: :application_installation_events_installation_idx
      )
    )

    create(
      constraint(:application_installation_events, :application_installation_events_type_check,
        check:
          "event_type IN ('installed', 'enabled', 'disabled', 'application_upgraded', 'configuration_updated')"
      )
    )

    execute("""
    ALTER TABLE application_installation_events
    ADD CONSTRAINT application_installation_events_installation_fk
    FOREIGN KEY (application_installation_id)
    REFERENCES application_installations (application_installation_id)
    ON DELETE CASCADE
    """)

    execute("""
    INSERT INTO application_installations (
      application_installation_id,
      organization_id,
      mission_id,
      scope_kind,
      scope_id,
      spacecraft_id,
      application_key,
      application_version,
      configuration_kind,
      configuration_id,
      configuration_version,
      lifecycle_state,
      metadata,
      inserted_at,
      updated_at
    )
    SELECT
      'application_installation:' || spacecraft_id || ':telemetry_decom',
      organization_id,
      mission_id,
      'spacecraft',
      spacecraft_id,
      spacecraft_id,
      application_key,
      1,
      'spacecraft_application_binding',
      application_binding_id,
      configuration_version,
      'installed',
      '{"value": {}}'::jsonb,
      inserted_at,
      updated_at
    FROM spacecraft_application_bindings
    WHERE application_key = 'telemetry_decom'
    ON CONFLICT DO NOTHING
    """)

    execute("""
    INSERT INTO application_installation_events (
      application_installation_event_id,
      application_installation_id,
      organization_id,
      mission_id,
      scope_kind,
      scope_id,
      application_key,
      event_type,
      current_lifecycle_state,
      current_application_version,
      current_configuration_version,
      actor_id,
      occurred_at,
      payload,
      inserted_at
    )
    SELECT
      'application_installation_event:' || spacecraft_id || ':telemetry_decom:migrated',
      'application_installation:' || spacecraft_id || ':telemetry_decom',
      organization_id,
      mission_id,
      'spacecraft',
      spacecraft_id,
      application_key,
      'installed',
      'installed',
      1,
      configuration_version,
      'system:migration',
      updated_at,
      '{"value": {"source": "spacecraft_application_binding"}}'::jsonb,
      updated_at
    FROM spacecraft_application_bindings
    WHERE application_key = 'telemetry_decom'
    ON CONFLICT DO NOTHING
    """)
  end

  def down do
    drop(table(:application_installation_events))

    execute("""
    ALTER TABLE application_installations
    DROP CONSTRAINT IF EXISTS application_installations_spacecraft_fk
    """)

    execute("""
    ALTER TABLE application_installations
    DROP CONSTRAINT IF EXISTS application_installations_mission_fk
    """)

    drop(table(:application_installations))

    drop(
      constraint(
        :spacecraft_application_bindings,
        :spacecraft_application_bindings_config_version_check
      )
    )

    alter table(:spacecraft_application_bindings) do
      remove(:configuration_version)
    end
  end
end
