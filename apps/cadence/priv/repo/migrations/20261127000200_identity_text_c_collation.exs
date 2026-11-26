defmodule Cadence.Repo.Migrations.IdentityTextCCollation do
  use Ecto.Migration

  # PostgreSQL refuses a column type change while a user trigger refers to it. Save and restore
  # those triggers around each table's change; the migration transaction hides the interval.
  def up, do: execute(collate_identity_columns("C", "<>"))
  def down, do: execute(collate_identity_columns("default", "="))

  defp collate_identity_columns(target, comparison) do
    """
    DO $migration$
    DECLARE target_table record;
    DECLARE saved_trigger record;
    BEGIN
      CREATE TEMP TABLE cadence_identity_collation_triggers ON COMMIT DROP AS
      SELECT n.nspname AS schema_name, c.relname AS table_name,
        t.tgname AS trigger_name, pg_get_triggerdef(t.oid) AS definition, t.tgenabled
      FROM pg_trigger t
      JOIN pg_class c ON c.oid = t.tgrelid
      JOIN pg_namespace n ON n.oid = c.relnamespace
      WHERE NOT t.tgisinternal AND n.nspname = 'public'
        AND EXISTS (
          SELECT 1 FROM pg_attribute a
          WHERE a.attrelid = c.oid AND a.attnum > 0 AND NOT a.attisdropped
            AND a.atttypid IN ('text'::regtype, 'character varying'::regtype)
            AND (a.attname ~ '(_id|_key)$' OR a.attname IN ('slug', 'key'))
            AND a.attcollation #{comparison} '"C"'::regcollation
        );

      FOR saved_trigger IN SELECT * FROM cadence_identity_collation_triggers LOOP
        EXECUTE format('DROP TRIGGER %I ON %I.%I',
          saved_trigger.trigger_name, saved_trigger.schema_name, saved_trigger.table_name);
      END LOOP;

      FOR target_table IN
        SELECT n.nspname AS schema_name, c.relname AS table_name,
          string_agg(
            format('ALTER COLUMN %I TYPE %s COLLATE %I',
              a.attname, format_type(a.atttypid, a.atttypmod), '#{target}'),
            ', ' ORDER BY a.attnum
          ) AS clauses
        FROM pg_class c
        JOIN pg_namespace n ON n.oid = c.relnamespace
        JOIN pg_attribute a ON a.attrelid = c.oid
        WHERE n.nspname = 'public' AND c.relkind = 'r'
          AND a.attnum > 0 AND NOT a.attisdropped
          AND a.atttypid IN ('text'::regtype, 'character varying'::regtype)
          AND (a.attname ~ '(_id|_key)$' OR a.attname IN ('slug', 'key'))
          AND a.attcollation #{comparison} '"C"'::regcollation
        GROUP BY n.nspname, c.relname
        ORDER BY n.nspname, c.relname
      LOOP
        EXECUTE format('ALTER TABLE %I.%I %s',
          target_table.schema_name, target_table.table_name, target_table.clauses);
      END LOOP;

      FOR saved_trigger IN SELECT * FROM cadence_identity_collation_triggers LOOP
        EXECUTE saved_trigger.definition;
        IF saved_trigger.tgenabled = 'D' THEN
          EXECUTE format('ALTER TABLE %I.%I DISABLE TRIGGER %I',
            saved_trigger.schema_name, saved_trigger.table_name, saved_trigger.trigger_name);
        ELSIF saved_trigger.tgenabled = 'R' THEN
          EXECUTE format('ALTER TABLE %I.%I ENABLE REPLICA TRIGGER %I',
            saved_trigger.schema_name, saved_trigger.table_name, saved_trigger.trigger_name);
        ELSIF saved_trigger.tgenabled = 'A' THEN
          EXECUTE format('ALTER TABLE %I.%I ENABLE ALWAYS TRIGGER %I',
            saved_trigger.schema_name, saved_trigger.table_name, saved_trigger.trigger_name);
        END IF;
      END LOOP;
    END
    $migration$;
    """
  end
end
