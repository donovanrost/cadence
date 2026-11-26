defmodule Cadence.Repo.Migrations.MissionScopeImmutable do
  use Ecto.Migration

  # A mission's identity and organization never change (#687, commanding on #774):
  # `Missions.organization_id_for_mission/1` memoizes the answer per process, and `Auth.Policy`'s
  # mission-scope check relies on it. This makes the database refuse such a change, raw SQL
  # included, instead of leaving it to convention.
  def up do
    execute("""
    CREATE FUNCTION cadence_mission_scope_immutable() RETURNS trigger
    LANGUAGE plpgsql AS $$
    BEGIN
      IF NEW.mission_id IS DISTINCT FROM OLD.mission_id
         OR NEW.organization_id IS DISTINCT FROM OLD.organization_id THEN
        RAISE EXCEPTION 'a mission''s mission_id and organization_id never change (mission %)',
          OLD.mission_id
          USING ERRCODE = 'raise_exception';
      END IF;
      RETURN NEW;
    END;
    $$;
    """)

    execute("""
    CREATE TRIGGER missions_scope_immutable
      BEFORE UPDATE OF mission_id, organization_id ON missions
      FOR EACH ROW EXECUTE FUNCTION cadence_mission_scope_immutable();
    """)
  end

  def down do
    execute("DROP TRIGGER missions_scope_immutable ON missions")
    execute("DROP FUNCTION cadence_mission_scope_immutable()")
  end
end
