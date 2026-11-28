defmodule Cadence.Reads.ApplicationSurfaces.TelemetryDecomConfigurationTest do
  use Cadence.DataCase, async: false

  alias Cadence.Applications.{
    ApplicationInstallations,
    HostContext,
    Registry,
    TelemetryDecom,
    TelemetryDecomFixtures
  }

  alias Cadence.Auth.Scope
  alias Cadence.Missions
  alias Cadence.Reads.ApplicationSurfaces
  alias Cadence.Reads.ApplicationSurfaces.TelemetryDecom.Configuration

  @organization_id "org-decom-configuration"
  @mission_id "mission-decom-configuration"

  setup do
    {spacecraft, revision, endpoint} =
      TelemetryDecomFixtures.setup_imported_mission!(@organization_id, @mission_id,
        approve: false
      )

    scope = TelemetryDecomFixtures.user_scope(@organization_id, "decom-configuration")
    host = HostContext.spacecraft(@mission_id, spacecraft.spacecraft_id)
    {:ok, _} = ApplicationInstallations.install(scope, host, "telemetry_decom")
    {:ok, mission} = Missions.fetch_mission(@organization_id, @mission_id)

    %{
      scope: scope,
      host: host,
      spacecraft: spacecraft,
      revision: revision,
      endpoint: endpoint,
      mission: mission
    }
  end

  test "the manage surface resolves to the scoped domain read", c do
    {:ok, canonical} =
      Registry.fetch_surface(
        TelemetryDecom.definition(),
        :spacecraft,
        "manage"
      )

    assert {:ok, current} =
             ApplicationSurfaces.load(
               c.scope,
               c.host,
               "telemetry_decom",
               1,
               canonical
             )

    assert current["data"]["context"]["spacecraft_id"] == c.spacecraft.spacecraft_id

    unauthorized =
      Scope.new(%{
        user: %{c.scope.user | capabilities: []},
        organization_id: @organization_id
      })

    assert {:error, _reason} =
             ApplicationSurfaces.load(
               unauthorized,
               c.host,
               "telemetry_decom",
               1,
               canonical
             )
  end

  test "rejects cross-scope reads and unavailable installation", c do
    assert {:error, :invalid_application_scope} =
             Configuration.load(%{c.scope | organization_id: "other"}, c.host, c.mission)

    assert {:error, :invalid_application_scope} =
             Configuration.load(
               c.scope,
               HostContext.spacecraft("other", c.spacecraft.spacecraft_id),
               c.mission
             )

    other =
      TelemetryDecomFixtures.persist_spacecraft!(@organization_id, @mission_id,
        display_name: "Uninstalled"
      )

    assert {:error, :application_not_installed} =
             Configuration.load(
               c.scope,
               HostContext.spacecraft(@mission_id, other.spacecraft_id),
               c.mission
             )
  end
end
