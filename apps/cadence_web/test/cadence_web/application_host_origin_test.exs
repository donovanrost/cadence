defmodule CadenceWeb.ApplicationHostOriginTest do
  @moduledoc """
  Sweep row 3 W1: the bridge stamps each action with the host it came through. The legacy host's
  catalog and the console's surface host each mint their own host session id; the session plug
  knows which one a call carries, so a limits save records `via` "legacy_host" or "console" (and
  `saved_by`), never a value the client chose. An id neither host issued is refused.
  """
  use CadenceWeb.ConnCase, async: false

  alias Cadence.Applications.{ApplicationInstallations, HostContext}
  alias Cadence.Auth.Scope
  alias Cadence.Limits
  alias CadenceWeb.TestFixtures

  setup do
    user = TestFixtures.persist_user!()
    org = TestFixtures.persist_org!()
    membership = TestFixtures.grant_membership!(user, org)
    mission = TestFixtures.persist_mission!(org)

    scope =
      Scope.new(%{
        user: user,
        organization_id: org.organization_id,
        organization: org,
        organization_membership: membership
      })

    {:ok, _installation} =
      ApplicationInstallations.install(scope, HostContext.mission(mission.mission_id), "limits")

    prefix = "/api/cadence/application-host/v1/missions/#{mission.mission_id}"

    legacy =
      get(TestFixtures.member_conn(user), prefix <> "/catalog", %{"application_key" => "limits"})

    # The console's surface host, in the same browser session (cookie) as the legacy catalog.
    console =
      legacy
      |> recycle()
      |> get("/api/console/v1/missions/#{mission.mission_id}/apps/limits/surfaces/manage/host")

    %{
      user: user,
      org: org,
      mission: mission,
      prefix: prefix,
      conn: console,
      legacy_session: json_response(legacy, 200)["session"],
      console_session: json_response(console, 200)["data"]["catalog"]["session"]
    }
  end

  test "each host's session id is its own, and a save records the host it came through", c do
    refute c.legacy_session["sessionId"] == c.console_session["sessionId"]

    for {session, set, via} <- [
          {c.legacy_session, "LEGACY", "legacy_host"},
          {c.console_session, "CONSOLE", "console"}
        ] do
      receipt = c |> send_action(session, input(set), "origin-#{via}") |> json_response(200)
      id = receipt["result"]["definitionId"]

      assert {:ok, saved} =
               Limits.fetch_limit_definition(c.org.organization_id, c.mission.mission_id, id, 1)

      assert saved.metadata["via"] == via
      assert saved.metadata["saved_by"] == %{"kind" => "user", "id" => c.user.user_id}
    end
  end

  test "a host session id neither host issued is refused before any save", c do
    forged = %{c.console_session | "sessionId" => "not-a-host-session"}

    assert %{"code" => "invalid_session"} =
             c |> send_action(forged, input("FORGED"), "origin-forged") |> json_response(401)
  end

  defp send_action(c, session, input, key) do
    c.conn
    |> recycle()
    |> put_req_header("content-type", "application/json")
    |> put_req_header("x-cadence-poc-session", session["sessionId"])
    |> put_req_header("x-csrf-token", session["csrfToken"])
    |> put_req_header("idempotency-key", key)
    |> post(
      c.prefix <> "/actions",
      Jason.encode!(%{
        "applicationKey" => "limits",
        "applicationVersion" => 1,
        "surfaceId" => "manage",
        "surfaceVersion" => 1,
        "actionId" => "save_limit_definition",
        "scope" => %{
          "organizationId" => c.org.organization_id,
          "missionId" => c.mission.mission_id,
          "spacecraftId" => nil
        },
        "input" => input
      })
    )
  end

  defp input(set),
    do: %{
      "point_id" => "HK.voltage",
      "limit_set_name" => set,
      "red_low" => "",
      "yellow_low" => "",
      "yellow_high" => "31.5",
      "red_high" => "34",
      "expected_definition_id" => nil,
      "expected_version" => 0,
      "expected_activation_event_id" => nil
    }
end
