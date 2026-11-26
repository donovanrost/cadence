defmodule Cadence.Telemetry.Storage.QuestDB.SchemaMigratorTest do
  use Cadence.UnitCase, async: true
  @moduletag :tmp_dir

  alias Cadence.Telemetry.Storage.QuestDB.{ObservationReader, ObservationRow, SchemaMigrator}

  test "default migrations include telemetry observations schema" do
    assert {:ok, migrations} =
             SchemaMigrator.load_migrations(SchemaMigrator.default_migrations_path())

    assert [
             %{
               version: "20260617000000",
               name: "create_telemetry_observations",
               sql: create_sql,
               checksum: create_checksum
             }
             | rest
           ] = migrations

    assert create_sql =~ "CREATE TABLE IF NOT EXISTS telemetry_observations"
    assert create_sql =~ "TIMESTAMP(observed_at) PARTITION BY DAY WAL"
    assert create_sql =~ "DEDUP UPSERT KEYS(observed_at, idempotency_key)"
    assert create_sql =~ "observation_identity_id STRING"
    assert is_binary(create_checksum)

    # Sized for 1,000+ craft: the symbols that grow with the fleet carry an explicit capacity.
    for column <- ~w(spacecraft_id source_endpoint_id) do
      assert create_sql =~ "#{column} SYMBOL CAPACITY 4096"
    end

    for column <- ~w(observable_id point_id) do
      assert create_sql =~ "#{column} SYMBOL CAPACITY 16384"
    end

    # DECISIONS #103: provenance as typed columns, CAPACITY per the design's tenant-mix sizing, in
    # the one create (a WAL table refuses a multi-column ADD COLUMN, and dev is disposable).
    for definition <- [
          "mission_model_revision_id SYMBOL CAPACITY 16384 CACHE",
          "runtime_plan_id SYMBOL CAPACITY 32768 CACHE",
          "producer_kind SYMBOL CAPACITY 256 CACHE",
          "producer_id SYMBOL CAPACITY 16384 CACHE",
          "semantic_id SYMBOL CAPACITY 262144 NOCACHE",
          "qualified_name SYMBOL CAPACITY 262144 NOCACHE",
          "identity_ref VARCHAR",
          "binding_rule_derived BOOLEAN",
          "packet_refs_derived BOOLEAN"
        ] do
      assert create_sql =~ definition
    end

    assert rest == []
  end

  test "migration plan sorts files by version and ignores non-migration sql files", %{
    tmp_dir: migrations_path
  } do
    write_migration(
      migrations_path,
      "20260617000002_second.sql",
      "CREATE TABLE second (ts TIMESTAMP) TIMESTAMP(ts);"
    )

    write_migration(
      migrations_path,
      "20260617000001_first.sql",
      "CREATE TABLE first (ts TIMESTAMP) TIMESTAMP(ts);"
    )

    File.write!(Path.join(migrations_path, "scratch.sql"), "SELECT 1;")

    assert {:ok, migrations} = SchemaMigrator.migration_plan(migrations_path)

    assert Enum.map(migrations, & &1.version) == ["20260617000001", "20260617000002"]
    assert Enum.map(migrations, & &1.name) == ["first", "second"]
  end

  test "migration plan excludes applied versions", %{tmp_dir: migrations_path} do
    write_migration(
      migrations_path,
      "20260617000001_first.sql",
      "CREATE TABLE first (ts TIMESTAMP) TIMESTAMP(ts);"
    )

    write_migration(
      migrations_path,
      "20260617000002_second.sql",
      "CREATE TABLE second (ts TIMESTAMP) TIMESTAMP(ts);"
    )

    assert {:ok, [pending]} = SchemaMigrator.migration_plan(migrations_path, ["20260617000001"])

    assert pending.version == "20260617000002"
  end

  test "connection config uses QuestDB local defaults" do
    assert [
             hostname: "127.0.0.1",
             port: 8812,
             database: "qdb",
             username: "admin",
             password: "quest",
             timeout: 15_000,
             http_endpoint: "http://127.0.0.1:9000"
           ] = SchemaMigrator.connection_config(environment: %{})
  end

  test "connection config reads explicit environment without changing process environment" do
    assert [
             hostname: "fixture-host",
             port: 10_101,
             database: "fixture-db",
             username: "fixture-user",
             password: "quest",
             timeout: 15_000,
             http_endpoint: "http://fixture-host:10001"
           ] =
             SchemaMigrator.connection_config(
               environment: %{
                 "CADENCE_QUESTDB_HOST" => "fixture-host",
                 "CADENCE_QUESTDB_PORT" => "10101",
                 "CADENCE_QUESTDB_DATABASE" => "fixture-db",
                 "CADENCE_QUESTDB_USERNAME" => "fixture-user",
                 "CADENCE_QUESTDB_HTTP_ENDPOINT" => "http://fixture-host:10001"
               }
             )
  end

  describe "check/1 (read-only, mix cadence.questdb.migrate --check)" do
    setup %{tmp_dir: migrations_path} do
      write_migration(migrations_path, "20260617000001_first.sql", "SELECT 1;")
      write_migration(migrations_path, "20260617000002_second.sql", "SELECT 2;")
      %{migrations_path: migrations_path}
    end

    test "is :ok when the table has every column this build uses and every file is applied", c do
      exec = schema(SchemaMigrator.required_columns(), ["20260617000001", "20260617000002"])

      assert SchemaMigrator.check(migrations_path: c.migrations_path, exec_fun: exec) == :ok
      assert_only_selects()
    end

    test "is behind when the table lacks columns this build reads or writes", c do
      columns = SchemaMigrator.required_columns() -- ["semantic_id", "packet_refs_derived"]
      exec = schema(columns, ["20260617000001", "20260617000002"])

      assert {:behind,
              %{missing_columns: ["semantic_id", "packet_refs_derived"], pending_migrations: []}} =
               SchemaMigrator.check(migrations_path: c.migrations_path, exec_fun: exec)

      assert_only_selects()
    end

    test "is behind when a migration file isn't applied", c do
      exec = schema(SchemaMigrator.required_columns(), ["20260617000001"])

      assert {:behind, %{missing_columns: [], pending_migrations: ["20260617000002"]}} =
               SchemaMigrator.check(migrations_path: c.migrations_path, exec_fun: exec)
    end

    test "is an error when the schema can't be read", c do
      exec = fn sql, _opts ->
        send(self(), {:sql, sql})
        {:error, :econnrefused}
      end

      assert {:error, :econnrefused} =
               SchemaMigrator.check(migrations_path: c.migrations_path, exec_fun: exec)

      assert_only_selects()
    end

    # qa (#483): a fresh QuestDB, or the reset's renamed table, has no table yet. That's a schema
    # to migrate (exit 1), not one that can't be read (exit 2).
    test "is behind, with every column and file, when the tables don't exist yet", c do
      exec = fn sql, _opts ->
        send(self(), {:sql, sql})

        {:error,
         {:http_error, 400, %{"error" => "table does not exist [table=telemetry_observations]"}}}
      end

      assert {:behind,
              %{
                missing_columns: missing,
                pending_migrations: ["20260617000001", "20260617000002"]
              }} =
               SchemaMigrator.check(migrations_path: c.migrations_path, exec_fun: exec)

      assert missing == SchemaMigrator.required_columns()
      assert_only_selects()
    end

    test "the probe and the check compare against the same columns, reader's and writer's" do
      required = SchemaMigrator.required_columns()

      assert Enum.all?(ObservationReader.select_columns(), &(&1 in required))
      assert Enum.all?(ObservationRow.columns(), &(Atom.to_string(&1) in required))
      assert "semantic_id" in required and "packet_refs_derived" in required
    end
  end

  describe "await_current/1 (after applying, until QuestDB has applied the WAL)" do
    setup %{tmp_dir: migrations_path} do
      write_migration(migrations_path, "20260617000001_first.sql", "SELECT 1;")
      %{migrations_path: migrations_path}
    end

    # qa (#483): right after the ALTERs, table_columns showed 4 of 9; a second later, all 9.
    test "polls until the new columns are visible", c do
      {:ok, agent} = Agent.start_link(fn -> 0 end)
      partial = SchemaMigrator.required_columns() -- ["semantic_id", "identity_ref"]

      exec = fn sql, _opts ->
        cond do
          sql =~ "table_columns('telemetry_observations')" ->
            seen = Agent.get_and_update(agent, &{&1, &1 + 1})
            columns = if seen < 2, do: partial, else: SchemaMigrator.required_columns()
            {:ok, %{"dataset" => Enum.map(columns, &[&1])}}

          sql =~ "FROM cadence_schema_migrations" ->
            {:ok, %{"dataset" => [["20260617000001"]]}}
        end
      end

      assert :ok =
               SchemaMigrator.await_current(
                 migrations_path: c.migrations_path,
                 exec_fun: exec,
                 sleep_fun: fn ms -> send(self(), {:slept, ms}) end
               )

      assert_received {:slept, 250}
      assert Agent.get(agent, & &1) == 3
    end

    test "gives up after its timeout with the last check", c do
      exec = schema(SchemaMigrator.required_columns() -- ["semantic_id"], ["20260617000001"])

      assert {:error,
              {:schema_not_current,
               {:behind, %{missing_columns: ["semantic_id"], pending_migrations: []}}}} =
               SchemaMigrator.await_current(
                 migrations_path: c.migrations_path,
                 exec_fun: exec,
                 await_timeout_ms: 0,
                 sleep_fun: fn _ms -> :ok end
               )
    end
  end

  defp schema(columns, applied_versions) do
    fn sql, _opts ->
      send(self(), {:sql, sql})

      cond do
        sql =~ "table_columns('telemetry_observations')" ->
          {:ok, %{"dataset" => Enum.map(columns, &[&1])}}

        sql =~ "FROM cadence_schema_migrations" ->
          {:ok, %{"dataset" => Enum.map(applied_versions, &[&1])}}
      end
    end
  end

  defp assert_only_selects do
    sqls = collect_sql([])
    assert sqls != []

    assert Enum.all?(sqls, &String.starts_with?(String.trim_leading(&1), "SELECT ")),
           inspect(sqls)
  end

  defp collect_sql(acc) do
    receive do
      {:sql, sql} -> collect_sql([sql | acc])
    after
      0 -> Enum.reverse(acc)
    end
  end

  defp write_migration(migrations_path, filename, sql) do
    File.write!(Path.join(migrations_path, filename), sql)
  end
end
