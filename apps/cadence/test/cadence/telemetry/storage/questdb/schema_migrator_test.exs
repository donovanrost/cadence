defmodule Cadence.Telemetry.Storage.QuestDB.SchemaMigratorTest do
  use Cadence.UnitCase, async: true

  alias Cadence.Telemetry.Storage.QuestDB.SchemaMigrator

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
  end

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
