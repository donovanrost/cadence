defmodule Cadence.Repo.Migrations.CreateDashboardUserPreferences do
  use Ecto.Migration

  def up do
    create table(:dashboard_user_preferences, primary_key: false) do
      add(:dashboard_user_preference_id, :string, primary_key: true)
      add(:organization_id, :string)
      add(:mission_id, :string, null: false)
      add(:user_id, :string, null: false)
      add(:dashboard_id, :string, null: false)
      add(:starred, :boolean, null: false, default: false)
      add(:last_viewed_at, :utc_datetime_usec)

      timestamps(type: :utc_datetime_usec)
    end

    create(
      unique_index(
        :dashboard_user_preferences,
        [:organization_id, :mission_id, :user_id, :dashboard_id],
        name: :dashboard_user_preferences_scope_idx
      )
    )

    create(
      index(
        :dashboard_user_preferences,
        [:organization_id, :mission_id, :user_id, :starred, :last_viewed_at],
        name: :dashboard_user_preferences_navigation_idx
      )
    )

    execute("""
    ALTER TABLE dashboard_user_preferences
    ADD CONSTRAINT dashboard_user_preferences_org_mission_fk
    FOREIGN KEY (organization_id, mission_id)
    REFERENCES missions (organization_id, mission_id)
    """)

    execute("""
    ALTER TABLE dashboard_user_preferences
    ADD CONSTRAINT dashboard_user_preferences_dashboard_fk
    FOREIGN KEY (dashboard_id)
    REFERENCES ops_dashboards (dashboard_id)
    ON DELETE CASCADE
    """)

    execute("""
    ALTER TABLE dashboard_user_preferences
    ADD CONSTRAINT dashboard_user_preferences_user_fk
    FOREIGN KEY (user_id)
    REFERENCES users (user_id)
    ON DELETE CASCADE
    """)

    execute("""
    CREATE TRIGGER sync_organization_id_from_mission
    BEFORE INSERT OR UPDATE OF mission_id, organization_id ON dashboard_user_preferences
    FOR EACH ROW
    EXECUTE FUNCTION cadence_sync_organization_id_from_mission()
    """)
  end

  def down do
    execute("""
    DROP TRIGGER IF EXISTS sync_organization_id_from_mission ON dashboard_user_preferences
    """)

    execute("""
    ALTER TABLE dashboard_user_preferences
    DROP CONSTRAINT IF EXISTS dashboard_user_preferences_user_fk
    """)

    execute("""
    ALTER TABLE dashboard_user_preferences
    DROP CONSTRAINT IF EXISTS dashboard_user_preferences_dashboard_fk
    """)

    execute("""
    ALTER TABLE dashboard_user_preferences
    DROP CONSTRAINT IF EXISTS dashboard_user_preferences_org_mission_fk
    """)

    drop_if_exists(
      index(
        :dashboard_user_preferences,
        [:organization_id, :mission_id, :user_id, :starred, :last_viewed_at],
        name: :dashboard_user_preferences_navigation_idx
      )
    )

    drop_if_exists(
      index(
        :dashboard_user_preferences,
        [:organization_id, :mission_id, :user_id, :dashboard_id],
        name: :dashboard_user_preferences_scope_idx
      )
    )

    drop(table(:dashboard_user_preferences))
  end
end
