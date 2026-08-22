defmodule CadenceWeb.OpsDashboardAuthoringEntryLiveTest do
  use CadenceWeb.ConnCase, async: false

  import Phoenix.LiveViewTest

  use Phoenix.VerifiedRoutes,
    endpoint: CadenceWeb.Endpoint,
    router: CadenceWeb.Router,
    statics: CadenceWeb.static_paths()

  alias Cadence.Dashboards.Document
  alias CadenceWeb.TestFixtures

  test "Directory exposes capability-aware clone and import entry points" do
    {conn, _user, _org, mission} = signed_in_user_org_and_mission()
    source = TestFixtures.persist_dashboard_document!(mission, name: "Flight Power")

    {:ok, directory, _html} = live(conn, directory_path(mission))

    assert has_element?(directory, "#dashboard-directory-import")
    assert has_element?(directory, "#clone-dashboard-#{source.dashboard_id}")

    {:ok, clone_view, _html} =
      live(
        conn,
        ~p"/missions/#{mission.mission_id}/ops/dashboards/new?source_dashboard_id=#{source.dashboard_id}"
      )

    assert has_element?(
             clone_view,
             ~s(#dashboard-clone-source[data-source-dashboard-id="#{source.dashboard_id}"])
           )

    clone_view
    |> form("#dashboard-form", dashboard: %{name: "Flight Power Copy", description: "Clone"})
    |> render_submit()

    {clone_editor_path, _flash} = assert_redirect(clone_view)
    assert clone_editor_path =~ "/edit"

    clone =
      mission.organization_id
      |> Cadence.Dashboards.list_documents(mission.mission_id)
      |> Enum.find(&(&1.name == "Flight Power Copy"))

    assert %Document{} = clone
    assert clone.dashboard_id != source.dashboard_id
    assert clone.metadata["source"] == "dashboard_clone"
    assert clone.metadata["source_dashboard_id"] == source.dashboard_id
  end

  test "import validates JSON and replaces untrusted identity with the current mission scope" do
    {conn, _user, org, mission} = signed_in_user_org_and_mission()

    foreign = %Document{
      dashboard_id: "foreign-dashboard",
      organization_id: "foreign-org",
      mission_id: "foreign-mission",
      name: "Foreign Dashboard",
      description: "Imported telemetry",
      metadata: %{"version" => 19, "tags" => ["flight"]}
    }

    {:ok, json} = Cadence.Dashboards.export_bundle(foreign)

    {:ok, import_view, _html} =
      live(conn, ~p"/missions/#{mission.mission_id}/ops/dashboards/new?mode=import")

    assert has_element?(import_view, "#dashboard-form textarea[name='dashboard[document_json]']")

    import_view
    |> form("#dashboard-form",
      dashboard: %{
        name: "Imported Flight Dashboard",
        description: "Governed import",
        document_json: json
      }
    )
    |> render_submit()

    {editor_path, _flash} = assert_redirect(import_view)
    assert editor_path =~ "/edit"

    assert [%Document{} = imported] =
             Cadence.Dashboards.list_documents(org.organization_id, mission.mission_id)

    assert imported.dashboard_id != foreign.dashboard_id
    assert imported.organization_id == org.organization_id
    assert imported.mission_id == mission.mission_id
    assert imported.name == "Imported Flight Dashboard"
    assert imported.metadata["source"] == "dashboard_import"
    assert Document.version(imported) == 1
  end

  defp directory_path(mission), do: ~p"/missions/#{mission.mission_id}/ops/dashboards"

  defp signed_in_user_org_and_mission do
    user = TestFixtures.persist_user!()
    org = TestFixtures.persist_org!()
    _membership = TestFixtures.grant_membership!(user, org)
    mission = TestFixtures.persist_mission!(org, slug: "dashboard-authoring")
    {TestFixtures.member_conn(user), user, org, mission}
  end
end
