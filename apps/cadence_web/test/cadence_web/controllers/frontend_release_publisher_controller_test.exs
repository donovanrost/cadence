defmodule CadenceWeb.FrontendReleasePublisherControllerTest do
  use CadenceWeb.ConnCase, async: false

  alias Cadence.Repo
  alias CadenceWeb.FrontendReleaseCatalog
  alias CadenceWeb.FrontendReleasePublication.ReleasePublication

  @path "/api/cadence/frontend-release/v1/releases"
  @fixture Path.expand("../../../../../test/fixtures/frontend_release_catalog_v1.json", __DIR__)
  @corpus @fixture |> File.read!() |> Jason.decode!()
  @release_seed "9d61b19deffd5a60ba844af492ec2cc44449c5697b326919703bac031cae7f60"
  @fork_seed "d4f7f6f5c3d5b7c7e4a2b7eecf8f6e5d6c8b4e6f7a8b9c0d1e2f3a4b5c6d7e8f"
  @origin "https://cdn.example.com"
  @token "frontend-release-publisher-test-token"
  @max_body_bytes 140_000_000

  setup do
    previous_publication_config =
      Application.get_env(:cadence_web, :frontend_release_publication)

    previous_publisher_config =
      Application.get_env(:cadence_web, :frontend_release_publisher)

    Application.put_env(
      :cadence_web,
      :frontend_release_publication,
      trust_records: @corpus["keys"],
      allowed_origins: [@origin]
    )

    Application.put_env(
      :cadence_web,
      :frontend_release_publisher,
      token_sha256: :crypto.hash(:sha256, @token)
    )

    on_exit(fn ->
      restore_config(:frontend_release_publication, previous_publication_config)
      restore_config(:frontend_release_publisher, previous_publisher_config)
    end)

    :ok
  end

  test "publishes exact document bytes through the API-only route and records provenance", %{
    conn: conn
  } do
    {document, _release, bytes_by_path} = release_document("http-success")

    response =
      conn
      |> authenticated()
      |> put_req_header("x-cadence-publisher-identity", "github-actions/frontend-release")
      |> post(@path, request_body(document, bytes_by_path))

    assert %{
             "data" => %{
               "release_id" => release_id,
               "publication_id" => publication_id,
               "status" => "published"
             }
           } = json_response(response, 201)

    publication = Repo.get_by!(ReleasePublication, release_id: release_id)
    assert publication.publication_id == publication_id
    assert publication.signed_document_bytes == document
    assert publication.metadata == %{"publisher_identity" => "github-actions/frontend-release"}
    assert publication.provenance["buildId"] == "http-success"
  end

  test "returns a deterministic exact replay response", %{conn: conn} do
    {document, _release, bytes_by_path} = release_document("http-replay")
    body = request_body(document, bytes_by_path)

    first = conn |> authenticated() |> post(@path, body)
    second = conn |> authenticated() |> post(@path, body)

    assert %{"data" => %{"status" => "published", "release_id" => release_id}} =
             json_response(first, 201)

    assert %{
             "data" => %{
               "status" => "replayed",
               "release_id" => ^release_id,
               "publication_id" => _publication_id
             }
           } = json_response(second, 200)

    assert Repo.aggregate(ReleasePublication, :count, :publication_id) == 1
  end

  test "returns conflict for a valid alternate signature over the same release", %{conn: conn} do
    {document, release, bytes_by_path} = release_document("http-conflict")

    assert %{"data" => %{"status" => "published"}} =
             conn
             |> authenticated()
             |> post(@path, request_body(document, bytes_by_path))
             |> json_response(201)

    alternate_key = alternate_release_key()

    Application.put_env(
      :cadence_web,
      :frontend_release_publication,
      trust_records: @corpus["keys"] ++ [alternate_key],
      allowed_origins: [@origin]
    )

    alternate_document =
      release
      |> canonical()
      |> sign_fixture("fixture-release-key-alt", "release", @fork_seed)
      |> canonical()

    response =
      conn
      |> authenticated()
      |> post(@path, request_body(alternate_document, bytes_by_path))

    assert %{"error" => %{"code" => "conflict"}} = json_response(response, 409)
  end

  test "returns admission rejection for a valid but untrusted signed document", %{conn: conn} do
    {document, _release, bytes_by_path} = release_document("http-admission-rejection")

    rejected_document =
      document
      |> Jason.decode!()
      |> Map.put("signature", "invalid-signature")
      |> canonical()

    response =
      conn
      |> authenticated()
      |> post(@path, request_body(rejected_document, bytes_by_path))

    assert %{"error" => %{"code" => "admission_rejected"}} = json_response(response, 422)
  end

  test "does not use browser session authentication or current scope", %{conn: conn} do
    response =
      conn
      |> Plug.Test.init_test_session(%{user_session_token: "browser-session-token"})
      |> put_req_header("accept", "application/json")
      |> put_req_header("content-type", "application/json")
      |> post(@path, "{}")

    assert %{"error" => %{"code" => "unauthenticated"}} = json_response(response, 401)
    assert get_req_header(response, "set-cookie") == []
  end

  test "fails closed for absent, malformed, wrong, and invalidly configured credentials", %{
    conn: conn
  } do
    requests = [
      conn |> put_req_header("content-type", "application/json") |> post(@path, "{}"),
      conn
      |> put_req_header("authorization", "Basic #{@token}")
      |> put_req_header("content-type", "application/json")
      |> post(@path, "{}"),
      conn
      |> put_req_header("authorization", "Bearer ")
      |> put_req_header("content-type", "application/json")
      |> post(@path, "{}"),
      conn
      |> put_req_header("authorization", "Bearer wrong-token")
      |> put_req_header("content-type", "application/json")
      |> post(@path, "{}")
    ]

    assert Enum.all?(
             requests,
             &(json_response(&1, 401) == %{"error" => %{"code" => "unauthenticated"}})
           )

    Application.put_env(:cadence_web, :frontend_release_publisher, token_sha256: "not-a-digest")

    response =
      conn
      |> authenticated()
      |> post(@path, "{}")

    assert %{"error" => %{"code" => "unauthenticated"}} = json_response(response, 401)
  end

  test "admits only application/json", %{conn: conn} do
    {document, _release, bytes_by_path} = release_document("http-media-type")
    body = request_body(document, bytes_by_path)

    response =
      conn
      |> authenticated()
      |> put_req_header("content-type", "application/problem+json")
      |> post(@path, body)

    assert %{"error" => %{"code" => "unsupported_media_type"}} = json_response(response, 415)
  end

  test "rejects unknown and duplicate request keys, duplicate paths, and malformed Base64", %{
    conn: conn
  } do
    {document, _release, bytes_by_path} = release_document("http-shape")
    encoded_document = Jason.encode!(document)
    encoded_bytes = Base.encode64("app-bytes")

    bodies = [
      Jason.encode!(%{
        "document" => document,
        "artifacts" => artifact_entries(bytes_by_path),
        "unknown" => true
      }),
      ~s({"document":#{encoded_document},"document":#{encoded_document},"artifacts":[]}),
      Jason.encode!(%{
        "document" => document,
        "artifacts" => [
          %{"path" => "assets/app.js", "bytesBase64" => encoded_bytes},
          %{"path" => "assets/app.js", "bytesBase64" => encoded_bytes}
        ]
      }),
      Jason.encode!(%{
        "document" => document,
        "artifacts" => [%{"path" => "assets/app.js", "bytesBase64" => "%%%"}]
      })
    ]

    responses =
      Enum.map(bodies, fn body ->
        conn
        |> authenticated()
        |> post(@path, body)
      end)

    assert Enum.all?(
             responses,
             &(json_response(&1, 400) == %{"error" => %{"code" => "malformed_body"}})
           )
  end

  test "rejects invalid UTF-8 and malformed JSON deterministically", %{conn: conn} do
    malformed_bodies = ["{\"document\":", <<"{\"document\":\"", 255, "\"}">>]

    responses =
      Enum.map(malformed_bodies, fn body ->
        conn
        |> authenticated()
        |> post(@path, body)
      end)

    assert Enum.all?(
             responses,
             &(json_response(&1, 400) == %{"error" => %{"code" => "malformed_json"}})
           )
  end

  test "rejects malformed and over-limit Content-Length before parsing", %{conn: conn} do
    malformed =
      conn
      |> authenticated()
      |> put_req_header("content-length", "not-a-length")
      |> post(@path, "{}")

    oversized =
      conn
      |> authenticated()
      |> put_req_header("content-length", Integer.to_string(@max_body_bytes + 1))
      |> post(@path, "{}")

    assert %{"error" => %{"code" => "malformed_body"}} = json_response(malformed, 400)
    assert %{"error" => %{"code" => "oversized_input"}} = json_response(oversized, 413)
  end

  test "rejects an over-limit chunked body without invoking the JSON parser", %{conn: conn} do
    body = String.duplicate("x", @max_body_bytes + 1)

    response =
      conn
      |> authenticated()
      |> post(@path, body)

    assert %{"error" => %{"code" => "oversized_input"}} = json_response(response, 413)
  end

  test "bypasses the default parser limit while retaining the exact bounded raw body", %{
    conn: conn
  } do
    body = " " <> String.duplicate("x", 8_000_000)

    response =
      conn
      |> authenticated()
      |> post(@path, body)

    assert %{"error" => %{"code" => "malformed_json"}} = json_response(response, 400)
  end

  defp authenticated(conn) do
    conn
    |> put_req_header("accept", "application/json")
    |> put_req_header("content-type", "application/json")
    |> put_req_header("authorization", "Bearer " <> @token)
  end

  defp request_body(document, bytes_by_path) do
    Jason.encode!(%{
      "document" => document,
      "artifacts" => artifact_entries(bytes_by_path)
    })
  end

  defp artifact_entries(bytes_by_path) do
    Enum.map(bytes_by_path, fn {path, bytes} ->
      %{"path" => path, "bytesBase64" => Base.encode64(bytes)}
    end)
  end

  defp release_document(build_id) do
    bytes_by_path = %{"assets/app.js" => "app-bytes", "mf-manifest.json" => "manifest-bytes"}
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
      |> Map.put("releasedAt", "2026-08-30T17:00:00Z")
      |> with_release_id()

    document =
      release
      |> canonical()
      |> sign_fixture("fixture-release-key", "release", @release_seed)
      |> canonical()

    {document, release, bytes_by_path}
  end

  defp with_release_id(release) do
    logical = release |> Map.delete("releaseId") |> Map.delete("artifactBaseUrl")
    release_id = sha256(canonical(logical))

    Map.put(release, "releaseId", release_id)
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

  defp restore_config(key, nil), do: Application.delete_env(:cadence_web, key)
  defp restore_config(key, value), do: Application.put_env(:cadence_web, key, value)
end
