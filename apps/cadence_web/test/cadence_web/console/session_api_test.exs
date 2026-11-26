defmodule CadenceWeb.Console.SessionAPITest do
  use CadenceWeb.ConnCase, async: true

  alias CadenceWeb.TestFixtures

  setup do
    org = TestFixtures.persist_org!(display_name: "Reflect Orbital")
    user = TestFixtures.persist_user!(display_name: "Mira K.")
    TestFixtures.grant_membership!(user, org, role: :member)
    mission = TestFixtures.persist_mission!(org, display_name: "Earendil")

    %{org: org, user: user, mission: mission}
  end

  describe "GET /api/v1/session" do
    test "without a session answers a JSON 401", %{conn: conn} do
      conn = get(conn, "/api/v1/session")

      assert %{"error" => %{"code" => "unauthenticated", "message" => _}} =
               json_response(conn, 401)
    end

    test "with a revoked session token answers a JSON 401" do
      conn =
        build_conn()
        |> init_test_session(%{user_session_token: "not-a-real-token"})
        |> get("/api/v1/session")

      assert %{"error" => %{"code" => "unauthenticated"}} = json_response(conn, 401)
    end

    test "returns the user, organizations with missions, capabilities and a CSRF token", c do
      data =
        c.user
        |> TestFixtures.member_conn()
        |> get("/api/v1/session")
        |> json_response(200)
        |> Map.fetch!("data")

      assert data["user"] == %{
               "id" => c.user.user_id,
               "email" => c.user.email,
               "display_name" => "Mira K."
             }

      assert data["current_organization_id"] == c.org.organization_id
      assert data["admin_mode"] == false
      assert data["platform_admin_eligible"] == false
      assert is_list(data["capabilities"])
      assert is_binary(data["csrf_token"]) and data["csrf_token"] != ""
      assert data["socket"] == %{"path" => "/socket"}

      assert [
               %{
                 "id" => org_id,
                 "name" => "Reflect Orbital",
                 "role" => "member",
                 "missions" => [mission]
               }
             ] = data["organizations"]

      assert org_id == c.org.organization_id

      assert mission == %{
               "id" => c.mission.mission_id,
               "slug" => c.mission.slug,
               "name" => "Earendil"
             }
    end

    test "lists every organization the user belongs to", c do
      other = TestFixtures.persist_org!(display_name: "Another Org")
      TestFixtures.grant_membership!(c.user, other, role: :organization_admin)

      orgs =
        c.user
        |> TestFixtures.member_conn()
        |> get("/api/v1/session")
        |> json_response(200)
        |> get_in(["data", "organizations"])

      assert Enum.map(orgs, &{&1["name"], &1["role"], &1["capabilities"]}) == [
               # command.* is "can operate one of its missions" (DECISIONS #42, #62): Another Org
               # has no missions to command, while a plain member of Reflect Orbital may request,
               # approve and abort there.
               {"Another Org", "organization_admin",
                ~w(org.invite org.manage_members organization_admin)},
               {"Reflect Orbital", "member",
                ~w(command.abort command.approve command.request dashboard.author)}
             ]
    end
  end

  describe "PUT /api/v1/session/organization" do
    test "rejects a write without a CSRF token", c do
      conn =
        c.user
        |> TestFixtures.member_conn()
        |> put_private(:plug_skip_csrf_protection, false)
        |> put("/api/v1/session/organization", %{
          "organization_id" => c.org.organization_id
        })

      assert %{"error" => %{"code" => "invalid_csrf"}} = json_response(conn, 403)
    end

    test "accepts the CSRF token from the session payload and switches organization", c do
      other = TestFixtures.persist_org!(display_name: "Another Org")
      TestFixtures.grant_membership!(c.user, other)

      bootstrap = c.user |> TestFixtures.member_conn() |> get("/api/v1/session")
      csrf_token = json_response(bootstrap, 200)["data"]["csrf_token"]

      conn =
        bootstrap
        |> recycle()
        |> put_private(:plug_skip_csrf_protection, false)
        |> put_req_header("x-csrf-token", csrf_token)
        |> put("/api/v1/session/organization", %{
          "organization_id" => other.organization_id
        })

      assert json_response(conn, 200)["data"]["current_organization_id"] ==
               other.organization_id

      assert get_session(conn, :current_organization_id) == other.organization_id
    end

    test "accepts an organization slug; a platform admin in admin mode can open any org", c do
      other = TestFixtures.persist_org!(display_name: "Another Org", slug: "another-org")

      member =
        c.user
        |> TestFixtures.member_conn()
        |> put("/api/v1/session/organization", %{"organization_slug" => "another-org"})

      assert json_response(member, 404)["error"]["code"] == "organization_not_found"

      admin = TestFixtures.persist_user!(capabilities: [:platform_admin])

      conn =
        admin
        |> TestFixtures.member_conn()
        |> init_test_session(%{admin_mode_expires_at: System.system_time(:second) + 600})
        |> put("/api/v1/session/organization", %{"organization_slug" => "another-org"})

      data = json_response(conn, 200)["data"]
      assert data["current_organization_id"] == other.organization_id

      assert [%{"slug" => "another-org", "role" => nil, "capabilities" => caps}] =
               data["organizations"]

      assert "platform_admin" in caps

      unknown =
        c.user
        |> TestFixtures.member_conn()
        |> put("/api/v1/session/organization", %{"organization_slug" => "nope"})

      assert json_response(unknown, 404)["error"]["code"] == "organization_not_found"
    end

    test "refuses an organization the user is not a member of", c do
      stranger = TestFixtures.persist_org!()

      conn =
        c.user
        |> TestFixtures.member_conn()
        |> put("/api/v1/session/organization", %{
          "organization_id" => stranger.organization_id
        })

      assert %{"error" => %{"code" => "organization_not_found"}} = json_response(conn, 404)
    end

    test "requires organization_id", c do
      conn =
        c.user
        |> TestFixtures.member_conn()
        |> put("/api/v1/session/organization", %{})

      assert %{"error" => %{"code" => "invalid_params", "details" => %{"organization_id" => _}}} =
               json_response(conn, 422)
    end
  end

  describe "GET /api/v1/missions/:mission_id" do
    test "returns the mission for an organization member", c do
      data =
        c.user
        |> TestFixtures.member_conn()
        |> get("/api/v1/missions/#{c.mission.mission_id}")
        |> json_response(200)
        |> Map.fetch!("data")

      assert data["id"] == c.mission.mission_id
      assert data["organization"]["id"] == c.org.organization_id
    end

    test "resolves a mission in a non-current organization the user belongs to", c do
      other = TestFixtures.persist_org!()
      TestFixtures.grant_membership!(c.user, other)
      other_mission = TestFixtures.persist_mission!(other)

      data =
        c.user
        |> TestFixtures.member_conn()
        |> get("/api/v1/missions/#{other_mission.mission_id}")
        |> json_response(200)
        |> Map.fetch!("data")

      assert data["organization"]["id"] == other.organization_id
    end

    test "reports another organization's mission as not found", c do
      stranger_mission = TestFixtures.persist_org!() |> TestFixtures.persist_mission!()

      conn =
        c.user
        |> TestFixtures.member_conn()
        |> get("/api/v1/missions/#{stranger_mission.mission_id}")

      assert %{"error" => %{"code" => "mission_not_found"}} = json_response(conn, 404)
    end

    test "reports an unknown mission as not found", c do
      conn =
        c.user
        |> TestFixtures.member_conn()
        |> get("/api/v1/missions/mission_does_not_exist")

      assert %{"error" => %{"code" => "mission_not_found"}} = json_response(conn, 404)
    end
  end

  test "unknown console API routes answer a JSON 404", c do
    conn = c.user |> TestFixtures.member_conn() |> get("/api/v1/nope")

    assert %{"error" => %{"code" => "not_found"}} = json_response(conn, 404)
  end

  describe "L6 admin mode" do
    setup do
      %{admin: TestFixtures.persist_user!(capabilities: [:platform_admin])}
    end

    defp enter(conn, password),
      do: post(conn, "/api/v1/session/admin-mode", %{"password" => password})

    test "the right password enters for an hour; the session shows when it ends; leave ends it",
         c do
      conn = c.admin |> TestFixtures.member_conn() |> enter(TestFixtures.default_password())
      assert %{"data" => %{"expires_at" => expires_at}} = json_response(conn, 200)
      {:ok, expires, 0} = DateTime.from_iso8601(expires_at)
      assert_in_delta DateTime.diff(expires, DateTime.utc_now()), 3600, 5

      session = conn |> recycle() |> get("/api/v1/session") |> json_response(200)
      assert session["data"]["admin_mode"] == true
      assert session["data"]["admin_mode_expires_at"] == expires_at

      left = conn |> recycle() |> delete("/api/v1/session/admin-mode")
      assert response(left, 204)

      after_leave = left |> recycle() |> get("/api/v1/session") |> json_response(200)
      assert after_leave["data"]["admin_mode"] == false
      assert after_leave["data"]["admin_mode_expires_at"] == nil
    end

    test "a wrong password is one stable code, and repeated ones are held back", c do
      conn = TestFixtures.member_conn(c.admin)

      for _ <- 1..6 do
        assert %{"error" => %{"code" => "password_incorrect"}} =
                 conn |> enter("wrong-password-1") |> json_response(422)
      end

      held = enter(conn, TestFixtures.default_password())

      assert %{"error" => %{"code" => "too_many_attempts", "details" => %{"retry_after" => _}}} =
               json_response(held, 429)

      assert [_seconds] = get_resp_header(held, "retry-after")
    end

    test "someone who isn't a platform admin is refused before any password check", c do
      assert %{"error" => %{"code" => "forbidden"}} =
               c.user
               |> TestFixtures.member_conn()
               |> enter(TestFixtures.default_password())
               |> json_response(403)

      assert c.user
             |> TestFixtures.member_conn()
             |> get("/api/v1/session")
             |> json_response(200)
             |> get_in(["data", "admin_mode_expires_at"]) == nil
    end
  end
end
