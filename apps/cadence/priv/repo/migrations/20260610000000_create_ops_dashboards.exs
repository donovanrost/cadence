defmodule Cadence.Repo.Migrations.CreateOpsDashboards do
  use Ecto.Migration

  def up do
    create table(:ops_dashboards, primary_key: false) do
      add(:dashboard_id, :string, primary_key: true)
      add(:organization_id, :string)
      add(:mission_id, :string, null: false)
      add(:name, :string, null: false)
      add(:description, :text)
      add(:widgets, :map, null: false, default: %{})

      timestamps(type: :utc_datetime_usec)
    end

    create(
      unique_index(:ops_dashboards, [:mission_id, :dashboard_id], name: :ops_dashboards_scope_idx)
    )

    create(
      index(:ops_dashboards, [:organization_id, :mission_id],
        name: :ops_dashboards_org_mission_idx
      )
    )

    execute("""
    ALTER TABLE ops_dashboards
    ADD CONSTRAINT ops_dashboards_org_mission_fk
    FOREIGN KEY (organization_id, mission_id)
    REFERENCES missions (organization_id, mission_id)
    """)

    execute("""
    CREATE TRIGGER sync_organization_id_from_mission
    BEFORE INSERT OR UPDATE OF mission_id, organization_id ON ops_dashboards
    FOR EACH ROW
    EXECUTE FUNCTION cadence_sync_organization_id_from_mission()
    """)
  end

  def down do
    execute("""
    DROP TRIGGER IF EXISTS sync_organization_id_from_mission ON ops_dashboards
    """)

    execute("""
    ALTER TABLE ops_dashboards
    DROP CONSTRAINT IF EXISTS ops_dashboards_org_mission_fk
    """)

    drop_if_exists(
      index(:ops_dashboards, [:organization_id, :mission_id],
        name: :ops_dashboards_org_mission_idx
      )
    )

    drop_if_exists(
      index(:ops_dashboards, [:mission_id, :dashboard_id], name: :ops_dashboards_scope_idx)
    )

    drop(table(:ops_dashboards))
  end
end
