defmodule Cadence.Repo.Migrations.AuthoredVersionsCheckedAtCommit do
  use Ecto.Migration

  # ADR-020 P3 M2 (#451; agreed with commanding and mm-engineer there). A version is recorded
  # during its set's apply, before the ledger revision is written and the set marked applied
  # (the generation needs the head first). So "applied, as exactly this revision" is checked at
  # COMMIT, by the database: a transaction that doesn't complete the apply can't commit the
  # version.
  def up do
    execute("""
    ALTER TABLE mission_model_authored_versions
      DROP CONSTRAINT mission_model_authored_versions_revision_fk,
      ADD CONSTRAINT mission_model_authored_versions_revision_fk
      FOREIGN KEY (mission_id, revision_number)
      REFERENCES mission_config_revisions (mission_id, revision_number)
      DEFERRABLE INITIALLY DEFERRED
    """)

    execute("""
    CREATE FUNCTION cadence_authored_version_applied() RETURNS trigger
    LANGUAGE plpgsql AS $$
    BEGIN
      IF NOT EXISTS (
        SELECT 1 FROM mission_config_change_sets s
        WHERE s.change_set_id = NEW.change_set_id
          AND s.organization_id = NEW.organization_id
          AND s.mission_id = NEW.mission_id
          AND s.lane = 'monitoring'
          AND s.state = 'applied'
          AND s.applied_revision_number = NEW.revision_number
      ) THEN
        RAISE EXCEPTION 'authored version % of mission % is not its applied monitoring set''s revision',
          NEW.version, NEW.mission_id
          USING ERRCODE = 'check_violation',
                CONSTRAINT = 'mission_model_authored_versions_applied';
      END IF;
      RETURN NULL;
    END;
    $$
    """)

    execute("""
    CREATE CONSTRAINT TRIGGER mission_model_authored_versions_applied
      AFTER INSERT ON mission_model_authored_versions
      DEFERRABLE INITIALLY DEFERRED
      FOR EACH ROW EXECUTE FUNCTION cadence_authored_version_applied()
    """)
  end

  def down do
    execute(
      "DROP TRIGGER mission_model_authored_versions_applied ON mission_model_authored_versions"
    )

    execute("DROP FUNCTION cadence_authored_version_applied()")

    execute("""
    ALTER TABLE mission_model_authored_versions
      DROP CONSTRAINT mission_model_authored_versions_revision_fk,
      ADD CONSTRAINT mission_model_authored_versions_revision_fk
      FOREIGN KEY (mission_id, revision_number)
      REFERENCES mission_config_revisions (mission_id, revision_number)
    """)
  end
end
