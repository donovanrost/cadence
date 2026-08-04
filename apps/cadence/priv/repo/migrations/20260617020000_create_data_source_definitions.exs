defmodule Cadence.Repo.Migrations.CreateDataSourceDefinitions do
  use Ecto.Migration

  def up do
    create table(:data_source_definitions, primary_key: false) do
      add(:data_source_id, :string, primary_key: true)
      add(:owner, :string, null: false)
      add(:kind, :string, null: false)
      add(:adapter, :string)
      add(:organization_id, :string)
      add(:mission_id, :string)
      add(:isolation_level, :string, null: false)
      add(:capabilities, :map, null: false, default: %{})
      add(:metadata, :map, null: false, default: %{})

      timestamps(type: :utc_datetime_usec)
    end

    create(
      index(:data_source_definitions, [:organization_id, :mission_id],
        name: :data_source_definitions_org_mission_idx
      )
    )

    execute("""
    ALTER TABLE data_source_definitions
    ADD CONSTRAINT data_source_definitions_org_fk
    FOREIGN KEY (organization_id)
    REFERENCES organizations (organization_id)
    """)

    execute("""
    ALTER TABLE data_source_definitions
    ADD CONSTRAINT data_source_definitions_org_mission_fk
    FOREIGN KEY (organization_id, mission_id)
    REFERENCES missions (organization_id, mission_id)
    """)

    create table(:data_source_bindings, primary_key: false) do
      add(:binding_id, :string, primary_key: true)
      add(:organization_id, :string)
      add(:mission_id, :string)
      add(:realm, :string, null: false)
      add(:logical_source, :string, null: false)
      add(:data_source_id, :string, null: false)
      add(:dataset, :string)
      add(:priority, :integer, null: false, default: 0)
      add(:active_from, :utc_datetime_usec)
      add(:active_to, :utc_datetime_usec)
      add(:metadata, :map, null: false, default: %{})

      timestamps(type: :utc_datetime_usec)
    end

    create(
      index(:data_source_bindings, [:organization_id, :mission_id, :realm, :logical_source],
        name: :data_source_bindings_resolution_idx
      )
    )

    create(
      index(:data_source_bindings, [:data_source_id], name: :data_source_bindings_data_source_idx)
    )

    execute("""
    ALTER TABLE data_source_bindings
    ADD CONSTRAINT data_source_bindings_data_source_fk
    FOREIGN KEY (data_source_id)
    REFERENCES data_source_definitions (data_source_id)
    """)

    execute("""
    ALTER TABLE data_source_bindings
    ADD CONSTRAINT data_source_bindings_org_fk
    FOREIGN KEY (organization_id)
    REFERENCES organizations (organization_id)
    """)

    execute("""
    ALTER TABLE data_source_bindings
    ADD CONSTRAINT data_source_bindings_org_mission_fk
    FOREIGN KEY (organization_id, mission_id)
    REFERENCES missions (organization_id, mission_id)
    """)
  end

  def down do
    execute("""
    ALTER TABLE data_source_bindings
    DROP CONSTRAINT IF EXISTS data_source_bindings_org_mission_fk
    """)

    execute("""
    ALTER TABLE data_source_bindings
    DROP CONSTRAINT IF EXISTS data_source_bindings_org_fk
    """)

    execute("""
    ALTER TABLE data_source_bindings
    DROP CONSTRAINT IF EXISTS data_source_bindings_data_source_fk
    """)

    drop_if_exists(
      index(:data_source_bindings, [:data_source_id], name: :data_source_bindings_data_source_idx)
    )

    drop_if_exists(
      index(:data_source_bindings, [:organization_id, :mission_id, :realm, :logical_source],
        name: :data_source_bindings_resolution_idx
      )
    )

    drop(table(:data_source_bindings))

    execute("""
    ALTER TABLE data_source_definitions
    DROP CONSTRAINT IF EXISTS data_source_definitions_org_mission_fk
    """)

    execute("""
    ALTER TABLE data_source_definitions
    DROP CONSTRAINT IF EXISTS data_source_definitions_org_fk
    """)

    drop_if_exists(
      index(:data_source_definitions, [:organization_id, :mission_id],
        name: :data_source_definitions_org_mission_idx
      )
    )

    drop(table(:data_source_definitions))
  end
end
