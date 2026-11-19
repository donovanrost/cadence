defmodule CadenceWeb.ControlPlaneApiAuthTest do
  use CadenceWeb.ConnCase, async: true

  import CadenceWeb.ControlPlaneApiFixtures

  alias Cadence.Auth.ServiceIdentity

  test "browser session tokens are rejected as API bearer credentials", %{conn: conn} do
    user = CadenceWeb.TestFixtures.persist_user!()
    session_token = CadenceWeb.TestFixtures.member_session_token!(user)

    current_scope_conn = conn |> authorize(session_token) |> get("/api/current_scope")

    assert %{"errors" => [%{"reason" => "unauthenticated"}]} =
             json_response(current_scope_conn, 401)
  end

  test "mission-scoped token is constrained to its mission", %{conn: conn} do
    %{conn: conn, api_token: org_api_token, organization_id: organization_id} = bootstrap(conn)

    conn
    |> authorize(org_api_token)
    |> post("/api/organizations/#{organization_id}/missions", %{
      "mission" => %{
        "mission_id" => "mission-bravo",
        "slug" => "mission-bravo",
        "display_name" => "Mission Bravo"
      }
    })

    # REST can't issue service identities (#281), so the mission-scoped token is issued
    # through the domain directly, as `bootstrap/1` issues its own.
    assert {:ok, %{api_token: mission_api_token}} =
             Cadence.Auth.issue_service_identity(
               ServiceIdentity.new(%{
                 organization_id: organization_id,
                 mission_id: "mission-bravo",
                 display_name: "Mission Bravo Service",
                 capabilities: [:mission_admin]
               })
             )

    allowed_conn =
      conn
      |> authorize(mission_api_token)
      |> get("/api/organizations/#{organization_id}/missions/mission-bravo")

    assert %{"data" => %{"mission_id" => "mission-bravo"}} = json_response(allowed_conn, 200)

    forbidden_conn =
      conn
      |> authorize(mission_api_token)
      |> get("/api/organizations/#{organization_id}/missions/mission-alpha")

    assert %{"errors" => [%{"reason" => "forbidden"}]} = json_response(forbidden_conn, 403)
  end

  # #281: a REST bearer is always a service identity, and services never manage service
  # identities, so the REST endpoints are gone; people issue them in the console.
  test "the REST service identity endpoints no longer exist", %{conn: conn} do
    %{api_token: api_token, organization_id: organization_id} = bootstrap(conn)
    path = "/api/organizations/#{organization_id}/service_identities"

    body = %{
      "service_identity" => %{
        "display_name" => "Minted",
        "capabilities" => ["organization_admin"]
      }
    }

    assert conn |> authorize(api_token) |> get(path) |> response(404)
    assert conn |> authorize(api_token) |> post(path, body) |> response(404)
    assert [_bootstrap_only] = Cadence.Auth.list_service_identities(organization_id)
  end
end
