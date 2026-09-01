defmodule CadenceWeb.FrontendReleasePublicationTest do
  use Cadence.DataCase, async: false

  alias Ecto.Adapters.SQL.Sandbox

  alias CadenceWeb.FrontendReleaseCatalog
  alias CadenceWeb.FrontendReleasePublication

  alias CadenceWeb.FrontendReleasePublication.{
    CatalogPublication,
    DatabaseArtifactStore,
    ReleaseObject,
    ReleasePublication
  }

  @fixture Path.expand("../../../../test/fixtures/frontend_release_catalog_v1.json", __DIR__)
  @corpus @fixture |> File.read!() |> Jason.decode!()
  @release_seed "9d61b19deffd5a60ba844af492ec2cc44449c5697b326919703bac031cae7f60"
  @promotion_seed "4ccd089b28ff96da9db6c346ec114e0f5b8a319f35aba624da8cf6ed4fb8a6fb"
  @fork_seed "d4f7f6f5c3d5b7c7e4a2b7eecf8f6e5d6c8b4e6f7a8b9c0d1e2f3a4b5c6d7e8f"
  @origin "https://cdn.example.com"
  @now "2026-08-30T18:30:00Z"
  @artifact_bytes %{
    "assets/app.js" => "app-bytes",
    "mf-manifest.json" => "manifest-bytes"
  }

  setup do
    previous_config = Application.get_env(:cadence_web, :frontend_release_publication)

    Application.put_env(
      :cadence_web,
      :frontend_release_publication,
      publication_config(@corpus["keys"])
    )

    on_exit(fn -> restore_config(previous_config) end)
    :ok
  end

  test "valid release admission stores immutable metadata and database objects" do
    {envelope, payload, release} = release_document(@artifact_bytes, "build-valid")

    assert {:ok, %ReleasePublication{} = publication} =
             FrontendReleasePublication.admit_release(envelope, @artifact_bytes, now: @now)

    assert publication.release_id == release["releaseId"]
    assert publication.payload_bytes == payload
    assert publication.payload_digest == sha256(payload)
    assert publication.signed_document_bytes == canonical(envelope)
    assert length(publication.artifacts) == 2

    Enum.each(publication.artifacts, fn artifact ->
      assert artifact.release_id == publication.release_id
      assert artifact.object_key == "sha256:" <> artifact.sha256

      object = Repo.get!(ReleaseObject, artifact.sha256)
      assert object.size == artifact.size
      assert object.bytes == Map.fetch!(@artifact_bytes, artifact.path)
    end)
  end

  test "put deduplicates identical objects and preserves the logical key" do
    bytes = "deduplicated-object"
    digest = sha256(bytes)

    assert {:ok, %{digest: ^digest, object_key: ^digest, status: :stored, size: size}} =
             DatabaseArtifactStore.put(digest, bytes)

    assert size == byte_size(bytes)

    assert {:ok, %{digest: ^digest, object_key: ^digest, status: :existing}} =
             DatabaseArtifactStore.put(digest, bytes)

    assert Repo.aggregate(ReleaseObject, :count, :sha256) == 1
  end

  test "a conflicting existing object fails closed without replacement" do
    bytes = "expected-data"
    conflicting_bytes = String.duplicate("x", byte_size(bytes))
    digest = sha256(bytes)
    sha256_hex = digest_hex(bytes)

    Repo.query!(
      """
      INSERT INTO frontend_release_objects (sha256, bytes, size, inserted_at)
      VALUES ($1, $2, $3, now())
      """,
      [sha256_hex, conflicting_bytes, byte_size(conflicting_bytes)]
    )

    assert {:error, :artifact_bytes_mismatch} = DatabaseArtifactStore.put(digest, bytes)
    assert Repo.one(from(object in ReleaseObject, select: object.bytes)) == conflicting_bytes
  end

  test "verify and read_chunk enforce metadata-first bounded reads at chunk boundaries" do
    bytes = :binary.copy(<<"a">>, 1_048_581)
    digest = sha256(bytes)

    assert {:ok, %{status: :stored}} = DatabaseArtifactStore.put(digest, bytes)
    assert :ok = DatabaseArtifactStore.verify(digest, byte_size(bytes))
    assert :ok = DatabaseArtifactStore.verify(digest, bytes)

    assert {:error, :invalid_chunk_bounds} =
             DatabaseArtifactStore.read_chunk(digest, 0, 1_048_577)

    assert {:ok, first_chunk} = DatabaseArtifactStore.read_chunk(digest, 0, 1_048_576)
    assert byte_size(first_chunk) == 1_048_576

    assert {:ok, last_chunk} = DatabaseArtifactStore.read_chunk(digest, 1_048_576, 5)
    assert last_chunk == :binary.copy(<<"a">>, 5)

    assert {:ok, <<>>} = DatabaseArtifactStore.read_chunk(digest, byte_size(bytes), 1)
    assert {:error, :invalid_chunk_bounds} = DatabaseArtifactStore.read_chunk(digest, 1, 0)
  end

  test "file uploads stay staged until promotion and serve from immutable chunks" do
    bytes = :binary.copy(<<"a">>, 1_048_581)
    digest = sha256(bytes)
    file_path = write_temp_file(bytes)

    assert {:ok, %{status: :stored, size: 1_048_581}} =
             DatabaseArtifactStore.put_file(digest, file_path)

    assert [[1, 1_048_581]] =
             Repo.query!(
               "SELECT COUNT(*), MAX(size) FROM frontend_release_staged_objects",
               []
             ).rows

    assert [[2]] =
             Repo.query!(
               "SELECT COUNT(*) FROM frontend_release_staged_object_chunks",
               []
             ).rows

    assert Repo.aggregate(ReleaseObject, :count, :sha256) == 0
    assert {:error, :artifact_not_found} = DatabaseArtifactStore.read_chunk(digest, 0, 1)

    assert {:ok, %{status: :existing}} = DatabaseArtifactStore.put_file(digest, file_path)

    assert {:ok, %{status: :stored}} =
             Repo.transaction(fn ->
               {:ok, stored} = DatabaseArtifactStore.promote_staged(digest, byte_size(bytes))
               stored
             end)

    assert Repo.aggregate(ReleaseObject, :count, :sha256) == 1
    assert [[nil]] = Repo.query!("SELECT bytes FROM frontend_release_objects", []).rows
    assert [[2]] = Repo.query!("SELECT COUNT(*) FROM frontend_release_object_chunks", []).rows
    assert [[0]] = Repo.query!("SELECT COUNT(*) FROM frontend_release_staged_objects", []).rows
    assert :ok = DatabaseArtifactStore.verify(digest, bytes)
    assert {:ok, first_chunk} = DatabaseArtifactStore.read_chunk(digest, 0, 1_048_576)
    assert byte_size(first_chunk) == 1_048_576
    assert {:ok, last_chunk} = DatabaseArtifactStore.read_chunk(digest, 1_048_576, 5)
    assert last_chunk == :binary.copy(<<"a">>, 5)
  end

  test "failed finalization retains stages and retry promotes them atomically" do
    {envelope, _payload, _release} = release_document(@artifact_bytes, "build-staged-retry")
    app_digest = sha256(@artifact_bytes["assets/app.js"])
    manifest_digest = sha256(@artifact_bytes["mf-manifest.json"])

    stage_file!(app_digest, @artifact_bytes["assets/app.js"])

    assert {:error, %{code: :artifact_not_found}} =
             FrontendReleasePublication.admit_release(
               envelope,
               %{
                 "assets/app.js" =>
                   {:object, app_digest, byte_size(@artifact_bytes["assets/app.js"])},
                 "mf-manifest.json" =>
                   {:object, manifest_digest, byte_size(@artifact_bytes["mf-manifest.json"])}
               },
               now: @now
             )

    assert [[1]] = Repo.query!("SELECT COUNT(*) FROM frontend_release_staged_objects", []).rows
    assert Repo.aggregate(ReleaseObject, :count, :sha256) == 0

    stage_file!(manifest_digest, @artifact_bytes["mf-manifest.json"])

    assert {:ok, publication} =
             FrontendReleasePublication.admit_release(
               envelope,
               staged_artifacts(@artifact_bytes),
               now: @now
             )

    assert length(publication.artifacts) == 2
    assert [[0]] = Repo.query!("SELECT COUNT(*) FROM frontend_release_staged_objects", []).rows
    assert [[2]] = Repo.query!("SELECT COUNT(*) FROM frontend_release_objects", []).rows
  end

  test "exact release replay is honored before staged-object promotion" do
    {envelope, _payload, release} = release_document(@artifact_bytes, "build-replay-stage")

    assert {:ok, _publication} =
             FrontendReleasePublication.admit_release(envelope, @artifact_bytes, now: @now)

    assert {:ok, replayed} =
             FrontendReleasePublication.admit_release(
               envelope,
               staged_artifacts(@artifact_bytes),
               now: @now
             )

    assert replayed.release_id == release["releaseId"]
    assert Repo.aggregate(ReleaseObject, :count, :sha256) == 2
  end

  test "expiry cleanup removes only unreferenced stages" do
    {envelope, _payload, _release} = release_document(@artifact_bytes, "build-stage-expiry")

    assert {:ok, _publication} =
             FrontendReleasePublication.admit_release(envelope, @artifact_bytes, now: @now)

    referenced_digest = sha256(@artifact_bytes["assets/app.js"])
    unreferenced_bytes = "unreferenced-staged-object"
    unreferenced_digest = sha256(unreferenced_bytes)
    stage_file!(referenced_digest, @artifact_bytes["assets/app.js"])
    stage_file!(unreferenced_digest, unreferenced_bytes)

    Repo.query!(
      "UPDATE frontend_release_staged_objects SET expires_at = now() - interval '1 hour'",
      []
    )

    assert {:ok, 1} = DatabaseArtifactStore.cleanup_expired_staged_artifacts()
    assert [[1]] = Repo.query!("SELECT COUNT(*) FROM frontend_release_staged_objects", []).rows

    expected_stage_digest = digest_hex(@artifact_bytes["assets/app.js"])

    assert [[^expected_stage_digest]] =
             Repo.query!("SELECT sha256 FROM frontend_release_staged_objects", []).rows
  end

  test "release objects and publication rows roll back together" do
    {envelope, _payload, release} = release_document(@artifact_bytes, "build-rollback")

    assert {:error, :forced_rollback} =
             Repo.transaction(fn ->
               assert {:ok, _publication} =
                        FrontendReleasePublication.admit_release(
                          envelope,
                          @artifact_bytes,
                          now: @now
                        )

               Repo.rollback(:forced_rollback)
             end)

    assert Repo.get_by(ReleasePublication, release_id: release["releaseId"]) == nil
    assert Repo.aggregate(ReleaseObject, :count, :sha256) == 0
  end

  test "identical release retry returns the original immutable publication" do
    {envelope, _payload, release} = release_document(@artifact_bytes, "build-retry")

    assert {:ok, first} =
             FrontendReleasePublication.admit_release(envelope, @artifact_bytes, now: @now)

    assert {:ok, second} =
             FrontendReleasePublication.admit_release(envelope, @artifact_bytes, now: @now)

    assert second.publication_id == first.publication_id
    assert second.release_id == release["releaseId"]
    assert Repo.aggregate(ReleasePublication, :count, :publication_id) == 1
    assert Repo.aggregate(ReleaseObject, :count, :sha256) == 2
  end

  test "same release identity with different signed bytes fails closed" do
    {envelope, _payload, release} = release_document(@artifact_bytes, "build-fork")
    alternate_key = alternate_release_key()

    Application.put_env(
      :cadence_web,
      :frontend_release_publication,
      publication_config(@corpus["keys"] ++ [alternate_key])
    )

    alternate_envelope =
      sign_fixture(
        canonical(release),
        "fixture-release-key-alt",
        "release",
        @fork_seed
      )

    assert {:ok, first} =
             FrontendReleasePublication.admit_release(envelope, @artifact_bytes, now: @now)

    assert first.release_id == release["releaseId"]

    assert {:error, %{code: :release_identity_fork}} =
             FrontendReleasePublication.admit_release(
               alternate_envelope,
               @artifact_bytes,
               now: @now
             )
  end

  test "artifact admission is exact and rejects missing, extra, duplicate, size, and hash inputs" do
    {envelope, _payload, _release} = release_document(@artifact_bytes, "build-artifacts")

    assert {:error, %{code: :missing_artifact}} =
             FrontendReleasePublication.admit_release(
               envelope,
               %{"assets/app.js" => @artifact_bytes["assets/app.js"]},
               now: @now
             )

    assert {:error, %{code: :undeclared_artifact}} =
             FrontendReleasePublication.admit_release(
               envelope,
               Map.put(@artifact_bytes, "assets/extra.js", "extra"),
               now: @now
             )

    assert {:error, %{code: :duplicate_artifact_path}} =
             FrontendReleasePublication.admit_release(
               envelope,
               [
                 {"assets/app.js", "app-bytes"},
                 {"assets/app.js", "app-bytes"},
                 {"mf-manifest.json", "manifest-bytes"}
               ],
               now: @now
             )

    assert {:error, %{code: :artifact_size_mismatch}} =
             FrontendReleasePublication.admit_release(
               envelope,
               Map.put(@artifact_bytes, "assets/app.js", "wrong"),
               now: @now
             )

    assert {:error, %{code: :artifact_hash_mismatch}} =
             FrontendReleasePublication.admit_release(
               envelope,
               Map.put(@artifact_bytes, "assets/app.js", "app-bytez"),
               now: @now
             )
  end

  test "artifact path spellings outside the signed allowlist fail closed" do
    {envelope, _payload, _release} = release_document(@artifact_bytes, "build-paths")

    for file_path <- [
          "../assets/app.js",
          "assets/../app.js",
          "assets\\app.js",
          "/assets/app.js"
        ] do
      assert {:error, %{code: :undeclared_artifact}} =
               FrontendReleasePublication.admit_release(
                 envelope,
                 Map.put(@artifact_bytes, file_path, "app-bytes"),
                 now: @now
               )
    end
  end

  test "aggregate artifact byte cap is enforced before storage and by PostgreSQL" do
    large_bytes = :binary.copy(<<"l">>, 100_000_000)
    small_bytes = "s"

    {over_cap_envelope, _payload, over_cap_release} =
      release_document(
        %{"assets/large.js" => large_bytes, "mf-manifest.json" => small_bytes},
        "build-over-cap"
      )

    assert {:error, %{code: :artifact_byte_cap_exceeded}} =
             FrontendReleasePublication.admit_release(
               over_cap_envelope,
               %{"assets/large.js" => large_bytes, "mf-manifest.json" => small_bytes},
               now: @now
             )

    assert Repo.get_by(ReleasePublication, release_id: over_cap_release["releaseId"]) == nil
    assert Repo.aggregate(ReleaseObject, :count, :sha256) == 0

    {seed_envelope, _seed_payload, seed_release} =
      release_document(%{"mf-manifest.json" => small_bytes}, "build-cap-trigger")

    assert {:ok, seed_publication} =
             FrontendReleasePublication.admit_release(
               seed_envelope,
               %{"mf-manifest.json" => small_bytes},
               now: @now
             )

    large_digest = digest_hex(large_bytes)

    Repo.query!(
      """
      INSERT INTO frontend_release_objects (sha256, bytes, size, inserted_at)
      VALUES ($1, $2, $3, now())
      """,
      [large_digest, large_bytes, byte_size(large_bytes)]
    )

    assert_sql_rejected(
      """
      INSERT INTO frontend_release_artifacts
        (artifact_id, release_publication_id, release_id, path, sha256, size, media_type, object_key, metadata, inserted_at)
      VALUES
        ('cap-trigger-artifact', $1, $2, 'assets/large.js', $3, 100000000,
         'application/javascript', $4, '{}'::jsonb, now())
      """,
      [
        seed_publication.publication_id,
        seed_release["releaseId"],
        large_digest,
        "sha256:" <> large_digest
      ]
    )
  end

  test "concurrent identical release admissions converge to one publication and objects" do
    {envelope, _payload, release} = release_document(@artifact_bytes, "build-concurrent")

    release_tasks =
      Enum.map(1..2, fn _index ->
        Task.async(fn ->
          FrontendReleasePublication.admit_release(envelope, @artifact_bytes, now: @now)
        end)
      end)

    Enum.each(release_tasks, fn %Task{pid: pid} -> Sandbox.allow(Cadence.Repo, self(), pid) end)
    release_results = Enum.map(release_tasks, &Task.await(&1, 30_000))

    assert Enum.all?(release_results, &match?({:ok, %ReleasePublication{}}, &1))
    assert Repo.aggregate(ReleasePublication, :count, :publication_id) == 1
    assert Repo.aggregate(ReleaseObject, :count, :sha256) == 2

    catalog = catalog_document(release, nil, 1, "2026-08-30T18:00:00Z")

    catalog_tasks =
      Enum.map(1..2, fn _index ->
        Task.async(fn -> FrontendReleasePublication.admit_catalog(catalog, now: @now) end)
      end)

    Enum.each(catalog_tasks, fn %Task{pid: pid} -> Sandbox.allow(Cadence.Repo, self(), pid) end)
    catalog_results = Enum.map(catalog_tasks, &Task.await(&1, 30_000))

    assert [{:ok, first}, {:ok, second}] =
             Enum.sort_by(catalog_results, &elem(&1, 1).publication_id)

    assert first.publication_id == second.publication_id
    assert Repo.aggregate(CatalogPublication, :count, :publication_id) == 1
  end

  test "catalog admission binds exact current and fallback nested envelope bytes" do
    {current_envelope, _current_payload, current_release} =
      release_document(@artifact_bytes, "build-catalog-current", "2026-08-30T17:30:00Z")

    fallback_bytes = Map.put(@artifact_bytes, "assets/app.js", "fallback-bytes")

    {fallback_envelope, _fallback_payload, fallback_release} =
      release_document(fallback_bytes, "build-catalog-fallback", "2026-08-30T16:30:00Z")

    assert {:ok, _} =
             FrontendReleasePublication.admit_release(
               current_envelope,
               @artifact_bytes,
               now: @now
             )

    assert {:ok, _} =
             FrontendReleasePublication.admit_release(fallback_envelope, fallback_bytes,
               now: @now
             )

    catalog = catalog_document(current_release, fallback_release, 2, "2026-08-30T18:00:00Z")

    assert {:ok, publication} =
             FrontendReleasePublication.admit_catalog(catalog, now: @now)

    current_row = Repo.get_by!(ReleasePublication, release_id: current_release["releaseId"])
    fallback_row = Repo.get_by!(ReleasePublication, release_id: fallback_release["releaseId"])

    assert publication.release_references == %{
             "entries" => [
               %{
                 "identity" => identity(current_release),
                 "currentReleaseId" => current_release["releaseId"],
                 "currentReleaseDigest" => current_row.payload_digest,
                 "currentSignedDocumentDigest" => current_row.signed_document_digest,
                 "fallbackReleaseId" => fallback_release["releaseId"],
                 "fallbackReleaseDigest" => fallback_row.payload_digest,
                 "fallbackSignedDocumentDigest" => fallback_row.signed_document_digest
               }
             ]
           }
  end

  test "alternate valid signature over identical nested payload fails closed" do
    {canonical_envelope, _payload, release} =
      release_document(@artifact_bytes, "build-nested-envelope")

    alternate_key = alternate_release_key()

    Application.put_env(
      :cadence_web,
      :frontend_release_publication,
      publication_config(@corpus["keys"] ++ [alternate_key])
    )

    alternate_envelope =
      sign_fixture(
        canonical(release),
        "fixture-release-key-alt",
        "release",
        @fork_seed
      )

    assert alternate_envelope["payload"] == canonical_envelope["payload"]
    assert alternate_envelope["signature"] != canonical_envelope["signature"]

    assert {:ok, _publication} =
             FrontendReleasePublication.admit_release(
               alternate_envelope,
               @artifact_bytes,
               now: @now
             )

    catalog = catalog_document(release, nil, 1, "2026-08-30T18:00:00Z")

    assert {:error, %{code: :release_publication_mismatch, path: "$.payload.entries[0].current"}} =
             FrontendReleasePublication.admit_catalog(catalog, now: @now)

    assert Repo.aggregate(CatalogPublication, :count, :publication_id) == 0
  end

  test "catalog replay, fork, lower, and non-monotonic publication cases are enforced" do
    {current_envelope, _current_payload, current_release} =
      release_document(@artifact_bytes, "build-catalog-rules", "2026-08-30T17:30:00Z")

    assert {:ok, _} =
             FrontendReleasePublication.admit_release(
               current_envelope,
               @artifact_bytes,
               now: @now
             )

    catalog = catalog_document(current_release, nil, 2, "2026-08-30T18:00:00Z")
    assert {:ok, first} = FrontendReleasePublication.admit_catalog(catalog, now: @now)
    assert {:ok, retry} = FrontendReleasePublication.admit_catalog(catalog, now: @now)
    assert retry.publication_id == first.publication_id

    fork = catalog_document(current_release, nil, 2, "2026-08-30T18:01:00Z")

    assert {:error, %{code: :same_sequence_fork}} =
             FrontendReleasePublication.admit_catalog(fork, now: @now)

    lower = catalog_document(current_release, nil, 1, "2026-08-30T18:02:00Z")

    assert {:error, %{code: :lower_sequence}} =
             FrontendReleasePublication.admit_catalog(lower, now: @now)

    non_monotonic = catalog_document(current_release, nil, 3, "2026-08-30T18:00:00Z")

    assert {:error, %{code: :non_monotonic_publication}} =
             FrontendReleasePublication.admit_catalog(non_monotonic, now: @now)
  end

  test "catalog references to a missing release roll back the catalog transaction" do
    {_missing_envelope, _missing_payload, missing_release} =
      release_document(@artifact_bytes, "build-missing-catalog-release")

    catalog = catalog_document(missing_release, nil, 1, "2026-08-30T18:00:00Z")

    assert {:error, %{code: :missing_release_publication}} =
             FrontendReleasePublication.admit_catalog(catalog, now: @now)

    assert Repo.aggregate(CatalogPublication, :count, :publication_id) == 0
  end

  test "configured trust records and allowed origins are mandatory" do
    {envelope, _payload, _release} = release_document(@artifact_bytes, "build-policy")
    config = Application.get_env(:cadence_web, :frontend_release_publication)

    Application.put_env(
      :cadence_web,
      :frontend_release_publication,
      Keyword.put(config, :trust_records, [])
    )

    assert {:error, %{code: :unknown_key}} =
             FrontendReleasePublication.admit_release(envelope, @artifact_bytes, now: @now)

    Application.put_env(
      :cadence_web,
      :frontend_release_publication,
      config
      |> Keyword.put(:trust_records, @corpus["keys"])
      |> Keyword.put(:allowed_origins, ["https://other.example.com"])
    )

    assert {:error, %{code: :invalid_base_url}} =
             FrontendReleasePublication.admit_release(envelope, @artifact_bytes, now: @now)

    refute Keyword.has_key?(config, :artifact_root)
    refute Keyword.has_key?(config, :artifact_store)
    refute function_exported?(CadenceWeb.FrontendReleasePublication, :readback, 1)
  end

  test "publication and object tables reject update, delete, and truncate" do
    {envelope, _payload, release} = release_document(@artifact_bytes, "build-mutations")

    assert {:ok, publication} =
             FrontendReleasePublication.admit_release(envelope, @artifact_bytes, now: @now)

    catalog = catalog_document(release, nil, 1, "2026-08-30T18:00:00Z")
    assert {:ok, _catalog} = FrontendReleasePublication.admit_catalog(catalog, now: @now)

    for sql <- [
          "UPDATE frontend_release_objects SET size = size",
          "DELETE FROM frontend_release_objects",
          "TRUNCATE frontend_release_objects CASCADE",
          "UPDATE frontend_release_artifacts SET size = size",
          "DELETE FROM frontend_release_artifacts",
          "TRUNCATE frontend_release_artifacts CASCADE",
          "UPDATE frontend_release_publications SET accepted_at = accepted_at",
          "DELETE FROM frontend_release_publications",
          "TRUNCATE frontend_release_publications CASCADE",
          "UPDATE frontend_release_catalog_publications SET accepted_at = accepted_at",
          "DELETE FROM frontend_release_catalog_publications",
          "TRUNCATE frontend_release_catalog_publications CASCADE"
        ] do
      assert_sql_rejected(sql)
    end

    assert Repo.get!(ReleasePublication, publication.publication_id).release_id ==
             release["releaseId"]
  end

  test "publication boundary exposes no update or delete API" do
    refute function_exported?(FrontendReleasePublication, :update_release, 2)
    refute function_exported?(FrontendReleasePublication, :delete_release, 1)
    refute function_exported?(FrontendReleasePublication, :update_catalog, 2)
    refute function_exported?(FrontendReleasePublication, :delete_catalog, 1)
  end

  test "invalid direct signed-document terms remain coded without masking" do
    assert {:error, %{code: :invalid_document, path: "$"}} =
             FrontendReleasePublication.admit_release(
               %{"unsupported" => self()},
               %{},
               now: @now
             )
  end

  defp assert_sql_rejected(sql, params \\ []) do
    result =
      Repo.transaction(fn ->
        case Repo.query(sql, params) do
          {:error, %Postgrex.Error{} = error} -> Repo.rollback(error)
          {:ok, _result} -> flunk("expected SQL rejection: #{sql}")
        end
      end)

    assert {:error, %Postgrex.Error{}} = result
  end

  defp publication_config(trust_records) do
    [trust_records: trust_records, allowed_origins: [@origin]]
  end

  defp restore_config(nil),
    do: Application.delete_env(:cadence_web, :frontend_release_publication)

  defp restore_config(config),
    do: Application.put_env(:cadence_web, :frontend_release_publication, config)

  defp release_document(bytes_by_path, build_id, released_at \\ "2026-08-30T17:00:00Z") do
    base = Jason.decode!(@corpus["release"]["payload"])

    artifacts =
      bytes_by_path
      |> Enum.sort_by(fn {file_path, _bytes} -> file_path end)
      |> Enum.map(fn {file_path, bytes} ->
        %{
          "mediaType" =>
            if(file_path == "mf-manifest.json",
              do: "application/json",
              else: "application/javascript"
            ),
          "path" => file_path,
          "sha256" => digest_hex(bytes),
          "size" => byte_size(bytes)
        }
      end)

    release =
      base
      |> Map.put("artifacts", artifacts)
      |> Map.put("manifest", Enum.find(artifacts, &(&1["path"] == "mf-manifest.json")))
      |> put_in(["provenance", "buildId"], build_id)
      |> Map.put("releasedAt", released_at)
      |> with_release_id()

    payload = canonical(release)
    {sign_fixture(payload, "fixture-release-key", "release", @release_seed), payload, release}
  end

  defp catalog_document(current, fallback, sequence, published_at) do
    entry = %{
      "identity" => identity(current),
      "current" => release_envelope(current)
    }

    entry = if fallback, do: Map.put(entry, "fallback", release_envelope(fallback)), else: entry

    payload =
      canonical(%{
        "entries" => [entry],
        "expiresAt" => "2026-09-01T18:00:00Z",
        "publishedAt" => published_at,
        "schema" => FrontendReleaseCatalog.catalog_schema(),
        "sequence" => sequence
      })

    sign_fixture(payload, "fixture-promotion-key", "promotion", @promotion_seed)
  end

  defp release_envelope(release),
    do: sign_fixture(canonical(release), "fixture-release-key", "release", @release_seed)

  defp identity(release) do
    %{
      "application" => release["application"],
      "package" => release["package"],
      "surface" => release["surface"]
    }
  end

  defp with_release_id(release) do
    logical = release |> Map.delete("releaseId") |> Map.delete("artifactBaseUrl")
    release_id = sha256(canonical(logical))

    Map.put(
      release,
      "releaseId",
      release_id
    )
    |> Map.put(
      "artifactBaseUrl",
      @origin <>
        "/releases/" <> release["application"]["id"] <> "/" <> release_id <> "/artifacts/"
    )
  end

  defp sign_fixture(payload, key_id, role, seed_hex) do
    private_key = Base.decode16!(seed_hex, case: :lower)
    signature = :crypto.sign(:eddsa, :none, payload, [private_key, :ed25519])

    %{
      "schema" => FrontendReleaseCatalog.envelope_schema(),
      "keyId" => key_id,
      "algorithm" => "ed25519",
      "signingRole" => role,
      "payloadEncoding" => "base64url-json",
      "payload" => Base.url_encode64(payload, padding: false),
      "signature" => Base.url_encode64(signature, padding: false)
    }
  end

  defp alternate_release_key do
    {public_key, _private_key} =
      :crypto.generate_key(
        :eddsa,
        :ed25519,
        Base.decode16!(@fork_seed, case: :lower)
      )

    %{
      "keyId" => "fixture-release-key-alt",
      "algorithm" => "ed25519",
      "publicKey" => Base.url_encode64(public_key, padding: false),
      "allowedRoles" => ["release"],
      "validFrom" => "2026-01-01T00:00:00Z",
      "validUntil" => "2027-01-01T00:00:00Z",
      "revokedAt" => nil
    }
  end

  defp staged_artifacts(bytes_by_path) do
    Map.new(bytes_by_path, fn {file_path, bytes} ->
      {file_path, {:object, sha256(bytes), byte_size(bytes)}}
    end)
  end

  defp stage_file!(digest, bytes) do
    file_path = write_temp_file(bytes)

    assert {:ok, %{digest: ^digest}} = DatabaseArtifactStore.put_file(digest, file_path)
    file_path
  end

  defp write_temp_file(bytes) do
    file_path =
      Path.join(
        System.tmp_dir!(),
        ".cadence_frontend_release_test_" <> Integer.to_string(System.unique_integer([:positive]))
      )

    File.write!(file_path, bytes)
    on_exit(fn -> File.rm(file_path) end)
    file_path
  end

  defp canonical(value) when is_map(value) do
    value
    |> Map.keys()
    |> Enum.sort()
    |> Enum.map_join(",", fn key ->
      Jason.encode!(key) <> ":" <> canonical(Map.fetch!(value, key))
    end)
    |> then(&("{" <> &1 <> "}"))
  end

  defp canonical(value) when is_list(value),
    do: "[" <> Enum.map_join(value, ",", &canonical/1) <> "]"

  defp canonical(value) when is_binary(value), do: Jason.encode!(value)
  defp canonical(value) when is_integer(value), do: Integer.to_string(value)
  defp canonical(true), do: "true"
  defp canonical(false), do: "false"
  defp canonical(nil), do: "null"

  defp sha256(bytes), do: "sha256:" <> digest_hex(bytes)
  defp digest_hex(bytes), do: Base.encode16(:crypto.hash(:sha256, bytes), case: :lower)
end
