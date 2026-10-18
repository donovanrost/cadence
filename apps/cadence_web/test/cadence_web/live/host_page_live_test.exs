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
    {:ok, view, _html} = live(conn, "/missions/#{mission.mission_id}")
    target = "/missions/#{other_mission.mission_id}"

    assert {:error, {:redirect, %{to: "/missions"}}} =
             render_hook(view, "host:context", %{"path" => target})

    assert {:error, {:redirect, %{to: "/missions"}}} = live(conn, target)
  end

  test "requesting context within a mission updates the frontend surface and bounded query" do
    user = TestFixtures.persist_user!()
    organization = TestFixtures.persist_org!()
    TestFixtures.grant_membership!(user, organization)
    mission = TestFixtures.persist_mission!(organization)
    conn = TestFixtures.member_conn(user)
    {:ok, view, _html} = live(conn, "/missions/#{mission.mission_id}/comms/transports")

    render_hook(view, "host:context", %{
      "path" =>
        "/missions/#{mission.mission_id}/comms/transports/transport-1?application_key=forged"
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
    {:ok, view, _html} = live(conn, "/")
    pid = view.pid

    for {path, _variant, mission_id} <- [
          {"/missions", "sidebar", nil},
          {"/missions/#{mission.mission_id}", "mission_sidebar", mission.mission_id},
          {"/missions/#{mission.mission_id}/comms", "mission_sidebar", mission.mission_id},
          {"/missions/#{mission.mission_id}/applications", "mission_sidebar", mission.mission_id},
          {"/missions/#{mission.mission_id}/spacecraft", "mission_sidebar", mission.mission_id},
          {"/missions/#{mission.mission_id}/spacecraft/#{spacecraft.spacecraft_id}/applications",
           "mission_sidebar", mission.mission_id},
          {"/missions/#{mission.mission_id}/ops/dashboards", "ops", mission.mission_id},
          {"/missions/#{mission.mission_id}/ops/activations", "ops", mission.mission_id},
          {"/missions", "sidebar", nil},
          {"/missions/#{second.mission_id}/ops/dashboards", "ops", second.mission_id},
          {"/", "sidebar", nil}
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

  test "management actions follow the current page and cannot run after leaving it" do
    {conn, organization, mission} = navigation_fixture()
    second = TestFixtures.persist_mission!(organization)
    {:ok, view, _html} = live(conn, "/missions/#{mission.mission_id}/applications")
    pid = view.pid
    render_hook(view, "host:context", %{"path" => "/missions/#{mission.mission_id}/spacecraft"})
    refute has_element?(view, "#mission-applications-page-component")

    render_hook(view, "host:manage", %{
      "event" => "install",
      "key" => "limits",
      "path" => "/missions/#{mission.mission_id}/spacecraft"
    })

    refute installation(mission, "limits")

    render_hook(view, "host:context", %{"path" => "/missions/#{second.mission_id}/applications"})
    assert LiveVue.Test.get_vue(view, id: "application-shell").props["snapshot"]["presentation"]

    render_hook(view, "host:manage", %{
      "event" => "install",
      "key" => "limits",
      "path" => "/missions/#{second.mission_id}/applications"
    })

    assert installation(second, "limits")
    refute installation(mission, "limits")
    assert view.pid == pid
  end

  test "management actions recheck a revoked browser session" do
    {conn, _organization, mission} = navigation_fixture()
    {:ok, view, _html} = live(conn, "/missions/#{mission.mission_id}/applications")
    :ok = Cadence.Auth.revoke_user_session(Plug.Conn.get_session(conn, :user_session_token))

    render_hook(view, "host:manage", %{
      "event" => "install",
      "key" => "limits",
      "path" => "/missions/#{mission.mission_id}/applications"
    })

    assert_redirect(view, "/sign-in")
    refute installation(mission, "limits")
  end

  test "context requests cannot bypass organization or platform administrator policies" do
    {conn, _organization, _mission} = navigation_fixture()

    for target <- [
          "/provider-accounts",
          "/admin"
        ] do
      {:ok, view, _html} = live(conn, "/")

      assert {:error, {:redirect, %{to: "/"}}} =
               render_hook(view, "host:context", %{"path" => target})
    end
  end

  test "a spacecraft from another mission cannot be selected through a context request" do
    {conn, organization, mission} = navigation_fixture()
    other = TestFixtures.persist_mission!(organization)
    spacecraft = TestFixtures.persist_spacecraft!(other)
    {:ok, view, _html} = live(conn, "/missions/#{mission.mission_id}")
    fallback = "/missions/#{mission.mission_id}/spacecraft"

    assert {:error, {:redirect, %{to: ^fallback}}} =
             render_hook(view, "host:context", %{
               "path" => "/missions/#{mission.mission_id}/spacecraft/#{spacecraft.spacecraft_id}"
             })
  end

  test "revoked browser sessions cannot keep navigating on an existing socket" do
    {conn, _organization, _mission} = navigation_fixture()
    {:ok, view, _html} = live(conn, "/")
    :ok = Cadence.Auth.revoke_user_session(Plug.Conn.get_session(conn, :user_session_token))

    assert {:error, {:redirect, %{to: "/sign-in"}}} =
             render_hook(view, "host:context", %{"path" => "/missions"})
  end

  test "query parameters cannot replace authorized path resources" do
    {conn, organization, mission} = navigation_fixture()
    other = TestFixtures.persist_mission!(organization)
    {:ok, view, _html} = live(conn, "/missions")
    path = "/missions/#{mission.mission_id}?mission_id=#{other.mission_id}&host_policy=admin"
    render_hook(view, "host:context", %{"path" => path})
    snapshot = LiveVue.Test.get_vue(view, id: "application-shell").props["snapshot"]
    assert snapshot["context"]["mission"]["mission_id"] == mission.mission_id
    refute snapshot["context"]["admin_mode"]
  end

  test "invalid context targets leave the authorized snapshot unchanged" do
    {conn, _organization, _mission} = navigation_fixture()
    {:ok, view, _html} = live(conn, "/missions")
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

  test "a delayed management action is rejected after switching missions" do
    {conn, organization, mission} = navigation_fixture()
    second = TestFixtures.persist_mission!(organization)
    {:ok, view, _html} = live(conn, "/missions/#{mission.mission_id}/applications")
    render_hook(view, "host:context", %{"path" => "/missions/#{second.mission_id}/applications"})

    render_hook(view, "host:manage", %{
      "event" => "install",
      "key" => "limits",
      "path" => "/missions/#{mission.mission_id}/applications"
    })

    refute installation(mission, "limits")
    refute installation(second, "limits")
  end

  defp navigation_fixture do
    user = TestFixtures.persist_user!()
    organization = TestFixtures.persist_org!()
    TestFixtures.grant_membership!(user, organization)
    mission = TestFixtures.persist_mission!(organization)
    {TestFixtures.member_conn(user), organization, mission}
  end

  defp installation(mission, key) do
    Cadence.Repo.get_by(Cadence.Applications.ApplicationInstallations.InstallationRow,
      mission_id: mission.mission_id,
      application_key: key
    )
  end
end
