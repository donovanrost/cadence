defmodule CadenceWeb.OpsDashboardShowLive.RenameDashboardFormLiveTest do
  use CadenceWeb.ConnCase, async: false

  import Phoenix.LiveViewTest
  import CadenceWeb.OpsDashboardShowLive.ViewTestSupport

  use Phoenix.VerifiedRoutes,
    endpoint: CadenceWeb.Endpoint,
    router: CadenceWeb.Router,
    statics: CadenceWeb.static_paths()

  alias Cadence.Dashboards.Document
  alias CadenceWeb.TestFixtures

  test "submits every browser form value through the authoritative rename event" do
    {conn, user, org, mission} = signed_in_user_org_and_mission()
    dashboard = TestFixtures.persist_dashboard_document!(mission, name: "Power")

    {:ok, view, _html} =
      conn
      |> live(editor_path(mission, dashboard))
      |> await_live_result()

    render_hook(view, "open_rename", %{})

    assert has_element?(view, "#dashboard-panel")
    assert has_element?(view, "#rename-dashboard-form-component")
    refute has_element?(view, "#rename-dashboard-form")

    presentation = rename_form_presentation(view)

    assert presentation["root"]["params"] == %{
             "name" => "Power",
             "description" => ""
           }

    submit_browser_form(view, presentation, %{
      "name" => "Power North",
      "description" => "Primary EPS"
    })

    refute has_element?(view, "#dashboard-panel")

    assert has_element?(
             view,
             ~s(#ops-dashboard-show-page[data-dashboard-editor="true"][data-editor-dirty="true"])
           )

    render_hook(view, "save_editor", %{})
    stop_dashboard_view(view)

    renamed = fetch_dashboard_document!(org, mission, dashboard)
    assert renamed.name == "Power North"
    assert renamed.description == "Primary EPS"
    assert Document.version(renamed) == 2

    version = fetch_dashboard_version!(org, mission, dashboard, 2)
    assert version.change_summary == "Renamed dashboard"
    assert version.created_by == user.user_id
  end

  test "submits an empty browser description so Phoenix restores nil semantics" do
    {conn, _user, org, mission} = signed_in_user_org_and_mission()

    dashboard =
      TestFixtures.persist_dashboard_document!(mission,
        name: "Power",
        description: "Primary EPS"
      )

    {:ok, view, _html} =
      conn
      |> live(editor_path(mission, dashboard))
      |> await_live_result()

    render_hook(view, "open_rename", %{})
    presentation = rename_form_presentation(view)

    submit_browser_form(view, presentation, %{
      "name" => "Power",
      "description" => ""
    })

    render_hook(view, "save_editor", %{})
    stop_dashboard_view(view)

    renamed = fetch_dashboard_document!(org, mission, dashboard)
    assert renamed.name == "Power"
    assert renamed.description == nil
  end

  defp signed_in_user_org_and_mission do
    user = TestFixtures.persist_user!()
    org = TestFixtures.persist_org!()
    _membership = TestFixtures.grant_membership!(user, org)
    mission = TestFixtures.persist_mission!(org, slug: "ops", display_name: "Ops Mission")
    {TestFixtures.member_conn(user), user, org, mission}
  end

  defp editor_path(mission, dashboard) do
    ~p"/missions/#{mission.mission_id}/ops/dashboards/#{dashboard.dashboard_id}/edit"
  end

  defp rename_form_presentation(view) do
    vue = LiveVue.Test.get_vue(view, id: "rename-dashboard-form-component")

    assert vue.component == "RenameDashboardForm"
    assert vue.ssr == false
    assert vue.handlers == %{}
    assert vue.props == Jason.decode!(Jason.encode!(vue.props))

    Map.fetch!(vue.props, "presentation")
  end

  defp submit_browser_form(view, presentation, overrides) do
    root = presentation["root"]

    browser_params =
      Map.new(presentation["fields"], fn field ->
        [_, param, key] =
          Regex.run(~r/\A([^\[]+)\[([^\]]+)\]\z/, field["control"]["attrs"]["name"])

        assert param == root["param"]
        {key, field["control"]["value"] || ""}
      end)

    assert browser_params == root["params"]

    params = Map.merge(browser_params, overrides)
    assert Map.keys(params) |> Enum.sort() == ["description", "name"]
    assert params == Jason.decode!(Jason.encode!(params))

    render_submit(view, root["attrs"]["phx-submit"], %{root["param"] => params})
  end

  defp fetch_dashboard_document!(org, mission, dashboard) do
    assert {:ok, document} =
             Cadence.Dashboards.fetch_document(
               org.organization_id,
               mission.mission_id,
               dashboard.dashboard_id
             )

    document
  end

  defp fetch_dashboard_version!(org, mission, dashboard, version_number) do
    assert {:ok, version} =
             Cadence.Dashboards.fetch_version(
               org.organization_id,
               mission.mission_id,
               dashboard.dashboard_id,
               version_number
             )

    version
  end
end
