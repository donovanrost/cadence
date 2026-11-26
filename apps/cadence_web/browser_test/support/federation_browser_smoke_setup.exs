Code.require_file(Path.join(__DIR__, "dashboard_rendered_viewport_runner.exs"))
Code.require_file(Path.join(__DIR__, "federation_release_fixture.exs"))

defmodule CadenceWeb.Assets.FederationBrowserSmokeSetup do
  @moduledoc false

  import ExUnit.Assertions

  alias Cadence.Applications.{ApplicationInstallations, HostContext, TelemetryDecom}
  alias Cadence.Auth.Scope
  alias Cadence.Comms.{Transport, TransportStore}
  alias Cadence.SourceEndpoints.SourceEndpoint
  alias CadenceWeb.TestFixtures

  def persist_context! do
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
      scope: scope,
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
