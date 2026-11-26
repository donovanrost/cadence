defmodule Cadence.Governance.DecisionRecordRetentionTest do
  @moduledoc """
  Decision records are insert-only and never deleted (DECISIONS #107; P3 step 1). Guards: every
  pure decision table (`DecisionRecord.tables/0`) carries the append-only triggers; the trigger
  refuses UPDATE, DELETE and TRUNCATE, with one test-only bypass honoured only in a test
  database; no lib code that deletes, truncates, drops, prunes or retires names a decision table;
  no foreign key from a decision table cascades a parent's delete; and the bypass setting's name
  appears nowhere under lib/ or priv/ but the baseline SQL.
  """
  use Cadence.DataCase, async: false

  alias Cadence.Governance.DecisionRecord
  alias Cadence.TestSupport.DecisionRecordPurge

  @root Path.expand("../../../../..", __DIR__)
  @setting "decision_record_test_purge"

  @schemas %{
    "mission_config_reviews" => "ReviewRow",
    "mission_config_revisions" => "RevisionRow",
    "activation_decisions" => "ActivationDecisionRow",
    "command_approvals" => "CommandApprovalRow",
    "contact_plan_approvals" => "ContactPlanApprovalRow",
    "contact_plan_submissions" => "PlanSubmissions",
    "fleet_planning_policy_approvals" => "FleetPlanningPolicyApprovalRow",
    "provider_change_approvals" => "ProviderChangeApprovalRow"
  }

  test "every pure decision table carries the row and truncate triggers" do
    for table <- DecisionRecord.tables() do
      %{rows: rows} =
        Repo.query!(
          """
          SELECT t.tgname FROM pg_trigger t JOIN pg_class c ON c.oid = t.tgrelid
          WHERE c.relname = $1 AND NOT t.tgisinternal
          """,
          [table]
        )

      names = List.flatten(rows)
      assert "#{table}_append_only_rows" in names, "#{table} lacks its append-only row trigger"
      assert "#{table}_append_only_truncate" in names, "#{table} lacks its truncate trigger"
    end
  end

  test "the trigger refuses UPDATE, DELETE and TRUNCATE" do
    guarded_table!()

    for sql <- [
          "UPDATE decision_guard_probe SET x = 2",
          "DELETE FROM decision_guard_probe",
          "TRUNCATE decision_guard_probe"
        ] do
      assert {:error, %Postgrex.Error{postgres: %{message: message}}} = in_savepoint(sql)
      assert message =~ "decision records are append-only"
    end

    assert %{rows: [[1]]} = Repo.query!("SELECT count(*) FROM decision_guard_probe")
  end

  test "the purge setting lets a test clean up, in a test database only" do
    guarded_table!()

    # Without the setting, not even a test database is allowed. (Checked first: SET LOCAL lasts
    # until the outermost transaction ends, which in the SQL sandbox is the whole test.)
    assert %{rows: [[false]]} =
             Repo.query!("SELECT cadence_decision_record_purge_allowed('cadence_test12')")

    assert {:ok, _} =
             DecisionRecordPurge.run(fn -> Repo.query!("DELETE FROM decision_guard_probe") end)

    assert %{rows: [[0]]} = Repo.query!("SELECT count(*) FROM decision_guard_probe")

    # A dev database name is refused even with the setting on (lead 11-17).
    assert {:ok, [false, true, false]} =
             DecisionRecordPurge.run(fn ->
               for name <- ["cadence_apogee_dev", "cadence_test12", "cadence_dev"] do
                 %{rows: [[allowed]]} =
                   Repo.query!("SELECT cadence_decision_record_purge_allowed($1)", [name])

                 allowed
               end
             end)
  end

  test "no decision table's foreign key cascades a parent's delete" do
    %{rows: rows} =
      Repo.query!(
        """
        SELECT c.relname, con.conname FROM pg_constraint con JOIN pg_class c ON c.oid = con.conrelid
        WHERE con.contype = 'f' AND con.confdeltype = 'c' AND c.relname = ANY($1)
        """,
        [DecisionRecord.tables()]
      )

    assert rows == [],
           "a decision table's FK would delete decisions with its parent: #{inspect(rows)}"
  end

  # Files that match the scan but don't delete decision rows, each with why.
  @allowed %{
    # `retire` is a fleet planning policy's lifecycle state (a retired policy), not row deletion;
    # the file only reads its approvals (undecided/2) and inserts them.
    "apps/cadence/lib/cadence/contact_planning/fleet_planning_policies.ex" =>
      "FleetPlanningPolicyApprovalRow"
  }

  test "no lib code that deletes, truncates, drops, prunes or retires names a decision table" do
    names = DecisionRecord.tables() ++ Map.values(@schemas)

    offenders =
      for file <- lib_files(),
          relative = Path.relative_to(file, @root),
          text = File.read!(file),
          deletes?(text),
          name <- names,
          String.contains?(text, name),
          Map.get(@allowed, relative) != name,
          do: {relative, name}

    assert offenders == [],
           "decision records are never deleted (DECISIONS #107); these files delete and name a " <>
             "decision table: #{inspect(offenders)}"
  end

  test "the purge setting's name appears in no lib or priv file but the baseline SQL" do
    files = lib_files() ++ Path.wildcard(Path.join(@root, "apps/*/priv/**/*.{ex,exs,sql}"))
    baseline = Path.join(@root, "apps/cadence/priv/repo/baseline.sql")

    assert File.read!(baseline) =~ @setting

    offenders =
      for file <- files,
          file != baseline,
          File.read!(file) =~ @setting,
          do: Path.relative_to(file, @root)

    assert offenders == []
  end

  defp lib_files, do: Path.wildcard(Path.join(@root, "apps/*/lib/**/*.ex"))

  # Code that removes rows or tables, or a module or function named for retention.
  defp deletes?(text) do
    text =~ ~r/delete_all|Repo\.delete\b|DELETE FROM|TRUNCATE\s|DROP TABLE/ or
      text =~ ~r/def[a-z]*\s+[a-z_]*(prune|retire|reclaim|cleanup|retention)/ or
      text =~ ~r/defmodule\s+[\w.]*(Prune|Retire|Reclaim|Cleanup|Retention)/
  end

  # A table carrying the same trigger function, so the trigger's behaviour is proven without
  # each decision table's foreign keys. One row in it.
  defp guarded_table! do
    Repo.query!("CREATE TEMP TABLE decision_guard_probe (x integer)")

    Repo.query!("""
    CREATE TRIGGER decision_guard_probe_rows BEFORE UPDATE OR DELETE ON decision_guard_probe
      FOR EACH ROW EXECUTE FUNCTION cadence_decision_record_append_only()
    """)

    Repo.query!("""
    CREATE TRIGGER decision_guard_probe_truncate BEFORE TRUNCATE ON decision_guard_probe
      FOR EACH STATEMENT EXECUTE FUNCTION cadence_decision_record_append_only()
    """)

    Repo.query!("INSERT INTO decision_guard_probe VALUES (1)")
  end

  defp in_savepoint(sql) do
    Repo.transaction(fn ->
      case Repo.query(sql) do
        {:error, error} -> Repo.rollback(error)
        {:ok, result} -> result
      end
    end)
  end
end
