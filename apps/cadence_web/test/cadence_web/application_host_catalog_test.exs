defmodule CadenceWeb.ApplicationHostCatalogTest do
  use CadenceWeb.ConnCase, async: false

  alias Cadence.Applications.{ApplicationInstallations, HostContext}
  alias Cadence.Applications.Registry, as: ApplicationRegistry
  alias Cadence.Auth.Scope
  alias Cadence.Missions.Mission
  alias CadenceWeb.{ApplicationHostCatalog, TestFixtures}

  @now "2026-09-03T12:00:00Z"
  @comms_surfaces ~w(overview validation transports transport routing routing_detail ground_stations ground_station)

  test "passes explicit validated time to release lookup boundaries", %{conn: _conn} do
    {scope, route_context} = installed_telemetry_context()

    assert {:ok, admission} =
             ApplicationHostCatalog.admit_application(
               scope,
               route_context,
               "telemetry_decom",
               "packet_bindings",
               now: @now
             )

    assert admission.release.release_id == "telemetry-decom-v1"

    assert {:error, {:integrity_failure, :invalid_snapshot_clock}} =
             ApplicationHostCatalog.admit_application(
               scope,
               route_context,
               "telemetry_decom",
               "packet_bindings"
             )

    assert {:error, {:integrity_failure, :invalid_snapshot_clock}} =
             ApplicationHostCatalog.admit_application(
               scope,
               route_context,
               "telemetry_decom",
               "packet_bindings",
               now: "not-a-canonical-timestamp"
             )
  end

  test "admits the registered telemetry packet_bindings surface after release lookup", %{
    conn: _conn
  } do
    {scope, route_context} = installed_telemetry_context()

    assert {:ok, definition} =
             Cadence.ExtensionCatalog.fetch_available_application("telemetry_decom")

    assert {:ok, surface} =
             ApplicationRegistry.fetch_surface(
               definition,
               :spacecraft,
               "packet_bindings"
             )

    assert surface.surface_id == "packet_bindings"

    assert {:ok, admission} =
             ApplicationHostCatalog.admit_application(
               scope,
               route_context,
               "telemetry_decom",
               "packet_bindings",
               now: @now
             )

    assert admission.release.release_id == "telemetry-decom-v1"
    assert admission.release.remote_name == "cadence_telemetry_decom"

    assert admission.release.manifest_path ==
             "/assets/application-host/telemetry-decom/mf-manifest.json"
  end

  test "generic catalog and fallback routing support a second registry application", %{
    conn: _conn
  } do
    {scope, route_context} = installed_telemetry_context()

    assert {:ok, catalog} =
             ApplicationHostCatalog.build(
               scope,
               route_context,
               session_id: "catalog-session",
               csrf_token: "catalog-csrf",
               bridge_base_url: ApplicationHostCatalog.bridge_base_path(route_context),
               manifest_url: fn path -> "https://example.test" <> path end,
               now: @now
             )

    assert catalog["generatedAt"] == @now
    assert [application] = catalog["applications"]
    assert application["applicationKey"] == "telemetry_decom"
    assert application["surface"]["surfaceId"] == "packet_bindings"
    assert application["release"]["releaseId"] == "telemetry-decom-v1"

    assert {:ok, fallback} =
             ApplicationHostCatalog.fallback_href(
               route_context,
               "telemetry_decom",
               "packet_bindings"
             )

    assert fallback ==
             "/missions/#{route_context.mission.mission_id}/spacecraft/#{route_context.spacecraft.spacecraft_id}/applications/telemetry_decom/packet_bindings"
  end

  test "rejects oversized persisted display data before returning a catalog" do
    {scope, route_context} = installed_telemetry_context()
    mission = %{route_context.mission | display_name: String.duplicate("x", 241)}
    route_context = %{route_context | mission: mission}

    assert {:error, :application_catalog_bounds_exceeded} =
             ApplicationHostCatalog.build(
               scope,
               route_context,
               session_id: "catalog-session",
               csrf_token: "catalog-csrf",
               bridge_base_url: ApplicationHostCatalog.bridge_base_path(route_context),
               manifest_url: fn path -> "https://example.test" <> path end,
               now: @now
             )
  end

  test "uses native semantic fallbacks when the installed Comms surfaces have no release" do
    {scope, %{mission: mission} = route_context} = installed_comms_context()

    for surface_id <- @comms_surfaces do
      assert {:error, :unknown_application_release} =
               ApplicationHostCatalog.admit_application(
                 scope,
                 route_context,
                 "comms",
                 surface_id,
                 now: @now
               )
    end

    assert {:ok, "/missions/#{mission.mission_id}/comms"} ==
             ApplicationHostCatalog.workspace_href(scope, route_context, "comms", now: @now)

    assert {:ok, workspace_href} =
             ApplicationHostCatalog.workspace_href(scope, route_context, "comms", now: @now)

    refute workspace_href =~ "/federated"

    assert {:ok, "/missions/#{mission.mission_id}/comms"} ==
             ApplicationHostCatalog.fallback_href(route_context, "comms", "overview")

    assert {:ok, "/missions/#{mission.mission_id}/comms/validation"} ==
             ApplicationHostCatalog.fallback_href(route_context, "comms", "validation")

    assert {:ok, "/missions/#{mission.mission_id}/comms/transports/transport-1"} ==
             ApplicationHostCatalog.fallback_href(
               route_context,
               "comms",
               "transport",
               "transport-1"
             )

    assert {:ok, "/missions/#{mission.mission_id}/comms/routing/routing-rule-1"} ==
             ApplicationHostCatalog.fallback_href(
               route_context,
               "comms",
               "routing_detail",
               "routing-rule-1"
             )

    assert {:ok, "/missions/#{mission.mission_id}/comms/ground-stations/ground-station-1"} ==
             ApplicationHostCatalog.fallback_href(
               route_context,
               "comms",
               "ground_station",
               "ground-station-1"
             )

    result = ApplicationHostCatalog.fallback_href(route_context, "bad/key", "overview")
    assert result == {:error, :invalid_application_request}
    refute inspect(result) =~ "/invalid"
  end

  test "rejects cross-organization, missing-user, and unauthorized catalog admissions before lookup" do
    route_context = %{
      host_context: HostContext.mission("mission-policy"),
      mission: %Mission{
        mission_id: "mission-policy",
        organization_id: "org-beta",
        slug: "policy",
        display_name: "Policy Mission"
      },
      spacecraft: nil
    }

    member_scope = %Scope{
      actor_kind: :user,
      organization_id: "org-alpha",
      user: %{user_id: "user-alpha"},
      organization_membership: %{lifecycle_state: :active}
    }

    assert {:error, :scope_mismatch} =
             ApplicationHostCatalog.admit_application(
               member_scope,
               route_context,
               "comms_overview"
             )

    missing_user_scope = %{member_scope | user: nil}

    assert {:error, :authenticated_user_required} =
             ApplicationHostCatalog.admit_application(
               missing_user_scope,
               %{
                 route_context
                 | mission: %{route_context.mission | organization_id: "org-alpha"}
               },
               "comms_overview"
             )

    unauthorized_scope = %{member_scope | organization_membership: nil}

    assert {:error, :forbidden} =
             ApplicationHostCatalog.admit_application(
               unauthorized_scope,
               %{
                 route_context
                 | mission: %{route_context.mission | organization_id: "org-alpha"}
               },
               "comms_overview"
             )
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

  defp installed_comms_context do
    user = TestFixtures.persist_user!()
    organization = TestFixtures.persist_org!()
    membership = TestFixtures.grant_membership!(user, organization)
    mission = TestFixtures.persist_mission!(organization, mission_id: "mission-comms-registry")

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
end
