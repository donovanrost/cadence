defmodule Cadence.Repo.Migrations.CreateDashboardDataSourceEvents do
  use Ecto.Migration

  def up do
    create table(:dashboard_data_source_events, primary_key: false) do
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
      index(:dashboard_data_source_events, [:data_source_id, :occurred_at],
        name: :dashboard_data_source_events_source_time_idx
      )
    )

    create(
      index(:dashboard_data_source_events, [:organization_id, :mission_id, :event_type],
        name: :dashboard_data_source_events_scope_type_idx
      )
    )

    execute("""
    ALTER TABLE dashboard_data_source_events
    ADD CONSTRAINT dashboard_data_source_events_source_fk
    FOREIGN KEY (data_source_id)
    REFERENCES dashboard_data_sources (data_source_id)
    """)

    execute("""
    ALTER TABLE dashboard_data_source_events
    ADD CONSTRAINT dashboard_data_source_events_org_fk
    FOREIGN KEY (organization_id)
    REFERENCES organizations (organization_id)
    """)

    execute("""
    ALTER TABLE dashboard_data_source_events
    ADD CONSTRAINT dashboard_data_source_events_org_mission_fk
    FOREIGN KEY (organization_id, mission_id)
    REFERENCES missions (organization_id, mission_id)
    """)
  end

  def down do
    execute("""
    ALTER TABLE dashboard_data_source_events
    DROP CONSTRAINT IF EXISTS dashboard_data_source_events_org_mission_fk
    """)

    execute("""
    ALTER TABLE dashboard_data_source_events
    DROP CONSTRAINT IF EXISTS dashboard_data_source_events_org_fk
    """)

    execute("""
    ALTER TABLE dashboard_data_source_events
    DROP CONSTRAINT IF EXISTS dashboard_data_source_events_source_fk
    """)

    drop_if_exists(
      index(:dashboard_data_source_events, [:organization_id, :mission_id, :event_type],
        name: :dashboard_data_source_events_scope_type_idx
      )
    )

    drop_if_exists(
      index(:dashboard_data_source_events, [:data_source_id, :occurred_at],
        name: :dashboard_data_source_events_source_time_idx
      )
    )

    drop(table(:dashboard_data_source_events))
  end
end
