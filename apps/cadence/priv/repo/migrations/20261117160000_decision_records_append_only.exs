defmodule Cadence.Repo.Migrations.DecisionRecordsAppendOnly do
  use Ecto.Migration

  # Decision records are INSERT-ONLY and never deleted (DECISIONS #107; BACKLOG P3 step 1, director
  # 11-17). Each pure decision table refuses UPDATE and DELETE (row triggers) and TRUNCATE
  # (statement trigger). This layer also catches raw SQL from scripts, which no Elixir test sees.
  #
  # The one bypass, for tests that clean up outside the SQL sandbox: the transaction-local setting
  # cadence.decision_record_test_purge = on, honoured ONLY in a database whose name starts with
  # cadence_test (lead 11-17), so a dev script that sets it is still refused. The predicate is its
  # own function so a test can prove the refusal with a dev-style database name.
  @tables ~w(
    mission_config_reviews
    mission_config_revisions
    activation_decisions
    command_approvals
    contact_plan_approvals
    contact_plan_submissions
    fleet_planning_policy_approvals
    provider_change_approvals
  )

  # A parent's delete must not take its decisions with it (design guard (c)): these two cascaded
  # and now restrict, so deleting the parent fails loudly. No lib path deletes either parent.
  @restricted [
    {"mission_config_reviews", "mission_config_reviews_change_set_id_fkey", "change_set_id",
     "mission_config_change_sets", "change_set_id"},
    {"activation_decisions", "activation_decisions_activation_request_id_fkey",
     "activation_request_id", "activation_requests", "activation_request_id"}
  ]

  def up do
    for {table, name, column, parent, parent_column} <- @restricted do
      execute("""
      ALTER TABLE #{table} DROP CONSTRAINT #{name},
        ADD CONSTRAINT #{name} FOREIGN KEY (#{column}) REFERENCES #{parent} (#{parent_column})
        ON DELETE RESTRICT;
      """)
    end

    execute("""
    CREATE FUNCTION cadence_decision_record_purge_allowed(database_name text) RETURNS boolean
    LANGUAGE sql STABLE AS $$
      SELECT coalesce(current_setting('cadence.decision_record_test_purge', true), '') = 'on'
         AND database_name LIKE 'cadence\\_test%'
    $$;
    """)

    execute("""
    CREATE FUNCTION cadence_decision_record_append_only() RETURNS trigger
    LANGUAGE plpgsql AS $$
    BEGIN
      IF cadence_decision_record_purge_allowed(current_database()) THEN
        IF TG_OP = 'DELETE' THEN RETURN OLD; END IF;
        IF TG_OP = 'UPDATE' THEN RETURN NEW; END IF;
        RETURN NULL;
      END IF;
      RAISE EXCEPTION 'decision records are append-only: % on % refused', TG_OP, TG_TABLE_NAME
        USING ERRCODE = 'raise_exception';
    END;
    $$;
    """)

    for table <- @tables do
      execute("""
      CREATE TRIGGER #{table}_append_only_rows
        BEFORE UPDATE OR DELETE ON #{table}
        FOR EACH ROW EXECUTE FUNCTION cadence_decision_record_append_only();
      """)

      execute("""
      CREATE TRIGGER #{table}_append_only_truncate
        BEFORE TRUNCATE ON #{table}
        FOR EACH STATEMENT EXECUTE FUNCTION cadence_decision_record_append_only();
      """)
    end
  end

  def down do
    for table <- @tables do
      execute("DROP TRIGGER IF EXISTS #{table}_append_only_truncate ON #{table};")
      execute("DROP TRIGGER IF EXISTS #{table}_append_only_rows ON #{table};")
    end

    execute("DROP FUNCTION IF EXISTS cadence_decision_record_append_only();")
    execute("DROP FUNCTION IF EXISTS cadence_decision_record_purge_allowed(text);")

    for {table, name, column, parent, parent_column} <- @restricted do
      execute("""
      ALTER TABLE #{table} DROP CONSTRAINT #{name},
        ADD CONSTRAINT #{name} FOREIGN KEY (#{column}) REFERENCES #{parent} (#{parent_column})
        ON DELETE CASCADE;
      """)
    end
  end
end
