defmodule Cadence.FrontendReleaseStagedChunksMigrationTest do
  use ExUnit.Case, async: false

  alias Cadence.FrontendReleaseMigrationTestRepo, as: MigrationRepo

  @migration_path Path.expand("../../priv/repo/migrations", __DIR__)
  @migration_version 20_260_831_020_000
  @create_publication_version 20_260_831_000_000
  @create_objects_version 20_260_831_010_000
  @max_object_size 100_000_000
  @migration_telemetry_prefix [:cadence, :frontend_release_migration_test_repo, :query]

  test "rollback reconstructs inline and chunk-backed bytes and re-up succeeds" do
    with_migrated_repo(fn repo ->
      inline_bytes = <<0, 1, 2, 3>>
      inline_digest = digest_hex(inline_bytes)

      insert_inline_object!(repo, inline_digest, inline_bytes)

      assert Ecto.Migrator.run(repo, migration_source(), :up, step: 1, log: false) == [
               @migration_version
             ]

      chunked_bytes = <<255, 0, 1, 2, 3, 4, 5, 6, 7>>
      chunked_digest = digest_hex(chunked_bytes)

      insert_chunked_object!(repo, chunked_digest, byte_size(chunked_bytes), [
        {2, <<4, 5, 6, 7>>},
        {0, <<255, 0, 1>>},
        {1, <<2, 3>>}
      ])

      assert Ecto.Migrator.run(repo, migration_source(), :down, step: 1, log: false) == [
               @migration_version
             ]

      assert [[^inline_bytes, 4]] =
               repo.query!("SELECT bytes, size FROM frontend_release_objects WHERE sha256 = $1", [
                 inline_digest
               ]).rows

      assert [[^chunked_bytes, 9]] =
               repo.query!("SELECT bytes, size FROM frontend_release_objects WHERE sha256 = $1", [
                 chunked_digest
               ]).rows

      assert [[nil]] = repo.query!("SELECT to_regclass('frontend_release_object_chunks')").rows
      assert [[nil]] = repo.query!("SELECT to_regclass('frontend_release_staged_objects')").rows

      assert Ecto.Migrator.run(repo, migration_source(), :up, step: 1, log: false) == [
               @migration_version
             ]

      assert [[2]] = repo.query!("SELECT COUNT(*) FROM frontend_release_objects").rows

      assert [[^chunked_bytes]] =
               repo.query!("SELECT bytes FROM frontend_release_objects WHERE sha256 = $1", [
                 chunked_digest
               ]).rows
    end)
  end

  test "rollback rejects malformed chunks without losing state or weakening triggers" do
    for scenario <- [
          :missing,
          :gapped,
          :extra,
          :wrong_declared_length,
          :total_size_mismatch,
          :digest_mismatch
        ] do
      with_migrated_repo(fn repo ->
        run_staged_chunks_up!(repo)
        {digest, expected_rows} = insert_corrupt_fixture!(repo, scenario)
        assert_failed_down_preserves_state(repo, digest, expected_rows)
      end)
    end
  end

  test "rollback rejects an oversized object before reading its chunks" do
    with_migrated_repo(fn repo ->
      run_staged_chunks_up!(repo)
      digest = digest_hex("oversized-object")
      loosen_object_size_constraint!(repo)
      insert_chunked_object!(repo, digest, @max_object_size + 1, [{0, <<"x">>}])
      restore_object_size_constraint_for_fixture!(repo)

      handler_id = {__MODULE__, :oversized_object, System.unique_integer([:positive])}

      :ok =
        :telemetry.attach(
          handler_id,
          @migration_telemetry_prefix,
          fn _event, _measurements, %{query: query}, owner ->
            if String.contains?(query, "frontend_release_object_chunks") do
              send(owner, :oversized_object_chunk_query)
            end
          end,
          self()
        )

      try do
        assert_raise Ecto.MigrationError, ~r/cannot restore frontend release object/, fn ->
          Ecto.Migrator.run(repo, migration_source(), :down, step: 1, log: false)
        end

        refute_receive :oversized_object_chunk_query, 100
        assert_failed_down_preserves_state(repo, digest, [[0, <<"x">>, 1]])
      after
        :telemetry.detach(handler_id)
      end
    end)
  end

  defp with_migrated_repo(fun) do
    database = unique_database_name()
    admin = start_admin_connection!()

    try do
      create_database!(admin, database)
      {:ok, _pid} = MigrationRepo.start_link(migration_repo_config(database))

      assert Ecto.Migrator.run(MigrationRepo, migration_source(), :up, step: 2, log: false) == [
               @create_publication_version,
               @create_objects_version
             ]

      fun.(MigrationRepo)
    after
      stop_migration_repo()
      drop_database!(admin, database)
      GenServer.stop(admin)
    end
  end

  defp migration_repo_config(database) do
    Application.fetch_env!(:cadence, Cadence.Repo)
    |> Keyword.take([:username, :password, :hostname, :port, :socket_dir, :ssl])
    |> Keyword.merge(
      database: database,
      pool_size: 2,
      telemetry_prefix: @migration_telemetry_prefix
    )
  end

  defp stop_migration_repo do
    if Process.whereis(MigrationRepo), do: MigrationRepo.stop()
  end

  defp run_staged_chunks_up!(repo) do
    assert Ecto.Migrator.run(repo, migration_source(), :up, step: 1, log: false) == [
             @migration_version
           ]
  end

  defp insert_inline_object!(repo, digest, bytes) do
    repo.query!(
      """
      INSERT INTO frontend_release_objects (sha256, bytes, size, inserted_at)
      VALUES ($1, $2, $3, TIMESTAMP '2026-08-31 00:00:00.123456')
      """,
      [digest, bytes, byte_size(bytes)]
    )
  end

  defp insert_chunked_object!(repo, digest, size, chunks) do
    repo.query!(
      """
      INSERT INTO frontend_release_objects (sha256, bytes, size, inserted_at)
      VALUES ($1, NULL, $2, TIMESTAMP '2026-08-31 00:01:02.654321')
      """,
      [digest, size]
    )

    for {chunk_index, bytes} <- chunks do
      repo.query!(
        """
        INSERT INTO frontend_release_object_chunks
          (sha256, chunk_index, bytes, size, inserted_at)
        VALUES ($1, $2, $3, $4, now())
        """,
        [digest, chunk_index, bytes, byte_size(bytes)]
      )
    end
  end

  defp insert_chunked_object_with_declared_size!(
         repo,
         digest,
         size,
         chunk_index,
         bytes,
         declared_size
       ) do
    repo.query!(
      """
      INSERT INTO frontend_release_objects (sha256, bytes, size, inserted_at)
      VALUES ($1, NULL, $2, TIMESTAMP '2026-08-31 00:01:02.654321')
      """,
      [digest, size]
    )

    repo.query!(
      """
      INSERT INTO frontend_release_object_chunks
        (sha256, chunk_index, bytes, size, inserted_at)
      VALUES ($1, $2, $3, $4, now())
      """,
      [digest, chunk_index, bytes, declared_size]
    )
  end

  defp insert_corrupt_fixture!(repo, :missing) do
    digest = digest_hex("missing-chunks")
    insert_chunked_object!(repo, digest, 3, [])
    {digest, []}
  end

  defp insert_corrupt_fixture!(repo, :gapped) do
    digest = digest_hex("gapped-chunks")
    insert_chunked_object!(repo, digest, 3, [{1, <<"abc">>}])
    {digest, [[1, <<"abc">>, 3]]}
  end

  defp insert_corrupt_fixture!(repo, :extra) do
    digest = digest_hex("extra-chunks")
    insert_chunked_object!(repo, digest, 3, [{0, <<"abc">>}, {1, <<"x">>}])
    {digest, [[0, <<"abc">>, 3], [1, <<"x">>, 1]]}
  end

  defp insert_corrupt_fixture!(repo, :wrong_declared_length) do
    digest = digest_hex("wrong-declared-length")
    loosen_chunk_size_constraint!(repo)
    insert_chunked_object_with_declared_size!(repo, digest, 3, 0, <<"abc">>, 2)

    restore_chunk_size_constraint_for_fixture!(repo)
    {digest, [[0, <<"abc">>, 2]]}
  end

  defp insert_corrupt_fixture!(repo, :total_size_mismatch) do
    digest = digest_hex("total-size-mismatch")
    insert_chunked_object!(repo, digest, 4, [{0, <<"abc">>}])
    {digest, [[0, <<"abc">>, 3]]}
  end

  defp insert_corrupt_fixture!(repo, :digest_mismatch) do
    digest = digest_hex("different-digest")
    insert_chunked_object!(repo, digest, 3, [{0, <<"abc">>}])
    {digest, [[0, <<"abc">>, 3]]}
  end

  defp assert_failed_down_preserves_state(repo, digest, expected_rows) do
    assert_raise Ecto.MigrationError, ~r/cannot restore frontend release object/, fn ->
      Ecto.Migrator.run(repo, migration_source(), :down, step: 1, log: false)
    end

    assert [[true]] =
             repo.query!("SELECT bytes IS NULL FROM frontend_release_objects WHERE sha256 = $1", [
               digest
             ]).rows

    assert ^expected_rows =
             repo.query!(
               """
               SELECT chunk_index, bytes, size
               FROM frontend_release_object_chunks
               WHERE sha256 = $1
               ORDER BY chunk_index
               """,
               [digest]
             ).rows

    assert [["O"]] =
             repo.query!("""
             SELECT tgenabled
             FROM pg_trigger
             WHERE tgrelid = 'frontend_release_objects'::regclass
               AND tgname = 'frontend_release_objects_append_only'
             """).rows

    assert [["O"]] =
             repo.query!("""
             SELECT tgenabled
             FROM pg_trigger
             WHERE tgrelid = 'frontend_release_object_chunks'::regclass
               AND tgname = 'frontend_release_object_chunks_append_only'
             """).rows
  end

  defp loosen_object_size_constraint!(repo) do
    repo.query!(
      "ALTER TABLE frontend_release_objects DROP CONSTRAINT frontend_release_objects_size_check"
    )
  end

  defp restore_object_size_constraint_for_fixture!(repo) do
    repo.query!("""
    ALTER TABLE frontend_release_objects
    ADD CONSTRAINT frontend_release_objects_size_check
    CHECK (size >= 0 AND size <= 100000000) NOT VALID
    """)
  end

  defp loosen_chunk_size_constraint!(repo) do
    repo.query!(
      "ALTER TABLE frontend_release_object_chunks DROP CONSTRAINT frontend_release_object_chunks_size_check"
    )
  end

  defp restore_chunk_size_constraint_for_fixture!(repo) do
    repo.query!("""
    ALTER TABLE frontend_release_object_chunks
    ADD CONSTRAINT frontend_release_object_chunks_size_check
    CHECK (size > 0 AND size <= 1048576 AND octet_length(bytes) = size) NOT VALID
    """)
  end

  defp start_admin_connection! do
    options =
      Application.fetch_env!(:cadence, Cadence.Repo)
      |> Keyword.take([:username, :password, :hostname, :port, :socket_dir, :ssl])
      |> Keyword.put(:database, "postgres")

    {:ok, connection} = Postgrex.start_link(options)
    connection
  end

  defp create_database!(admin, database),
    do: Postgrex.query!(admin, ~s(CREATE DATABASE "#{database}"), [])

  defp drop_database!(admin, database),
    do: Postgrex.query!(admin, ~s(DROP DATABASE IF EXISTS "#{database}"), [])

  defp unique_database_name do
    database = "cadence_frontend_release_migration_#{System.unique_integer([:positive])}"

    if Regex.match?(~r/\Acadence_frontend_release_migration_[0-9]+\z/, database),
      do: database,
      else: raise("invalid generated migration database name")
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

  defp digest_hex(bytes), do: Base.encode16(:crypto.hash(:sha256, bytes), case: :lower)
end
