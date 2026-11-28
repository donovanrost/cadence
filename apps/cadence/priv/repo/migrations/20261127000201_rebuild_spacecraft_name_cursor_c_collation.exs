defmodule Cadence.Repo.Migrations.RebuildSpacecraftNameCursorCCollation do
  use Ecto.Migration

  def up do
    execute("DROP INDEX mission_spacecraft_name_cursor_idx")

    execute("""
    CREATE INDEX mission_spacecraft_name_cursor_idx
    ON mission_spacecraft (organization_id, mission_id, display_name COLLATE "C", spacecraft_id)
    """)
  end

  def down do
    execute("DROP INDEX mission_spacecraft_name_cursor_idx")

    execute("""
    CREATE INDEX mission_spacecraft_name_cursor_idx
    ON mission_spacecraft (organization_id, mission_id, display_name, spacecraft_id)
    """)
  end
end
