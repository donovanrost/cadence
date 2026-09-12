defmodule CadenceWeb.SpacecraftCommandingPageTest do
  use CadenceWeb.ConnCase, async: false
  import Phoenix.LiveViewTest
  alias Cadence.Applications.{HostContext, SurfaceQueryRequest}
  alias Cadence.Auth.Scope
  alias Cadence.Reads.ApplicationSurfaces.Spacecraft, as: LegacySpacecraft
  alias Cadence.SourceEndpoints
  alias Cadence.SourceEndpoints.SourceEndpoint
  alias CadenceWeb.TestFixtures

  setup do
    user = TestFixtures.persist_user!()
    org = TestFixtures.persist_org!()
    TestFixtures.grant_membership!(user, org)
    mission = TestFixtures.persist_mission!(org)
    spacecraft = TestFixtures.persist_spacecraft!(mission, display_name: "Nova-1")

    %{
      conn: TestFixtures.member_conn(user),
      user: user,
      mission: mission,
      spacecraft: spacecraft,
      path: "/missions/#{mission.mission_id}/spacecraft/#{spacecraft.spacecraft_id}/commanding"
    }
  end

  test "host admits the owner without a remote installation and retains canonical paging", c do
    for i <- 1..26 do
      endpoint =
        SourceEndpoint.new(%{
          mission_id: c.mission.mission_id,
          spacecraft_id: c.spacecraft.spacecraft_id,
          source_endpoint_id: "command-#{String.pad_leading(to_string(i), 2, "0")}",
          display_name: "Command endpoint #{i}"
        })

      assert {:ok, _} =
               SourceEndpoints.persist_source_endpoint(c.mission.organization_id, endpoint)
    end

    {:ok, view, _} = live(c.conn, c.path <> "?page=2&query=command")
    assert has_element?(view, "#application-shell")
    assert page(view)["id"] == "commanding.spacecraft"
    assert page(view)["status"] == "ready"
    assert page(view)["data"]["query"] == %{"page" => 2, "query" => "command"}
    assert page(view)["data"]["endpoints"]["total_count"] == 26
    assert [%{"id" => "command-26"}] = page(view)["data"]["endpoints"]["items"]

    render_hook(view, "host:context", %{
      "path" => c.path <> "?page=2&spacecraft_id=foreign&mission_id=foreign"
    })

    assert page(view)["context"]["spacecraftId"] == c.spacecraft.spacecraft_id
    assert page(view)["data"]["endpoints"]["total_count"] == 26
  end

  test "bad filters isolate the feature and navigation clears its prior evidence", c do
    {:ok, view, _} = live(c.conn, c.path <> "?page=bad")
    assert page(view)["status"] == "unavailable"
    assert has_element?(view, "#application-shell")
    render_hook(view, "host:context", %{"path" => c.path})
    assert page(view)["status"] == "ready"
    render_hook(view, "host:context", %{"path" => "/missions/#{c.mission.mission_id}/spacecraft"})
    assert page(view) == nil
  end

  test "unauthenticated, foreign mission and revoked-session refreshes are rejected", c do
    assert {:error, {:redirect, %{to: "/sign-in"}}} = live(build_conn(), c.path)
    other = TestFixtures.persist_mission!(TestFixtures.persist_org!())
    spacecraft = TestFixtures.persist_spacecraft!(other)

    assert {:error, {:redirect, _}} =
             live(
               c.conn,
               "/missions/#{other.mission_id}/spacecraft/#{spacecraft.spacecraft_id}/commanding"
             )

    {:ok, view, _} = live(c.conn, c.path)
    :ok = Cadence.Auth.revoke_user_session(get_session(c.conn, :user_session_token))
    render_hook(view, "host:context", %{"path" => c.path})
    assert_redirect(view, "/sign-in")
  end

  test "legacy commanding returns only the scoped owner destination and rejects missing spacecraft",
       c do
    scope = %Scope{
      actor_kind: :user,
      organization_id: c.mission.organization_id,
      user: %{user_id: c.user.user_id},
      organization_membership: %{lifecycle_state: :active}
    }

    request = %SurfaceQueryRequest{
      application_key: "spacecraft",
      application_version: 1,
      surface_id: "commanding",
      surface_version: 1,
      query_id: "cadence.spacecraft.commanding",
      query_version: 1,
      params: %{}
    }

    host = HostContext.spacecraft(c.mission.mission_id, c.spacecraft.spacecraft_id)
    assert {:ok, legacy} = LegacySpacecraft.load(scope, host, request)

    assert legacy["data"] == %{
             "mission_id" => c.mission.mission_id,
             "spacecraft_id" => c.spacecraft.spacecraft_id
           }

    assert {:error, _} = LegacySpacecraft.load(scope, %{host | spacecraft_id: "missing"}, request)

    assert {:error, _} =
             LegacySpacecraft.load(%{scope | organization_id: "foreign"}, host, request)
  end

  defp page(view),
    do:
      LiveVue.Test.get_vue(view, id: "application-shell").props["snapshot"][
        "spacecraft_module_page"
      ]
end
