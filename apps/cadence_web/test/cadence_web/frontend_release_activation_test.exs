defmodule CadenceWeb.FrontendReleaseActivationTest do
  use Cadence.DataCase, async: false

  alias Ecto.Adapters.SQL.Sandbox

  alias CadenceWeb.FrontendReleaseActivation
  alias CadenceWeb.FrontendReleaseCatalog
  alias CadenceWeb.FrontendReleasePublication

  alias CadenceWeb.FrontendReleaseActivation.{CatalogBinding, CatalogGeneration, Request}

  alias CadenceWeb.FrontendReleasePublication.{CatalogPublication, ReleasePublication}

  @fixture Path.expand("../../../../test/fixtures/frontend_release_catalog_v1.json", __DIR__)
  @corpus @fixture |> File.read!() |> Jason.decode!()
  @release_seed "9d61b19deffd5a60ba844af492ec2cc44449c5697b326919703bac031cae7f60"
  @promotion_seed "4ccd089b28ff96da9db6c346ec114e0f5b8a319f35aba624da8cf6ed4fb8a6fb"
  @origin "https://cdn.example.com"
  @now "2026-09-01T19:00:00Z"
  @config [trust_records: @corpus["keys"], allowed_origins: [@origin]]
  @artifact_bytes %{
    "assets/app.js" => "app-bytes",
    "mf-manifest.json" => "manifest-bytes"
  }

  setup do
    previous = Process.get({FrontendReleasePublication, :publication_config}, :not_configured)
    Process.put({FrontendReleasePublication, :publication_config}, @config)

    on_exit(fn ->
      if previous == :not_configured do
        Process.delete({FrontendReleasePublication, :publication_config})
      else
        Process.put({FrontendReleasePublication, :publication_config}, previous)
      end
    end)

    :ok
  end

  test "initial activation persists a generation and exact immutable bindings" do
    {_document, _payload, release} = admit_release!(@artifact_bytes, "activation-initial")
    snapshot_digest = snapshot_digest("initial", 1, "2026-09-01T18:00:00Z", release, nil)
    catalog = v2_document("initial", 1, "2026-09-01T18:00:00Z", release, nil, snapshot_digest)

    assert {:ok, %{status: 201, outcome: "initial", replay?: false} = response} =
             activate(catalog, "initial-key")

    assert response.body ==
             canonical_response(%{
               "data" => %{
                 "catalogPublicationId" => response.catalog_publication_id,
                 "generationId" => response.generation_id,
                 "identityCount" => 1,
                 "outcome" => "initial",
                 "sequence" => 1,
                 "status" => "activated"
               }
             })

    assert Repo.aggregate(CatalogPublication, :count, :publication_id) == 1
    assert Repo.aggregate(CatalogGeneration, :count, :generation_id) == 1
    assert Repo.aggregate(CatalogBinding, :count, :generation_id) == 1
    assert Repo.aggregate(Request, :count, :request_id) == 1

    assert [[1, nil, false]] =
             Repo.query!("""
             SELECT cutover_epoch, legacy_catalog_publication_id, cutover_at IS NULL
             FROM frontend_release_activation_controls
             WHERE control_id = 1
             """).rows

    binding = Repo.one!(CatalogBinding)
    assert binding.current_release_id == release["releaseId"]
    assert binding.previous_publication_id == nil
    assert binding.previous_release_id == nil

    assert_immutable_row!(
      "frontend_release_catalog_generations",
      "generation_id",
      response.generation_id
    )

    assert_immutable_row!(
      "frontend_release_catalog_bindings",
      "generation_id",
      response.generation_id
    )

    assert_immutable_row!(
      "frontend_release_activation_requests",
      "request_id",
      Repo.one!(Request).request_id
    )

    assert [[1, 1, 1]] =
             Repo.query!("""
             SELECT
               (SELECT COUNT(*) FROM frontend_release_catalog_generations),
               (SELECT COUNT(*) FROM frontend_release_catalog_bindings),
               (SELECT COUNT(*) FROM frontend_release_activation_requests)
             """).rows
  end

  test "same key replays exact accepted bytes, while a different document is a 409" do
    {_document, _payload, release} = admit_release!(@artifact_bytes, "activation-replay")
    digest = snapshot_digest("initial", 1, "2026-09-01T18:00:00Z", release, nil)
    document = v2_document("initial", 1, "2026-09-01T18:00:00Z", release, nil, digest)

    assert {:ok, first} = activate(document, "replay-key")
    assert {:ok, second} = activate(document, "replay-key")
    assert second.replay? == true
    assert second.status == 201
    assert second.body == first.body
    assert Repo.aggregate(Request, :count, :request_id) == 1

    different = v2_document("initial", 1, "2026-09-01T18:00:01Z", release, nil, digest)
    assert {:error, %{status: 409, body: body}} = activate(different, "replay-key")
    assert body == ~s({"error":{"code":"idempotency_key_reused"}})
    assert Repo.aggregate(CatalogPublication, :count, :publication_id) == 1
    assert Repo.aggregate(Request, :count, :request_id) == 1
  end

  test "concurrent same-key same-document activation commits one row and one exact replay" do
    {_document, _payload, release} =
      admit_release!(@artifact_bytes, "activation-concurrent-replay")

    digest = snapshot_digest("initial", 1, "2026-09-01T18:00:00Z", release, nil)
    document = v2_document("initial", 1, "2026-09-01T18:00:00Z", release, nil, digest)

    results =
      concurrently([
        fn -> activate(document, "concurrent-replay-key") end,
        fn -> activate(document, "concurrent-replay-key") end
      ])

    assert Enum.count(results, &match?({:ok, %{status: 201, replay?: false}}, &1)) == 1
    assert Enum.count(results, &match?({:ok, %{status: 201, replay?: true}}, &1)) == 1

    [{:ok, accepted}, {:ok, replay}] =
      Enum.sort_by(results, &Map.fetch!(elem(&1, 1), :replay?))

    assert replay.body == accepted.body
    assert Repo.aggregate(CatalogPublication, :count, :publication_id) == 1
    assert Repo.aggregate(CatalogGeneration, :count, :generation_id) == 1
    assert Repo.aggregate(CatalogBinding, :count, :generation_id) == 1
    assert Repo.aggregate(Request, :count, :request_id) == 1
  end

  test "concurrent same-key different-document activation commits one and returns one exact 409" do
    {_document, _payload, release} =
      admit_release!(@artifact_bytes, "activation-concurrent-conflict")

    first_digest = snapshot_digest("initial", 1, "2026-09-01T18:00:00Z", release, nil)
    first = v2_document("initial", 1, "2026-09-01T18:00:00Z", release, nil, first_digest)

    second_digest = snapshot_digest("initial", 1, "2026-09-01T18:00:01Z", release, nil)
    second = v2_document("initial", 1, "2026-09-01T18:00:01Z", release, nil, second_digest)

    results =
      concurrently([
        fn -> activate(first, "concurrent-conflict-key") end,
        fn -> activate(second, "concurrent-conflict-key") end
      ])

    assert Enum.count(results, &match?({:ok, %{status: 201, replay?: false}}, &1)) == 1

    assert Enum.count(
             results,
             &match?(
               {:error, %{status: 409, body: ~s({"error":{"code":"idempotency_key_reused"}})}},
               &1
             )
           ) == 1

    assert Repo.aggregate(CatalogPublication, :count, :publication_id) == 1
    assert Repo.aggregate(CatalogGeneration, :count, :generation_id) == 1
    assert Repo.aggregate(CatalogBinding, :count, :generation_id) == 1
    assert Repo.aggregate(Request, :count, :request_id) == 1
  end

  test "semantic rejection is committed once without a catalog or generation" do
    {_document, _payload, release} = admit_release!(@artifact_bytes, "activation-rejected")
    document = v2_document("initial", 2, "2026-09-01T18:00:00Z", release, nil, sha256("wrong"))

    assert {:ok, %{status: 422, body: body}} = activate(document, "rejected-key")
    assert body == ~s({"error":{"code":"invalid_sequence","path":"$.payload.sequence"}})
    assert Repo.aggregate(CatalogPublication, :count, :publication_id) == 0
    assert Repo.aggregate(CatalogGeneration, :count, :generation_id) == 0
    assert Repo.aggregate(Request, :count, :request_id) == 1

    assert {:ok, replay} = activate(document, "rejected-key")
    assert replay.status == 422
    assert replay.body == body
    assert Repo.aggregate(Request, :count, :request_id) == 1
  end

  test "snapshot integrity failure rolls back catalog, generation, bindings, control, and ledger" do
    {_document, _payload, release} = admit_release!(@artifact_bytes, "activation-integrity")
    document = v2_document("initial", 1, "2026-09-01T18:00:00Z", release, nil, sha256("wrong"))

    assert {:error, %{status: 500, body: ~s({"error":{"code":"integrity_failure"}})}} =
             activate(document, "integrity-key")

    assert Repo.aggregate(CatalogPublication, :count, :publication_id) == 0
    assert Repo.aggregate(CatalogGeneration, :count, :generation_id) == 0
    assert Repo.aggregate(CatalogBinding, :count, :generation_id) == 0
    assert Repo.aggregate(Request, :count, :request_id) == 0

    assert [[0, nil]] =
             Repo.query!("""
             SELECT cutover_epoch, legacy_catalog_publication_id
             FROM frontend_release_activation_controls
             WHERE control_id = 1
             """).rows
  end

  test "promotion and rollback use exact predecessor pairs" do
    {_document, _payload, first_release} = admit_release!(@artifact_bytes, "activation-first")
    first_digest = snapshot_digest("initial", 1, "2026-09-01T18:00:00Z", first_release, nil)

    first_catalog =
      v2_document("initial", 1, "2026-09-01T18:00:00Z", first_release, nil, first_digest)

    assert {:ok, _} = activate(first_catalog, "transition-1")

    second_bytes = Map.put(@artifact_bytes, "assets/app.js", "second-app-bytes")
    {_document, _payload, second_release} = admit_release!(second_bytes, "activation-second")

    promotion_digest =
      snapshot_digest("promotion", 2, "2026-09-01T18:30:00Z", second_release, first_release)

    promotion =
      v2_document(
        "promotion",
        2,
        "2026-09-01T18:30:00Z",
        second_release,
        first_release,
        promotion_digest
      )

    assert {:ok, %{status: 201, outcome: "promotion"}} = activate(promotion, "transition-2")

    rollback_digest =
      snapshot_digest("rollback", 3, "2026-09-01T18:45:00Z", first_release, second_release)

    rollback =
      v2_document(
        "rollback",
        3,
        "2026-09-01T18:45:00Z",
        first_release,
        second_release,
        rollback_digest
      )

    assert {:ok, %{status: 201, outcome: "rollback"}} = activate(rollback, "transition-3")

    assert Repo.aggregate(CatalogPublication, :count, :publication_id) == 3
    assert Repo.aggregate(CatalogGeneration, :count, :generation_id) == 3

    [latest | _] =
      Repo.all(from(generation in CatalogGeneration, order_by: [desc: generation.sequence]))

    binding =
      Repo.one!(
        from(binding in CatalogBinding, where: binding.generation_id == ^latest.generation_id)
      )

    assert binding.current_release_id == first_release["releaseId"]
    assert binding.previous_release_id == second_release["releaseId"]
  end

  test "first legacy successor records exact legacy provenance and ignores only legacy expiry" do
    {_document, _payload, first_release} = admit_release!(@artifact_bytes, "activation-legacy")

    legacy_payload =
      canonical(%{
        "entries" => [
          %{"identity" => identity(first_release), "current" => release_envelope(first_release)}
        ],
        "expiresAt" => "2026-09-01T18:00:00Z",
        "publishedAt" => "2026-09-01T17:30:00Z",
        "schema" => FrontendReleaseCatalog.catalog_schema(),
        "sequence" => 10
      })

    legacy_document =
      sign_fixture(legacy_payload, "fixture-promotion-key", "promotion", @promotion_seed)
      |> canonical()

    legacy = insert_legacy_catalog!(legacy_document, legacy_payload, 10)

    second_bytes = Map.put(@artifact_bytes, "assets/app.js", "legacy-successor-bytes")

    {_document, _payload, second_release} =
      admit_release!(second_bytes, "activation-legacy-successor")

    successor_digest =
      snapshot_digest(
        "legacy_successor",
        11,
        "2026-09-01T18:30:00Z",
        second_release,
        first_release
      )

    successor =
      v2_document(
        "legacy_successor",
        11,
        "2026-09-01T18:30:00Z",
        second_release,
        first_release,
        successor_digest
      )

    assert {:ok, %{status: 201, outcome: "legacy_successor"} = response} =
             activate(successor, "legacy-successor-key")

    generation =
      Repo.get_by!(CatalogGeneration, catalog_publication_id: response.catalog_publication_id)

    assert generation.predecessor_kind == "legacy"
    assert generation.predecessor_catalog_publication_id == legacy.publication_id
    legacy_publication_id = legacy.publication_id

    assert [[1, ^legacy_publication_id]] =
             Repo.query!("""
             SELECT cutover_epoch, legacy_catalog_publication_id
             FROM frontend_release_activation_controls
             WHERE control_id = 1
             """).rows
  end

  test "direct catalog writers return the activation-required closure without reading or writing" do
    assert FrontendReleasePublication.admit_catalog(%{"bad" => self()}) ==
             {:error, :catalog_activation_required}

    assert FrontendReleasePublication.publish_catalog(%{"bad" => self()}) ==
             {:error, :catalog_activation_required}

    assert Repo.aggregate(CatalogPublication, :count, :publication_id) == 0
  end

  defp activate(document, key) do
    FrontendReleaseActivation.activate_catalog(document, key,
      now: @now,
      publication_config: @config,
      publisher_identity: "github-actions/frontend-release"
    )
  end

  defp concurrently(functions) do
    tasks =
      Enum.map(functions, fn function ->
        Task.async(fn ->
          receive do
            :activate -> function.()
          end
        end)
      end)

    Enum.each(tasks, fn %Task{pid: pid} ->
      :ok = Sandbox.allow(Repo, self(), pid)
    end)

    Enum.each(tasks, fn %Task{pid: pid} -> send(pid, :activate) end)
    Enum.map(tasks, &Task.await(&1, 30_000))
  end

  defp assert_immutable_row!(table, key_column, key) do
    assert_raise Postgrex.Error, fn ->
      Repo.query!("UPDATE #{table} SET inserted_at = inserted_at WHERE #{key_column} = $1", [key])
    end

    assert_raise Postgrex.Error, fn ->
      Repo.query!("DELETE FROM #{table} WHERE #{key_column} = $1", [key])
    end

    assert_raise Postgrex.Error, fn ->
      Repo.query!("TRUNCATE #{table}")
    end
  end

  defp admit_release!(bytes_by_path, build_id) do
    {document, payload, release} = release_document(bytes_by_path, build_id)

    assert {:ok, %ReleasePublication{}} =
             FrontendReleasePublication.admit_release(document, bytes_by_path, now: @now)

    {document, payload, release}
  end

  defp v2_document(transition, sequence, published_at, current, previous, snapshot_digest) do
    entry = %{"identity" => identity(current), "current" => release_envelope(current)}
    entry = if previous, do: Map.put(entry, "fallback", release_envelope(previous)), else: entry

    payload =
      canonical(%{
        "entries" => [entry],
        "expiresAt" => "2026-09-02T18:00:00Z",
        "identityCount" => 1,
        "publishedAt" => published_at,
        "schema" => FrontendReleaseCatalog.catalog_v2_schema(),
        "sequence" => sequence,
        "snapshotDigest" => snapshot_digest,
        "transition" => transition
      })

    sign_fixture(payload, "fixture-promotion-key", "promotion", @promotion_seed)
    |> canonical()
  end

  defp snapshot_digest(transition, sequence, published_at, current, previous) do
    snapshot = %{
      "entries" => [
        %{
          "current" => snapshot_release(current),
          "identity" => identity(current),
          "previous" => if(previous, do: snapshot_release(previous), else: nil)
        }
      ],
      "expiresAt" => "2026-09-02T18:00:00.000000Z",
      "identityCount" => 1,
      "publishedAt" => normalize_timestamp(published_at),
      "schema" => "cadence.first-party-frontend-release-persisted-snapshot.v1",
      "sequence" => sequence,
      "transition" => transition
    }

    sha256(canonical(snapshot))
  end

  defp snapshot_release(release) do
    row = Repo.get_by!(ReleasePublication, release_id: release["releaseId"])

    %{
      "artifactCount" => row.artifact_count,
      "artifactBaseUrl" => row.artifact_base_url,
      "identity" => identity(release),
      "manifest" => %{
        "mediaType" => row.manifest_media_type,
        "path" => row.manifest_path,
        "sha256" => row.manifest_sha256,
        "size" => row.manifest_size
      },
      "payloadDigest" => row.payload_digest,
      "provenance" => row.provenance,
      "releaseId" => row.release_id,
      "releasedAt" => normalize_datetime(row.released_at),
      "remoteName" => row.remote_name,
      "signingKeyId" => row.signing_key_id,
      "signingRole" => row.signing_role,
      "signedDocumentDigest" => row.signed_document_digest,
      "exposedModule" => row.exposed_module
    }
  end

  defp insert_legacy_catalog!(document, payload, sequence) do
    attrs = %{
      publication_id: "legacy-catalog-publication",
      sequence: sequence,
      catalog_digest: sha256(payload),
      signed_document_digest: sha256(document),
      signed_document_bytes: document,
      payload_bytes: payload,
      signing_key_id: "fixture-promotion-key",
      signing_role: "promotion",
      published_at: ~U[2026-09-01 17:30:00.000000Z],
      expires_at: ~U[2026-09-01 18:00:00.000000Z],
      acceptance_state: "accepted",
      accepted_state: %{},
      release_references: %{},
      accepted_at: ~U[2026-09-01 17:30:00.000000Z],
      inserted_at: ~U[2026-09-01 17:30:00.000000Z]
    }

    Repo.insert!(CatalogPublication.changeset(attrs))
  end

  defp release_document(bytes_by_path, build_id, released_at \\ "2026-09-01T17:00:00Z") do
    base = Jason.decode!(@corpus["release"]["payload"])

    artifacts =
      bytes_by_path
      |> Enum.sort_by(fn {path, _bytes} -> path end)
      |> Enum.map(fn {path, bytes} ->
        %{
          "mediaType" =>
            if(path == "mf-manifest.json", do: "application/json", else: "application/javascript"),
          "path" => path,
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

    {sign_fixture(payload, "fixture-release-key", "release", @release_seed) |> canonical(),
     payload, release}
  end

  defp release_envelope(release),
    do: sign_fixture(canonical(release), "fixture-release-key", "release", @release_seed)

  defp identity(release), do: Map.take(release, ["application", "package", "surface"])

  defp with_release_id(release) do
    logical = release |> Map.delete("releaseId") |> Map.delete("artifactBaseUrl")
    release_id = sha256(canonical(logical))

    release
    |> Map.put("releaseId", release_id)
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
      "algorithm" => "ed25519",
      "keyId" => key_id,
      "payload" => Base.url_encode64(payload, padding: false),
      "payloadEncoding" => "base64url-json",
      "schema" => FrontendReleaseCatalog.envelope_schema(),
      "signature" => Base.url_encode64(signature, padding: false),
      "signingRole" => role
    }
  end

  defp canonical_response(value), do: canonical(value)

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

  defp normalize_timestamp(value) do
    {:ok, datetime, _offset} = DateTime.from_iso8601(value)
    normalize_datetime(datetime)
  end

  defp normalize_datetime(datetime) do
    datetime = DateTime.from_unix!(DateTime.to_unix(datetime, :microsecond), :microsecond)
    Calendar.strftime(datetime, "%Y-%m-%dT%H:%M:%S.%fZ")
  end

  defp sha256(bytes), do: "sha256:" <> digest_hex(bytes)
  defp digest_hex(bytes), do: Base.encode16(:crypto.hash(:sha256, bytes), case: :lower)
end
