Code.require_file(Path.join(__DIR__, "dashboard_rendered_viewport_runner.exs"))
Code.require_file(Path.join(__DIR__, "federation_release_fixture.exs"))

defmodule CadenceWeb.Assets.FederationBrowserSmokeSetup do
  @moduledoc false

  import ExUnit.Assertions
  import ExUnit.Callbacks

  alias Cadence.Applications.{ApplicationInstallations, HostContext, TelemetryDecom}
  alias Cadence.Auth.Scope
  alias Cadence.Comms.{Transport, TransportStore}
  alias Cadence.SourceEndpoints.SourceEndpoint
  alias CadenceWeb.Assets.DashboardRenderedViewportRunner
  alias CadenceWeb.Assets.FederationReleaseFixture
  alias CadenceWeb.TestFixtures

  @publication_paths [
    "assets/application-host/host/host.js",
    "assets/application-host/comms/mf-manifest.json",
    "assets/application-host/telemetry-decom/mf-manifest.json"
  ]

  @spec run(pid()) :: :ok
  def run(sandbox_owner) when is_pid(sandbox_owner) do
    app_root = Path.expand("../..", __DIR__)
    assert_production_publication!(app_root)

    previous_publication_config =
      Application.get_env(:cadence_web, :frontend_release_publication, :not_configured)

    Application.put_env(
      :cadence_web,
      :frontend_release_publication,
      FederationReleaseFixture.publication_config()
    )

    on_exit(fn ->
      case previous_publication_config do
        :not_configured -> Application.delete_env(:cadence_web, :frontend_release_publication)
        config -> Application.put_env(:cadence_web, :frontend_release_publication, config)
      end
    end)

    context = persist_context!()
    # Bandit owns the ephemeral listener before its actual port is returned.
    # The published catalog and manifest URLs are derived from that origin.
    port =
      DashboardRenderedViewportRunner.start_browser_endpoint_on_ephemeral_port!(sandbox_owner)

    base_url = "http://127.0.0.1:#{port}"

    release_fixture =
      FederationReleaseFixture.prepare_and_activate!(app_root, sandbox_owner: sandbox_owner)

    on_exit(fn -> FederationReleaseFixture.cleanup!(release_fixture) end)
    IO.puts("federation release generation activated: #{inspect(release_fixture.release_ids)}")

    args = [
      Path.join(app_root, "assets/test/federation_browser_smoke.mjs"),
      "--comms-url",
      "#{base_url}/missions/#{context.mission.mission_id}/applications/comms_overview/federated",
      "--telemetry-url",
      "#{base_url}/missions/#{context.mission.mission_id}/spacecraft/#{context.spacecraft.spacecraft_id}/applications/telemetry_decom/packet_bindings/federated",
      "--login-url",
      "#{base_url}/sign-in",
      "--login-email",
      context.user.email,
      "--mission-id",
      context.mission.mission_id,
      "--spacecraft-id",
      context.spacecraft.spacecraft_id,
      "--catalog-revision-id",
      context.catalog_revision_id,
      "--source-endpoint-id",
      context.source_endpoint_id,
      "--expected-apid",
      "42",
      "--federation-lifecycle-url",
      release_fixture.lifecycle.url,
      "--n-minus-1-comms-release-id",
      Map.fetch!(release_fixture.release_ids.n_minus_1, "comms_overview"),
      "--n-minus-1-telemetry-release-id",
      Map.fetch!(release_fixture.release_ids.n_minus_1, "telemetry_decom"),
      "--n-comms-release-id",
      Map.fetch!(release_fixture.release_ids.n, "comms_overview"),
      "--n-telemetry-release-id",
      Map.fetch!(release_fixture.release_ids.n, "telemetry_decom")
    ]

    args =
      case System.get_env("FEDERATION_BROWSER_SCENARIO_TIMEOUT_MS") do
        nil -> args
        timeout_ms -> args ++ ["--scenario-timeout-ms", timeout_ms]
      end

    assert {output, 0} =
             DashboardRenderedViewportRunner.run_dashboard_viewport_smoke(args,
               cd: app_root,
               timeout: 540_000,
               shutdown_timeout: 15_000,
               stdin: Jason.encode!(%{"password" => TestFixtures.default_password()}) <> "\n"
             )

    assert output =~ "federation_browser_smoke passed"
    :ok
  end

  defp assert_production_publication!(app_root) do
    missing =
      Enum.reject(@publication_paths, fn relative_path ->
        File.exists?(Path.join(app_root, "priv/static/#{relative_path}"))
      end)

    assert missing == [],
           "production federation publication is missing #{inspect(missing)}; run mix test.browser.federation"
  end

  defp persist_context! do
    user = TestFixtures.persist_user!()
    organization = TestFixtures.persist_org!(display_name: "Federation Browser Organization")
    membership = TestFixtures.grant_membership!(user, organization)

    mission =
      TestFixtures.persist_mission!(organization,
        slug: "federation-browser",
        display_name: "Federation Browser Mission"
      )

    spacecraft = TestFixtures.persist_spacecraft!(mission, display_name: "Federation Browser SC")

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

    persist_transport!(organization.organization_id, mission.mission_id)
    {revision, endpoint} = persist_packet_model!(mission, spacecraft, organization)

    assert {:ok, _configuration} =
             TelemetryDecom.configure(
               organization.organization_id,
               mission.mission_id,
               spacecraft.spacecraft_id,
               catalog_revision_id: revision.catalog_revision_id,
               handled_apids: [42],
               source_endpoint_id: endpoint.source_endpoint_id
             )

    %{
      user: user,
      mission: mission,
      spacecraft: spacecraft,
      catalog_revision_id: revision.catalog_revision_id,
      source_endpoint_id: endpoint.source_endpoint_id
    }
  end

  defp persist_transport!(organization_id, mission_id) do
    transport =
      Transport.new(%{
        mission_id: mission_id,
        display_name: "Federation Browser Transport",
        transport_kind: :tcp_socket,
        direction_capability: :inbound,
        adapter_key: :tcp_socket,
        configuration: %{
          "mode" => "listen",
          "direction_capability" => "inbound",
          "host" => "0.0.0.0",
          "port" => "5000",
          "framing_mode" => "raw",
          "tls_enabled" => "false"
        }
      })

    assert {:ok, _persisted} = TransportStore.persist_transport(organization_id, transport)
  end

  defp persist_packet_model!(mission, spacecraft, organization) do
    suffix = Integer.to_string(System.unique_integer([:positive]))

    database =
      TestFixtures.persist_catalog_database!(mission, slug: "federation-browser-#{suffix}")

    run =
      TestFixtures.start_catalog_revision_import!(database,
        revision_label: "Federation Browser Revision",
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
        source_endpoint_id: "federation-browser-source-#{suffix}",
        mission_id: mission.mission_id,
        spacecraft_id: spacecraft.spacecraft_id,
        display_name: "Federation Browser Downlink"
      })

    assert {:ok, persisted_endpoint} =
             Cadence.SourceEndpoints.persist_source_endpoint(
               organization.organization_id,
               endpoint
             )

    {revision, persisted_endpoint}
  end
end
