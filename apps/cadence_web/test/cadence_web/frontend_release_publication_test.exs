defmodule CadenceWeb.FrontendReleasePublicationTest do
  use Cadence.DataCase, async: false

  alias Ecto.Adapters.SQL.Sandbox

  alias CadenceWeb.FrontendReleaseCatalog
  alias CadenceWeb.FrontendReleasePublication

  alias CadenceWeb.FrontendReleasePublication.{
    CatalogPublication,
    LocalArtifactStore,
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
    root =
      Path.join(
        File.cwd!(),
        ".cadence-frontend-release-publication-#{System.unique_integer([:positive])}"
      )

    :ok = File.mkdir_p(root)
    previous_config = Application.get_env(:cadence_web, :frontend_release_publication)

    Application.put_env(
      :cadence_web,
      :frontend_release_publication,
      publication_config(root, @corpus["keys"])
    )

    on_exit(fn ->
      restore_config(previous_config)
      File.rm_rf!(root)
    end)

    {:ok, root: root}
  end

  test "valid release admission stores immutable metadata and readback-verified objects", %{
    root: root
  } do
    {envelope, payload, release} = release_document(@artifact_bytes, "build-valid")

    assert {:ok, %ReleasePublication{} = publication} =
             FrontendReleasePublication.admit_release(envelope, @artifact_bytes, now: @now)

    assert publication.release_id == release["releaseId"]
    assert publication.payload_bytes == payload
    assert publication.payload_digest == sha256(payload)
    assert publication.signed_document_bytes == Jason.encode!(envelope, maps: :strict)

    assert {:ok, verified} =
             FrontendReleaseCatalog.verify_release(
               publication.signed_document_bytes,
               @corpus["keys"],
               allowed_origins: [@origin],
               now: @now
             )

    assert verified.payload_bytes == publication.payload_bytes
    assert verified.digest == publication.payload_digest
    assert publication.signing_key_id == "fixture-release-key"
    assert publication.signing_role == "release"
    assert publication.acceptance_state == "accepted"
    assert length(publication.artifacts) == 2

    Enum.each(publication.artifacts, fn artifact ->
      assert artifact.release_id == publication.release_id
      assert artifact.object_key =~ ~r/^sha256\/[0-9a-f]{2}\/[0-9a-f]{64}$/

      assert File.read!(Path.join(root, artifact.object_key)) ==
               Map.fetch!(@artifact_bytes, artifact.path)
    end)
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
  end

  test "same release identity with different signed bytes fails closed" do
    {envelope, _payload, release} = release_document(@artifact_bytes, "build-fork")
    alternate_key = alternate_release_key()

    Application.put_env(
      :cadence_web,
      :frontend_release_publication,
      publication_config(
        Application.get_env(:cadence_web, :frontend_release_publication)[:artifact_root],
        @corpus["keys"] ++ [alternate_key]
      )
    )

    alternate_envelope =
      sign_fixture(
        Jason.encode!(release, maps: :strict),
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

  test "destination symlinks, hardlinks, and collisions are rejected", %{root: root} do
    {envelope, _payload, _release} = release_document(@artifact_bytes, "build-destinations")
    object_path = prepare_object_path(root, @artifact_bytes["assets/app.js"])

    outside_path = Path.join(root, "outside")
    File.write!(outside_path, "outside")
    File.ln_s(outside_path, object_path)

    assert {:error, %{code: :destination_symlink}} =
             FrontendReleasePublication.admit_release(envelope, @artifact_bytes, now: @now)

    File.rm!(object_path)
    File.write!(outside_path, "hardlink")
    :ok = File.ln(outside_path, object_path)

    assert {:error, %{code: :destination_hardlink}} =
             FrontendReleasePublication.admit_release(envelope, @artifact_bytes, now: @now)

    File.rm!(object_path)
    File.rm!(outside_path)
    File.write!(object_path, "collision")

    assert {:error, %{code: :destination_collision}} =
             FrontendReleasePublication.admit_release(envelope, @artifact_bytes, now: @now)

    File.rm!(object_path)
    File.rm_rf!(Path.join(root, "sha256"))
    File.mkdir_p!(Path.join(root, "sha256"))

    symlinked_sha_root = Path.join(root, "sha256")
    outside_sha_root = Path.join(root, "outside-sha-root")
    File.mkdir!(outside_sha_root)
    File.rm_rf!(symlinked_sha_root)
    File.ln_s(outside_sha_root, symlinked_sha_root)

    assert {:error, %{code: :artifact_store_symlink}} =
             FrontendReleasePublication.admit_release(envelope, @artifact_bytes, now: @now)

    File.rm!(symlinked_sha_root)
    File.mkdir!(symlinked_sha_root)
    bucket = Path.join(symlinked_sha_root, digest_bucket(@artifact_bytes["assets/app.js"]))
    outside_bucket = Path.join(root, "outside-bucket")
    File.mkdir!(outside_bucket)
    File.ln_s(outside_bucket, bucket)

    assert {:error, %{code: :artifact_store_symlink}} =
             FrontendReleasePublication.admit_release(envelope, @artifact_bytes, now: @now)

    File.rm!(bucket)
    File.rm_rf!(outside_bucket)
    File.rm_rf!(symlinked_sha_root)
    object_path = prepare_object_path(root, @artifact_bytes["assets/app.js"])
    File.mkdir!(object_path)

    assert {:error, %{code: :destination_not_regular}} =
             FrontendReleasePublication.admit_release(envelope, @artifact_bytes, now: @now)

    refute Enum.any?(Path.wildcard(Path.join(root, "**/.tmp-*")))
  end

  test "a release transaction rolls back while an orphaned object remains harmless", %{root: root} do
    {envelope, _payload, release} = release_document(@artifact_bytes, "build-partial-failure")
    collision_path = prepare_object_path(root, @artifact_bytes["mf-manifest.json"])
    File.write!(collision_path, "collision")

    assert {:error, %{code: :destination_collision}} =
             FrontendReleasePublication.admit_release(envelope, @artifact_bytes, now: @now)

    first_object = prepare_object_path(root, @artifact_bytes["assets/app.js"])
    assert File.read!(first_object) == @artifact_bytes["assets/app.js"]
    assert Repo.get_by(ReleasePublication, release_id: release["releaseId"]) == nil
    assert Repo.aggregate(ReleasePublication, :count, :publication_id) == 0
    refute Enum.any?(Path.wildcard(Path.join(root, "**/.tmp-*")))
  end

  test "local readback rejects corruption after admission", %{root: root} do
    {envelope, _payload, _release} = release_document(@artifact_bytes, "build-corruption")

    assert {:ok, publication} =
             FrontendReleasePublication.admit_release(envelope, @artifact_bytes, now: @now)

    [artifact | _] = publication.artifacts
    file_path = Path.join(root, artifact.object_key)
    File.write!(file_path, "corrupted")

    assert {:error, :artifact_digest_mismatch} =
             LocalArtifactStore.readback("sha256:" <> artifact.sha256)
  end

  test "catalog admission persists only admitted current and fallback releases" do
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

    assert publication.sequence == 2
    assert publication.catalog_digest == sha256(payload_from_envelope(catalog))
    assert publication.acceptance_state == "accepted"

    assert {:ok, verified_catalog} =
             FrontendReleaseCatalog.verify_catalog(
               publication.signed_document_bytes,
               @corpus["keys"],
               allowed_origins: [@origin],
               now: @now
             )

    assert verified_catalog.payload_bytes == publication.payload_bytes
    assert verified_catalog.digest == publication.catalog_digest
    current_row = Repo.get_by!(ReleasePublication, release_id: current_release["releaseId"])

    assert publication.release_references == %{
             "entries" => [
               %{
                 "identity" => identity(current_release),
                 "currentReleaseId" => current_release["releaseId"],
                 "currentReleaseDigest" => current_row.payload_digest,
                 "currentSignedDocumentDigest" => current_row.signed_document_digest,
                 "fallbackReleaseId" => fallback_release["releaseId"],
                 "fallbackReleaseDigest" =>
                   Repo.get_by!(ReleasePublication, release_id: fallback_release["releaseId"]).payload_digest,
                 "fallbackSignedDocumentDigest" =>
                   Repo.get_by!(ReleasePublication, release_id: fallback_release["releaseId"]).signed_document_digest
               }
             ]
           }
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

  test "concurrent identical release and catalog admissions converge to one row" do
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

    Application.put_env(
      :cadence_web,
      :frontend_release_publication,
      Keyword.put(config, :artifact_root, "relative-artifact-root")
    )

    assert {:error, %{code: :artifact_store_root_not_absolute}} =
             FrontendReleasePublication.admit_release(envelope, @artifact_bytes, now: @now)
  end

  test "publication boundary exposes no update or delete API" do
    refute function_exported?(FrontendReleasePublication, :update_release, 2)
    refute function_exported?(FrontendReleasePublication, :delete_release, 1)
    refute function_exported?(FrontendReleasePublication, :update_catalog, 2)
    refute function_exported?(FrontendReleasePublication, :delete_catalog, 1)
  end

  defp publication_config(root, trust_records) do
    [
      artifact_store: LocalArtifactStore,
      artifact_root: root,
      trust_records: trust_records,
      allowed_origins: [@origin]
    ]
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

  defp payload_from_envelope(envelope) do
    envelope["payload"]
    |> Base.url_decode64!(padding: false)
  end

  defp prepare_object_path(root, bytes) do
    hex = digest_hex(bytes)
    bucket = Path.join(root, "sha256/" <> binary_part(hex, 0, 2))
    File.mkdir_p!(bucket)
    Path.join(bucket, hex)
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
  defp digest_bucket(bytes), do: bytes |> digest_hex() |> binary_part(0, 2)
  defp digest_hex(bytes), do: Base.encode16(:crypto.hash(:sha256, bytes), case: :lower)
end
