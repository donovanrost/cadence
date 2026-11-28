defmodule Cadence.Reads.ApplicationSurfaces.TelemetryDecomPacketBindingsTest do
  use Cadence.DataCase, async: false

  alias Cadence.Applications.{
    ApplicationInstallations,
    HostContext,
    Registry,
    SurfaceQueryRequest,
    TelemetryDecomFixtures
  }

  alias Cadence.Reads.ApplicationSurfaces
  alias Cadence.Reads.ApplicationSurfaces.TelemetryDecom.PacketBindings, as: PacketSurface

  @organization_id "org-packet-feature"
  @mission_id "mission-packet-feature"

  setup do
    {spacecraft, revision, endpoint} =
      TelemetryDecomFixtures.setup_imported_mission!(@organization_id, @mission_id)

    scope = TelemetryDecomFixtures.user_scope(@organization_id, "packet-feature")
    host = HostContext.spacecraft(@mission_id, spacecraft.spacecraft_id)
    {:ok, installation} = ApplicationInstallations.install(scope, host, "telemetry_decom")

    %{
      scope: scope,
      host: host,
      spacecraft: spacecraft,
      revision: revision,
      endpoint: endpoint,
      installation: installation
    }
  end

  test "unconfigured packet read uses the trusted scoped contribution and rejects invalid query or scope",
       c do
    {:ok, definition} = Registry.fetch_available("telemetry_decom")
    {:ok, surface} = Registry.fetch_surface(definition, :spacecraft, "packet_bindings")

    assert {:ok, %{"data" => page}} =
             ApplicationSurfaces.load(c.scope, c.host, "telemetry_decom", 1, surface)

    assert page["configuration"] == nil
    assert page["status"] == "unconfigured"
    assert page["context"]["actor_id"] == c.scope.user.user_id

    assert page["input"] == %{
             "id" => "telemetry-fields",
             "version" => 1,
             "minimum" => 1,
             "maximum" => 512
           }

    assert {:error, :invalid_application_surface_query} =
             PacketSurface.load(c.scope, c.host, query(%{"page" => "1x"}))

    assert {:error, :invalid_application_surface_query} =
             PacketSurface.load(c.scope, c.host, query(%{"mission_id" => "foreign"}))

    assert {:error, _} =
             PacketSurface.load(%{c.scope | organization_id: "foreign"}, c.host, query())
  end

  test "endpoint pages include mission endpoints and exclude another spacecraft even beyond 128 rows",
       c do
    for index <- 1..130 do
      TelemetryDecomFixtures.persist_source_endpoint!(
        @organization_id,
        @mission_id,
        c.spacecraft.spacecraft_id,
        display_name: "Endpoint #{index}"
      )
    end

    TelemetryDecomFixtures.persist_source_endpoint!(@organization_id, @mission_id, nil,
      display_name: "Mission shared"
    )

    other =
      TelemetryDecomFixtures.persist_spacecraft!(@organization_id, @mission_id,
        display_name: "Other"
      )

    foreign =
      TelemetryDecomFixtures.persist_source_endpoint!(
        @organization_id,
        @mission_id,
        other.spacecraft_id,
        display_name: "Foreign only"
      )

    page = read(c, %{"endpoint_page" => "6"})
    assert page["endpoints"]["total_count"] == 132
    assert length(page["endpoints"]["items"]) == 7
    refute Enum.any?(page["endpoints"]["items"], &(&1["id"] == foreign.source_endpoint_id))
    assert read(c, %{"endpoint_q" => "Foreign only"})["endpoints"]["total_count"] == 0
    assert read(c, %{"endpoint_q" => "Mission shared"})["endpoints"]["total_count"] == 1
    assert read(c, %{"endpoint_page" => "999"})["endpoints"]["page"] == 6
    export_fixture("endpoints-final", page)
  end

  defp query(params \\ %{}),
    do: %SurfaceQueryRequest{
      application_key: "telemetry_decom",
      application_version: 1,
      surface_id: "packet_bindings",
      surface_version: 1,
      query_id: "cadence.packet_bindings.manage",
      query_version: 1,
      params: params
    }

  defp read(c, params \\ %{}) do
    assert {:ok, %{"data" => page}} = PacketSurface.load(c.scope, c.host, query(params))
    page
  end

  defp export_fixture(name, page) do
    if directory = System.get_env("CADENCE_PACKET_FIXTURES") do
      File.mkdir_p!(directory)
      File.write!(Path.join(directory, name <> ".json"), Jason.encode!(%{page: page}))
    end
  end
end
