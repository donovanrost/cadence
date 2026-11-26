defmodule CadenceWeb.Console.ContactRuntimeAPITest do
  use CadenceWeb.ConnCase, async: false

  alias Cadence.Auth.ServiceIdentity
  alias Cadence.SourceEndpoints
  alias CadenceWeb.{ControlPlaneApiFixtures, TestFixtures}

  setup %{conn: conn} do
    fixture = ControlPlaneApiFixtures.bootstrap(conn)
    {:ok, organization} = Cadence.Organizations.fetch_organization(fixture.organization_id)
    admin = TestFixtures.persist_user!()
    TestFixtures.grant_membership!(admin, organization, role: :organization_admin)

    {:ok, %{api_token: service_token}} =
      Cadence.Auth.issue_service_identity(
        ServiceIdentity.new(%{
          service_identity_id: "runtime-simulator-service",
          organization_id: fixture.organization_id,
          mission_id: fixture.mission_id,
          display_name: "Runtime simulator",
          capabilities: [:mission_admin]
        }),
        ControlPlaneApiFixtures.organization_admin_scope(fixture.organization_id)
      )

    {:ok, source} =
      SourceEndpoints.create_source_endpoint(fixture.organization_id, fixture.mission_id, %{
        source_ref: "source-runtime-api"
      })

    contact =
      ControlPlaneApiFixtures.persist_active_uplink_contact_for_command_release(
        fixture.organization_id,
        fixture.mission_id,
        source.source_endpoint_id
      )

    [path] = contact.paths

    prefix =
      "/api/v1/missions/#{fixture.mission_id}/realized-contacts/#{contact.realized_contact_id}"

    Map.merge(fixture, %{
      session: TestFixtures.member_session_token!(admin),
      service_token: service_token,
      contact: contact,
      runtime_path: prefix <> "/runtime",
      path: path,
      path_runtime_path: prefix <> "/paths/#{path.path_id}/runtime"
    })
  end

  test "a mission administrator reads both runtime snapshots with a session", context do
    conn = Plug.Test.init_test_session(build_conn(), %{user_session_token: context.session})
    contact_id = context.contact.realized_contact_id
    path_id = context.path.path_id

    assert %{"data" => %{"realized_contact_id" => ^contact_id, "path_count" => 1}} =
             conn |> get(context.runtime_path) |> json_response(200)

    assert %{"data" => %{"realized_contact_id" => ^contact_id, "path_id" => ^path_id}} =
             conn |> get(context.path_runtime_path) |> json_response(200)
  end

  test "an authorized service can read only the path runtime", context do
    conn = ControlPlaneApiFixtures.authorize(build_conn(), context.service_token)
    path_id = context.path.path_id

    assert %{"data" => %{"path_id" => ^path_id, "direction" => "uplink"}} =
             conn |> get(context.path_runtime_path) |> json_response(200)

    assert %{"error" => %{"code" => "service_not_allowed"}} =
             conn |> get(context.runtime_path) |> json_response(403)

    assert %{"error" => %{"code" => "path_runtime_not_running"}} =
             conn
             |> get(String.replace(context.path_runtime_path, path_id, "missing-path"))
             |> json_response(404)
  end
end
