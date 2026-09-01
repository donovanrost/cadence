defmodule Cadence.FrontendReleaseActivationMigrationTest do
  use ExUnit.Case, async: false

  alias Cadence.FrontendReleaseMigrationTestRepo, as: MigrationRepo

  @migration_path Path.expand("../../priv/repo/migrations", __DIR__)
  @create_publication_version 20_260_831_000_000
  @create_objects_version 20_260_831_010_000
  @create_chunks_version 20_260_831_020_000
  @manifest_version 20_260_901_000_000
  @activation_version 20_260_901_010_000

  test "manifest metadata is backfilled from the exact release artifact and object" do
    with_base_repo(fn repo ->
      payload = release_payload()
      fixture = insert_release_fixture!(repo, payload)
      path = fixture.path
      sha256 = fixture.sha256
      size = fixture.size
      media_type = fixture.media_type

      assert Ecto.Migrator.run(repo, migration_source(), :up, step: 1, log: false) == [
               @manifest_version
             ]

      assert [[^path, ^sha256, ^size, ^media_type]] =
               repo.query!(
                 """
                 SELECT manifest_path, manifest_sha256, manifest_size, manifest_media_type
                 FROM frontend_release_publications
                 WHERE publication_id = $1
                 """,
                 [fixture.publication_id]
               ).rows

      assert [["O"]] = trigger_state(repo, "frontend_release_publications_append_only")

      assert Enum.all?(
               repo.query!("""
               SELECT is_nullable = 'NO', is_nullable = 'NO', is_nullable = 'NO', is_nullable = 'NO'
               FROM information_schema.columns
               WHERE table_name = 'frontend_release_publications'
                 AND column_name IN ('manifest_path', 'manifest_sha256', 'manifest_size', 'manifest_media_type')
               ORDER BY column_name
               """).rows,
               fn [path_not_null, sha_not_null, size_not_null, media_not_null] ->
                 path_not_null and sha_not_null and size_not_null and media_not_null
               end
             )
    end)
  end

  test "malformed payload and mismatched artifact/object roll back the manifest migration" do
    with_base_repo(fn repo ->
      malformed =
        ~s({"schema":"cadence.first-party-frontend-release.v1","manifest":{"mediaType":"application/javascript","path":"assets/main.js","sha256":"#{digest_hex("test")}","size":4}})

      insert_release_fixture!(repo, malformed)

      assert_raise Ecto.MigrationError, ~r/noncanonical_release_payload/, fn ->
        Ecto.Migrator.run(repo, migration_source(), :up, step: 1, log: false)
      end

      assert [[nil]] =
               repo.query!(
                 "SELECT to_regclass('frontend_release_publications_manifest_path_check')::text"
               ).rows

      assert [["O"]] = trigger_state(repo, "frontend_release_publications_append_only")
    end)

    with_base_repo(fn repo ->
      payload = release_payload()
      insert_release_fixture!(repo, payload, artifact_size: 3)

      assert_raise Ecto.MigrationError, ~r/manifest_artifact_object_mismatch/, fn ->
        Ecto.Migrator.run(repo, migration_source(), :up, step: 1, log: false)
      end

      assert [[nil]] =
               repo.query!(
                 "SELECT to_regclass('frontend_release_publications_manifest_path_check')::text"
               ).rows

      assert [["O"]] = trigger_state(repo, "frontend_release_publications_append_only")
    end)

    with_base_repo(fn repo ->
      payload = release_payload()
      insert_release_fixture!(repo, payload, artifact_media_type: "text/plain")

      assert_raise Ecto.MigrationError, ~r/manifest_artifact_object_mismatch/, fn ->
        Ecto.Migrator.run(repo, migration_source(), :up, step: 1, log: false)
      end

      assert [[nil]] =
               repo.query!(
                 "SELECT to_regclass('frontend_release_publications_manifest_path_check')::text"
               ).rows

      assert [["O"]] = trigger_state(repo, "frontend_release_publications_append_only")
    end)
  end

  test "activation migration preserves epoch-zero legacy writes and guards positive epochs" do
    with_phase_a_repo(fn repo ->
      insert_catalog!(repo, "legacy-catalog", 1)

      assert [[0, nil, nil]] =
               repo.query!("""
               SELECT cutover_epoch, cutover_at, legacy_catalog_publication_id
               FROM frontend_release_activation_controls
               WHERE control_id = 1
               """).rows

      repo.query!("""
      UPDATE frontend_release_activation_controls
      SET cutover_epoch = 1, cutover_at = TIMESTAMP '2026-09-01 00:00:00.123456'
      WHERE control_id = 1
      """)

      assert_raise Postgrex.Error,
                   ~r/accepted frontend release catalog publication requires a generation/,
                   fn ->
                     MigrationRepo.transaction(fn repo ->
                       insert_catalog!(repo, "orphan-catalog", 2)
                     end)
                   end

      assert [[0]] =
               repo.query!(
                 "SELECT COUNT(*) FROM frontend_release_catalog_publications WHERE publication_id = 'orphan-catalog'"
               ).rows

      assert_raise Postgrex.Error, fn ->
        repo.query!(
          "UPDATE frontend_release_activation_controls SET cutover_epoch = 0 WHERE control_id = 1"
        )
      end
    end)
  end

  test "activation DDL protects immutable tables and reversible down refuses populated state" do
    with_phase_a_repo(fn repo ->
      assert_raise Postgrex.Error, fn ->
        repo.query!("TRUNCATE frontend_release_catalog_generations")
      end

      assert_raise Postgrex.Error, fn ->
        repo.query!("DELETE FROM frontend_release_activation_controls")
      end

      assert_raise Postgrex.Error, fn ->
        repo.query!("TRUNCATE frontend_release_activation_controls")
      end

      assert_raise Ecto.MigrationError, ~r/nonzero_cutover_epoch/, fn ->
        repo.query!("""
        UPDATE frontend_release_activation_controls
        SET cutover_epoch = 1, cutover_at = TIMESTAMP '2026-09-01 00:00:00.123456'
        WHERE control_id = 1
        """)

        Ecto.Migrator.run(repo, migration_source(), :down, step: 1, log: false)
      end

      assert [["frontend_release_activation_controls"]] =
               repo.query!("SELECT to_regclass('frontend_release_activation_controls')::text").rows
    end)
  end

  test "safe down removes only Phase A metadata and tables" do
    with_base_repo(fn repo ->
      payload = release_payload()
      fixture = insert_release_fixture!(repo, payload)
      payload_bytes = fixture.payload_bytes
      object_bytes = fixture.object_bytes

      assert Ecto.Migrator.run(repo, migration_source(), :up, step: 2, log: false) == [
               @manifest_version,
               @activation_version
             ]

      assert Ecto.Migrator.run(repo, migration_source(), :down, step: 1, log: false) == [
               @activation_version
             ]

      assert Ecto.Migrator.run(repo, migration_source(), :down, step: 1, log: false) == [
               @manifest_version
             ]

      assert [[nil]] =
               repo.query!("SELECT to_regclass('frontend_release_activation_controls')::text").rows

      assert [[nil]] =
               repo.query!(
                 "SELECT to_regclass('frontend_release_publications_manifest_path_check')::text"
               ).rows

      assert [[^payload_bytes, ^object_bytes]] =
               repo.query!(
                 """
                 SELECT publication.payload_bytes, object.bytes
                 FROM frontend_release_publications AS publication
                 JOIN frontend_release_objects AS object ON object.sha256 = $2
                 WHERE publication.publication_id = $1
                 """,
                 [fixture.publication_id, fixture.sha256]
               ).rows

      assert [[1]] =
               repo.query!(
                 "SELECT COUNT(*) FROM frontend_release_artifacts WHERE artifact_id = $1",
                 [fixture.artifact_id]
               ).rows
    end)
  end

  defp with_phase_a_repo(fun) do
    with_base_repo(fn repo ->
      assert Ecto.Migrator.run(repo, migration_source(), :up, step: 2, log: false) == [
               @manifest_version,
               @activation_version
             ]

      fun.(repo)
    end)
  end

  defp with_base_repo(fun) do
    database =
      "cadence_frontend_release_activation_migration_#{System.unique_integer([:positive])}"

    admin = start_admin_connection!()

    try do
      Postgrex.query!(admin, ~s(CREATE DATABASE "#{database}"), [])
      {:ok, _pid} = MigrationRepo.start_link(migration_repo_config(database))

      assert Ecto.Migrator.run(MigrationRepo, migration_source(), :up, step: 3, log: false) == [
               @create_publication_version,
               @create_objects_version,
               @create_chunks_version
             ]

      fun.(MigrationRepo)
    after
      if Process.whereis(MigrationRepo), do: MigrationRepo.stop()
      Postgrex.query!(admin, ~s(DROP DATABASE IF EXISTS "#{database}"), [])
      GenServer.stop(admin)
    end
  end

  defp insert_release_fixture!(repo, payload, opts \\ []) do
    publication_id =
      Keyword.get(opts, :publication_id, "publication-#{System.unique_integer([:positive])}")

    release_id = "sha256:" <> String.duplicate("a", 64)
    payload_digest = "sha256:" <> digest_hex(payload)
    signed_digest = "sha256:" <> String.duplicate("b", 64)
    object_bytes = "test"
    sha256 = digest_hex(object_bytes)
    path = "assets/main.js"
    size = Keyword.get(opts, :artifact_size, byte_size(object_bytes))
    media_type = Keyword.get(opts, :artifact_media_type, "application/javascript")
    inserted_at = ~U[2026-09-01 00:00:00.123456Z]

    repo.query!(
      """
      INSERT INTO frontend_release_publications
        (publication_id, release_id, application_id, application_version, package_id, package_version,
         surface_id, surface_version, remote_name, exposed_module, artifact_base_url, payload_digest,
         signed_document_digest, signed_document_bytes, payload_bytes, signing_key_id, signing_role,
         released_at, artifact_count, accepted_at, inserted_at)
      VALUES ($1, $2, 'app', 1, 'pkg', 1, 'surface', 1, 'remote', './Main', 'https://example.test/assets',
              $3, $4, $5, $6, 'release-key', 'release', $7, 1, $7, $7)
      """,
      [publication_id, release_id, payload_digest, signed_digest, <<1>>, payload, inserted_at]
    )

    repo.query!(
      """
      INSERT INTO frontend_release_objects (sha256, bytes, size, inserted_at)
      VALUES ($1, $2, $3, $4)
      """,
      [sha256, object_bytes, byte_size(object_bytes), inserted_at]
    )

    artifact_id = "artifact-#{System.unique_integer([:positive])}"

    repo.query!(
      """
      INSERT INTO frontend_release_artifacts
        (artifact_id, release_publication_id, release_id, path, sha256, size, media_type, object_key, inserted_at)
      VALUES ($1, $2, $3, $4, $5, $6, $7, $8, $9)
      """,
      [
        artifact_id,
        publication_id,
        release_id,
        path,
        sha256,
        size,
        media_type,
        "sha256:" <> sha256,
        inserted_at
      ]
    )

    %{
      publication_id: publication_id,
      artifact_id: artifact_id,
      payload_bytes: payload,
      object_bytes: object_bytes,
      path: path,
      sha256: sha256,
      size: size,
      media_type: media_type
    }
  end

  defp release_payload do
    canonical_json(%{
      "manifest" => %{
        "mediaType" => "application/javascript",
        "path" => "assets/main.js",
        "sha256" => digest_hex("test"),
        "size" => 4
      },
      "schema" => "cadence.first-party-frontend-release.v1"
    })
  end

  defp insert_catalog!(repo, publication_id, sequence) do
    digest = "sha256:" <> digest_hex(publication_id)
    signed_digest = "sha256:" <> digest_hex("signed:" <> publication_id)

    repo.query!(
      """
      INSERT INTO frontend_release_catalog_publications
        (publication_id, sequence, catalog_digest, signed_document_digest, signed_document_bytes,
         payload_bytes, signing_key_id, signing_role, published_at, expires_at, accepted_state,
         release_references, accepted_at, inserted_at)
      VALUES ($1, $2, $3, $4, $5, $6, 'catalog-key', 'promotion',
              TIMESTAMP '2026-09-01 00:00:00.123456', TIMESTAMP '2026-09-02 00:00:00.123456',
              '{}'::jsonb, '{}'::jsonb, TIMESTAMP '2026-09-01 00:00:00.123456', TIMESTAMP '2026-09-01 00:00:00.123456')
      """,
      [publication_id, sequence, digest, signed_digest, <<1>>, <<2>>]
    )
  end

  defp trigger_state(repo, trigger_name) do
    repo.query!(
      """
      SELECT tgenabled
      FROM pg_trigger
      WHERE tgrelid = 'frontend_release_publications'::regclass AND tgname = $1
      """,
      [trigger_name]
    ).rows
  end

  defp migration_repo_config(database) do
    Application.fetch_env!(:cadence, Cadence.Repo)
    |> Keyword.take([:username, :password, :hostname, :port, :socket_dir, :ssl])
    |> Keyword.merge(database: database, pool_size: 2)
  end

  defp start_admin_connection! do
    options =
      Application.fetch_env!(:cadence, Cadence.Repo)
      |> Keyword.take([:username, :password, :hostname, :port, :socket_dir, :ssl])
      |> Keyword.put(:database, "postgres")

    {:ok, connection} = Postgrex.start_link(options)
    connection
  end

  defp migration_source do
    [
      {@create_publication_version,
       "20260831000000_create_frontend_release_publication_tables.exs"},
      {@create_objects_version, "20260831010000_add_frontend_release_objects.exs"},
      {@create_chunks_version, "20260831020000_add_frontend_release_staged_chunks.exs"},
      {@manifest_version, "20260901000000_add_frontend_release_manifest_metadata.exs"},
      {@activation_version, "20260901010000_create_frontend_release_activation_tables.exs"}
    ]
    |> Enum.map(fn {version, filename} -> {version, Path.join(@migration_path, filename)} end)
  end

  defp canonical_json(value) when is_map(value) do
    value
    |> Map.keys()
    |> Enum.sort()
    |> Enum.map_join(",", fn key ->
      Jason.encode!(key) <> ":" <> canonical_json(Map.fetch!(value, key))
    end)
    |> then(&("{" <> &1 <> "}"))
  end

  defp canonical_json(value) when is_binary(value), do: Jason.encode!(value)
  defp canonical_json(value) when is_integer(value), do: Integer.to_string(value)
  defp canonical_json(true), do: "true"
  defp canonical_json(false), do: "false"
  defp canonical_json(nil), do: "null"
  defp digest_hex(bytes), do: Base.encode16(:crypto.hash(:sha256, bytes), case: :lower)
end
