defmodule Cadence.FrontendReleaseStagedChunksMigrationTest do
  use ExUnit.Case, async: false

  alias Cadence.FrontendReleaseMigrationTestRepo, as: MigrationRepo

  @migration_path Path.expand("../../priv/repo/migrations", __DIR__)
  @migration_version 20_260_831_020_000
  @create_publication_version 20_260_831_000_000
  @create_objects_version 20_260_831_010_000

  test "rollback reconstructs chunk-backed bytes and re-up succeeds in an isolated database" do
    database = "cadence_frontend_release_migration_#{System.unique_integer([:positive])}"
    admin = start_admin_connection!()

    try do
      create_database!(admin, database)
      configure_migration_repo(database)

      Ecto.Migrator.with_repo(MigrationRepo, fn repo ->
        source = migration_source()

        assert Ecto.Migrator.run(repo, source, :up, step: 2, log: false) == [
                 @create_publication_version,
                 @create_objects_version
               ]

        legacy_bytes = <<0, 1, 2, 3>>
        legacy_digest = digest_hex(legacy_bytes)
        legacy_inserted_at = "2026-08-31 00:00:00.123456"

        repo.query!(
          """
          INSERT INTO frontend_release_objects (sha256, bytes, size, inserted_at)
          VALUES ($1, $2, $3, TIMESTAMP '2026-08-31 00:00:00.123456')
          """,
          [legacy_digest, legacy_bytes, byte_size(legacy_bytes)]
        )

        assert Ecto.Migrator.run(repo, source, :up, step: 1, log: false) == [@migration_version]

        chunked_bytes = <<255, 0, 1, 2, 3, 4, 5, 6, 7>>
        chunked_digest = digest_hex(chunked_bytes)
        chunked_inserted_at = "2026-08-31 00:01:02.654321"

        repo.query!(
          """
          INSERT INTO frontend_release_objects (sha256, bytes, size, inserted_at)
          VALUES ($1, NULL, $2, TIMESTAMP '2026-08-31 00:01:02.654321')
          """,
          [chunked_digest, byte_size(chunked_bytes)]
        )

        for {chunk_index, bytes} <- [{2, <<4, 5, 6, 7>>}, {0, <<255, 0, 1>>}, {1, <<2, 3>>}] do
          repo.query!(
            """
            INSERT INTO frontend_release_object_chunks
              (sha256, chunk_index, bytes, size, inserted_at)
            VALUES ($1, $2, $3, $4, now())
            """,
            [chunked_digest, chunk_index, bytes, byte_size(bytes)]
          )
        end

        assert Ecto.Migrator.run(repo, source, :down, step: 1, log: false) == [@migration_version]

        assert [
                 [^legacy_digest, ^legacy_bytes, 4, ^legacy_inserted_at],
                 [^chunked_digest, ^chunked_bytes, 9, ^chunked_inserted_at]
               ] =
                 repo.query!("""
                 SELECT sha256, bytes, size, to_char(inserted_at, 'YYYY-MM-DD HH24:MI:SS.US')
                 FROM frontend_release_objects
                 ORDER BY sha256
                 """).rows

        assert [[nil]] = repo.query!("SELECT to_regclass('frontend_release_object_chunks')").rows
        assert [[nil]] = repo.query!("SELECT to_regclass('frontend_release_staged_objects')").rows

        assert Ecto.Migrator.run(repo, source, :up, step: 1, log: false) == [@migration_version]
        assert [[2]] = repo.query!("SELECT COUNT(*) FROM frontend_release_objects").rows

        assert [[^chunked_bytes]] =
                 repo.query!("SELECT bytes FROM frontend_release_objects WHERE sha256 = $1", [
                   chunked_digest
                 ]).rows
      end)
    after
      drop_database!(admin, database)
      GenServer.stop(admin)
      Application.delete_env(:cadence, MigrationRepo)
    end
  end

  defp migration_source do
    [
      {@create_publication_version,
       "20260831000000_create_frontend_release_publication_tables.exs"},
      {@create_objects_version, "20260831010000_add_frontend_release_objects.exs"},
      {@migration_version, "20260831020000_add_frontend_release_staged_chunks.exs"}
    ]
    |> Enum.map(fn {version, filename} -> {version, Path.join(@migration_path, filename)} end)
  end

  defp configure_migration_repo(database) do
    config =
      Application.fetch_env!(:cadence, Cadence.Repo)
      |> Keyword.take([:username, :password, :hostname, :port, :socket_dir, :ssl])
      |> Keyword.put(:database, database)
      |> Keyword.put(:pool_size, 2)

    Application.put_env(:cadence, MigrationRepo, config)
  end

  defp start_admin_connection! do
    options =
      Application.fetch_env!(:cadence, Cadence.Repo)
      |> Keyword.take([:username, :password, :hostname, :port, :socket_dir, :ssl])
      |> Keyword.put(:database, "postgres")

    {:ok, connection} = Postgrex.start_link(options)
    connection
  end

  defp create_database!(admin, database) do
    Postgrex.query!(admin, ~s(CREATE DATABASE "#{database}"), [])
  end

  defp drop_database!(admin, database) do
    Postgrex.query!(admin, ~s(DROP DATABASE IF EXISTS "#{database}"), [])
  end

  defp digest_hex(bytes), do: Base.encode16(:crypto.hash(:sha256, bytes), case: :lower)
end
