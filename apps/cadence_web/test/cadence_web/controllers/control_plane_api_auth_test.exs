defmodule CadenceWeb.ControlPlaneApiAuthTest do
  use CadenceWeb.ConnCase, async: true

  import CadenceWeb.ControlPlaneApiFixtures

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

    mission_identity_conn =
      conn
      |> authorize(org_api_token)
      |> post("/api/organizations/#{organization_id}/service_identities", %{
        "service_identity" => %{
          "service_identity_id" => "svc-mission",
          "mission_id" => "mission-bravo",
          "display_name" => "Mission Bravo Service",
          "capabilities" => ["mission_admin"]
        }
      })

    assert %{
             "data" => %{
               "service_identity" => %{
                 "service_identity_id" => "svc-mission",
                 "mission_id" => "mission-bravo",
                 "capabilities" => ["mission_admin"]
               },
               "api_token" => mission_api_token
             }
           } = json_response(mission_identity_conn, 201)

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
end
