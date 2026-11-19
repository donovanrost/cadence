defmodule Mix.Tasks.Cadence.Questdb.MigrateTest do
  use Cadence.UnitCase, async: true

  alias Mix.Tasks.Cadence.Questdb.Migrate

  describe "--check report (a restart's pre-flight gate)" do
    test "exits 0 when the schema is current" do
      assert {0, "QuestDB at http://127.0.0.1:9000: schema is current for this build."} =
               Migrate.check_report(:ok, "http://127.0.0.1:9000")
    end

    test "exits 1 and says to migrate before restarting when the schema is behind" do
      assert {1, message} =
               Migrate.check_report(
                 {:behind,
                  %{missing_columns: ["semantic_id", "identity_ref"], pending_migrations: []}},
                 "http://questdb:9000"
               )

      assert message =~ "QuestDB at http://questdb:9000: schema is behind"

      assert message =~ "missing columns semantic_id, identity_ref"
      assert message =~ "unapplied migrations none"
      assert message =~ "Run mix cadence.questdb.migrate before restarting"
    end

    test "exits 1 for an unapplied migration alone" do
      assert {1, message} =
               Migrate.check_report(
                 {:behind, %{missing_columns: [], pending_migrations: ["20261117000000"]}},
                 "http://questdb:9000"
               )

      assert message =~ "unapplied migrations 20261117000000"
    end

    test "exits 2 when the schema can't be read" do
      assert {2, message} = Migrate.check_report({:error, :econnrefused}, "http://questdb:9000")
      assert message =~ "QuestDB at http://questdb:9000: could not read the schema"
    end
  end
end
