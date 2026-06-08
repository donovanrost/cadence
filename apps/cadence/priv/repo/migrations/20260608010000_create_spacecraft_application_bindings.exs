defmodule Cadence.Repo.Migrations.CreateSpacecraftApplicationBindings do
  use Ecto.Migration

  def up do
    create table(:spacecraft_application_bindings, primary_key: false) do
      add(:application_binding_id, :string, primary_key: true)
      add(:organization_id, :string)
      add(:mission_id, :string, null: false)
      add(:spacecraft_id, :string, null: false)
      add(:application_key, :string, null: false)
      add(:catalog_revision_id, :string, null: false)
      add(:handled_apids, {:array, :integer}, null: false, default: [])
      add(:source_endpoint_id, :string, null: false)
      add(:enabled, :boolean, null: false, default: true)
      add(:applied_binding_set_id, :string)
      add(:applied_binding_set_version, :integer)
      add(:applied_at, :utc_datetime_usec)
      add(:metadata, :map, null: false, default: %{})

      timestamps(type: :utc_datetime_usec)
    end

    create(
      unique_index(
        :spacecraft_application_bindings,
        [:organization_id, :mission_id, :spacecraft_id, :application_key],
        name: :spacecraft_application_bindings_scope_idx
      )
    )

    create(
      index(:spacecraft_application_bindings, [:organization_id, :mission_id],
        name: :spacecraft_application_bindings_mission_idx
      )
    )

    execute("""
    ALTER TABLE spacecraft_application_bindings
    ADD CONSTRAINT spacecraft_application_bindings_spacecraft_fk
    FOREIGN KEY (organization_id, mission_id, spacecraft_id)
    REFERENCES mission_spacecraft (organization_id, mission_id, spacecraft_id)
    ON DELETE CASCADE
    """)

    execute("""
    INSERT INTO spacecraft_application_bindings (
      application_binding_id,
      organization_id,
      mission_id,
      spacecraft_id,
      application_key,
      catalog_revision_id,
      handled_apids,
      source_endpoint_id,
      enabled,
      applied_binding_set_id,
      applied_binding_set_version,
      applied_at,
      metadata,
      inserted_at,
      updated_at
    )
    SELECT
      'application_binding:' || spacecraft_id || ':telemetry_decom',
      organization_id,
      mission_id,
      spacecraft_id,
      'telemetry_decom',
      catalog_revision_id,
      handled_apids,
      source_endpoint_id,
      enabled,
      applied_binding_set_id,
      applied_binding_set_version,
      applied_at,
      metadata,
      inserted_at,
      updated_at
    FROM spacecraft_telemetry_decom_configs
    """)

    drop(table(:spacecraft_telemetry_decom_configs))
  end

  def down do
    create table(:spacecraft_telemetry_decom_configs, primary_key: false) do
      add(:spacecraft_id, :string, primary_key: true)
      add(:organization_id, :string)
      add(:mission_id, :string, null: false)
      add(:catalog_revision_id, :string, null: false)
      add(:handled_apids, {:array, :integer}, null: false, default: [])
      add(:source_endpoint_id, :string, null: false)
      add(:enabled, :boolean, null: false, default: true)
      add(:applied_binding_set_id, :string)
      add(:applied_binding_set_version, :integer)
      add(:applied_at, :utc_datetime_usec)
      add(:metadata, :map, null: false, default: %{})

      timestamps(type: :utc_datetime_usec)
    end

    create(
      index(:spacecraft_telemetry_decom_configs, [:organization_id, :mission_id],
        name: :spacecraft_telemetry_decom_configs_mission_idx
      )
    )

    execute("""
    ALTER TABLE spacecraft_telemetry_decom_configs
    ADD CONSTRAINT spacecraft_telemetry_decom_configs_spacecraft_fk
    FOREIGN KEY (organization_id, mission_id, spacecraft_id)
    REFERENCES mission_spacecraft (organization_id, mission_id, spacecraft_id)
    ON DELETE CASCADE
    """)

    execute("""
    INSERT INTO spacecraft_telemetry_decom_configs (
      spacecraft_id,
      organization_id,
      mission_id,
      catalog_revision_id,
      handled_apids,
      source_endpoint_id,
      enabled,
      applied_binding_set_id,
      applied_binding_set_version,
      applied_at,
      metadata,
      inserted_at,
      updated_at
    )
    SELECT
      spacecraft_id,
      organization_id,
      mission_id,
      catalog_revision_id,
      handled_apids,
      source_endpoint_id,
      enabled,
      applied_binding_set_id,
      applied_binding_set_version,
      applied_at,
      metadata,
      inserted_at,
      updated_at
    FROM spacecraft_application_bindings
    WHERE application_key = 'telemetry_decom'
    """)

    drop(table(:spacecraft_application_bindings))
  end
end
