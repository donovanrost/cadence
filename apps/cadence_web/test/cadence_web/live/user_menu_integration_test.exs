defmodule CadenceWeb.UserMenuIntegrationTest do
  use CadenceWeb.ConnCase, async: false
  @moduletag :integration
  import Phoenix.LiveViewTest
  alias CadenceWeb.TestFixtures

  test "authenticated shell variants receive the scoped identity and organization data" do
    user = TestFixtures.persist_user!(display_name: "Shell User")
    org = TestFixtures.persist_org!(display_name: "Mission Org")
    TestFixtures.grant_membership!(user, org)
    mission = TestFixtures.persist_mission!(org)

    for {path, _variant} <- [
          {"/", "sidebar"},
          {"/missions/#{mission.mission_id}", "mission_sidebar"},
          {"/notifications", "user_shell"}
        ] do
      {:ok, view, _html} = live(TestFixtures.member_conn(user), path)
      shell = LiveVue.Test.get_vue(view, id: "application-shell")
      assert shell.component == "BrowserHost"
      assert shell.props["snapshot"]["context"]["user"]["user_id"] == user.user_id
      assert shell.props["snapshot"]["context"]["user"]["display_name"] == "Shell User"

      assert shell.props["snapshot"]["context"]["organization"]["organization_id"] ==
               org.organization_id

      assert shell.props["snapshot"]["context"]["organization"]["display_name"] == "Mission Org"
      assert is_binary(shell.props["snapshot"]["context"]["csrf_token"])
    end
  end
end
