defmodule Cadence.Repo.Migrations.CreateDashboardDataBindingEvents do
  use Ecto.Migration

  def up do
    alter table(:dashboard_data_bindings) do
      add(:status, :string, null: false, default: "active")
      add(:binding_version, :integer, null: false, default: 1)
      add(:current_event_id, :string)
      add(:disabled_at, :utc_datetime_usec)
      add(:superseded_at, :utc_datetime_usec)
    end

    create(
      index(:dashboard_data_bindings, [:status, :organization_id, :mission_id],
        name: :dashboard_data_bindings_status_scope_idx
      )
    )

    create table(:dashboard_data_binding_events, primary_key: false) do
      add(:data_binding_event_id, :string, primary_key: true)
      add(:binding_id, :string, null: false)
      add(:organization_id, :string)
      add(:mission_id, :string)
      add(:event_type, :string, null: false)
      add(:previous_status, :string)
      add(:current_status, :string, null: false)
      add(:previous_binding_version, :integer)
      add(:current_binding_version, :integer, null: false)
      add(:previous_logical_source, :string)
      add(:current_logical_source, :string, null: false)
      add(:previous_realm, :string)
      add(:current_realm, :string, null: false)
      add(:previous_data_source_id, :string)
      add(:current_data_source_id, :string, null: false)
      add(:previous_dataset, :string)
      add(:current_dataset, :string)
      add(:previous_priority, :integer)
      add(:current_priority, :integer, null: false)
      add(:previous_active_from, :utc_datetime_usec)
      add(:current_active_from, :utc_datetime_usec)
      add(:previous_active_to, :utc_datetime_usec)
      add(:current_active_to, :utc_datetime_usec)
      add(:actor_id, :string)
      add(:occurred_at, :utc_datetime_usec, null: false)
      add(:payload, :map, null: false, default: %{})

      timestamps(type: :utc_datetime_usec, updated_at: false)
    end

    create(
      index(:dashboard_data_binding_events, [:binding_id, :occurred_at],
        name: :dashboard_data_binding_events_binding_time_idx
      )
    )

    create(
      index(:dashboard_data_binding_events, [:organization_id, :mission_id, :event_type],
        name: :dashboard_data_binding_events_scope_type_idx
      )
    )

    create(
      index(:dashboard_data_binding_events, [:current_data_source_id],
        name: :dashboard_data_binding_events_current_source_idx
      )
    )

    execute("""
    ALTER TABLE dashboard_data_binding_events
    ADD CONSTRAINT dashboard_data_binding_events_binding_fk
    FOREIGN KEY (binding_id)
    REFERENCES dashboard_data_bindings (binding_id)
    """)

    execute("""
    ALTER TABLE dashboard_data_binding_events
    ADD CONSTRAINT dashboard_data_binding_events_org_fk
    FOREIGN KEY (organization_id)
    REFERENCES organizations (organization_id)
    """)

    execute("""
    ALTER TABLE dashboard_data_binding_events
    ADD CONSTRAINT dashboard_data_binding_events_org_mission_fk
    FOREIGN KEY (organization_id, mission_id)
    REFERENCES missions (organization_id, mission_id)
    """)
  end

  def down do
    execute("""
    ALTER TABLE dashboard_data_binding_events
    DROP CONSTRAINT IF EXISTS dashboard_data_binding_events_org_mission_fk
    """)

    execute("""
    ALTER TABLE dashboard_data_binding_events
    DROP CONSTRAINT IF EXISTS dashboard_data_binding_events_org_fk
    """)

    execute("""
    ALTER TABLE dashboard_data_binding_events
    DROP CONSTRAINT IF EXISTS dashboard_data_binding_events_binding_fk
    """)

    drop_if_exists(
      index(:dashboard_data_binding_events, [:current_data_source_id],
        name: :dashboard_data_binding_events_current_source_idx
      )
    )

    drop_if_exists(
      index(:dashboard_data_binding_events, [:organization_id, :mission_id, :event_type],
        name: :dashboard_data_binding_events_scope_type_idx
      )
    )

    drop_if_exists(
      index(:dashboard_data_binding_events, [:binding_id, :occurred_at],
        name: :dashboard_data_binding_events_binding_time_idx
      )
    )

    drop(table(:dashboard_data_binding_events))

    drop_if_exists(
      index(:dashboard_data_bindings, [:status, :organization_id, :mission_id],
        name: :dashboard_data_bindings_status_scope_idx
      )
    )

    alter table(:dashboard_data_bindings) do
      remove(:superseded_at)
      remove(:disabled_at)
      remove(:current_event_id)
      remove(:binding_version)
      remove(:status)
    end
  end
end
