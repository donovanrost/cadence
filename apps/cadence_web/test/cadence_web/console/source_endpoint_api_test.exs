defmodule CadenceWeb.Console.SourceEndpointAPITest do
  use CadenceWeb.ConnCase, async: true

  alias CadenceWeb.{ControlPlaneApiFixtures, TestFixtures}

  setup %{conn: conn} do
    fixture = ControlPlaneApiFixtures.bootstrap(conn)
    {:ok, organization} = Cadence.Organizations.fetch_organization(fixture.organization_id)
    admin = TestFixtures.persist_user!()
    TestFixtures.grant_membership!(admin, organization, role: :organization_admin)

    spacecraft =
      ControlPlaneApiFixtures.persist_api_spacecraft!(
        fixture.organization_id,
        fixture.mission_id,
        %{
          spacecraft_id: "craft-source-endpoint",
          display_name: "Source endpoint fixture"
        }
      )

    Map.merge(fixture, %{
      spacecraft_id: spacecraft.spacecraft_id,
      session: TestFixtures.member_session_token!(admin),
      path: "/api/v1/missions/#{fixture.mission_id}"
    })
  end

  test "creates mission and spacecraft endpoints and lists bounded pages", context do
    mission_path = context.path <> "/source-endpoints"
    spacecraft_path = context.path <> "/spacecraft/#{context.spacecraft_id}/source-endpoints"
    conn = session_conn(context.session)

    assert %{"data" => %{"source_endpoint_id" => "endpoint-mission", "spacecraft_id" => nil}} =
             conn
             |> post(mission_path, endpoint("endpoint-mission"))
             |> json_response(201)

    assert %{"data" => %{"source_endpoint_id" => "endpoint-spacecraft", "spacecraft_id" => id}} =
             conn
             |> post(spacecraft_path, endpoint("endpoint-spacecraft"))
             |> json_response(201)

    assert id == context.spacecraft_id

    assert %{
             "data" => [%{"source_endpoint_id" => "endpoint-spacecraft"}],
             "meta" => %{"page" => 2, "page_size" => 1, "total_count" => 2}
           } = conn |> get(mission_path <> "?page=2&page_size=1") |> json_response(200)

    assert %{"data" => [%{"source_endpoint_id" => "endpoint-spacecraft"}]} =
             conn |> get(spacecraft_path) |> json_response(200)

    assert %{"data" => %{"display_name" => "endpoint-spacecraft"}} =
             conn |> get(mission_path <> "/endpoint-spacecraft") |> json_response(200)
  end

  test "requires CSRF, denies services and removes the bearer route", context do
    path = context.path <> "/source-endpoints"
    params = endpoint("endpoint-denied")

    assert %{"error" => %{"code" => "invalid_csrf"}} =
             context.session
             |> session_conn()
             |> put_private(:plug_skip_csrf_protection, false)
             |> post(path, params)
             |> json_response(403)

    assert %{"error" => %{"code" => "service_not_allowed"}} =
             build_conn()
             |> ControlPlaneApiFixtures.authorize(context.api_token)
             |> get(path)
             |> json_response(403)

    legacy_path =
      "/api/organizations/#{context.organization_id}/missions/#{context.mission_id}/source_endpoints"

    assert build_conn()
           |> ControlPlaneApiFixtures.authorize(context.api_token)
           |> get(legacy_path)
           |> Map.fetch!(:status) == 404
  end

  test "checks the spacecraft route before accepting a source endpoint", context do
    conn = session_conn(context.session)

    assert %{"error" => %{"code" => "spacecraft_not_found"}} =
             conn
             |> get(context.path <> "/spacecraft/unknown/source-endpoints")
             |> json_response(404)

    params =
      put_in(endpoint("endpoint-wrong-craft"), ["source_endpoint", "spacecraft_id"], "wrong")

    assert %{"error" => %{"code" => "scope_mismatch"}} =
             conn
             |> post(
               context.path <> "/spacecraft/#{context.spacecraft_id}/source-endpoints",
               params
             )
             |> json_response(403)
  end

  defp session_conn(session),
    do: Plug.Test.init_test_session(build_conn(), %{user_session_token: session})

  defp endpoint(id) do
    %{
      "source_endpoint" => %{
        "source_endpoint_id" => id,
        "source_ref" => id,
        "display_name" => id,
        "scid" => 23
      }
    }
  end
end
