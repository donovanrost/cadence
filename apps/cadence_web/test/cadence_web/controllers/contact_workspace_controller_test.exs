defmodule CadenceWeb.ContactWorkspaceControllerTest do
  use CadenceWeb.ConnCase, async: false

  alias Cadence.ProviderChangeFixtures
  alias CadenceWeb.TestFixtures

  setup do
    fixture = ProviderChangeFixtures.setup_contact()
    user = TestFixtures.persist_user!()
    TestFixtures.grant_membership!(user, fixture.organization, role: :organization_admin)
    conn = TestFixtures.member_conn(user)

    Map.merge(fixture, %{
      conn: conn,
      user: user,
      api: "/api/cadence/contact-workspace/v1/missions/#{fixture.mission_id}",
      page: "/missions/#{fixture.mission_id}/ops/contact-workspace"
    })
  end

  test "both deep links boot a client workspace without a LiveView", c do
    for path <- [c.page, c.page <> "/records/#{c.reservation.scheduled_contact_id}"] do
      html = c.conn |> get(path) |> html_response(200) |> LazyHTML.from_document()

      [encoded] =
        html |> LazyHTML.query("#contact-workspace-root") |> LazyHTML.attribute("data-bootstrap")

      bootstrap = Jason.decode!(encoded)
      assert bootstrap["mission_id"] == c.mission_id
      assert bootstrap["actor_id"] == c.user.user_id
      assert bootstrap["context"]["mission"]["mission_id"] == c.mission_id
      assert Enum.empty?(LazyHTML.query(html, "[data-phx-main]"))
    end
  end

  test "the browser route requires authentication", c do
    assert build_conn() |> get(c.page) |> redirected_to() == "/sign-in"
  end

  test "reads are independently scoped and do not require a page or catalog visit", c do
    response = c |> api_conn() |> get(c.api <> "/schedule")
    body = json_response(response, 200)
    assert get_resp_header(response, "cache-control") == ["no-store"]
    assert body["actor_id"] == c.user.user_id
    assert body["data"]["schedule"]["context"]["mission_id"] == c.mission_id
    assert body["data"]["schedule"]["workflow"]["actor_id"] == c.user.user_id

    id = c.reservation.scheduled_contact_id
    record = c |> api_conn() |> get(c.api <> "/records/#{id}") |> json_response(200)
    assert record["data"]["record"]["subject"]["id"] == id
  end

  test "path identity wins over query identity and unrelated filters are rejected", c do
    id = c.reservation.scheduled_contact_id

    record =
      c |> api_conn() |> get(c.api <> "/records/#{id}?contact_id=foreign") |> json_response(200)

    assert record["data"]["record"]["subject"]["id"] == id

    response = c |> api_conn() |> get(c.api <> "/schedule?mission_id=foreign")
    assert json_response(response, 422)["code"] == "invalid_request"
  end

  test "foreign mission and contact requests cannot read the current mission's data", c do
    assert c |> api_conn() |> get(c.api <> "/records/foreign") |> json_response(404)
    foreign = "/api/cadence/contact-workspace/v1/missions/foreign/schedule"
    assert c |> api_conn() |> get(foreign) |> json_response(404)

    other = ProviderChangeFixtures.setup_contact()
    foreign_mission = "/api/cadence/contact-workspace/v1/missions/#{other.mission_id}"
    assert c |> api_conn() |> get(foreign_mission <> "/schedule") |> json_response(404)

    assert c
           |> api_conn()
           |> post(foreign_mission <> "/actions/reserve", %{})
           |> json_response(404)

    assert c
           |> api_conn()
           |> get(c.api <> "/records/#{other.reservation.scheduled_contact_id}")
           |> json_response(404)
  end

  test "a session identity change is rejected before reads or effects", c do
    conn = c |> api_conn() |> put_req_header("x-cadence-workspace-user", "previous-user")

    assert conn |> get(c.api <> "/schedule") |> json_response(409) == %{
             "code" => "session_changed"
           }

    assert conn |> post(c.api <> "/actions/reserve", %{}) |> json_response(409) == %{
             "code" => "session_changed"
           }

    # Session changes are detected even when the old mission is no longer accessible.
    conn = c |> api_conn() |> put_req_header("x-cadence-workspace-organization", "previous-org")

    assert conn
           |> get("/api/cadence/contact-workspace/v1/missions/old-mission/schedule")
           |> json_response(409)
  end

  test "unsupported actions and malformed requests cannot enter the domain workflow", c do
    for action <- ["delete", "reserve", "search"] do
      assert c |> api_conn() |> post(c.api <> "/actions/#{action}", %{}) |> json_response(422)
    end
  end

  test "a recorded operation lookup remains scoped without an active page", c do
    response =
      c
      |> api_conn()
      |> post(c.api <> "/actions/reserve", %{
        "contract_version" => 2,
        "operation_id" => Ecto.UUID.generate(),
        "observe" => true
      })
      |> json_response(200)

    assert response["data"] == %{"operation" => nil}
  end

  test "the API retains browser CSRF protection", c do
    response =
      c
      |> api_conn()
      |> put_private(:plug_skip_csrf_protection, false)
      |> post(c.api <> "/actions/reserve", %{})

    assert json_response(response, 403) == %{"code" => "invalid_csrf"}
  end

  defp api_conn(c) do
    c.conn
    |> put_req_header("accept", "application/json")
    |> put_req_header("x-cadence-workspace-user", c.user.user_id)
    |> put_req_header("x-cadence-workspace-organization", c.organization_id)
  end
end
