defmodule CadenceWeb.ApplicationHostCatalogTest do
  use CadenceWeb.ConnCase, async: false

  alias Cadence.Applications.{ApplicationInstallations, HostContext}
  alias Cadence.Auth.Scope
  alias Cadence.Missions.Mission
  alias CadenceWeb.{ApplicationHostCatalog, TestFixtures}

  @now "2026-09-03T12:00:00Z"
  test "serializes the tagged user scope document without mission ids" do
    scope = %Scope{organization_id: "org-1", actor_kind: :user, user: %{id: "user-1"}}

    assert ApplicationHostCatalog.scope_document(scope, %{
             host_context: HostContext.user("user-1"),
             mission: nil,
             spacecraft: nil
           }) == %{"scope" => "user", "userId" => "user-1"}
  end

  test "passes explicit validated time to release lookup boundaries", %{conn: _conn} do
    {scope, route_context} = installed_mission_representatives_context()

    assert {:ok, admission} =
             ApplicationHostCatalog.admit_application(
               scope,
               route_context,
               "ops_console",
               "workspace",
               now: @now
             )

    assert admission.release.release_id == "ops-console-v1"

    assert {:error, {:integrity_failure, :invalid_snapshot_clock}} =
             ApplicationHostCatalog.admit_application(
               scope,
               route_context,
               "ops_console",
               "workspace"
             )

    assert {:error, {:integrity_failure, :invalid_snapshot_clock}} =
             ApplicationHostCatalog.admit_application(
               scope,
               route_context,
               "ops_console",
               "workspace",
               now: "not-a-canonical-timestamp"
             )
  end

  test "an installed headless application has nothing to admit or catalog (#669)", %{
    conn: _conn
  } do
    {scope, route_context} = installed_telemetry_context()

    assert {:error, :unknown_surface} =
             ApplicationHostCatalog.admit_application(
               scope,
               route_context,
               "telemetry_decom",
               nil,
               now: @now
             )

    assert {:error, :unknown_surface} =
             ApplicationHostCatalog.admit_application(
               scope,
               route_context,
               "telemetry_decom",
               "packet_bindings",
               now: @now
             )

    # No spacecraft-scope application has a surface, so the spacecraft catalog is empty.
    assert {:error, :application_catalog_unavailable} =
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

  test "mission catalogs include platform modules without installations", %{conn: _conn} do
    {scope, route_context} = installed_mission_representatives_context()

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

    assert Enum.sort(Enum.map(catalog["applications"], & &1["applicationKey"])) ==
             ["ops_console"]
  end

  test "rejects oversized persisted display data before returning a catalog" do
    {scope, route_context} = installed_mission_representatives_context()
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
               "ops_console"
             )

    missing_user_scope = %{member_scope | user: nil}

    assert {:error, :authenticated_user_required} =
             ApplicationHostCatalog.admit_application(
               missing_user_scope,
               %{
                 route_context
                 | mission: %{route_context.mission | organization_id: "org-alpha"}
               },
               "ops_console"
             )

    unauthorized_scope = %{member_scope | organization_membership: nil}

    assert {:error, :forbidden} =
             ApplicationHostCatalog.admit_application(
               unauthorized_scope,
               %{
                 route_context
                 | mission: %{route_context.mission | organization_id: "org-alpha"}
               },
               "ops_console"
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

  defp installed_mission_representatives_context do
    user = TestFixtures.persist_user!()
    organization = TestFixtures.persist_org!()
    membership = TestFixtures.grant_membership!(user, organization)
    mission = TestFixtures.persist_mission!(organization)

    scope =
      Scope.new(%{
        user: user,
        organization_id: organization.organization_id,
        organization: organization,
        organization_membership: membership
      })

    host_context = HostContext.mission(mission.mission_id)

    assert {:error, :platform_application} =
             ApplicationInstallations.install(scope, host_context, "ops_console")

    {scope, %{host_context: host_context, mission: mission, spacecraft: nil}}
  end
end
