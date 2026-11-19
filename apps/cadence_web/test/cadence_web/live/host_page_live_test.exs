defmodule CadenceWeb.HostPageLiveTest do
  use CadenceWeb.ConnCase, async: false
  import Phoenix.LiveViewTest
  alias CadenceWeb.TestFixtures

  test "requesting context to another organization is rejected before rendering its surface" do
    user = TestFixtures.persist_user!()
    organization = TestFixtures.persist_org!()
    TestFixtures.grant_membership!(user, organization)
    mission = TestFixtures.persist_mission!(organization)
    other_organization = TestFixtures.persist_org!()
    other_mission = TestFixtures.persist_mission!(other_organization)
    conn = TestFixtures.member_conn(user)
    # §11c B: the mission home redirects to the console, so the socket starts on a kept page.
    {:ok, view, _html} = live(conn, "/missions/#{mission.mission_id}/ops")
    target = "/missions/#{other_mission.mission_id}/ops"

    assert {:error, {:redirect, %{to: "/console/" <> _}}} =
             render_hook(view, "host:context", %{"path" => target})

    assert {:error, {:redirect, %{to: "/console/" <> _}}} = live(conn, target)
  end

  test "requesting context within a mission updates the frontend surface and bounded query" do
    user = TestFixtures.persist_user!()
    organization = TestFixtures.persist_org!()
    TestFixtures.grant_membership!(user, organization)
    mission = TestFixtures.persist_mission!(organization)
    conn = TestFixtures.member_conn(user)
    {:ok, view, _html} = live(conn, "/missions/#{mission.mission_id}/ops/timeline")

    render_hook(view, "host:context", %{
      "path" => "/missions/#{mission.mission_id}/ops/explore?application_key=forged"
    })

    snapshot = LiveVue.Test.get_vue(view, id: "application-shell").props["snapshot"]
    assert snapshot["context"]["mission"]["mission_id"] == mission.mission_id
    refute Map.has_key?(snapshot, "application_key")
    refute Map.has_key?(snapshot, "surface_id")
  end

  test "ordinary feature navigation retains the LiveView and refreshes shell context" do
    {conn, organization, mission} = navigation_fixture()
    second = TestFixtures.persist_mission!(organization)
    spacecraft = TestFixtures.persist_spacecraft!(mission)
    # §11c A: "/" left the host (it redirects to the console), so navigation starts in a mission.
    {:ok, view, _html} = live(conn, "/missions/#{second.mission_id}/ops/explore")
    pid = view.pid

    for {path, _variant, mission_id} <- [
          # §11c B: the mission's setup pages redirect to the console; these stay in the host.
          {"/missions/#{mission.mission_id}/ops", "ops", mission.mission_id},
          {"/missions/#{mission.mission_id}/ops/timeline", "ops", mission.mission_id},
          {"/missions/#{mission.mission_id}/spacecraft/#{spacecraft.spacecraft_id}",
           "mission_sidebar", mission.mission_id},
          {"/missions/#{mission.mission_id}/ops/explore", "ops", mission.mission_id},
          {"/missions/#{mission.mission_id}/ops/activations", "ops", mission.mission_id},
          {"/missions/#{second.mission_id}/ops/explore", "ops", second.mission_id}
        ] do
      render_hook(view, "host:context", %{"path" => path})
      shell = LiveVue.Test.get_vue(view, id: "application-shell")
      refute Map.has_key?(shell.props, "variant")
      assert get_in(shell.props, ["snapshot", "context", "mission", "mission_id"]) == mission_id
      assert view.pid == pid
    end

    # A previously scheduled Ops tick must also be harmless outside Ops.
    send(pid, :ops_context_refresh)
    assert has_element?(view, "#application-shell")
  end

  test "context requests cannot bypass organization or platform administrator policies" do
    {conn, _organization, mission} = navigation_fixture()

    # L7 moved /admin and L13 /provider-accounts to the console; data-operations/manage keeps the
    # organization-admin policy. §11c A: "/" redirects to the console, so start on the mission.
    for target <- ["/missions/#{mission.mission_id}/ops/data-operations/manage"] do
      {:ok, view, _html} = live(conn, "/missions/#{mission.mission_id}/ops")

      assert {:error, {:redirect, %{to: "/"}}} =
               render_hook(view, "host:context", %{"path" => target})
    end
  end

  test "a spacecraft from another mission cannot be selected through a context request" do
    {conn, organization, mission} = navigation_fixture()
    other = TestFixtures.persist_mission!(organization)
    spacecraft = TestFixtures.persist_spacecraft!(other)
    {:ok, view, _html} = live(conn, "/missions/#{mission.mission_id}/ops")
    fallback = "/missions/#{mission.mission_id}/spacecraft"

    assert {:error, {:redirect, %{to: ^fallback}}} =
             render_hook(view, "host:context", %{
               "path" => "/missions/#{mission.mission_id}/spacecraft/#{spacecraft.spacecraft_id}"
             })
  end

  test "revoked browser sessions cannot keep navigating on an existing socket" do
    {conn, _organization, mission} = navigation_fixture()
    path = "/missions/#{mission.mission_id}/ops"
    {:ok, view, _html} = live(conn, path)
    :ok = Cadence.Auth.revoke_user_session(Plug.Conn.get_session(conn, :user_session_token))

    assert {:error, {:redirect, %{to: "/sign-in"}}} =
             render_hook(view, "host:context", %{"path" => path})
  end

  test "query parameters cannot replace authorized path resources" do
    {conn, organization, mission} = navigation_fixture()
    other = TestFixtures.persist_mission!(organization)
    {:ok, view, _html} = live(conn, "/missions/#{other.mission_id}/ops")
    path = "/missions/#{mission.mission_id}/ops?mission_id=#{other.mission_id}&host_policy=admin"
    render_hook(view, "host:context", %{"path" => path})
    snapshot = LiveVue.Test.get_vue(view, id: "application-shell").props["snapshot"]
    assert snapshot["context"]["mission"]["mission_id"] == mission.mission_id
    refute snapshot["context"]["admin_mode"]
  end

  test "invalid context targets leave the authorized snapshot unchanged" do
    {conn, _organization, mission} = navigation_fixture()
    {:ok, view, _html} = live(conn, "/missions/#{mission.mission_id}/ops")
    initial = LiveVue.Test.get_vue(view, id: "application-shell").props["snapshot"]

    for path <- [
          nil,
          %{},
          "https://other.test/missions",
          "//other.test/missions",
          "/session",
          "/unknown",
          "/missions#fragment",
          String.duplicate("/", 8193)
        ] do
      render_hook(view, "host:context", %{"path" => path})
      assert LiveVue.Test.get_vue(view, id: "application-shell").props["snapshot"] == initial
    end
  end

  defp navigation_fixture do
    user = TestFixtures.persist_user!()
    organization = TestFixtures.persist_org!()
    TestFixtures.grant_membership!(user, organization)
    mission = TestFixtures.persist_mission!(organization)
    {TestFixtures.member_conn(user), organization, mission}
  end
end
