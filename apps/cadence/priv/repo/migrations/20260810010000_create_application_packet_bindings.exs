defmodule Cadence.Repo.Migrations.CreateApplicationPacketBindings do
  use Ecto.Migration

  def change do
    create table(:application_packet_binding_configurations, primary_key: false) do
      add(:packet_binding_configuration_id, :string, primary_key: true)
      add(:organization_id, :string, null: false)
      add(:mission_id, :string, null: false)
      add(:spacecraft_id, :string)
      add(:application_installation_id, :string, null: false)
      add(:application_key, :string, null: false)
      add(:application_version, :integer, null: false)
      add(:capability_family_key, :string, null: false)
      add(:input_id, :string, null: false)
      add(:input_version, :integer, null: false)
      add(:configuration_version, :integer, null: false, default: 1)
      add(:enabled, :boolean, null: false, default: true)
      add(:applied_binding_set_id, :string)
      add(:applied_binding_set_version, :integer)
      add(:applied_at, :utc_datetime_usec)
      add(:metadata, :map, null: false, default: %{})

      timestamps(type: :utc_datetime_usec)
    end

    create(
      unique_index(
        :application_packet_binding_configurations,
        [:application_installation_id, :input_id, :input_version],
        name: :application_packet_binding_configurations_input_idx
      )
    )

    create(
      index(:application_packet_binding_configurations, [:organization_id, :mission_id],
        name: :application_packet_binding_configurations_mission_idx
      )
    )

    create(
      constraint(
        :application_packet_binding_configurations,
        :application_packet_binding_configurations_versions_check,
        check: "application_version > 0 AND input_version > 0 AND configuration_version > 0"
      )
    )

    execute(
      """
      ALTER TABLE application_packet_binding_configurations
      ADD CONSTRAINT application_packet_binding_configurations_installation_fk
      FOREIGN KEY (application_installation_id)
      REFERENCES application_installations (application_installation_id)
      ON DELETE CASCADE
      """,
      """
      ALTER TABLE application_packet_binding_configurations
      DROP CONSTRAINT application_packet_binding_configurations_installation_fk
      """
    )

    execute(
      """
      ALTER TABLE application_packet_binding_configurations
      ADD CONSTRAINT application_packet_binding_configurations_mission_fk
      FOREIGN KEY (organization_id, mission_id)
      REFERENCES missions (organization_id, mission_id)
      ON DELETE CASCADE
      """,
      """
      ALTER TABLE application_packet_binding_configurations
      DROP CONSTRAINT application_packet_binding_configurations_mission_fk
      """
    )

    execute(
      """
      ALTER TABLE application_packet_binding_configurations
      ADD CONSTRAINT application_packet_binding_configurations_spacecraft_fk
      FOREIGN KEY (organization_id, mission_id, spacecraft_id)
      REFERENCES mission_spacecraft (organization_id, mission_id, spacecraft_id)
      ON DELETE CASCADE
      """,
      """
      ALTER TABLE application_packet_binding_configurations
      DROP CONSTRAINT application_packet_binding_configurations_spacecraft_fk
      """
    )

    create table(:application_packet_bindings, primary_key: false) do
      add(:packet_binding_id, :string, primary_key: true)
      add(:packet_binding_configuration_id, :string, null: false)
      add(:source_endpoint_ref, :string)
      add(:catalog_revision_id, :string)
      add(:telemetry_snapshot_id, :string)
      add(:packet_id, :string)
      add(:packet_model_content_sha256, :string)
      add(:packet_name, :string, null: false)
      add(:apid, :integer, null: false)
      add(:selector, :map, null: false, default: %{})
      add(:metadata, :map, null: false, default: %{})

      timestamps(type: :utc_datetime_usec)
    end

    create(
      index(:application_packet_bindings, [:packet_binding_configuration_id],
        name: :application_packet_bindings_configuration_idx
      )
    )

    create(
      constraint(:application_packet_bindings, :application_packet_bindings_apid_check,
        check: "apid >= 0 AND apid <= 2047"
      )
    )

    execute(
      """
      ALTER TABLE application_packet_bindings
      ADD CONSTRAINT application_packet_bindings_configuration_fk
      FOREIGN KEY (packet_binding_configuration_id)
      REFERENCES application_packet_binding_configurations (packet_binding_configuration_id)
      ON DELETE CASCADE
      """,
      """
      ALTER TABLE application_packet_bindings
      DROP CONSTRAINT application_packet_bindings_configuration_fk
      """
    )

    create table(:application_packet_binding_resources, primary_key: false) do
      add(:packet_binding_resource_id, :string, primary_key: true)
      add(:packet_binding_id, :string, null: false)
      add(:resource_id, :string, null: false)
      add(:resource_kind, :string, null: false)
      add(:path, :string)
      add(:data_type, :string)
      add(:offset_bits, :integer)
      add(:size_bits, :integer)
      add(:role, :string, null: false)
      add(:metadata, :map, null: false, default: %{})

      timestamps(type: :utc_datetime_usec)
    end

    create(
      unique_index(:application_packet_binding_resources, [:packet_binding_id, :resource_id],
        name: :application_packet_binding_resources_identity_idx
      )
    )

    create(
      constraint(:application_packet_binding_resources, :application_packet_resources_kind_check,
        check: "resource_kind IN ('whole_packet', 'field', 'binary_region')"
      )
    )

    create(
      constraint(:application_packet_binding_resources, :application_packet_resources_role_check,
        check: "role IN ('primary', 'context')"
      )
    )

    execute(
      """
      ALTER TABLE application_packet_binding_resources
      ADD CONSTRAINT application_packet_binding_resources_binding_fk
      FOREIGN KEY (packet_binding_id)
      REFERENCES application_packet_bindings (packet_binding_id)
      ON DELETE CASCADE
      """,
      """
      ALTER TABLE application_packet_binding_resources
      DROP CONSTRAINT application_packet_binding_resources_binding_fk
      """
    )
  end
end
