defmodule Cadence.Telemetry.Storage.QuestDB.SchemaMigratorTest do
  use Cadence.UnitCase, async: true

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
             },
             %{
               version: "20260627000000",
               name: "enable_telemetry_observation_dedup",
               sql: dedup_sql,
               checksum: dedup_checksum
             },
             %{
               version: "20260628000000",
               name: "add_telemetry_observation_identity_id",
               sql: observation_identity_sql,
               checksum: observation_identity_checksum
             }
             | provenance_migrations
           ] = migrations

    assert create_sql =~ "CREATE TABLE IF NOT EXISTS telemetry_observations"
    assert create_sql =~ "TIMESTAMP(observed_at) PARTITION BY DAY WAL"
    assert create_sql =~ "DEDUP UPSERT KEYS(observed_at, idempotency_key)"
    assert is_binary(create_checksum)

    assert dedup_sql =~ "ALTER TABLE telemetry_observations"
    assert dedup_sql =~ "DEDUP ENABLE UPSERT KEYS(observed_at, idempotency_key)"
    assert is_binary(dedup_checksum)

    assert observation_identity_sql =~ "ALTER TABLE telemetry_observations"

    assert observation_identity_sql =~
             "ADD COLUMN IF NOT EXISTS observation_identity_id STRING"

    assert is_binary(observation_identity_checksum)

    # DECISIONS #103: one column per file (QuestDB refuses a multi-column ADD COLUMN on a WAL
    # table), CAPACITY per the design's tenant-mix sizing.
    assert Enum.map(
             provenance_migrations,
             &{&1.version, &1.sql |> String.split("\n") |> List.last()}
           ) ==
             [
               {"20261117000000",
                add_column("mission_model_revision_id SYMBOL CAPACITY 16384 CACHE")},
               {"20261117000001", add_column("runtime_plan_id SYMBOL CAPACITY 32768 CACHE")},
               {"20261117000002", add_column("producer_kind SYMBOL CAPACITY 256 CACHE")},
               {"20261117000003", add_column("producer_id SYMBOL CAPACITY 16384 CACHE")},
               {"20261117000004", add_column("semantic_id SYMBOL CAPACITY 262144 NOCACHE")},
               {"20261117000005", add_column("qualified_name SYMBOL CAPACITY 262144 NOCACHE")},
               {"20261117000006", add_column("identity_ref VARCHAR")},
               {"20261117000007", add_column("binding_rule_derived BOOLEAN")},
               {"20261117000008", add_column("packet_refs_derived BOOLEAN")}
             ]
  end

  defp add_column(definition),
    do: "ALTER TABLE telemetry_observations ADD COLUMN IF NOT EXISTS #{definition};"

  test "migration plan sorts files by version and ignores non-migration sql files" do
    migrations_path = temp_migrations_path()

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

  test "migration plan excludes applied versions" do
    migrations_path = temp_migrations_path()

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
           ] = SchemaMigrator.connection_config([])
  end

  describe "check/1 (read-only, mix cadence.questdb.migrate --check)" do
    setup do
      migrations_path = temp_migrations_path()
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
        {:error, {:http_error, 400, "table does not exist"}}
      end

      assert {:error, {:http_error, 400, _body}} =
               SchemaMigrator.check(migrations_path: c.migrations_path, exec_fun: exec)

      assert_only_selects()
    end

    test "the probe and the check compare against the same columns, reader's and writer's" do
      required = SchemaMigrator.required_columns()

      assert Enum.all?(ObservationReader.select_columns(), &(&1 in required))
      assert Enum.all?(ObservationRow.columns(), &(Atom.to_string(&1) in required))
      assert "semantic_id" in required and "packet_refs_derived" in required
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

  defp temp_migrations_path do
    path =
      Path.join([
        System.tmp_dir!(),
        "cadence-questdb-migrations-#{System.unique_integer([:positive])}"
      ])

    File.mkdir_p!(path)
    path
  end

  defp write_migration(migrations_path, filename, sql) do
    File.write!(Path.join(migrations_path, filename), sql)
  end
end
