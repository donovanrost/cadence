defmodule CadenceWeb.FrontendReleaseSignedActivationTest do
  use CadenceWeb.ConnCase, async: false

  import Ecto.Query
  import Plug.Conn

  alias Cadence.Applications.{ApplicationInstallations, HostContext, TelemetryDecom}
  alias Cadence.Auth.Scope
  alias Cadence.Repo
  alias Cadence.SourceEndpoints.SourceEndpoint
  alias CadenceWeb.ApplicationActionIdempotency
  alias CadenceWeb.FrontendReleaseActivation.{CatalogBinding, CatalogGeneration, Request}
  alias CadenceWeb.FrontendReleaseCatalog
  alias CadenceWeb.FrontendReleasePublication

  alias CadenceWeb.FrontendReleasePublication.{
    CatalogPublication,
    DatabaseArtifactStore,
    ReleasePublication
  }

  alias CadenceWeb.FrontendReleaseSignedActivationFixtures, as: Fixtures
  alias CadenceWeb.TestFixtures

  @moduletag timeout: :infinity

  @release_path "/api/cadence/frontend-release/v1/releases"
  @promotion_path "/api/cadence/frontend-release/v1/promotions"
  @object_prefix "/api/cadence/frontend-release/v1/objects/"
  @host_catalog_suffix "/api/cadence/application-host/v1/missions"
  @artifact_origin "https://cdn.example.com"
  @publisher_token "frontend-release-publisher-test-token"
  @promotion_seed "4ccd089b28ff96da9db6c346ec114e0f5b8a319f35aba624da8cf6ed4fb8a6fb"
  @fork_seed "d4f7f6f5c3d5b7c7e4a2b7eecf8f6e5d6c8b4e6f7a8b9c0d1e2f3a4b5c6d7e8f"
  @catalog_expires_at "2026-09-30T00:00:00Z"
  @n_minus_1_catalog_published_at "2026-09-01T18:00:00Z"
  @n_catalog_published_at "2026-09-01T18:01:00Z"
  @rollback_catalog_published_at "2026-09-01T18:02:00Z"

  @fixture Path.expand("../../../../test/fixtures/frontend_release_catalog_v1.json", __DIR__)
  @corpus @fixture |> File.read!() |> Jason.decode!()
  @publication_config [trust_records: @corpus["keys"], allowed_origins: [@artifact_origin]]
  @publisher_config [token_sha256: :crypto.hash(:sha256, @publisher_token)]

  setup_all do
    fixture = Fixtures.prepare!()
    on_exit(fn -> Fixtures.cleanup!(fixture) end)
    {:ok, release_fixture: fixture}
  end

  setup do
    process_key = {FrontendReleasePublication, :publication_config}
    previous = Process.get(process_key, :not_configured)
    Process.put(process_key, @publication_config)

    on_exit(fn ->
      if previous == :not_configured do
        Process.delete(process_key)
      else
        Process.put(process_key, previous)
      end
    end)

    :ok
  end

  test "proves the real Vite packages through publication, activation, host, and public delivery",
       %{release_fixture: fixture} do
    n_minus_1 = fixture.packages.n_minus_1
    n = fixture.packages.n

    assert_package_evidence!(fixture)

    assert n_minus_1.release["provenance"]["buildId"] ==
             "phase-d-signed-activation-n-minus-1"

    context = telemetry_context()
    {revision, endpoint} = imported_packet_context(context)

    upload_all_artifacts!(n_minus_1)
    upload_all_artifacts!(n)

    assert Repo.query!("SELECT COUNT(*) FROM frontend_release_objects", []).rows == [[0]]
    assert staged_object_count() == length(unique_artifacts(n_minus_1))
    assert_staged_artifacts!(n_minus_1)
    assert_staged_chunk_reads!(n_minus_1)

    assert response(
             get(build_conn(), artifact_path(n_minus_1, "mf-manifest.json")),
             404
           ) == ""

    publish_response = publish_release!(n_minus_1)
    assert publish_response.status == 201
    assert %{"data" => %{"status" => "published"}} = json_response(publish_response, 201)
    assert_persisted_release!(n_minus_1, "phase-d-signed-activation")
    assert_stored_artifacts!(n_minus_1)
    assert_chunk_reads!(n_minus_1)

    upload_all_artifacts!(n)

    replay_before = state_snapshot()
    replay = publish_release!(n_minus_1)
    assert replay.status == 200
    assert %{"data" => %{"status" => "replayed"}} = json_response(replay, 200)
    assert state_snapshot() == replay_before

    assert_rejected_without_mutation!(
      fn ->
        publisher_conn()
        |> put_req_header("authorization", "Bearer wrong-publisher-credential")
        |> post(@release_path, publication_body(n_minus_1))
      end,
      401,
      :no_request
    )

    assert_rejected_without_mutation!(
      fn ->
        publisher_conn()
        |> post(
          @release_path,
          publication_body(n_minus_1, document: invalid_release_signature(n_minus_1))
        )
      end,
      422,
      :no_request
    )

    assert_rejected_without_mutation!(
      fn ->
        publisher_conn()
        |> post(
          @release_path,
          publication_body(n_minus_1, document: n_minus_1.document_bytes <> " ")
        )
      end,
      422,
      :no_request
    )

    alternate_key = alternate_release_key()
    alternate_document = alternate_release_document(n_minus_1)

    assert_rejected_without_mutation!(
      fn ->
        publisher_conn(publication_config: publication_config([alternate_key]))
        |> post(@release_path, publication_body(n_minus_1, document: alternate_document))
      end,
      409,
      :no_request
    )

    publish_n_response = publish_release!(n)
    assert publish_n_response.status == 201, publish_n_response.resp_body
    assert %{"data" => %{"status" => "published"}} = json_response(publish_n_response, 201)
    assert_persisted_release!(n, "phase-d-signed-activation")
    assert_stored_artifacts!(n)
    assert_chunk_reads!(n)

    assert_rejected_without_mutation!(
      fn ->
        publisher_conn()
        |> post(@release_path, publication_body(n, artifacts: mixed_artifact_set(n)))
      end,
      422,
      :no_request
    )

    assert_rejected_without_mutation!(
      fn ->
        publisher_conn()
        |> post(@release_path, publication_body(n, artifacts: changed_artifact_bytes(n)))
      end,
      422,
      :no_request
    )

    assert_rejected_without_mutation!(
      fn ->
        publisher_conn()
        |> post(@release_path, publication_body(n, artifacts: digest_size_drift(n)))
      end,
      422,
      :no_request
    )

    overwritten = overwrite_probe(n)

    assert_rejected_without_mutation!(
      fn ->
        publisher_conn()
        |> put_req_header("content-type", "application/octet-stream")
        |> put(@object_prefix <> overwritten.digest, overwritten.bytes)
      end,
      422,
      :no_request
    )

    n_minus_1_catalog =
      promotion_document(
        "initial",
        1,
        @n_minus_1_catalog_published_at,
        n_minus_1,
        nil,
        route_snapshot_digest("initial", 1, @n_minus_1_catalog_published_at, n_minus_1, nil)
      )

    assert {:ok, n_minus_1_activation} = activate_catalog!(n_minus_1_catalog, "phase-d-initial")
    assert n_minus_1_activation.sequence == 1
    assert n_minus_1_activation.outcome == "initial"
    assert_host_catalog!(context, n_minus_1)

    never_predecessor_rollback =
      promotion_document(
        "rollback",
        2,
        @n_catalog_published_at,
        n,
        n_minus_1,
        route_snapshot_digest("rollback", 2, @n_catalog_published_at, n, n_minus_1)
      )

    assert_rejected_activation!(
      never_predecessor_rollback,
      "phase-d-never-predecessor",
      fn body ->
        assert body["code"] == "rollback_previous_required"
      end
    )

    n_catalog =
      promotion_document(
        "promotion",
        2,
        @n_catalog_published_at,
        n,
        n_minus_1,
        route_snapshot_digest("promotion", 2, @n_catalog_published_at, n, n_minus_1)
      )

    initial_replay_before = state_snapshot()
    assert {:ok, initial_replay} = activate_catalog!(n_minus_1_catalog, "phase-d-initial")
    assert initial_replay.response == n_minus_1_activation.response
    assert state_snapshot() == initial_replay_before

    assert_rejected_activation_conflict!(n_catalog, "phase-d-initial")

    assert {:ok, n_activation} = activate_catalog!(n_catalog, "phase-d-promotion")
    assert n_activation.sequence == 2
    assert n_activation.outcome == "promotion"
    assert_host_catalog!(context, n)

    rollback_catalog =
      promotion_document(
        "rollback",
        3,
        @rollback_catalog_published_at,
        n_minus_1,
        n,
        route_snapshot_digest("rollback", 3, @rollback_catalog_published_at, n_minus_1, n)
      )

    assert {:ok, rollback_activation} = activate_catalog!(rollback_catalog, "phase-d-rollback")
    assert rollback_activation.sequence == 3
    assert rollback_activation.outcome == "rollback"
    assert_host_catalog!(context, n_minus_1)

    assert_activation_records!(
      n_minus_1_catalog,
      n_catalog,
      rollback_catalog,
      n_minus_1_activation,
      n_activation,
      rollback_activation,
      n_minus_1,
      n
    )

    assert_rejected_activation!(
      invalid_promotion_signature(n_catalog),
      "phase-d-bad-signature",
      fn body ->
        assert body["code"] in ["invalid_signature", "invalid_base64"]
      end
    )

    mixed_identity_catalog =
      promotion_document(
        "promotion",
        4,
        "2026-09-01T18:03:00Z",
        n,
        n_minus_1,
        route_snapshot_digest("promotion", 4, "2026-09-01T18:03:00Z", n, n_minus_1),
        identity: %{
          "application" => %{"id" => "telemetry_decom", "version" => 2},
          "package" => %{"id" => "cadence.telemetry-applications", "version" => 1},
          "surface" => %{"id" => "packet_bindings", "version" => 1}
        }
      )

    assert_rejected_activation!(mixed_identity_catalog, "phase-d-mixed-identity", fn body ->
      assert body["code"] == "identity_mismatch"
    end)

    assert_rejected_activation!(rollback_catalog <> " ", "phase-d-changed-document", fn body ->
      assert body["code"] in ["noncanonical_json", "invalid_json"]
    end)

    assert {:ok, %{source: :database, entries: entries}} =
             CadenceWeb.ApplicationReleaseRegistry.snapshot(now: "2026-09-03T00:00:00Z")

    assert [{{"telemetry_decom", 1, "packet_bindings", 1}, active_release}] = entries
    assert active_release.release_id == n_minus_1.release["releaseId"]

    assert active_release.manifest_path ==
             "/releases/telemetry_decom/#{n_minus_1.release["releaseId"]}/artifacts/mf-manifest.json"

    assert_host_query_and_action!(context, revision, endpoint, n_minus_1)
    assert_public_artifact_semantics!(n, "remoteEntry.js")
    assert_public_artifact_semantics!(n_minus_1, "mf-manifest.json")
    restart_endpoint_and_assert_catalog!(context, n_minus_1)

    refute Map.has_key?(n_minus_1.release, "query")
    refute Map.has_key?(n_minus_1.release, "actions")

    assert fixture.metadata.n_minus_1["query"] == %{
             "id" => "cadence.packet_bindings.manage",
             "version" => 1
           }

    assert fixture.metadata.n_minus_1["actions"] == ["save_packet_bindings"]
  end

  test "accepted staged references fail closed when final chunks are missing or corrupt",
       %{release_fixture: fixture} do
    package = fixture.packages.n_minus_1
    upload_all_artifacts!(package)

    response = publish_release!(package)
    assert response.status == 201
    assert_persisted_release!(package, "phase-d-signed-activation")

    artifact = Enum.find(package.artifacts, &(&1.size > 0))
    assert artifact
    chunk = object_chunk!(artifact.sha256, 0)

    delete_object_chunk!(artifact.sha256, 0)

    assert_integrity_activation_rejected!(
      package,
      "phase-d-missing-final-chunk"
    )

    insert_object_chunk!(artifact.sha256, chunk.index, chunk.bytes)
    assert DatabaseArtifactStore.verify(artifact.sha256, artifact.size) == :ok

    tamper_object_chunk!(artifact.sha256, 0, mutate_same_size(chunk.bytes))

    assert_integrity_activation_rejected!(
      package,
      "phase-d-corrupt-final-chunk"
    )

    tamper_object_chunk!(artifact.sha256, chunk.index, chunk.bytes)
    assert DatabaseArtifactStore.verify(artifact.sha256, artifact.size) == :ok
    assert read_chunks(artifact.sha256, artifact.size) == artifact.bytes
  end

  defp telemetry_context do
    user = TestFixtures.persist_user!()
    organization = TestFixtures.persist_org!()
    membership = TestFixtures.grant_membership!(user, organization)
    mission = TestFixtures.persist_mission!(organization)
    spacecraft = TestFixtures.persist_spacecraft!(mission)

    scope =
      Scope.new(%{
        user: user,
        organization_id: organization.organization_id,
        organization: organization,
        organization_membership: membership
      })

    host_context = HostContext.spacecraft(mission.mission_id, spacecraft.spacecraft_id)

    assert {:ok, installation} =
             ApplicationInstallations.install(scope, host_context, "telemetry_decom")

    %{
      member_conn: TestFixtures.member_conn(user),
      organization: organization,
      mission: mission,
      spacecraft: spacecraft,
      scope: scope,
      host_context: host_context,
      installation: installation
    }
  end

  defp imported_packet_context(context) do
    suffix = Integer.to_string(System.unique_integer([:positive]))
    database = TestFixtures.persist_catalog_database!(context.mission, slug: "phase-d-#{suffix}")

    run =
      TestFixtures.start_catalog_revision_import!(database,
        revision_label: "Phase D Revision",
        source_artifact: """
        packets:
          - name: HEALTH
            apid: 42
            items:
              - name: mode
                data_type: uint
                bit_offset: 0
                bit_size: 8
        commands: []
        """
      )

    TestFixtures.complete_catalog_import_run!(run)
    revision = TestFixtures.fetch_catalog_revision_for_run!(run)

    endpoint =
      SourceEndpoint.new(%{
        source_endpoint_id: "phase-d-source-#{suffix}",
        mission_id: context.mission.mission_id,
        spacecraft_id: context.spacecraft.spacecraft_id,
        display_name: "Phase D Downlink"
      })

    assert {:ok, endpoint} =
             Cadence.SourceEndpoints.persist_source_endpoint(
               context.organization.organization_id,
               endpoint
             )

    assert {:ok, _configuration} =
             TelemetryDecom.configure(
               context.organization.organization_id,
               context.mission.mission_id,
               context.spacecraft.spacecraft_id,
               catalog_revision_id: revision.catalog_revision_id,
               handled_apids: [42],
               source_endpoint_id: endpoint.source_endpoint_id
             )

    {revision, endpoint}
  end

  defp assert_package_evidence!(fixture) do
    for package <- [fixture.packages.n_minus_1, fixture.packages.n] do
      assert File.read!(package.document_path) == package.document_bytes
      assert package.envelope["schema"] == "cadence.signed-frontend-document.v1"
      assert package.envelope["keyId"] == "fixture-release-key"
      assert package.envelope["signingRole"] == "release"
      assert package.envelope["payloadEncoding"] == "base64url-json"

      assert package.payload_bytes ==
               Base.url_decode64!(package.envelope["payload"], padding: false)

      assert package.release == Jason.decode!(package.payload_bytes)

      assert FrontendReleaseCatalog.verify_release(
               package.document_bytes,
               @corpus["keys"],
               allowed_origins: [@artifact_origin],
               now: "2026-09-01T19:00:00Z"
             )
             |> elem(0) == :ok

      logical_release = Map.drop(package.release, ["releaseId", "artifactBaseUrl"])
      assert sha256(canonical(logical_release)) == package.release["releaseId"]

      assert package.release["artifactBaseUrl"] ==
               @artifact_origin <>
                 "/releases/telemetry_decom/#{package.release["releaseId"]}/artifacts/"

      assert sha256(package.payload_bytes) ==
               FrontendReleaseCatalog.digest(package.payload_bytes)

      key = Enum.find(@corpus["keys"], &(&1["keyId"] == "fixture-release-key"))
      public_key = Base.url_decode64!(key["publicKey"], padding: false)
      signature = Base.url_decode64!(package.envelope["signature"], padding: false)

      assert :crypto.verify(:eddsa, :none, package.payload_bytes, signature, [
               public_key,
               :ed25519
             ])

      declarations =
        Map.new(package.release["artifacts"], fn artifact -> {artifact["path"], artifact} end)

      for artifact <- package.artifacts do
        declaration = Map.fetch!(declarations, artifact.path)

        assert File.read!(Path.join(package.output_directory, "artifacts/#{artifact.path}")) ==
                 artifact.bytes

        assert artifact.sha256 == "sha256:" <> declaration["sha256"]
        assert artifact.size == declaration["size"]
        assert artifact.media_type == declaration["mediaType"]
      end
    end

    assert Enum.map(fixture.packages.n_minus_1.artifacts, &{&1.path, &1.sha256, &1.size}) ==
             Enum.map(fixture.packages.n.artifacts, &{&1.path, &1.sha256, &1.size})

    assert Enum.map(fixture.packages.n_minus_1.artifacts, &{&1.path, &1.bytes}) ==
             Enum.map(fixture.packages.n.artifacts, &{&1.path, &1.bytes})
  end

  defp upload_all_artifacts!(package) do
    for artifact <- package.artifacts do
      response =
        publisher_conn()
        |> put_req_header("content-type", "application/octet-stream")
        |> put(@object_prefix <> artifact.sha256, artifact.bytes)

      assert response.status in [200, 201]

      assert %{"data" => %{"digest" => digest, "size" => size, "status" => status}} =
               json_response(response, response.status)

      assert digest == artifact.sha256
      assert size == artifact.size
      assert status in ["stored", "existing"]
    end
  end

  defp publish_release!(package, opts \\ []) do
    publisher_conn(Keyword.take(opts, [:publication_config]))
    |> put_req_header("x-cadence-publisher-identity", "phase-d-signed-activation")
    |> post(
      @release_path,
      publication_body(package,
        document: Keyword.get(opts, :document, package.document_bytes),
        artifacts: Keyword.get(opts, :artifacts, staged_artifacts(package))
      )
    )
  end

  defp publisher_conn(opts \\ []) do
    build_conn()
    |> put_private(
      :frontend_release_publication_config,
      Keyword.get(opts, :publication_config, @publication_config)
    )
    |> put_private(
      :frontend_release_publisher_config,
      Keyword.get(opts, :publisher_config, @publisher_config)
    )
    |> put_req_header("accept", "application/json")
    |> put_req_header("content-type", "application/json")
    |> put_req_header("authorization", "Bearer " <> @publisher_token)
  end

  defp publication_body(package, opts \\ []) do
    Jason.encode!(%{
      "document" => Keyword.get(opts, :document, package.document_bytes),
      "artifacts" => Keyword.get(opts, :artifacts, staged_artifacts(package))
    })
  end

  defp staged_artifacts(package) do
    Enum.map(package.artifacts, fn artifact ->
      %{"path" => artifact.path, "sha256" => artifact.sha256, "size" => artifact.size}
    end)
  end

  defp unique_artifacts(package), do: Enum.uniq_by(package.artifacts, & &1.sha256)

  defp staged_object_count do
    Repo.query!("SELECT COUNT(*) FROM frontend_release_staged_objects", []).rows
    |> List.first()
    |> List.first()
  end

  defp assert_persisted_release!(package, publisher_identity) do
    publication = Repo.get_by!(ReleasePublication, release_id: package.release["releaseId"])
    publication = Repo.preload(publication, :artifacts)

    assert publication.signed_document_bytes == package.document_bytes
    assert publication.payload_bytes == package.payload_bytes
    assert publication.release_id == package.release["releaseId"]
    assert publication.payload_digest == sha256(package.payload_bytes)
    assert publication.signed_document_digest == sha256(package.document_bytes)
    assert publication.application_id == "telemetry_decom"
    assert publication.application_version == 1
    assert publication.package_id == "cadence.telemetry-applications"
    assert publication.package_version == 1
    assert publication.surface_id == "packet_bindings"
    assert publication.surface_version == 1
    assert publication.remote_name == "cadence_telemetry_decom"
    assert publication.exposed_module == "./Application"
    assert publication.artifact_base_url == package.release["artifactBaseUrl"]
    assert publication.manifest_path == "mf-manifest.json"
    assert publication.manifest_sha256 == package.release["manifest"]["sha256"]
    assert publication.manifest_size == package.release["manifest"]["size"]
    assert publication.manifest_media_type == "application/json"
    assert publication.signing_key_id == "fixture-release-key"
    assert publication.signing_role == "release"
    assert publication.provenance == package.release["provenance"]
    assert publication.artifact_count == length(package.artifacts)
    assert publication.acceptance_state == "accepted"
    assert publication.metadata == %{"publisher_identity" => publisher_identity}

    actual_artifacts =
      publication.artifacts
      |> Enum.sort_by(& &1.path)
      |> Enum.map(fn artifact ->
        %{
          "mediaType" => artifact.media_type,
          "path" => artifact.path,
          "sha256" => artifact.sha256,
          "size" => artifact.size
        }
      end)

    assert actual_artifacts == package.release["artifacts"]
    publication
  end

  defp assert_stored_artifacts!(package) do
    for artifact <- package.artifacts do
      assert stored_object_bytes(artifact.sha256) == artifact.bytes
    end
  end

  defp assert_staged_artifacts!(package) do
    for artifact <- package.artifacts do
      assert staged_object_bytes(artifact.sha256) == artifact.bytes
    end
  end

  defp assert_staged_chunk_reads!(package) do
    for artifact <- package.artifacts do
      staged_bytes = staged_object_bytes(artifact.sha256)
      assert staged_bytes == artifact.bytes
      assert sha256(staged_bytes) == artifact.sha256
    end
  end

  defp assert_chunk_reads!(package) do
    for artifact <- package.artifacts do
      assert DatabaseArtifactStore.verify(artifact.sha256, artifact.size) == :ok
      assert read_chunks(artifact.sha256, artifact.size) == artifact.bytes
    end
  end

  defp read_chunks(digest, size), do: read_chunks(digest, size, 0, [])

  defp read_chunks(_digest, size, offset, parts) when offset >= size,
    do: IO.iodata_to_binary(Enum.reverse(parts))

  defp read_chunks(digest, size, offset, parts) do
    length = min(1_048_576, size - offset)
    assert {:ok, bytes} = DatabaseArtifactStore.read_chunk(digest, offset, length)
    read_chunks(digest, size, offset + byte_size(bytes), [bytes | parts])
  end

  defp object_chunk!("sha256:" <> digest, index) do
    case Repo.query!(
           """
           SELECT chunk_index, bytes, size
           FROM frontend_release_object_chunks
           WHERE sha256 = $1 AND chunk_index = $2
           """,
           [digest, index]
         ).rows do
      [[^index, bytes, size]] when is_binary(bytes) and is_integer(size) ->
        %{index: index, bytes: bytes, size: size}

      rows ->
        flunk("missing object chunk #{digest}/#{index}: #{inspect(rows)}")
    end
  end

  defp staged_object_bytes("sha256:" <> digest) do
    Repo.query!(
      "SELECT bytes FROM frontend_release_staged_object_chunks WHERE sha256 = $1 ORDER BY chunk_index",
      [digest]
    ).rows
    |> Enum.map(&List.first/1)
    |> IO.iodata_to_binary()
  end

  defp stored_object_bytes("sha256:" <> digest) do
    case Repo.query!("SELECT bytes FROM frontend_release_objects WHERE sha256 = $1", [digest]).rows do
      [[bytes]] when is_binary(bytes) ->
        bytes

      [[nil]] ->
        Repo.query!(
          "SELECT bytes FROM frontend_release_object_chunks WHERE sha256 = $1 ORDER BY chunk_index",
          [digest]
        ).rows
        |> Enum.map(&List.first/1)
        |> IO.iodata_to_binary()
    end
  end

  defp assert_host_catalog!(context, package) do
    catalog_response =
      get(context.member_conn, catalog_path(context), %{application_key: "telemetry_decom"})

    assert catalog_response.status == 200
    catalog = json_response(catalog_response, 200)
    assert [application] = catalog["applications"]
    assert application["applicationKey"] == "telemetry_decom"
    assert application["applicationVersion"] == 1

    assert application["package"] == %{
             "packageId" => "cadence.telemetry-applications",
             "version" => 1
           }

    assert application["surface"]["surfaceId"] == "packet_bindings"
    assert application["surface"]["version"] == 1

    assert application["surface"]["dataContract"] == %{
             "id" => "cadence.packet_bindings.manage",
             "version" => 1
           }

    assert application["surface"]["actions"] == ["save_packet_bindings"]

    assert application["surface"]["renderer"] == %{
             "kind" => "federated-vue",
             "exposedModule" => "./Application"
           }

    assert application["release"]["federation"] == "module_federation"
    assert application["release"]["releaseId"] == package.release["releaseId"]
    assert application["release"]["remoteName"] == "cadence_telemetry_decom"
    assert application["release"]["exposedModule"] == "./Application"

    assert URI.parse(application["release"]["manifestUrl"]).path ==
             "/releases/telemetry_decom/#{package.release["releaseId"]}/artifacts/mf-manifest.json"

    assert catalog["session"]["bridgeBaseUrl"] ==
             "/api/cadence/application-host/v1/missions/#{context.mission.mission_id}/spacecraft/#{context.spacecraft.spacecraft_id}"
  end

  defp assert_host_query_and_action!(context, revision, endpoint, package) do
    catalog_response =
      get(context.member_conn, catalog_path(context), %{application_key: "telemetry_decom"})

    catalog = json_response(catalog_response, 200)
    assert [application] = catalog["applications"]
    assert application["release"]["releaseId"] == package.release["releaseId"]

    query_response =
      catalog_response
      |> bridge_conn(catalog)
      |> post(query_path(context), Jason.encode!(query_body(context)))

    query = json_response(query_response, 200)

    assert query["host"] == %{
             "application_installation_id" => context.installation.application_installation_id,
             "application_key" => "telemetry_decom",
             "application_version" => 1,
             "dom_id" => "spacecraft-application-host",
             "renderer" => "trusted",
             "surface_id" => "packet_bindings"
           }

    assert query["trusted_surface"]["contract_version"] == 1
    assert [%{"id" => packet_id}] = query["trusted_surface"]["packets"]["items"]
    refute Map.has_key?(query, "releaseId")

    action_response =
      catalog_response
      |> bridge_conn(catalog)
      |> put_req_header("idempotency-key", "phase-d-action")
      |> post(
        actions_path(context),
        Jason.encode!(
          action_body(
            context,
            revision,
            endpoint,
            packet_id,
            query["trusted_surface"]["review_token"]
          )
        )
      )

    action = json_response(action_response, 200)

    assert {:ok, idempotency_key_digest} =
             ApplicationActionIdempotency.key_digest("phase-d-action")

    assert action["receiptId"] == "application-host-receipt-" <> idempotency_key_digest
    assert action["result"]["applicationKey"] == "telemetry_decom"
    assert action["result"]["applicationVersion"] == 1
    assert action["result"]["inputId"] == "telemetry-fields"
    assert action["result"]["selectedPacketIds"] == [packet_id]
    refute Map.has_key?(action, "releaseId")
  end

  defp assert_public_artifact_semantics!(package, artifact_path_value) do
    artifact = Enum.find(package.artifacts, &(&1.path == artifact_path_value))
    assert artifact
    path = artifact_path(package, artifact.path)
    etag = ~s("#{artifact.sha256}")

    response_conn = get(build_conn(), path)
    assert response(response_conn, 200) == artifact.bytes
    assert get_resp_header(response_conn, "etag") == [etag]

    head_conn = head(build_conn(), path)
    assert response(head_conn, 200) == ""
    assert get_resp_header(head_conn, "etag") == [etag]

    not_modified = build_conn() |> put_req_header("if-none-match", etag) |> get(path)
    assert not_modified.status == 304
    assert response(not_modified, 304) == ""

    range = build_conn() |> put_req_header("range", "bytes=0-1") |> get(path)
    assert range.status == 416
    assert get_resp_header(range, "content-range") == ["bytes */#{artifact.size}"]
  end

  defp activate_catalog!(document, idempotency_key) do
    response =
      publisher_conn()
      |> put_req_header("idempotency-key", idempotency_key)
      |> post(@promotion_path, Jason.encode!(%{"document" => document}))

    case response.status do
      201 ->
        body = json_response(response, 201)
        data = body["data"]
        {:ok, %{sequence: data["sequence"], outcome: data["outcome"], response: body}}

      status ->
        flunk("promotion failed with #{status}: #{response.resp_body}")
    end
  end

  defp assert_rejected_activation_conflict!(document, idempotency_key) do
    before = state_snapshot()

    response =
      publisher_conn()
      |> put_req_header("idempotency-key", idempotency_key)
      |> post(@promotion_path, Jason.encode!(%{"document" => document <> " "}))

    assert response.status == 409
    assert json_response(response, 409) == %{"error" => %{"code" => "idempotency_key_reused"}}
    assert_state_unchanged!(before, state_snapshot(), :no_request)
  end

  defp restart_endpoint_and_assert_catalog!(context, package) do
    assert :ok = Supervisor.terminate_child(CadenceWeb.Supervisor, CadenceWeb.Endpoint)
    assert {:ok, _pid} = Supervisor.restart_child(CadenceWeb.Supervisor, CadenceWeb.Endpoint)
    assert_host_catalog!(context, package)
  end

  defp assert_activation_records!(
         n_minus_1_catalog,
         n_catalog,
         rollback_catalog,
         n_minus_1_activation,
         n_activation,
         rollback_activation,
         n_minus_1,
         n
       ) do
    catalogs = Repo.all(from(catalog in CatalogPublication, order_by: [asc: catalog.sequence]))
    assert Enum.map(catalogs, & &1.sequence) == [1, 2, 3]
    assert Enum.map(catalogs, & &1.transition) == ["initial", "promotion", "rollback"]

    documents = [n_minus_1_catalog, n_catalog, rollback_catalog]

    for {catalog, document} <- Enum.zip(catalogs, documents) do
      assert catalog.signed_document_bytes == document
      envelope = Jason.decode!(document)
      assert catalog.payload_bytes == Base.url_decode64!(envelope["payload"], padding: false)
      assert catalog.acceptance_state == "accepted"
      assert catalog.identity_count == 1
      assert catalog.release_references["entries"] |> length() == 1
    end

    generations =
      Repo.all(from(generation in CatalogGeneration, order_by: [asc: generation.sequence]))

    assert Enum.map(generations, & &1.predecessor_kind) == ["none", "generation", "generation"]
    assert hd(generations).predecessor_catalog_publication_id == nil

    assert Enum.at(generations, 1).predecessor_catalog_publication_id ==
             hd(catalogs).publication_id

    assert Enum.at(generations, 2).predecessor_catalog_publication_id ==
             Enum.at(catalogs, 1).publication_id

    bindings =
      Enum.map(generations, fn generation ->
        Repo.get_by!(CatalogBinding, generation_id: generation.generation_id)
      end)

    assert length(bindings) == 3

    assert Enum.map(bindings, & &1.current_release_id) |> Enum.sort() ==
             Enum.sort([
               n_minus_1.release["releaseId"],
               n.release["releaseId"],
               n_minus_1.release["releaseId"]
             ])

    assert hd(bindings).previous_release_id == nil

    assert Enum.at(bindings, 1).previous_release_id in [
             n_minus_1.release["releaseId"],
             n.release["releaseId"]
           ]

    assert Enum.at(bindings, 2).previous_release_id in [
             n_minus_1.release["releaseId"],
             n.release["releaseId"]
           ]

    assert Repo.aggregate(Request, :count, :request_id) == 3 + rejected_request_count()

    assert Enum.map([n_minus_1_activation, n_activation, rollback_activation], & &1.sequence) == [
             1,
             2,
             3
           ]

    assert [[1, nil, false]] =
             Repo.query!("""
             SELECT cutover_epoch, legacy_catalog_publication_id, cutover_at IS NULL
             FROM frontend_release_activation_controls
             WHERE control_id = 1
             """).rows
  end

  defp rejected_request_count do
    Repo.query!(
      "SELECT COUNT(*) FROM frontend_release_activation_requests WHERE outcome = 'rejected'",
      []
    ).rows
    |> List.first()
    |> List.first()
  end

  defp assert_rejected_without_mutation!(fun, expected_status, request_policy) do
    before = state_snapshot()
    response = fun.()
    assert response.status == expected_status
    after_snapshot = state_snapshot()
    assert_state_unchanged!(before, after_snapshot, request_policy)
    response
  end

  defp assert_rejected_activation!(document, idempotency_key, assertion) do
    before = state_snapshot()

    response =
      publisher_conn()
      |> put_req_header("idempotency-key", idempotency_key)
      |> post(@promotion_path, Jason.encode!(%{"document" => document}))

    assert response.status == 422
    body = json_response(response, 422)["error"]
    assertion.(body)
    after_snapshot = state_snapshot()
    assert_state_unchanged!(before, after_snapshot, :rejected_request)
    response
  end

  defp assert_integrity_activation_rejected!(package, idempotency_key) do
    document =
      promotion_document(
        "initial",
        1,
        @n_minus_1_catalog_published_at,
        package,
        nil,
        route_snapshot_digest("initial", 1, @n_minus_1_catalog_published_at, package, nil)
      )

    before = state_snapshot()

    response =
      publisher_conn()
      |> put_req_header("idempotency-key", idempotency_key)
      |> post(@promotion_path, Jason.encode!(%{"document" => document}))

    assert response.status == 500
    assert response.resp_body == ~s({"error":{"code":"integrity_failure"}})
    assert state_snapshot() == before
  end

  defp assert_state_unchanged!(before, after_snapshot, request_policy) do
    assert Map.drop(before, [:activation_requests]) ==
             Map.drop(after_snapshot, [:activation_requests])

    case request_policy do
      :no_request ->
        assert before.activation_requests == after_snapshot.activation_requests

      :rejected_request ->
        assert length(after_snapshot.activation_requests) ==
                 length(before.activation_requests) + 1

        assert Enum.all?(before.activation_requests, &(&1 in after_snapshot.activation_requests))
        assert [request] = after_snapshot.activation_requests -- before.activation_requests
        assert request["outcome"] == "rejected"
    end
  end

  defp state_snapshot do
    %{
      release_publications: table_rows("frontend_release_publications", "publication_id"),
      release_artifacts: table_rows("frontend_release_artifacts", "artifact_id"),
      objects: table_rows("frontend_release_objects", "sha256"),
      object_chunks: table_rows("frontend_release_object_chunks", "sha256, chunk_index"),
      staged_objects: table_rows("frontend_release_staged_objects", "sha256"),
      staged_chunks: table_rows("frontend_release_staged_object_chunks", "sha256, chunk_index"),
      catalog_publications: table_rows("frontend_release_catalog_publications", "publication_id"),
      generations: table_rows("frontend_release_catalog_generations", "generation_id"),
      bindings: table_rows("frontend_release_catalog_bindings", "generation_id, application_id"),
      controls: table_rows("frontend_release_activation_controls", "control_id"),
      activation_requests: table_rows("frontend_release_activation_requests", "request_id")
    }
  end

  defp table_rows(table, order_by) do
    Repo.query!(
      "SELECT row_to_json(row)::text FROM (SELECT * FROM #{table} ORDER BY #{order_by}) AS row",
      []
    ).rows
    |> Enum.map(fn [row] -> Jason.decode!(row) end)
  end

  defp delete_object_chunk!("sha256:" <> digest, chunk_index) do
    with_disabled_triggers!("frontend_release_object_chunks", fn ->
      assert %{num_rows: 1} =
               Repo.query!(
                 """
                 DELETE FROM frontend_release_object_chunks
                 WHERE sha256 = $1 AND chunk_index = $2
                 """,
                 [digest, chunk_index]
               )
    end)
  end

  defp tamper_object_chunk!("sha256:" <> digest, chunk_index, bytes) do
    with_disabled_triggers!("frontend_release_object_chunks", fn ->
      assert %{num_rows: 1} =
               Repo.query!(
                 """
                 UPDATE frontend_release_object_chunks
                 SET bytes = $1, size = $2
                 WHERE sha256 = $3 AND chunk_index = $4
                 """,
                 [bytes, byte_size(bytes), digest, chunk_index]
               )
    end)
  end

  defp insert_object_chunk!("sha256:" <> digest, chunk_index, bytes) do
    with_disabled_triggers!("frontend_release_object_chunks", fn ->
      assert %{num_rows: 1} =
               Repo.query!(
                 """
                 INSERT INTO frontend_release_object_chunks
                   (sha256, chunk_index, bytes, size, inserted_at)
                 VALUES ($1, $2, $3, $4, now())
                 """,
                 [digest, chunk_index, bytes, byte_size(bytes)]
               )
    end)
  end

  defp with_disabled_triggers!(table, fun) do
    trigger_states = trigger_states!(table)

    try do
      Repo.query!("ALTER TABLE #{quote_identifier(table)} DISABLE TRIGGER ALL")
      fun.()
    after
      restore_trigger_states!([{table, trigger_states}])
    end
  end

  defp trigger_states!(table) do
    Repo.query!(
      """
      SELECT tgname, tgenabled::text
      FROM pg_trigger
      WHERE tgrelid = to_regclass($1::text)
      ORDER BY tgname
      """,
      [table]
    ).rows
    |> Enum.map(fn [name, state] -> {name, state} end)
  end

  defp restore_trigger_states!(trigger_states) do
    Enum.each(trigger_states, fn {table, states} ->
      Enum.each(states, fn {name, state} ->
        Repo.query!(
          "ALTER TABLE #{quote_identifier(table)} #{trigger_state_sql(state)} #{quote_identifier(name)}"
        )
      end)
    end)
  end

  defp trigger_state_sql("O"), do: "ENABLE TRIGGER"
  defp trigger_state_sql("D"), do: "DISABLE TRIGGER"
  defp trigger_state_sql("R"), do: "ENABLE REPLICA TRIGGER"
  defp trigger_state_sql("A"), do: "ENABLE ALWAYS TRIGGER"

  defp quote_identifier(value), do: ~s("#{String.replace(value, "\"", "\"\"")}")

  defp invalid_release_signature(package) do
    package.envelope
    |> Map.put("signature", Base.url_encode64(:binary.copy(<<0>>, 64), padding: false))
    |> canonical()
  end

  defp publication_config(extra_keys),
    do: [trust_records: @corpus["keys"] ++ extra_keys, allowed_origins: [@artifact_origin]]

  defp alternate_release_document(package) do
    package.release
    |> canonical()
    |> sign_document("fixture-release-key-alt", "release", @fork_seed)
    |> canonical()
  end

  defp alternate_release_key do
    {public_key, _private_key} =
      :crypto.generate_key(:eddsa, :ed25519, Base.decode16!(@fork_seed, case: :lower))

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

  defp invalid_promotion_signature(document) do
    document
    |> Jason.decode!()
    |> Map.put("signature", Base.url_encode64(:binary.copy(<<0>>, 64), padding: false))
    |> canonical()
  end

  defp mixed_artifact_set(package) do
    staged_artifacts(package) ++
      [%{"path" => "phase-d-n-minus-1-only.js", "sha256" => sha256("wrong-set"), "size" => 9}]
  end

  defp changed_artifact_bytes(package) do
    [first | rest] = package.artifacts
    changed = %{first | bytes: mutate_same_size(first.bytes)}

    [
      %{"path" => changed.path, "bytesBase64" => Base.encode64(changed.bytes)}
      | Enum.map(rest, &%{"path" => &1.path, "bytesBase64" => Base.encode64(&1.bytes)})
    ]
  end

  defp digest_size_drift(package) do
    [first | rest] = staged_artifacts(package)
    [Map.put(first, "size", first["size"] + 1) | rest]
  end

  defp overwrite_probe(package) do
    artifact = Enum.find(package.artifacts, &(&1.size > 0))
    %{digest: artifact.sha256, bytes: mutate_same_size(artifact.bytes)}
  end

  defp mutate_same_size(<<>>), do: <<1>>

  defp mutate_same_size(bytes) do
    prefix_size = byte_size(bytes) - 1
    <<prefix::binary-size(^prefix_size), last>> = bytes
    <<prefix::binary, Bitwise.bxor(last, 1)>>
  end

  defp promotion_document(
         transition,
         sequence,
         published_at,
         current,
         fallback,
         snapshot_digest,
         opts \\ []
       ) do
    identity = Keyword.get(opts, :identity, identity(current.release))
    entry = %{"identity" => identity, "current" => current.envelope}
    entry = if fallback, do: Map.put(entry, "fallback", fallback.envelope), else: entry

    payload =
      canonical(%{
        "entries" => [entry],
        "expiresAt" => @catalog_expires_at,
        "identityCount" => 1,
        "publishedAt" => published_at,
        "schema" => "cadence.first-party-frontend-release-catalog.v2",
        "sequence" => sequence,
        "snapshotDigest" => snapshot_digest,
        "transition" => transition
      })

    payload
    |> sign_document("fixture-promotion-key", "promotion", @promotion_seed)
    |> canonical()
  end

  defp sign_document(payload, key_id, role, seed_hex) do
    private_key = Base.decode16!(seed_hex, case: :lower)
    signature = :crypto.sign(:eddsa, :none, payload, [private_key, :ed25519])

    %{
      "schema" => "cadence.signed-frontend-document.v1",
      "keyId" => key_id,
      "algorithm" => "ed25519",
      "signingRole" => role,
      "payloadEncoding" => "base64url-json",
      "payload" => Base.url_encode64(payload, padding: false),
      "signature" => Base.url_encode64(signature, padding: false)
    }
  end

  defp route_snapshot_digest(transition, sequence, published_at, current, previous) do
    snapshot = %{
      "entries" => [
        %{
          "current" => route_snapshot_release(current),
          "identity" => identity(current.release),
          "previous" => if(previous, do: route_snapshot_release(previous), else: nil)
        }
      ],
      "expiresAt" => normalize_datetime(@catalog_expires_at),
      "identityCount" => 1,
      "publishedAt" => normalize_datetime(published_at),
      "schema" => "cadence.first-party-frontend-release-persisted-snapshot.v1",
      "sequence" => sequence,
      "transition" => transition
    }

    sha256(canonical(snapshot))
  end

  defp route_snapshot_release(package) do
    publication = Repo.get_by!(ReleasePublication, release_id: package.release["releaseId"])

    %{
      "artifactBaseUrl" => publication.artifact_base_url,
      "artifactCount" => publication.artifact_count,
      "exposedModule" => publication.exposed_module,
      "identity" => identity(package.release),
      "manifest" => %{
        "mediaType" => publication.manifest_media_type,
        "path" => publication.manifest_path,
        "sha256" => publication.manifest_sha256,
        "size" => publication.manifest_size
      },
      "payloadDigest" => publication.payload_digest,
      "provenance" => publication.provenance,
      "releaseId" => publication.release_id,
      "releasedAt" => normalize_datetime(publication.released_at),
      "remoteName" => publication.remote_name,
      "signedDocumentDigest" => publication.signed_document_digest,
      "signingKeyId" => publication.signing_key_id,
      "signingRole" => publication.signing_role
    }
  end

  defp normalize_datetime(datetime) when is_binary(datetime) do
    {:ok, value, _offset} = DateTime.from_iso8601(datetime)
    normalize_datetime(value)
  end

  defp normalize_datetime(datetime) do
    datetime = DateTime.from_unix!(DateTime.to_unix(datetime, :microsecond), :microsecond)
    Calendar.strftime(datetime, "%Y-%m-%dT%H:%M:%S.%fZ")
  end

  defp identity(release), do: Map.take(release, ["application", "package", "surface"])

  defp catalog_path(context),
    do:
      @host_catalog_suffix <>
        "/#{context.mission.mission_id}/spacecraft/#{context.spacecraft.spacecraft_id}/catalog"

  defp query_path(context),
    do:
      @host_catalog_suffix <>
        "/#{context.mission.mission_id}/spacecraft/#{context.spacecraft.spacecraft_id}/query"

  defp actions_path(context),
    do:
      @host_catalog_suffix <>
        "/#{context.mission.mission_id}/spacecraft/#{context.spacecraft.spacecraft_id}/actions"

  defp artifact_path(package, path),
    do: "/releases/telemetry_decom/#{package.release["releaseId"]}/artifacts/#{path}"

  defp bridge_conn(conn, catalog) do
    conn
    |> recycle()
    |> put_req_header("content-type", "application/json")
    |> put_req_header("x-cadence-poc-session", catalog["session"]["sessionId"])
    |> put_req_header("x-csrf-token", catalog["session"]["csrfToken"])
  end

  defp query_body(context) do
    %{
      "applicationKey" => "telemetry_decom",
      "applicationVersion" => 1,
      "surfaceId" => "packet_bindings",
      "surfaceVersion" => 1,
      "queryId" => "cadence.packet_bindings.manage",
      "queryVersion" => 1,
      "scope" => scope_document(context),
      "params" => %{}
    }
  end

  defp action_body(context, revision, endpoint, packet_id, review) do
    %{
      "applicationKey" => "telemetry_decom",
      "applicationVersion" => 1,
      "surfaceId" => "packet_bindings",
      "surfaceVersion" => 1,
      "actionId" => "save_packet_bindings",
      "scope" => scope_document(context),
      "input" => %{
        "expected_review" => review,
        "expected_configuration_version" => 0,
        "input_id" => "telemetry-fields",
        "input_version" => 1,
        "catalog_revision_id" => revision.catalog_revision_id,
        "source_endpoint_ref" => endpoint.source_endpoint_id,
        "selected_packet_ids" => [packet_id]
      }
    }
  end

  defp scope_document(context) do
    %{
      "organizationId" => context.organization.organization_id,
      "missionId" => context.mission.mission_id,
      "spacecraftId" => context.spacecraft.spacecraft_id
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

  defp sha256(bytes), do: "sha256:" <> Base.encode16(:crypto.hash(:sha256, bytes), case: :lower)
end
