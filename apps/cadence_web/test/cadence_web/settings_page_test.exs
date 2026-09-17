defmodule CadenceWeb.SettingsPageTest do
  use CadenceWeb.ConnCase, async: false
  import Phoenix.LiveViewTest
  alias Cadence.Auth.Scope
  alias Cadence.Governance.ActivationPolicy
  alias Cadence.Management.Commanding.WorkspaceSettings
  alias Cadence.Management.Settings
  alias CadenceWeb.TestFixtures

  setup do
    user = TestFixtures.persist_user!()
    org = TestFixtures.persist_org!()
    membership = TestFixtures.grant_membership!(user, org)
    mission = TestFixtures.persist_mission!(org)

    scope =
      Scope.new(%{
        actor_kind: :user,
        user: user,
        organization_id: org.organization_id,
        organization_membership: membership
      })

    %{
      conn: TestFixtures.member_conn(user),
      scope: scope,
      mission: mission,
      org: org,
      path: "/missions/#{mission.mission_id}/settings"
    }
  end

  test "ordinary members discover organization and mission settings without an installation", c do
    for path <- ["/settings", c.path] do
      {:ok, view, _} = live(c.conn, path)
      assert %{"status" => "ready", "data" => data} = page(view)
      assert data["can_edit"]

      assert Enum.map(data["sections"], & &1["id"]) == [
               "cadence.governance",
               "commanding.defaults"
             ]

      assert Enum.all?(data["sections"], &(not Map.has_key?(&1, "provider")))
      assert has_element?(view, "#application-shell")
    end
  end

  test "writes persist at their exact scope, reject stale tokens, and record the actor", c do
    {:ok, view, _} = live(c.conn, c.path)
    before = page(view)
    write(view, c.path, before, %{"value" => %{"approval_requirement" => "direct"}})
    assert page(view)["data"]["settings"]["source"] == "overridden"
    assert page(view)["data"]["settings"]["version"] == 1
    assert [%{"actor" => actor, "version" => 1}] = page(view)["data"]["history"]
    assert actor == c.scope.user.display_name
    write(view, c.path, before, %{"value" => nil})
    assert page(view)["data"]["settings"]["version"] == 1
    assert ActivationPolicy.load(c.org.organization_id, nil).version == 0
  end

  test "page tokens cannot cross sections or survive navigation", c do
    {:ok, view, _} = live(c.conn, c.path)
    original = page(view)
    target = c.path <> "/commanding.defaults"
    render_hook(view, "host:context", %{"path" => target})
    write(view, target, original, %{"value" => %{"shelf" => "minimized"}})
    assert WorkspaceSettings.load(c.org.organization_id, c.mission.mission_id).version == 0
    render_hook(view, "host:context", %{"path" => c.path})
    refute page(view)["token"] == original["token"]
    write(view, c.path, original, %{"value" => nil})
    assert ActivationPolicy.load(c.org.organization_id, c.mission.mission_id).version == 0
  end

  test "organization invalidation refreshes inherited requirements and enforcement rejects mission writes",
       c do
    {:ok, view, _} = live(c.conn, c.path)
    original = page(view)
    current = ActivationPolicy.load(c.org.organization_id, nil)

    assert {:ok, _} =
             ActivationPolicy.save(c.scope, nil, current.token, %{
               "value" => %{"approval_requirement" => "independent"},
               "allow_override" => false
             })

    assert has_element?(view, "#application-shell")
    assert page(view)["data"]["settings"]["source"] == "enforced"
    assert page(view)["token"] == original["token"]
    write(view, c.path, page(view), %{"value" => %{"approval_requirement" => "direct"}})
    assert ActivationPolicy.load(c.org.organization_id, c.mission.mission_id).version == 0
  end

  test "revoked sessions cannot change settings", c do
    {:ok, view, _} = live(c.conn, c.path)
    original = page(view)
    :ok = Cadence.Auth.revoke_user_session(get_session(c.conn, :user_session_token))
    write(view, c.path, original, %{"value" => %{"approval_requirement" => "direct"}})
    assert_redirect(view, "/sign-in")
    assert ActivationPolicy.load(c.org.organization_id, c.mission.mission_id).version == 0
  end

  test "unknown sections and foreign mission scopes are not admitted", c do
    assert {:error, :unknown_settings_section} = Settings.load(c.scope, nil, "missing.settings")
    assert {:error, _} = Settings.load(c.scope, "foreign-mission", "cadence.governance")
    {:ok, view, _} = live(c.conn, c.path <> "/unknown.section")
    assert page(view)["status"] == "unavailable"
    assert has_element?(view, "#application-shell")
  end

  test "malformed values and client supplied scope fields leave the channel alive", c do
    {:ok, view, _} = live(c.conn, c.path)

    for document <- [
          %{"value" => %{"approval_requirement" => "skip"}},
          %{"value" => nil, "mission_id" => "other"}
        ] do
      write(view, c.path, page(view), document)
      assert Process.alive?(view.pid)
      assert page(view)["data"]["settings"]["version"] == 0
    end
  end

  defp page(view),
    do: LiveVue.Test.get_vue(view, id: "application-shell").props["snapshot"]["settings_page"]

  defp write(view, path, page, document),
    do:
      render_hook(view, "host:settings", %{
        "path" => path,
        "token" => page["token"],
        "input" => %{
          "revision_token" => page["data"]["settings"]["token"],
          "document" => document
        }
      })
end
