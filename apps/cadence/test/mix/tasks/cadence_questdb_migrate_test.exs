defmodule Mix.Tasks.Cadence.Questdb.MigrateTest do
  use Cadence.UnitCase, async: true

  alias Mix.Tasks.Cadence.Questdb.Migrate

  describe "--check report (a restart's pre-flight gate)" do
    test "exits 0 when the schema is current" do
      assert {0, "QuestDB schema is current for this build."} = Migrate.check_report(:ok)
    end

    test "exits 1 and says to migrate before restarting when the schema is behind" do
      assert {1, message} =
               Migrate.check_report(
                 {:behind,
                  %{missing_columns: ["semantic_id", "identity_ref"], pending_migrations: []}}
               )

      assert message =~ "missing columns semantic_id, identity_ref"
      assert message =~ "unapplied migrations none"
      assert message =~ "Run mix cadence.questdb.migrate before restarting"
    end

    test "exits 1 for an unapplied migration alone" do
      assert {1, message} =
               Migrate.check_report(
                 {:behind, %{missing_columns: [], pending_migrations: ["20261117000000"]}}
               )

      assert message =~ "unapplied migrations 20261117000000"
    end

    test "exits 2 when the schema can't be read" do
      assert {2, message} = Migrate.check_report({:error, :econnrefused})
      assert message =~ "Could not read the QuestDB schema"
    end
  end
end
