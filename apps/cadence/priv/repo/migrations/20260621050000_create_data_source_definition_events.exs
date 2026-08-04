defmodule Cadence.Repo.Migrations.CreateDataSourceDefinitionEvents do
  use Ecto.Migration

  def up do
    create table(:data_source_definition_events, primary_key: false) do
      add(:data_source_event_id, :string, primary_key: true)
      add(:data_source_id, :string, null: false)
      add(:organization_id, :string)
      add(:mission_id, :string)
      add(:event_type, :string, null: false)
      add(:previous_owner, :string)
      add(:current_owner, :string, null: false)
      add(:previous_kind, :string)
      add(:current_kind, :string, null: false)
      add(:previous_adapter, :string)
      add(:current_adapter, :string)
      add(:previous_isolation_level, :string)
      add(:current_isolation_level, :string, null: false)
      add(:previous_credentials_ref, :string)
      add(:current_credentials_ref, :string)
      add(:previous_capabilities, :map)
      add(:current_capabilities, :map, null: false, default: %{})
      add(:previous_metadata, :map)
      add(:current_metadata, :map, null: false, default: %{})
      add(:actor_id, :string)
      add(:occurred_at, :utc_datetime_usec, null: false)
      add(:payload, :map, null: false, default: %{})

      timestamps(type: :utc_datetime_usec, updated_at: false)
    end

    create(
      index(:data_source_definition_events, [:data_source_id, :occurred_at],
        name: :data_source_definition_events_source_time_idx
      )
    )

    create(
      index(:data_source_definition_events, [:organization_id, :mission_id, :event_type],
        name: :data_source_definition_events_scope_type_idx
      )
    )

    execute("""
    ALTER TABLE data_source_definition_events
    ADD CONSTRAINT data_source_definition_events_source_fk
    FOREIGN KEY (data_source_id)
    REFERENCES data_source_definitions (data_source_id)
    """)

    execute("""
    ALTER TABLE data_source_definition_events
    ADD CONSTRAINT data_source_definition_events_org_fk
    FOREIGN KEY (organization_id)
    REFERENCES organizations (organization_id)
    """)

    execute("""
    ALTER TABLE data_source_definition_events
    ADD CONSTRAINT data_source_definition_events_org_mission_fk
    FOREIGN KEY (organization_id, mission_id)
    REFERENCES missions (organization_id, mission_id)
    """)
  end

  def down do
    execute("""
    ALTER TABLE data_source_definition_events
    DROP CONSTRAINT IF EXISTS data_source_definition_events_org_mission_fk
    """)

    execute("""
    ALTER TABLE data_source_definition_events
    DROP CONSTRAINT IF EXISTS data_source_definition_events_org_fk
    """)

    execute("""
    ALTER TABLE data_source_definition_events
    DROP CONSTRAINT IF EXISTS data_source_definition_events_source_fk
    """)

    drop_if_exists(
      index(:data_source_definition_events, [:organization_id, :mission_id, :event_type],
        name: :data_source_definition_events_scope_type_idx
      )
    )

    drop_if_exists(
      index(:data_source_definition_events, [:data_source_id, :occurred_at],
        name: :data_source_definition_events_source_time_idx
      )
    )

    drop(table(:data_source_definition_events))
  end
end
