defmodule CadenceWeb.FrontendReleaseActivationTest do
  use Cadence.DataCase, async: false

  import Phoenix.ConnTest
  import Plug.Conn

  alias Ecto.Adapters.SQL.Sandbox

  alias Cadence.Applications.{ApplicationInstallations, HostContext}
  alias Cadence.Auth.Scope
  alias CadenceWeb.ApplicationHostCatalog
  alias CadenceWeb.ApplicationReleaseRegistry
  alias CadenceWeb.FrontendReleaseActivation
  alias CadenceWeb.FrontendReleaseActivation.{CatalogBinding, CatalogGeneration, Request}
  alias CadenceWeb.FrontendReleaseCatalog
  alias CadenceWeb.FrontendReleasePublication
  alias CadenceWeb.FrontendReleasePublication.{CatalogPublication, ReleasePublication}
  alias CadenceWeb.TestFixtures

  @fixture Path.expand("../../../../test/fixtures/frontend_release_catalog_v1.json", __DIR__)
  @endpoint CadenceWeb.Endpoint
  @corpus @fixture |> File.read!() |> Jason.decode!()
  @release_seed "9d61b19deffd5a60ba844af492ec2cc44449c5697b326919703bac031cae7f60"
  @promotion_seed "4ccd089b28ff96da9db6c346ec114e0f5b8a319f35aba624da8cf6ed4fb8a6fb"
  @origin "https://cdn.example.com"
  @now "2026-09-01T19:00:00Z"
  @host_catalog_suffix "/api/cadence/application-host/v1/missions"
  @config [trust_records: @corpus["keys"], allowed_origins: [@origin]]
  @artifact_bytes %{
    "assets/app.js" => "app-bytes",
    "mf-manifest.json" => "manifest-bytes"
  }

  @fixture_cleanup_tables [
    "frontend_release_activation_requests",
    "frontend_release_catalog_bindings",
    "frontend_release_catalog_generations",
    "frontend_release_catalog_publications",
    "frontend_release_artifacts",
    "frontend_release_publications",
    "frontend_release_objects",
    "frontend_release_activation_controls"
  ]

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

  test "post-cutover registry reads the active generation and emits its immutable manifest route" do
    {_document, _payload, release} = admit_release!(@artifact_bytes, "reader-post-cutover")
    digest = snapshot_digest("initial", 1, "2026-09-01T18:00:00Z", release, nil)
    document = v2_document("initial", 1, "2026-09-01T18:00:00Z", release, nil, digest)

    assert {:ok, %{status: 201}} = activate(document, "reader-post-cutover-key")

    handler_id = {__MODULE__, make_ref()}

    :telemetry.attach(
      handler_id,
      [:cadence, :repo, :query],
      fn _event, _measurements, metadata, pid ->
        send(pid, {:application_release_registry_query, Map.get(metadata, :query)})
      end,
      self()
    )

    try do
      assert {:ok,
              %{
                source: :database,
                entries: [{{"telemetry_decom", 1, "packet_bindings", 1}, entry}]
              }} =
               ApplicationReleaseRegistry.snapshot()

      assert_receive {:application_release_registry_query, query}
      refute_receive {:application_release_registry_query, _query}, 50
      refute inspect(query) =~ "payload_bytes"
      refute inspect(query) =~ "signed_document_bytes"
      refute inspect(query) =~ "object_bytes"

      assert entry == %{
               federation: :module_federation,
               package_id: release["package"]["id"],
               package_version: release["package"]["version"],
               release_id: release["releaseId"],
               remote_name: release["remoteName"],
               manifest_path:
                 "/releases/telemetry_decom/#{release["releaseId"]}/artifacts/mf-manifest.json",
               exposed_module: "./Application"
             }

      assert {:ok, ^entry} =
               ApplicationReleaseRegistry.fetch("telemetry_decom", 1, "packet_bindings", 1)

      assert release["artifactBaseUrl"] ==
               @origin <> "/releases/telemetry_decom/" <> release["releaseId"] <> "/artifacts/"

      refute entry.manifest_path =~ "cdn.example.com"
    after
      :telemetry.detach(handler_id)
    end

    assert {:error, :no_history} =
             ApplicationReleaseRegistry.fetch("missing_application", 1, "missing_surface", 1)
  end

  test "post-cutover default admission scans to the valid telemetry surface and builds its catalog" do
    {_document, _payload, release} = admit_release!(@artifact_bytes, "reader-default-scan")
    digest = snapshot_digest("initial", 1, "2026-09-01T18:00:00Z", release, nil)
    document = v2_document("initial", 1, "2026-09-01T18:00:00Z", release, nil, digest)

    assert {:ok, %{status: 201}} = activate(document, "reader-default-scan-key")

    {scope, route_context} = installed_telemetry_context()

    assert {:ok, admission} =
             ApplicationHostCatalog.admit_application(
               scope,
               route_context,
               "telemetry_decom"
             )

    assert admission.surface.surface_id == "packet_bindings"
    assert admission.release.package_id == "cadence.telemetry-applications"
    assert admission.release.package_version == 1

    assert {:ok, catalog} =
             ApplicationHostCatalog.build(
               scope,
               route_context,
               session_id: "reader-default-scan-session",
               csrf_token: "reader-default-scan-csrf",
               bridge_base_url: ApplicationHostCatalog.bridge_base_path(route_context),
               manifest_url: fn path -> "https://example.test" <> path end
             )

    assert [application] = catalog["applications"]
    assert application["applicationKey"] == "telemetry_decom"
    assert application["surface"]["surfaceId"] == "packet_bindings"
    assert application["release"]["releaseId"] == release["releaseId"]
  end

  test "post-cutover installed admission rejects a release with a mismatched package" do
    {_document, _payload, release} =
      admit_release!(
        @artifact_bytes,
        "reader-package-mismatch-installed",
        package: %{"id" => "cadence.untrusted-package", "version" => 1}
      )

    digest = snapshot_digest("initial", 1, "2026-09-01T18:00:00Z", release, nil)
    document = v2_document("initial", 1, "2026-09-01T18:00:00Z", release, nil, digest)

    assert {:ok, %{status: 201}} = activate(document, "reader-package-mismatch-installed-key")

    {scope, route_context} = installed_telemetry_context()

    assert {:error, :application_unavailable} =
             ApplicationHostCatalog.admit_application(scope, route_context, "telemetry_decom")
  end

  test "post-cutover contributed admission accepts its exact package identity" do
    {_document, _payload, release} =
      admit_release!(
        @artifact_bytes,
        "reader-package-mismatch-contributed",
        application: %{"id" => "comms_overview", "version" => 1},
        package: %{"id" => "cadence.comms_overview", "version" => 1},
        surface: %{"id" => "overview", "version" => 1}
      )

    digest = snapshot_digest("initial", 1, "2026-09-01T18:00:00Z", release, nil)
    document = v2_document("initial", 1, "2026-09-01T18:00:00Z", release, nil, digest)

    assert {:ok, %{status: 201}} = activate(document, "reader-package-mismatch-contributed-key")

    {scope, route_context} = installed_comms_context()

    assert {:ok, admission} =
             ApplicationHostCatalog.admit_application(scope, route_context, "comms_overview")

    assert admission.package == %{package_id: "cadence.comms_overview", version: 1}
    assert admission.release.package_id == "cadence.comms_overview"
    assert admission.release.package_version == 1
  end

  test "post-cutover contributed package mismatch is sanitized across host boundaries" do
    {scope, route_context} = installed_comms_context()
    mission_id = route_context.mission.mission_id
    member_conn = TestFixtures.member_conn(scope.user)
    catalog_conn = get(member_conn, catalog_path(mission_id))
    catalog = json_response(catalog_conn, 200)

    {_document, _payload, release} =
      admit_release!(
        @artifact_bytes,
        "reader-package-mismatch-contributed",
        application: %{"id" => "comms_overview", "version" => 1},
        package: %{"id" => "cadence.untrusted-package", "version" => 1},
        surface: %{"id" => "overview", "version" => 1}
      )

    digest = snapshot_digest("initial", 1, "2026-09-01T18:00:00Z", release, nil)
    document = v2_document("initial", 1, "2026-09-01T18:00:00Z", release, nil, digest)

    assert {:ok, %{status: 201}} = activate(document, "reader-package-mismatch-contributed-key")

    assert {:error, :application_unavailable} =
             ApplicationHostCatalog.admit_application(scope, route_context, "comms_overview")

    scope_document = ApplicationHostCatalog.scope_document(scope, route_context)

    catalog_response = get(member_conn, catalog_path(mission_id))

    query_response =
      post_host_bridge(catalog_conn, catalog, query_path(mission_id), %{
        "applicationKey" => "comms_overview",
        "applicationVersion" => 1,
        "surfaceId" => "overview",
        "surfaceVersion" => 1,
        "queryId" => "cadence.comms.overview",
        "version" => 1,
        "scope" => scope_document
      })

    action_response =
      post_host_bridge(
        catalog_conn,
        catalog,
        actions_path(mission_id),
        %{
          "applicationKey" => "comms_overview",
          "applicationVersion" => 1,
          "surfaceId" => "overview",
          "surfaceVersion" => 1,
          "actionId" => "anything",
          "input" => %{},
          "scope" => scope_document
        },
        "reader-package-mismatch-contributed-action"
      )

    for response <- [catalog_response, query_response, action_response] do
      assert %{
               "schema" => "cadence.application-host-problem.v1",
               "code" => "application_unavailable",
               "message" => "The requested application is not available in this scope."
             } = json_response(response, 404)

      refute response.resp_body =~ "cadence.comms_overview"
      refute response.resp_body =~ "cadence.untrusted-package"
      refute response.resp_body =~ "package"
      refute response.resp_body =~ "no_history"
      refute response.resp_body =~ "database_unavailable"
      refute response.resp_body =~ "integrity_failure"
      refute response.resp_body =~ release["releaseId"]
      refute response.resp_body =~ "reader-package-mismatch-contributed"
    end
  end

  test "post-cutover authoritative artifact paths remain readable by the registry" do
    bytes = %{
      "assets/app..js" => "app-bytes",
      "mf-manifest.json" => "manifest-bytes"
    }

    {_document, _payload, release} = admit_release!(bytes, "reader-artifact-path-parity")
    digest = snapshot_digest("initial", 1, "2026-09-01T18:00:00Z", release, nil)
    document = v2_document("initial", 1, "2026-09-01T18:00:00Z", release, nil, digest)

    assert {:ok, %{status: 201}} = activate(document, "reader-artifact-path-parity-key")

    assert {:ok, _release} =
             ApplicationReleaseRegistry.fetch("telemetry_decom", 1, "packet_bindings", 1)
  end

  test "post-cutover no_history is sanitized for catalog, registered query, and action paths" do
    user = TestFixtures.persist_user!()
    organization = TestFixtures.persist_org!()
    membership = TestFixtures.grant_membership!(user, organization)
    mission = TestFixtures.persist_mission!(organization, mission_id: "reader-no-history-mission")

    scope =
      Scope.new(%{
        user: user,
        organization_id: organization.organization_id,
        organization: organization,
        organization_membership: membership
      })

    member_conn = TestFixtures.member_conn(user)
    catalog_conn = get(member_conn, catalog_path(mission.mission_id))
    catalog = json_response(catalog_conn, 200)

    scope_document =
      ApplicationHostCatalog.scope_document(scope, %{
        host_context: HostContext.mission(mission.mission_id)
      })

    {_document, _payload, release} =
      admit_release!(@artifact_bytes, "reader-no-history-controller")

    digest = snapshot_digest("initial", 1, "2026-09-01T18:00:00Z", release, nil)
    document = v2_document("initial", 1, "2026-09-01T18:00:00Z", release, nil, digest)
    assert {:ok, %{status: 201}} = activate(document, "reader-no-history-controller-key")

    catalog_response = get(member_conn, catalog_path(mission.mission_id))

    query_response =
      post_host_bridge(catalog_conn, catalog, query_path(mission.mission_id), %{
        "applicationKey" => "comms_overview",
        "applicationVersion" => 1,
        "surfaceId" => "overview",
        "surfaceVersion" => 1,
        "queryId" => "cadence.comms.overview",
        "version" => 1,
        "scope" => scope_document
      })

    action_response =
      post_host_bridge(
        catalog_conn,
        catalog,
        actions_path(mission.mission_id),
        %{
          "applicationKey" => "comms_overview",
          "applicationVersion" => 1,
          "actionId" => "anything",
          "input" => %{},
          "scope" => scope_document
        },
        "reader-no-history-action"
      )

    for response <- [catalog_response, query_response, action_response] do
      assert %{
               "schema" => "cadence.application-host-problem.v1",
               "code" => "application_unavailable",
               "message" => "The requested application is not available in this scope."
             } = json_response(response, 404)

      refute response.resp_body =~ "no_history"
      refute response.resp_body =~ "database_unavailable"
      refute response.resp_body =~ "integrity_failure"
    end
  end

  test "host catalog propagates database no_history for a missing default surface" do
    {_document, _payload, release} = admit_release!(@artifact_bytes, "reader-host-miss")
    digest = snapshot_digest("initial", 1, "2026-09-01T18:00:00Z", release, nil)
    document = v2_document("initial", 1, "2026-09-01T18:00:00Z", release, nil, digest)

    assert {:ok, %{status: 201}} = activate(document, "reader-host-miss-key")

    {scope, route_context} = installed_comms_context()

    assert {:error, :no_history} =
             ApplicationHostCatalog.admit_application(scope, route_context, "comms")
  end

  test "host catalog build does not swallow database no_history for an installed application" do
    {_document, _payload, release} = admit_release!(@artifact_bytes, "reader-host-build-miss")
    digest = snapshot_digest("initial", 1, "2026-09-01T18:00:00Z", release, nil)
    document = v2_document("initial", 1, "2026-09-01T18:00:00Z", release, nil, digest)

    assert {:ok, %{status: 201}} = activate(document, "reader-host-build-miss-key")

    {scope, route_context} = installed_comms_context()

    assert {:error, :no_history} =
             ApplicationHostCatalog.build(
               scope,
               route_context,
               session_id: "reader-host-session",
               csrf_token: "reader-host-csrf",
               bridge_base_url: ApplicationHostCatalog.bridge_base_path(route_context),
               manifest_url: fn path -> "https://example.test" <> path end
             )
  end

  test "epoch zero preserves the static registry while inactive database history remains" do
    {_document, _payload, release} = admit_release!(@artifact_bytes, "reader-static-cutover")
    digest = snapshot_digest("initial", 1, "2026-09-01T18:00:00Z", release, nil)
    document = v2_document("initial", 1, "2026-09-01T18:00:00Z", release, nil, digest)

    assert {:ok, %{status: 201}} = activate(document, "reader-static-cutover-key")

    with_disabled_triggers!(["frontend_release_activation_controls"], fn ->
      Repo.query!("""
      UPDATE frontend_release_activation_controls
      SET cutover_epoch = 0, cutover_at = NULL, legacy_catalog_publication_id = NULL
      WHERE control_id = 1
      """)
    end)

    assert {:ok, %{source: :static, entries: entries}} = ApplicationReleaseRegistry.snapshot()

    assert {:ok, static_release} =
             ApplicationReleaseRegistry.fetch("telemetry_decom", 1, "packet_bindings", 1)

    assert static_release.manifest_path ==
             "/assets/application-host/telemetry-decom/mf-manifest.json"

    assert Enum.any?(entries, fn {key, _release} ->
             key == {"telemetry_decom", 1, "packet_bindings", 1}
           end)

    assert static_release.release_id == "telemetry-decom-v1"
    refute static_release.release_id == release["releaseId"]
  end

  test "post-cutover registry rejects tampered accepted publication metadata" do
    {_document, _payload, release} = admit_release!(@artifact_bytes, "reader-integrity")
    digest = snapshot_digest("initial", 1, "2026-09-01T18:00:00Z", release, nil)
    document = v2_document("initial", 1, "2026-09-01T18:00:00Z", release, nil, digest)

    assert {:ok, %{status: 201}} = activate(document, "reader-integrity-key")

    tampered_provenance = Map.put(release["provenance"], "buildId", "tampered-reader-build")

    tamper_release_publication_in_transaction!(
      release["releaseId"],
      :provenance,
      tampered_provenance
    )

    assert {:error, {:integrity_failure, :release_publication_integrity_failure}} =
             ApplicationReleaseRegistry.snapshot()
  end

  test "duplicate binding identities are rejected and snapshot reconstruction fails closed" do
    {_document, _payload, release} =
      admit_release!(@artifact_bytes, "activation-duplicate-binding")

    digest = snapshot_digest("initial", 1, "2026-09-01T18:00:00Z", release, nil)
    document = v2_document("initial", 1, "2026-09-01T18:00:00Z", release, nil, digest)

    assert {:ok, response} = activate(document, "duplicate-binding-key")
    binding = Repo.one!(CatalogBinding)

    duplicate_attrs = %{
      generation_id: binding.generation_id,
      application_id: binding.application_id,
      application_version: binding.application_version,
      package_id: binding.package_id,
      package_version: binding.package_version,
      surface_id: binding.surface_id,
      surface_version: binding.surface_version,
      current_publication_id: binding.current_publication_id,
      current_release_id: binding.current_release_id,
      previous_publication_id: binding.previous_publication_id,
      previous_release_id: binding.previous_release_id,
      inserted_at: binding.inserted_at
    }

    assert {:error, changeset} = Repo.insert(CatalogBinding.changeset(duplicate_attrs))
    assert changeset.errors != []

    Repo.query!(
      "ALTER TABLE frontend_release_catalog_bindings DROP CONSTRAINT frcb_identity_pkey"
    )

    Repo.query!("""
    ALTER TABLE frontend_release_catalog_generations
    DISABLE TRIGGER frontend_release_catalog_generations_immutable
    """)

    Repo.query!(
      """
      UPDATE frontend_release_catalog_generations
      SET identity_count = 2
      WHERE generation_id = $1
      """,
      [response.generation_id]
    )

    Repo.query!("""
    ALTER TABLE frontend_release_catalog_generations
    ENABLE TRIGGER frontend_release_catalog_generations_immutable
    """)

    assert {:ok, _duplicate} = Repo.insert(CatalogBinding.changeset(duplicate_attrs))

    assert {:error, :integrity} =
             FrontendReleaseActivation.persisted_snapshot_digest(response.catalog_publication_id)
  end

  test "distinct package bindings collapsing to one host identity fail closed" do
    {_document, _payload, release} = admit_release!(@artifact_bytes, "reader-duplicate-host")
    digest = snapshot_digest("initial", 1, "2026-09-01T18:00:00Z", release, nil)
    document = v2_document("initial", 1, "2026-09-01T18:00:00Z", release, nil, digest)

    assert {:ok, _response} = activate(document, "reader-duplicate-host-key")
    binding = Repo.one!(CatalogBinding)

    duplicate_attrs = %{
      generation_id: binding.generation_id,
      application_id: binding.application_id,
      application_version: binding.application_version,
      package_id: binding.package_id <> "-other",
      package_version: binding.package_version + 1,
      surface_id: binding.surface_id,
      surface_version: binding.surface_version,
      current_publication_id: binding.current_publication_id,
      current_release_id: binding.current_release_id,
      previous_publication_id: nil,
      previous_release_id: nil,
      inserted_at: binding.inserted_at
    }

    Repo.query!(
      "ALTER TABLE frontend_release_catalog_bindings DROP CONSTRAINT frcb_identity_pkey"
    )

    assert {:ok, _duplicate} = Repo.insert(CatalogBinding.changeset(duplicate_attrs))

    assert {:error, {:integrity_failure, :duplicate_application_surface_identity}} =
             ApplicationReleaseRegistry.snapshot()
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
    with_committed_release_fixture!(
      @artifact_bytes,
      "activation-concurrent-replay",
      fn release ->
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
    )
  end

  test "concurrent same-key different-document activation commits one and returns one exact 409" do
    with_committed_release_fixture!(
      @artifact_bytes,
      "activation-concurrent-conflict",
      fn release ->
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
                   {:error,
                    %{status: 409, body: ~s({"error":{"code":"idempotency_key_reused"}})}},
                   &1
                 )
               ) == 1

        assert Repo.aggregate(CatalogPublication, :count, :publication_id) == 1
        assert Repo.aggregate(CatalogGeneration, :count, :generation_id) == 1
        assert Repo.aggregate(CatalogBinding, :count, :generation_id) == 1
        assert Repo.aggregate(Request, :count, :request_id) == 1
      end
    )
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

  test "tampered persisted signing key rejects activation without partial writes" do
    assert_tampered_release_rejected!(
      :signing_key_id,
      fn _release -> "tampered-release-key" end,
      "activation-tampered-signing-key"
    )
  end

  test "tampered persisted release time rejects activation without partial writes" do
    assert_tampered_release_rejected!(
      :released_at,
      fn _release -> ~U[2026-09-01 18:00:00Z] end,
      "activation-tampered-released-at"
    )
  end

  test "tampered persisted provenance rejects activation without partial writes" do
    assert_tampered_release_rejected!(
      :provenance,
      fn release -> Map.put(release["provenance"], "buildId", "tampered-build") end,
      "activation-tampered-provenance"
    )
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

    with_disabled_triggers!(["frontend_release_catalog_generations"], fn ->
      Repo.query!(
        """
        UPDATE frontend_release_catalog_generations
        SET identity_count = identity_count + 1
        WHERE generation_id = $1
        """,
        [latest.generation_id]
      )
    end)

    assert {:error, {:integrity_failure, :generation_identity_count_mismatch}} =
             ApplicationReleaseRegistry.snapshot()
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

    assert {:ok, %{source: :database}} = ApplicationReleaseRegistry.snapshot()

    assert {:ok, reader_release} =
             ApplicationReleaseRegistry.fetch("telemetry_decom", 1, "packet_bindings", 1)

    assert reader_release.release_id == second_release["releaseId"]
  end

  test "direct catalog writers return the activation-required closure without reading or writing" do
    assert FrontendReleasePublication.admit_catalog(%{"bad" => self()}) ==
             {:error, :catalog_activation_required}

    assert FrontendReleasePublication.publish_catalog(%{"bad" => self()}) ==
             {:error, :catalog_activation_required}

    assert Repo.aggregate(CatalogPublication, :count, :publication_id) == 0
  end

  test "fixture cleanup restores exact prior trigger states" do
    {document, _payload, release} = release_document(@artifact_bytes, "activation-trigger-state")
    release_id = release["releaseId"]

    run_unboxed_task!(fn ->
      assert {:ok, %ReleasePublication{}} =
               FrontendReleasePublication.admit_release(document, @artifact_bytes,
                 now: @now,
                 publication_config: @config
               )
    end)

    try do
      before =
        run_unboxed_task!(fn ->
          Repo.query!("""
          ALTER TABLE frontend_release_publications
          DISABLE TRIGGER frontend_release_publications_append_only
          """)

          trigger_states!("frontend_release_publications")
        end)

      cleanup_committed_release_fixture!(release_id)

      after_cleanup =
        run_unboxed_task!(fn -> trigger_states!("frontend_release_publications") end)

      assert after_cleanup == before
    after
      run_unboxed_task!(fn ->
        Repo.query!("""
        ALTER TABLE frontend_release_publications
        ENABLE TRIGGER frontend_release_publications_append_only
        """)
      end)

      cleanup_committed_release_fixture!(release_id)
    end
  end

  test "fixture cleanup restores exact prior trigger states after partial disable failure" do
    {document, _payload, release} =
      release_document(@artifact_bytes, "activation-trigger-failure")

    release_id = release["releaseId"]

    run_unboxed_task!(fn ->
      assert {:ok, %ReleasePublication{}} =
               FrontendReleasePublication.admit_release(document, @artifact_bytes,
                 now: @now,
                 publication_config: @config
               )
    end)

    try do
      before =
        run_unboxed_task!(fn -> trigger_states!("frontend_release_publications") end)

      assert {:error, %Postgrex.Error{}} =
               run_unboxed_task!(fn ->
                 try do
                   with_disabled_triggers!(
                     ["frontend_release_publications"],
                     fn -> :unexpected_success end,
                     disable_tables: [
                       "frontend_release_publications",
                       "frontend_release_missing_for_partial_disable"
                     ]
                   )
                 rescue
                   error in Postgrex.Error -> {:error, error}
                 end
               end)

      after_failure =
        run_unboxed_task!(fn -> trigger_states!("frontend_release_publications") end)

      assert after_failure == before
    after
      cleanup_committed_release_fixture!(release_id)
    end
  end

  defp activate(document, key) do
    FrontendReleaseActivation.activate_catalog(document, key,
      now: @now,
      publication_config: @config,
      publisher_identity: "github-actions/frontend-release"
    )
  end

  defp installed_comms_context do
    user = TestFixtures.persist_user!()
    organization = TestFixtures.persist_org!()
    membership = TestFixtures.grant_membership!(user, organization)
    mission = TestFixtures.persist_mission!(organization, mission_id: "reader-comms-mission")

    scope =
      Scope.new(%{
        user: user,
        organization_id: organization.organization_id,
        organization: organization,
        organization_membership: membership
      })

    host_context = HostContext.mission(mission.mission_id)

    assert {:ok, _installation} =
             ApplicationInstallations.install(scope, host_context, "comms")

    {scope, %{host_context: host_context, mission: mission, spacecraft: nil}}
  end

  defp installed_telemetry_context do
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

    assert {:ok, _installation} =
             ApplicationInstallations.install(scope, host_context, "telemetry_decom")

    {scope,
     %{
       host_context: host_context,
       mission: mission,
       spacecraft: spacecraft
     }}
  end

  defp concurrently(functions) do
    parent = self()

    tasks =
      Enum.map(functions, fn function ->
        Task.async(fn ->
          :ok = Sandbox.checkout(Repo, sandbox: false)

          try do
            [[backend_pid]] = Repo.query!("SELECT pg_backend_pid()").rows
            send(parent, {:activation_worker_ready, self(), backend_pid})

            receive do
              :activate -> function.()
            end
          after
            :ok = Sandbox.checkin(Repo)
          end
        end)
      end)

    backend_pids =
      Enum.map(tasks, fn %Task{pid: pid} ->
        assert_receive {:activation_worker_ready, ^pid, backend_pid}, 30_000
        backend_pid
      end)

    assert length(Enum.uniq(backend_pids)) == length(tasks)

    Enum.each(tasks, fn %Task{pid: pid} -> send(pid, :activate) end)
    Enum.map(tasks, &Task.await(&1, 30_000))
  end

  defp assert_tampered_release_rejected!(field, tampered_value, build_id) do
    with_committed_release_fixture!(@artifact_bytes, build_id, fn release ->
      snapshot_digest = snapshot_digest("initial", 1, "2026-09-01T18:00:00Z", release, nil)
      document = v2_document("initial", 1, "2026-09-01T18:00:00Z", release, nil, snapshot_digest)

      tamper_release_publication!(release["releaseId"], field, tampered_value.(release))

      assert {:error, %{status: 500, body: ~s({"error":{"code":"integrity_failure"}})}} =
               activate(document, "tampered-" <> Atom.to_string(field))

      assert Repo.aggregate(CatalogPublication, :count, :publication_id) == 0
      assert Repo.aggregate(CatalogGeneration, :count, :generation_id) == 0
      assert Repo.aggregate(CatalogBinding, :count, :generation_id) == 0
      assert Repo.aggregate(Request, :count, :request_id) == 0
      assert Repo.aggregate(ReleasePublication, :count, :publication_id) == 1

      assert [[0, nil]] =
               Repo.query!("""
               SELECT cutover_epoch, legacy_catalog_publication_id
               FROM frontend_release_activation_controls
               WHERE control_id = 1
               """).rows
    end)
  end

  defp tamper_release_publication!(release_id, field, value) do
    run_unboxed_task!(fn ->
      with_disabled_triggers!(["frontend_release_publications"], fn ->
        update_tampered_release_field!(release_id, field, value)
      end)
    end)
  end

  defp tamper_release_publication_in_transaction!(release_id, field, value) do
    with_disabled_triggers!(["frontend_release_publications"], fn ->
      update_tampered_release_field!(release_id, field, value)
    end)
  end

  defp update_tampered_release_field!(release_id, :signing_key_id, value) do
    Repo.query!(
      """
      UPDATE frontend_release_publications
      SET signing_key_id = $1
      WHERE release_id = $2
      """,
      [value, release_id]
    )
  end

  defp update_tampered_release_field!(release_id, :released_at, value) do
    Repo.query!(
      """
      UPDATE frontend_release_publications
      SET released_at = $1::timestamptz
      WHERE release_id = $2
      """,
      [value, release_id]
    )
  end

  defp update_tampered_release_field!(release_id, :provenance, value) do
    Repo.query!(
      """
      UPDATE frontend_release_publications
      SET provenance = $1::jsonb
      WHERE release_id = $2
      """,
      [value, release_id]
    )
  end

  defp with_committed_release_fixture!(bytes_by_path, build_id, fun) do
    {document, _payload, release} = release_document(bytes_by_path, build_id)
    release_id = release["releaseId"]

    try do
      run_unboxed_task!(fn ->
        assert {:ok, %ReleasePublication{}} =
                 FrontendReleasePublication.admit_release(document, bytes_by_path,
                   now: @now,
                   publication_config: @config
                 )
      end)

      fun.(release)
    after
      cleanup_committed_release_fixture!(release_id)
    end
  end

  defp run_unboxed_task!(fun) do
    Task.async(fn ->
      :ok = Sandbox.checkout(Repo, sandbox: false)

      try do
        fun.()
      after
        :ok = Sandbox.checkin(Repo)
      end
    end)
    |> Task.await(30_000)
  end

  defp cleanup_committed_release_fixture!(release_id, opts \\ []) do
    run_unboxed_task!(fn ->
      catalog_ids =
        Repo.query!(
          """
          SELECT publication_id
          FROM frontend_release_catalog_publications
          WHERE EXISTS (
            SELECT 1
            FROM jsonb_array_elements(release_references->'entries') AS entry
            WHERE entry->>'currentReleaseId' = $1
               OR entry->>'fallbackReleaseId' = $1
          )
          """,
          [release_id]
        ).rows
        |> Enum.map(&List.first/1)

      generation_ids =
        Repo.query!(
          """
          SELECT generation_id
          FROM frontend_release_catalog_generations
          WHERE catalog_publication_id = ANY($1::text[])
          """,
          [catalog_ids]
        ).rows
        |> Enum.map(&List.first/1)

      publication_ids =
        Repo.query!(
          """
          SELECT publication_id
          FROM frontend_release_publications
          WHERE release_id = $1
          """,
          [release_id]
        ).rows
        |> Enum.map(&List.first/1)

      object_digests =
        Repo.query!(
          """
          SELECT DISTINCT sha256
          FROM frontend_release_artifacts
          WHERE release_publication_id = ANY($1::text[])
          """,
          [publication_ids]
        ).rows
        |> Enum.map(&List.first/1)

      tables = Keyword.get(opts, :trigger_tables, @fixture_cleanup_tables)
      disable_tables = Keyword.get(opts, :disable_tables, tables)

      with_disabled_triggers!(
        tables,
        fn ->
          Repo.query!(
            """
            DELETE FROM frontend_release_activation_requests
            WHERE catalog_publication_id = ANY($1::text[])
               OR generation_id = ANY($2::text[])
            """,
            [catalog_ids, generation_ids]
          )

          Repo.query!(
            """
            DELETE FROM frontend_release_catalog_bindings
            WHERE generation_id = ANY($1::text[])
            """,
            [generation_ids]
          )

          Repo.query!(
            """
            DELETE FROM frontend_release_catalog_generations
            WHERE generation_id = ANY($1::text[])
            """,
            [generation_ids]
          )

          Repo.query!(
            """
            DELETE FROM frontend_release_catalog_publications
            WHERE publication_id = ANY($1::text[])
            """,
            [catalog_ids]
          )

          Repo.query!(
            """
            DELETE FROM frontend_release_artifacts
            WHERE release_publication_id = ANY($1::text[])
            """,
            [publication_ids]
          )

          Repo.query!("DELETE FROM frontend_release_publications WHERE release_id = $1", [
            release_id
          ])

          Repo.query!(
            """
            DELETE FROM frontend_release_objects AS object
            WHERE object.sha256 = ANY($1::text[])
              AND NOT EXISTS (
                SELECT 1
                FROM frontend_release_artifacts AS artifact
                WHERE artifact.sha256 = object.sha256
              )
            """,
            [object_digests]
          )

          Repo.query!("""
          UPDATE frontend_release_activation_controls
          SET cutover_epoch = 0, cutover_at = NULL, legacy_catalog_publication_id = NULL
          WHERE control_id = 1
            AND cutover_epoch = 1
            AND NOT EXISTS (SELECT 1 FROM frontend_release_catalog_generations)
          """)
        end,
        disable_tables: disable_tables
      )
    end)
  end

  defp with_disabled_triggers!(tables, fun, opts \\ []) do
    trigger_states = Enum.map(tables, &{&1, trigger_states!(&1)})
    disable_tables = Keyword.get(opts, :disable_tables, tables)

    try do
      Enum.each(disable_tables, fn table ->
        Repo.query!("ALTER TABLE #{quote_identifier(table)} DISABLE TRIGGER ALL")
      end)

      fun.()
    after
      restore_trigger_states!(trigger_states)
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

  defp admit_release!(bytes_by_path, build_id, opts \\ []) do
    {document, payload, release} =
      release_document(bytes_by_path, build_id, "2026-09-01T17:00:00Z", opts)

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

  defp release_document(
         bytes_by_path,
         build_id,
         released_at \\ "2026-09-01T17:00:00Z",
         opts \\ []
       ) do
    base =
      @corpus["release"]["payload"]
      |> Jason.decode!()
      |> apply_release_options(opts)

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

  defp apply_release_options(release, opts) do
    Enum.reduce([:application, :package, :surface], release, fn key, release ->
      case Keyword.fetch(opts, key) do
        {:ok, value} -> Map.put(release, Atom.to_string(key), value)
        :error -> release
      end
    end)
  end

  defp catalog_path(mission_id),
    do: @host_catalog_suffix <> "/" <> mission_id <> "/catalog"

  defp query_path(mission_id),
    do: @host_catalog_suffix <> "/" <> mission_id <> "/query"

  defp actions_path(mission_id),
    do: @host_catalog_suffix <> "/" <> mission_id <> "/actions"

  defp post_host_bridge(conn, catalog, path, body, idempotency_key \\ nil) do
    conn =
      conn
      |> recycle()
      |> put_req_header("content-type", "application/json")
      |> put_req_header("x-cadence-poc-session", catalog["session"]["sessionId"])
      |> put_req_header("x-csrf-token", catalog["session"]["csrfToken"])

    conn =
      if idempotency_key do
        put_req_header(conn, "idempotency-key", idempotency_key)
      else
        conn
      end

    post(conn, path, Jason.encode!(body))
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
