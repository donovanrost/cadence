defmodule Cadence.Telemetry.Storage.QuestDB.SchemaMigratorTest do
  use ExUnit.Case, async: true

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
