defmodule Cadence.Repo.Migrations.AlarmEpisodesOrganizationFromMission do
  use Ecto.Migration

  # Episodes are written from the data plane, which doesn't resolve organizations itself; like
  # other mission tables, the organization comes from the mission.
  @tables [:alarm_episodes, :alarm_episode_events]

  def up do
    for table <- @tables do
      execute("ALTER TABLE #{table} ALTER COLUMN organization_id DROP NOT NULL")

      execute("""
      CREATE TRIGGER sync_organization_id_from_mission
      BEFORE INSERT OR UPDATE OF mission_id, organization_id ON #{table}
      FOR EACH ROW
      EXECUTE FUNCTION cadence_sync_organization_id_from_mission()
      """)
    end
  end

  def down do
    for table <- @tables do
      execute("DROP TRIGGER IF EXISTS sync_organization_id_from_mission ON #{table}")
    end
  end
end
