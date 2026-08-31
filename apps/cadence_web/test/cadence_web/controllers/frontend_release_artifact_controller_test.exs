defmodule CadenceWeb.FrontendReleaseArtifactControllerTest do
  use CadenceWeb.ConnCase, async: false

  alias Cadence.Repo
  alias CadenceWeb.FrontendReleaseArtifactController
  alias CadenceWeb.FrontendReleaseCatalog
  alias CadenceWeb.FrontendReleasePublication

  @fixture Path.expand("../../../../../test/fixtures/frontend_release_catalog_v1.json", __DIR__)
  @corpus @fixture |> File.read!() |> Jason.decode!()
  @release_seed "9d61b19deffd5a60ba844af492ec2cc44449c5697b326919703bac031cae7f60"
  @origin "https://cdn.example.com"
  @now "2026-08-30T18:30:00Z"

  setup do
    previous_config = Application.get_env(:cadence_web, :frontend_release_publication)

    Application.put_env(
      :cadence_web,
      :frontend_release_publication,
      trust_records: @corpus["keys"],
      allowed_origins: [@origin]
    )

    on_exit(fn -> restore_config(previous_config) end)
    :ok
  end

  test "public GET serves the release-addressed manifest with signed metadata", %{conn: conn} do
    published = publish_release!(%{"mf-manifest.json" => "manifest-bytes"})
    path = artifact_path(published.release, "mf-manifest.json")

    conn = get(conn, path)

    assert response(conn, 200) == "manifest-bytes"
    assert get_resp_header(conn, "content-type") == ["application/json"]
    assert get_resp_header(conn, "content-length") == ["14"]
    assert get_resp_header(conn, "etag") == [~s("#{published.manifest.object_key}")]
    assert get_resp_header(conn, "cache-control") == ["public, max-age=31536000, immutable"]
    assert get_resp_header(conn, "x-content-type-options") == ["nosniff"]
    assert get_resp_header(conn, "access-control-allow-origin") == []
  end

  test "context lookup requires the exact accepted application, release, path, and object metadata" do
    published = publish_release!(%{"assets/app.js" => "app-bytes"})
    artifact = published.app

    assert {:ok, lookup} =
             FrontendReleasePublication.fetch_artifact(
               published.release["application"]["id"],
               published.release["releaseId"],
               artifact.path
             )

    assert lookup == %{
             digest: artifact.object_key,
             sha256: artifact.sha256,
             size: artifact.size,
             media_type: artifact.media_type
           }

    assert {:error, :not_found} =
             FrontendReleasePublication.fetch_artifact(
               "other_application",
               published.release["releaseId"],
               artifact.path
             )

    assert {:error, :not_found} =
             FrontendReleasePublication.fetch_artifact(
               published.release["application"]["id"],
               published.release["releaseId"],
               "assets/missing.js"
             )

    assert {:error, :not_found} =
             FrontendReleasePublication.fetch_artifact(
               published.release["application"]["id"],
               String.upcase(published.release["releaseId"]),
               artifact.path
             )
  end

  test "HEAD preserves the original method and reads no object bytes", %{conn: conn} do
    published = publish_release!(%{"assets/app.js" => "app-bytes"})
    path = artifact_path(published.release, "assets/app.js")

    {conn, queries} = capture_queries(fn -> head(conn, path) end)

    assert response(conn, 200) == ""
    assert get_resp_header(conn, "content-type") == ["application/javascript"]
    assert get_resp_header(conn, "content-length") == ["9"]
    assert get_resp_header(conn, "etag") == [~s("#{published.app.object_key}")]
    refute any_chunk_read?(queries)
    refute full_bytea_select?(queries)
  end

  test "matching If-None-Match returns 304 without object reads", %{conn: conn} do
    published = publish_release!(%{"assets/app.js" => "app-bytes"})
    path = artifact_path(published.release, "assets/app.js")
    etag = ~s("#{published.app.object_key}")

    {conn, queries} =
      capture_queries(fn ->
        conn
        |> put_req_header("if-none-match", etag)
        |> get(path)
      end)

    assert conn.status == 304
    assert response(conn, 304) == ""
    assert get_resp_header(conn, "etag") == [etag]
    refute any_chunk_read?(queries)
    refute full_bytea_select?(queries)
  end

  test "weak If-None-Match uses GET and HEAD comparison with comma lists", %{conn: conn} do
    published = publish_release!(%{"assets/app.js" => "app-bytes"})
    path = artifact_path(published.release, "assets/app.js")
    etag = ~s("#{published.app.object_key}")
    header = ~s("stale", W/#{etag}, "also-stale")

    {get_conn, get_queries} =
      capture_queries(fn ->
        conn
        |> put_req_header("if-none-match", header)
        |> get(path)
      end)

    assert get_conn.status == 304
    assert response(get_conn, 304) == ""
    assert get_resp_header(get_conn, "etag") == [etag]
    refute any_chunk_read?(get_queries)

    {head_conn, head_queries} =
      capture_queries(fn ->
        Phoenix.ConnTest.build_conn()
        |> put_req_header("if-none-match", header)
        |> head(path)
      end)

    assert head_conn.status == 304
    assert response(head_conn, 304) == ""
    assert get_resp_header(head_conn, "etag") == [etag]
    refute any_chunk_read?(head_queries)
  end

  test "malformed and nonmatching If-None-Match tags continue normally", %{conn: conn} do
    published = publish_release!(%{"assets/app.js" => "app-bytes"})
    path = artifact_path(published.release, "assets/app.js")

    {conn, queries} =
      capture_queries(fn ->
        conn
        |> put_req_header("if-none-match", ~s(W/not-an-entity-tag))
        |> get(path)
      end)

    assert response(conn, 200) == "app-bytes"
    assert any_chunk_read?(queries)
  end

  test "Range and If-Range return 416 with the signed size without object reads", %{conn: conn} do
    published = publish_release!(%{"assets/app.js" => "app-bytes"})
    path = artifact_path(published.release, "assets/app.js")

    for {header, value} <- [{"range", "bytes=0-1"}, {"if-range", "stale"}] do
      {response_conn, queries} =
        capture_queries(fn ->
          conn
          |> put_req_header(header, value)
          |> get(path)
        end)

      assert response_conn.status == 416
      assert response(response_conn, 416) == ""
      assert get_resp_header(response_conn, "content-range") == ["bytes */9"]
      refute any_chunk_read?(queries)
      refute full_bytea_select?(queries)
    end
  end

  test "malformed, wrong, unpublished, unknown, and unreferenced requests are identical 404s", %{
    conn: conn
  } do
    published = publish_release!(%{"assets/app.js" => "app-bytes"})
    release = published.release
    valid_path = artifact_path(release, "assets/app.js")

    paths = [
      artifact_path(
        %{"application" => %{"id" => "Telemetry_decom"}, "releaseId" => release["releaseId"]},
        "assets/app.js"
      ),
      "/releases/#{release["application"]["id"]}/SHA256:#{String.duplicate("0", 64)}/artifacts/assets/app.js",
      "/releases/#{release["application"]["id"]}/#{release["releaseId"]}/artifacts/../assets/app.js",
      String.replace(valid_path, release["application"]["id"], "other_application"),
      "/releases/#{release["application"]["id"]}/sha256:#{String.duplicate("0", 64)}/artifacts/assets/app.js",
      artifact_path(release, "assets/missing.js"),
      artifact_path(release, "sha256/#{published.app.sha256}")
    ]

    responses =
      Enum.map(paths, fn path ->
        response_conn = get(conn, path)

        {
          response_conn.status,
          response(response_conn, response_conn.status),
          get_resp_header(response_conn, "cache-control"),
          get_resp_header(response_conn, "content-type")
        }
      end)

    assert Enum.uniq(responses) == [{404, "", ["no-store"], []}]
  end

  test "valid raw percent encoding resolves to the exact signed decoded path", %{conn: conn} do
    published = publish_release!(%{"assets/app.js" => "app-bytes"})
    path = artifact_path(published.release, "assets/app%2Ejs")

    conn = get(conn, path)

    assert response(conn, 200) == "app-bytes"
  end

  test "malformed raw percent escapes are an indistinguishable 404 before lookup", %{conn: conn} do
    published = publish_release!(%{"assets/app.js" => "app-bytes"})
    valid_path = artifact_path(published.release, "assets/app.js")
    malformed_path = String.replace(valid_path, "assets/app.js", "assets/app%zz.js")

    {conn, queries} = capture_queries(fn -> get(conn, malformed_path) end)

    assert response(conn, 404) == ""
    assert get_resp_header(conn, "cache-control") == ["no-store"]
    assert get_resp_header(conn, "content-type") == []
    assert queries == []
  end

  test "GET streams multiple bounded chunks sequentially", %{conn: conn} do
    bytes = :binary.copy(<<"a">>, 1_048_581)
    published = publish_release!(%{"assets/app.js" => bytes})
    path = artifact_path(published.release, "assets/app.js")

    {conn, queries} = capture_queries(fn -> get(conn, path) end)

    assert response(conn, 200) == bytes

    chunk_queries = Enum.filter(queries, &chunk_query?/1)
    assert Enum.map(chunk_queries, fn {_query, params} -> List.last(params) end) == [1_048_576, 5]
    refute full_bytea_select?(queries)
    refute any_octet_length_query?(queries)
  end

  test "corrupt stored artifact metadata fails closed without reading bytes" do
    published = publish_release!(%{"assets/app.js" => "app-bytes"})
    release_id = published.release["releaseId"]
    application_id = published.release["application"]["id"]

    Repo.query!(
      """
      INSERT INTO frontend_release_artifacts
        (artifact_id, release_publication_id, release_id, path, sha256, size, media_type, object_key, metadata, inserted_at)
      VALUES
        ($1, $2, $3, $4, $5, $6, $7, $8, '{}'::jsonb, now())
      """,
      [
        "corrupt-media-artifact",
        published.publication.publication_id,
        release_id,
        "assets/corrupt.js",
        published.app.sha256,
        published.app.size,
        "text/html\r\nx-poison: true",
        published.app.object_key
      ]
    )

    Repo.query!(
      """
      INSERT INTO frontend_release_artifacts
        (artifact_id, release_publication_id, release_id, path, sha256, size, media_type, object_key, metadata, inserted_at)
      VALUES
        ($1, $2, $3, $4, $5, $6, $7, $8, '{}'::jsonb, now())
      """,
      [
        "corrupt-size-artifact",
        published.publication.publication_id,
        release_id,
        "assets/corrupt-size.js",
        published.app.sha256,
        published.app.size + 1,
        published.app.media_type,
        published.app.object_key
      ]
    )

    for path <- ["assets/corrupt.js", "assets/corrupt-size.js"] do
      {result, queries} =
        capture_queries(fn ->
          FrontendReleasePublication.fetch_artifact(application_id, release_id, path)
        end)

      assert result == {:error, :not_found}
      refute any_chunk_read?(queries)
    end
  end

  test "a client disconnect stops streaming without a JSON error", %{conn: conn} do
    bytes = :binary.copy(<<"a">>, 1_048_581)
    published = publish_release!(%{"assets/app.js" => bytes})
    artifact = published.app

    params = %{
      "application_id" => published.release["application"]["id"],
      "release_id" => published.release["releaseId"],
      "artifact_path" => ["assets", "app.js"]
    }

    disconnected_conn = %{
      conn
      | adapter: {CadenceWeb.FrontendReleaseArtifactDisconnectAdapter, %{}}
    }

    disconnected_conn = FrontendReleaseArtifactController.show(disconnected_conn, params)

    assert disconnected_conn.status == 200
    assert disconnected_conn.state == :chunked
    assert disconnected_conn.resp_body == ""
    assert artifact.size == 1_048_581
  end

  defp publish_release!(bytes_by_path) do
    bytes_by_path = Map.put_new(bytes_by_path, "mf-manifest.json", "manifest-bytes")
    {envelope, _payload, release} = release_document(bytes_by_path)

    assert {:ok, publication} =
             FrontendReleasePublication.admit_release(envelope, bytes_by_path, now: @now)

    artifacts = Map.new(publication.artifacts, &{&1.path, &1})

    %{
      publication: publication,
      release: release,
      app: artifacts["assets/app.js"],
      manifest: artifacts["mf-manifest.json"]
    }
  end

  defp artifact_path(release, path) do
    "/releases/#{release["application"]["id"]}/#{release["releaseId"]}/artifacts/#{path}"
  end

  defp capture_queries(fun) do
    owner = self()
    handler_id = {__MODULE__, System.unique_integer([:positive])}

    :ok =
      :telemetry.attach(
        handler_id,
        [:cadence, :repo, :query],
        fn _event, _measurements, metadata, pid ->
          send(pid, {:frontend_release_artifact_query, metadata.query, metadata.params})
        end,
        owner
      )

    result =
      try do
        fun.()
      after
        :telemetry.detach(handler_id)
      end

    {result, collect_queries([])}
  end

  defp collect_queries(queries) do
    receive do
      {:frontend_release_artifact_query, query, params} ->
        collect_queries([{query, params} | queries])
    after
      0 -> Enum.reverse(queries)
    end
  end

  defp any_chunk_read?(queries), do: Enum.any?(queries, &chunk_query?/1)

  defp chunk_query?({query, _params}), do: String.contains?(query, "substring(bytes FROM")

  defp full_bytea_select?(queries) do
    Enum.any?(queries, fn {query, _params} ->
      Regex.match?(~r/SELECT\s+bytes\s+FROM/i, query)
    end)
  end

  defp any_octet_length_query?(queries) do
    Enum.any?(queries, fn {query, _params} -> String.contains?(query, "octet_length(bytes)") end)
  end

  defp restore_config(nil),
    do: Application.delete_env(:cadence_web, :frontend_release_publication)

  defp restore_config(config),
    do: Application.put_env(:cadence_web, :frontend_release_publication, config)

  defp release_document(bytes_by_path) do
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
      |> put_in(
        ["provenance", "buildId"],
        "artifact-serving-#{System.unique_integer([:positive])}"
      )
      |> Map.put("releasedAt", "2026-08-30T17:00:00Z")
      |> with_release_id()

    payload = canonical(release)
    {sign_fixture(payload, "fixture-release-key", "release", @release_seed), payload, release}
  end

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
      "schema" => FrontendReleaseCatalog.envelope_schema(),
      "keyId" => key_id,
      "algorithm" => "ed25519",
      "signingRole" => role,
      "payloadEncoding" => "base64url-json",
      "payload" => Base.url_encode64(payload, padding: false),
      "signature" => Base.url_encode64(signature, padding: false)
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
end
