defmodule CadenceWeb.FrontendReleasePublisherControllerTest do
  use CadenceWeb.ConnCase, async: false

  alias Ecto.Adapters.SQL.Sandbox

  alias Cadence.Repo
  alias CadenceWeb.Endpoint
  alias CadenceWeb.FrontendReleaseCatalog
  alias CadenceWeb.FrontendReleasePublication.DatabaseArtifactStore
  alias CadenceWeb.FrontendReleasePublication.ReleasePublication
  alias CadenceWeb.FrontendReleasePublisherTestAdapter
  alias CadenceWeb.Plugs.FrontendReleasePublisher

  @path "/api/cadence/frontend-release/v1/releases"
  @object_prefix "/api/cadence/frontend-release/v1/objects/"
  @fixture Path.expand("../../../../../test/fixtures/frontend_release_catalog_v1.json", __DIR__)
  @corpus @fixture |> File.read!() |> Jason.decode!()
  @release_seed "9d61b19deffd5a60ba844af492ec2cc44449c5697b326919703bac031cae7f60"
  @fork_seed "d4f7f6f5c3d5b7c7e4a2b7eecf8f6e5d6c8b4e6f7a8b9c0d1e2f3a4b5c6d7e8f"
  @origin "https://cdn.example.com"
  @token "frontend-release-publisher-test-token"
  @max_envelope_bytes 4_000_000

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

  test "public publication rejects improper configured role and origin lists", %{conn: conn} do
    {document, _release, bytes_by_path} = release_document("http-improper-config")
    first_key = hd(@corpus["keys"])
    improper_key = Map.put(first_key, "allowedRoles", ["release" | :tail])

    Application.put_env(
      :cadence_web,
      :frontend_release_publication,
      trust_records: [improper_key | tl(@corpus["keys"])],
      allowed_origins: [@origin]
    )

    role_response =
      conn
      |> authenticated()
      |> post(@path, request_body(document, bytes_by_path))

    assert %{"error" => %{"code" => "admission_rejected"}} = json_response(role_response, 422)

    Application.put_env(
      :cadence_web,
      :frontend_release_publication,
      trust_records: @corpus["keys"],
      allowed_origins: [@origin | :tail]
    )

    origin_response =
      conn
      |> authenticated()
      |> post(@path, request_body(document, bytes_by_path))

    assert %{"error" => %{"code" => "admission_rejected"}} =
             json_response(origin_response, 422)
  end

  test "maps direct and tagged database connection failures to 503 at the endpoint" do
    {document, _release, bytes_by_path} = release_document("http-db-failure")
    inline_body = request_body(document, bytes_by_path)
    staged_body = staged_request_body(document, bytes_by_path)

    assert 503 ==
             endpoint_db_failure("pg_advisory_xact_lock", inline_body, fn -> :ok end)

    assert 503 ==
             endpoint_db_failure(
               "FROM \"frontend_release_publications\"",
               inline_body,
               fn -> :ok end
             )

    assert 503 ==
             endpoint_db_failure(
               "FROM \"frontend_release_publications\"",
               staged_body,
               fn -> stage_worker_artifacts(bytes_by_path) end
             )

    assert 503 ==
             endpoint_db_failure(
               "SELECT size FROM frontend_release_staged_objects",
               staged_body,
               fn -> stage_worker_artifacts(bytes_by_path) end
             )
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

  test "PUT upload authenticates, validates media and digest path, and is idempotent", %{
    conn: conn
  } do
    body = "controller-staged-artifact"
    digest = sha256(body)

    unauthenticated =
      conn
      |> put_req_header("content-type", "application/octet-stream")
      |> put(@object_prefix <> digest, body)

    unsupported =
      conn
      |> authenticated()
      |> put_req_header("content-type", "application/json")
      |> put(@object_prefix <> digest, body)

    malformed_path =
      conn
      |> authenticated_upload()
      |> put(@object_prefix <> "not-a-digest", body)

    first = conn |> authenticated_upload() |> put(@object_prefix <> digest, body)
    second = conn |> authenticated_upload() |> put(@object_prefix <> digest, body)

    assert %{"error" => %{"code" => "unauthenticated"}} = json_response(unauthenticated, 401)
    assert %{"error" => %{"code" => "unsupported_media_type"}} = json_response(unsupported, 415)

    assert %{"error" => %{"code" => "malformed_artifact_path"}} =
             json_response(malformed_path, 400)

    assert %{"data" => %{"status" => "stored"}} = json_response(first, 201)
    assert %{"data" => %{"status" => "existing"}} = json_response(second, 200)

    assert Repo.aggregate(CadenceWeb.FrontendReleasePublication.ReleaseObject, :count, :sha256) ==
             0
  end

  test "staged uploads are invisible until release finalization", %{conn: conn} do
    {document, release, bytes_by_path} = release_document("http-staged-publication")

    Enum.each(bytes_by_path, fn {_artifact_path, bytes} ->
      digest = sha256(bytes)

      assert %{"data" => %{"status" => "stored"}} =
               conn
               |> authenticated_upload()
               |> put(@object_prefix <> digest, bytes)
               |> json_response(201)
    end)

    assert Repo.aggregate(CadenceWeb.FrontendReleasePublication.ReleaseObject, :count, :sha256) ==
             0

    response =
      conn
      |> authenticated()
      |> post(@path, staged_request_body(document, bytes_by_path))

    assert %{"data" => %{"release_id" => release_id, "status" => "published"}} =
             json_response(response, 201)

    assert release_id == release["releaseId"]
    assert Repo.query!("SELECT COUNT(*) FROM frontend_release_staged_objects", []).rows == [[0]]
    assert Repo.query!("SELECT COUNT(*) FROM frontend_release_objects", []).rows == [[2]]
    assert Repo.query!("SELECT COUNT(*) FROM frontend_release_object_chunks", []).rows == [[2]]
  end

  test "failed controller finalization retains a stage for retry", %{conn: conn} do
    {document, _release, bytes_by_path} = release_document("http-staged-retry")
    app_bytes = bytes_by_path["assets/app.js"]
    manifest_bytes = bytes_by_path["mf-manifest.json"]
    app_digest = sha256(app_bytes)
    manifest_digest = sha256(manifest_bytes)

    assert %{"data" => %{"status" => "stored"}} =
             conn
             |> authenticated_upload()
             |> put(@object_prefix <> app_digest, app_bytes)
             |> json_response(201)

    failed =
      conn
      |> authenticated()
      |> post(@path, staged_request_body(document, bytes_by_path))

    assert %{"error" => %{"code" => "admission_rejected"}} = json_response(failed, 422)
    assert Repo.query!("SELECT COUNT(*) FROM frontend_release_staged_objects", []).rows == [[1]]
    assert Repo.query!("SELECT COUNT(*) FROM frontend_release_objects", []).rows == [[0]]

    assert %{"data" => %{"status" => "stored"}} =
             conn
             |> authenticated_upload()
             |> put(@object_prefix <> manifest_digest, manifest_bytes)
             |> json_response(201)

    assert %{"data" => %{"status" => "published"}} =
             conn
             |> authenticated()
             |> post(@path, staged_request_body(document, bytes_by_path))
             |> json_response(201)

    assert Repo.query!("SELECT COUNT(*) FROM frontend_release_staged_objects", []).rows == [[0]]
  end

  test "endpoint preflight rejects invalid auth before any body read" do
    result =
      endpoint_conn([
        {"authorization", "Bearer wrong-token"},
        {"content-type", "application/json"},
        {"content-length", Integer.to_string(@max_envelope_bytes)}
      ])
      |> Endpoint.call([])

    assert result.status == 401
    refute_receive {:frontend_release_publisher_read, _, _}
  end

  test "endpoint preflight rejects unsupported media after auth before any body read" do
    result =
      endpoint_conn([
        {"authorization", "Bearer " <> @token},
        {"content-type", "text/plain"},
        {"content-length", Integer.to_string(@max_envelope_bytes)}
      ])
      |> Endpoint.call([])

    assert result.status == 415
    refute_receive {:frontend_release_publisher_read, _, _}
  end

  test "production endpoint propagates body-reader exits, exceptions, and throws" do
    signals = [
      {:exit, :adapter_exit},
      {:raise, RuntimeError},
      {:throw, :adapter_throw}
    ]

    for signal <- signals do
      conn =
        endpoint_conn_with_adapter(
          FrontendReleasePublisherTestAdapter.responses([signal], self()),
          [
            {"authorization", "Bearer " <> @token},
            {"content-type", "application/json"}
          ]
        )

      assert_signal_propagated(signal, fn -> Endpoint.call(conn, []) end)
    end
  end

  test "publisher auth is exact-path and idempotent when the router repeats it" do
    conn =
      Plug.Test.conn(:post, @path, "")
      |> put_req_header("authorization", "Bearer " <> @token)
      |> put_req_header("content-type", "application/json")

    assert %{halted: false} = first = FrontendReleasePublisher.call(conn, [])
    assert %{halted: false} = FrontendReleasePublisher.call(first, [])

    near_path =
      Plug.Test.conn(:post, @path <> "/extra", "")
      |> put_req_header("authorization", "Bearer wrong-token")

    get_request = Plug.Test.conn(:get, @path, "")

    assert %{halted: false} = FrontendReleasePublisher.call(near_path, [])
    assert %{halted: false} = FrontendReleasePublisher.call(get_request, [])
  end

  test "non-publisher requests retain default parser behavior" do
    result =
      Plug.Test.conn(:post, "/api/health", ~s({"outside":true}))
      |> put_req_header("accept", "application/json")
      |> put_req_header("content-type", "application/json")
      |> Endpoint.call([])

    assert result.status == 404
    assert result.body_params == %{"outside" => true}
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
      |> put_req_header("content-length", Integer.to_string(@max_envelope_bytes + 1))
      |> post(@path, "{}")

    assert %{"error" => %{"code" => "malformed_body"}} = json_response(malformed, 400)
    assert %{"error" => %{"code" => "oversized_input"}} = json_response(oversized, 413)
  end

  test "rejects an over-limit chunked body without invoking the JSON parser", %{conn: conn} do
    body = String.duplicate("x", @max_envelope_bytes + 1)

    response =
      conn
      |> authenticated()
      |> post(@path, body)

    assert %{"error" => %{"code" => "oversized_input"}} = json_response(response, 413)
  end

  test "bypasses the default parser limit while retaining the exact bounded raw body", %{
    conn: conn
  } do
    body = String.duplicate("x", @max_envelope_bytes)

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

  defp authenticated_upload(conn) do
    conn
    |> put_req_header("accept", "application/json")
    |> put_req_header("content-type", "application/octet-stream")
    |> put_req_header("authorization", "Bearer " <> @token)
  end

  defp endpoint_conn(headers) do
    endpoint_conn_with_adapter(FrontendReleasePublisherTestAdapter.body("", self()), headers)
  end

  defp endpoint_conn_with_adapter(adapter_state, headers) do
    Plug.Test.conn(:post, @path, "")
    |> then(&%{&1 | adapter: {FrontendReleasePublisherTestAdapter, adapter_state}})
    |> then(
      &Enum.reduce(headers, &1, fn {name, value}, conn -> put_req_header(conn, name, value) end)
    )
  end

  defp request_body(document, bytes_by_path) do
    Jason.encode!(%{
      "document" => document,
      "artifacts" => artifact_entries(bytes_by_path)
    })
  end

  defp staged_request_body(document, bytes_by_path) do
    Jason.encode!(%{
      "document" => document,
      "artifacts" =>
        Enum.map(bytes_by_path, fn {file_path, bytes} ->
          %{"path" => file_path, "sha256" => sha256(bytes), "size" => byte_size(bytes)}
        end)
    })
  end

  defp endpoint_db_failure(query_fragment, body, setup_fun) do
    owner = self()

    task =
      Task.async(fn ->
        :ok = Sandbox.checkout(Repo)

        try do
          setup_fun.()
          [[backend_pid]] = Repo.query!("SELECT pg_backend_pid()", []).rows
          send(owner, {:r5_worker_backend, backend_pid})

          receive do
            :publish ->
              Plug.Test.conn(:post, @path, body)
              |> put_req_header("accept", "application/json")
              |> put_req_header("content-type", "application/json")
              |> put_req_header("authorization", "Bearer " <> @token)
              |> Endpoint.call([])
              |> Map.fetch!(:status)
          end
        after
          try do
            Sandbox.checkin(Repo)
          catch
            _kind, _reason -> :ok
          end
        end
      end)

    assert_receive {:r5_worker_backend, backend_pid}, 5_000
    handler_id = {__MODULE__, :r5_db_failure, System.unique_integer([:positive])}

    :ok =
      :telemetry.attach(
        handler_id,
        [:cadence, :repo, :query],
        fn _event, _measurements, %{query: query}, {owner, query_fragment, backend_pid} ->
          if String.contains?(query, query_fragment) do
            terminate_backend!(backend_pid)
            send(owner, {:r5_db_failure_terminated, query_fragment})
          end
        end,
        {owner, query_fragment, backend_pid}
      )

    result =
      try do
        send(task.pid, :publish)
        assert_receive {:r5_db_failure_terminated, ^query_fragment}, 5_000
        Task.await(task, 10_000)
      after
        :telemetry.detach(handler_id)
      end

    result
  end

  defp terminate_backend!(backend_pid) do
    repo_config = Application.fetch_env!(:cadence, Repo)

    connection_options =
      repo_config
      |> Keyword.take([:username, :password, :hostname, :database, :port, :socket_dir, :ssl])
      |> Enum.reject(fn {_key, value} -> is_nil(value) end)

    {:ok, connection} = Postgrex.start_link(connection_options)

    try do
      %{rows: [[true]]} =
        Postgrex.query!(connection, "SELECT pg_terminate_backend($1)", [backend_pid])
    after
      GenServer.stop(connection)
    end
  end

  defp assert_signal_propagated({:exit, reason}, fun), do: assert(catch_exit(fun.()) == reason)

  defp assert_signal_propagated({:raise, exception}, fun), do: assert_raise(exception, fun)

  defp assert_signal_propagated({:throw, value}, fun), do: assert(catch_throw(fun.()) == value)

  defp stage_worker_artifacts(bytes_by_path) do
    Enum.each(bytes_by_path, fn {_artifact_path, bytes} ->
      digest = sha256(bytes)

      file_path =
        Path.join(
          System.tmp_dir!(),
          ".cadence_frontend_release_worker_#{System.unique_integer([:positive])}"
        )

      File.write!(file_path, bytes)

      try do
        {:ok, _stored} = DatabaseArtifactStore.put_file(digest, file_path)
      after
        File.rm(file_path)
      end
    end)
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
