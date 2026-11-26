defmodule CadenceWeb.Console.ServiceBearerAPITest do
  @moduledoc """
  #753 (#747, one public API): a service identity reaches the console API with its bearer token.
  Services are denied by default (`CadenceWeb.Console.ServiceAccess`), a bearer never needs CSRF,
  and an invalid bearer never falls back to the session cookie. Persons keep the session.
  """
  use CadenceWeb.ConnCase, async: true

  alias Cadence.Auth.ServiceIdentity
  alias CadenceWeb.Console.ServiceAccess
  alias CadenceWeb.{ControlPlaneApiFixtures, TestFixtures}

  setup %{conn: conn} do
    base = ControlPlaneApiFixtures.bootstrap(conn)
    _other = ControlPlaneApiFixtures.persist_mission!(base.organization_id, "mission-beta")

    {:ok, %{api_token: token}} =
      Cadence.Auth.issue_service_identity(
        ServiceIdentity.new(%{
          service_identity_id: "svc-mission-alpha",
          organization_id: base.organization_id,
          mission_id: base.mission_id,
          display_name: "Mission Alpha automation",
          capabilities: [:mission_admin]
        }),
        %Cadence.Auth.Scope{
          actor_kind: :user,
          organization_id: base.organization_id,
          user: %Cadence.Accounts.User{user_id: "user-service-issuer"}
        }
      )

    Map.put(base, :token, token)
  end

  # Phoenix.ConnTest skips CSRF by default; these requests check it for real.
  # The one API's prefix: /api/console/v1 until platform's router move (#757), /api/v1 after.
  @prefix if Enum.any?(CadenceWeb.Router.__routes__(), &String.starts_with?(&1.path, "/api/v1/")),
            do: "/api/v1",
            else: "/api/console/v1"

  defp csrf_checked, do: build_conn() |> put_private(:plug_skip_csrf_protection, false)

  defp bearer(token), do: csrf_checked() |> put_req_header("authorization", "Bearer " <> token)

  test "the opt-in list is exactly this (additions show up in review)" do
    assert ServiceAccess.allowed() == %{CadenceWeb.Console.MissionController => [:show]}
  end

  test "a mission-pinned service reads an opted-in action with its bearer token", c do
    body =
      c.token |> bearer() |> get("#{@prefix}/missions/#{c.mission_id}") |> json_response(200)

    assert body["data"]["id"] == c.mission_id
  end

  test "a service can't reach another mission, even in its own organization", c do
    assert %{"error" => %{"code" => "mission_not_found"}} =
             c.token
             |> bearer()
             |> get("#{@prefix}/missions/mission-beta")
             |> json_response(404)
  end

  test "an invalid bearer is 401 and never falls back to a valid session cookie", c do
    user = TestFixtures.persist_user!()
    {:ok, organization} = Cadence.Organizations.fetch_organization(c.organization_id)
    _membership = TestFixtures.grant_membership!(user, organization, role: :organization_admin)
    session = TestFixtures.member_session_token!(user)

    with_cookie = fn conn -> Plug.Test.init_test_session(conn, %{user_session_token: session}) end
    path = "#{@prefix}/missions/#{c.mission_id}"

    assert build_conn() |> with_cookie.() |> get(path) |> json_response(200)

    for header <- ["Bearer not-a-token", "Bearer ", "Basic abc", "bearer #{c.token}"] do
      conn =
        build_conn()
        |> with_cookie.()
        |> put_req_header("authorization", header)
        |> get(path)

      assert %{"error" => %{"code" => "unauthenticated"}} = json_response(conn, 401), header
    end
  end

  test "a person's bearer-less request still needs CSRF on unsafe methods" do
    assert %{"error" => %{"code" => "invalid_csrf"}} =
             csrf_checked()
             |> Plug.Test.init_test_session(%{user_session_token: "anything"})
             |> post("#{@prefix}/session/admin-mode")
             |> json_response(403)
  end

  test "every console API route: 401 without credentials, 403 for a service unless opted in", c do
    routes =
      for route <- CadenceWeb.Router.__routes__(),
          String.starts_with?(route.path, @prefix <> "/"),
          not String.starts_with?(route.path, @prefix <> "/auth/"),
          do: route

    assert length(routes) > 100

    for route <- routes do
      path = concrete(route.path, c.mission_id, c.organization_id)
      method = route.verb |> Atom.to_string() |> String.upcase()

      anonymous = dispatch(build_conn(), @endpoint, method, path)

      assert anonymous.status in [401, 403],
             "#{method} #{route.path} without credentials answered #{anonymous.status}"

      unless route.plug_opts in Map.get(ServiceAccess.allowed(), route.plug, []) do
        service = dispatch(bearer(c.token), @endpoint, method, path)

        assert %{"error" => %{"code" => "service_not_allowed", "details" => %{"action" => _}}} =
                 json_response(service, 403),
               "#{method} #{route.path} let a service through"
      end
    end
  end

  # A real mission and organization in the path, a placeholder for every other segment.
  defp concrete(path, mission_id, organization_id) do
    path
    |> String.split("/")
    |> Enum.map_join("/", fn
      ":mission_id" -> mission_id
      ":organization_id" -> organization_id
      ":" <> _param -> "x"
      "*" <> _glob -> "x"
      segment -> segment
    end)
  end
end
