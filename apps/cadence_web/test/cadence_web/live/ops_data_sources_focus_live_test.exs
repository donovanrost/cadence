defmodule CadenceWeb.OpsDataSourcesFocusLiveTest do
  use CadenceWeb.ConnCase, async: false

  import Phoenix.LiveViewTest

  use Phoenix.VerifiedRoutes,
    endpoint: CadenceWeb.Endpoint,
    router: CadenceWeb.Router,
    statics: CadenceWeb.static_paths()

  alias CadenceWeb.TestFixtures
  alias LiveVue.Test

  test "focus query context remains bounded to the source subject descriptor" do
    user = TestFixtures.persist_user!()
    organization = TestFixtures.persist_org!()
    TestFixtures.grant_membership!(user, organization, role: :organization_admin)
    mission = TestFixtures.persist_mission!(organization)

    {:ok, view, _html} =
      live(
        TestFixtures.member_conn(user),
        ~p"/missions/#{mission.mission_id}/ops/data-sources?#{%{data_source_id: "focus-source", source_binding_id: "binding-1", logical_source: "telemetry", realm: "flight", selected_target: "transport", selected_id: "transport-1"}}"
      )

    assert_surface(
      view,
      "ops-data-sources-component",
      "data_sources",
      mission,
      %{"data_source_id" => "focus-source"}
    )
  end

  test "settings focus carries the exact source subject and rejects presentation-only controls" do
    user = TestFixtures.persist_user!()
    organization = TestFixtures.persist_org!()
    TestFixtures.grant_membership!(user, organization, role: :organization_admin)
    mission = TestFixtures.persist_mission!(organization)

    {:ok, view, _html} =
      live(
        TestFixtures.member_conn(user),
        ~p"/missions/#{mission.mission_id}/ops/data-sources/focus-source/settings?#{%{source_binding_id: "binding-1", selected_target: "transport", selected_id: "transport-1"}}"
      )

    assert_surface(
      view,
      "ops-data-sources-component",
      "data_source_settings",
      mission,
      %{"data_source_id" => "focus-source"}
    )

    refute has_element?(view, "#ops-data-sources-page")
  end

  defp assert_surface(view, id, surface_id, mission, query_params) do
    assert has_element?(view, "##{id}.contents")
    vue = Test.get_vue(view, id: id)
    assert vue.component == "FederatedFullPageSurface"
    assert vue.id == id
    assert vue.class == "contents"
    assert vue.ssr == false
    assert vue.handlers == %{}

    assert vue.props == %{
             "application_key" => "ops_console",
             "host_scope" => "mission",
             "mission_id" => mission.mission_id,
             "query_params" => query_params,
             "surface_id" => surface_id
           }
  end
end
