defmodule Cadence.Repo.Migrations.CreateDashboardLifecycleEvents do
  use Ecto.Migration

  def up do
    create table(:dashboard_lifecycle_events, primary_key: false) do
      add(:dashboard_lifecycle_event_id, :string, primary_key: true)
      add(:organization_id, :string)
      add(:mission_id, :string, null: false)
      add(:dashboard_id, :string, null: false)
      add(:event_type, :string, null: false)
      add(:dashboard_version, :integer)
      add(:previous_lifecycle_state, :string)
      add(:current_lifecycle_state, :string)
      add(:previous_published_version, :integer)
      add(:current_published_version, :integer)
      add(:actor_id, :string)
      add(:occurred_at, :utc_datetime_usec, null: false)
      add(:payload, :map, null: false, default: %{})

      timestamps(type: :utc_datetime_usec, updated_at: false)
    end

    create(
      index(:dashboard_lifecycle_events, [:organization_id, :mission_id, :dashboard_id],
        name: :dashboard_lifecycle_events_dashboard_idx
      )
    )

    create(
      index(:dashboard_lifecycle_events, [:organization_id, :mission_id, :event_type],
        name: :dashboard_lifecycle_events_type_idx
      )
    )

    execute("""
    ALTER TABLE dashboard_lifecycle_events
    ADD CONSTRAINT dashboard_lifecycle_events_org_mission_fk
    FOREIGN KEY (organization_id, mission_id)
    REFERENCES missions (organization_id, mission_id)
    """)

    execute("""
    ALTER TABLE dashboard_lifecycle_events
    ADD CONSTRAINT dashboard_lifecycle_events_dashboard_fk
    FOREIGN KEY (dashboard_id)
    REFERENCES ops_dashboards (dashboard_id)
    ON DELETE CASCADE
    """)

    execute("""
    CREATE TRIGGER sync_organization_id_from_mission
    BEFORE INSERT OR UPDATE OF mission_id, organization_id ON dashboard_lifecycle_events
    FOR EACH ROW
    EXECUTE FUNCTION cadence_sync_organization_id_from_mission()
    """)
  end

  def down do
    execute("""
    DROP TRIGGER IF EXISTS sync_organization_id_from_mission ON dashboard_lifecycle_events
    """)

    execute("""
    ALTER TABLE dashboard_lifecycle_events
    DROP CONSTRAINT IF EXISTS dashboard_lifecycle_events_dashboard_fk
    """)

    execute("""
    ALTER TABLE dashboard_lifecycle_events
    DROP CONSTRAINT IF EXISTS dashboard_lifecycle_events_org_mission_fk
    """)

    drop_if_exists(
      index(:dashboard_lifecycle_events, [:organization_id, :mission_id, :event_type],
        name: :dashboard_lifecycle_events_type_idx
      )
    )

    drop_if_exists(
      index(:dashboard_lifecycle_events, [:organization_id, :mission_id, :dashboard_id],
        name: :dashboard_lifecycle_events_dashboard_idx
      )
    )

    drop(table(:dashboard_lifecycle_events))
  end
end
