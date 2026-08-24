defmodule CadenceWeb.OpsDashboardAuthoringEntryLiveTest do
  use CadenceWeb.ConnCase, async: false

  import Phoenix.LiveViewTest

  use Phoenix.VerifiedRoutes,
    endpoint: CadenceWeb.Endpoint,
    router: CadenceWeb.Router,
    statics: CadenceWeb.static_paths()

  alias Cadence.Dashboards.Document
  alias CadenceWeb.TestFixtures
  alias Phoenix.LiveView.JS

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

    assert has_element?(clone_view, "#ops-dashboard-new-component.contents")
    refute has_element?(clone_view, "#dashboard-clone-source")
    refute has_element?(clone_view, "#dashboard-form")

    clone_vue = dashboard_new_vue(clone_view)

    assert clone_vue.component == "OpsDashboardNew"
    assert clone_vue.class == "contents"
    assert clone_vue.ssr == false

    assert clone_vue.handlers == %{
             "save" => JS.push("save"),
             "validate" => JS.push("validate")
           }

    assert clone_vue.props == %{
             "page" => %{
               "id" => "ops-dashboard-new-page",
               "mode" => "clone",
               "eyebrow" => "Dashboard authoring / Clone",
               "heading" => "Clone Dashboard",
               "description" => "Create an independent draft from an existing mission dashboard.",
               "source" => %{
                 "id" => "dashboard-clone-source",
                 "dashboard_id" => source.dashboard_id,
                 "name" => "Flight Power",
                 "widget_count" => 0,
                 "latest_version" => 1
               },
               "import_guidance" => nil,
               "cancel" => %{
                 "id" => "dashboard-cancel",
                 "label" => "Cancel",
                 "href" => "/missions/#{mission.mission_id}/ops/dashboards"
               }
             },
             "form" => %{
               "id" => "dashboard-form",
               "name" => %{
                 "id" => "dashboard_name",
                 "name" => "dashboard[name]",
                 "type" => "text",
                 "label" => "Name",
                 "value" => "Copy of Flight Power",
                 "required" => true
               },
               "description" => %{
                 "id" => "dashboard_description",
                 "name" => "dashboard[description]",
                 "type" => "text",
                 "label" => "Description (what operators use this screen for)",
                 "value" => "",
                 "required" => false
               },
               "document_json" => nil,
               "submit" => %{
                 "id" => "dashboard-submit",
                 "label" => "Clone into Editor"
               }
             }
           }

    assert clone_vue.props == Jason.decode!(Jason.encode!(clone_vue.props))

    render_hook(clone_view, "validate", %{
      "dashboard" => %{"name" => "Flight Power Copy", "description" => "Clone"}
    })

    validated_form = dashboard_new_vue(clone_view).props["form"]
    assert validated_form["name"]["value"] == "Flight Power Copy"
    assert validated_form["description"]["value"] == "Clone"

    render_hook(clone_view, "save", %{
      "dashboard" => %{"name" => "Flight Power Copy", "description" => "Clone"}
    })

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

    assert has_element?(import_view, "#ops-dashboard-new-component.contents")
    refute has_element?(import_view, "#dashboard-form")

    import_vue = dashboard_new_vue(import_view)

    assert import_vue.component == "OpsDashboardNew"
    assert import_vue.class == "contents"
    assert import_vue.ssr == false

    assert import_vue.handlers == %{
             "save" => JS.push("save"),
             "validate" => JS.push("validate")
           }

    assert import_vue.props == %{
             "page" => %{
               "id" => "ops-dashboard-new-page",
               "mode" => "import",
               "eyebrow" => "Dashboard authoring / Import",
               "heading" => "Import Dashboard",
               "description" =>
                 "Validate a versioned Cadence dashboard document before creating a new draft.",
               "source" => nil,
               "import_guidance" =>
                 "Cadence validates and migrates the document before creating a new mission-scoped dashboard identity. Runtime bindings and widget semantics are preserved.",
               "cancel" => %{
                 "id" => "dashboard-cancel",
                 "label" => "Cancel",
                 "href" => "/missions/#{mission.mission_id}/ops/dashboards"
               }
             },
             "form" => %{
               "id" => "dashboard-form",
               "name" => %{
                 "id" => "dashboard_name",
                 "name" => "dashboard[name]",
                 "type" => "text",
                 "label" => "Name",
                 "value" => "",
                 "required" => true
               },
               "description" => %{
                 "id" => "dashboard_description",
                 "name" => "dashboard[description]",
                 "type" => "text",
                 "label" => "Description (what operators use this screen for)",
                 "value" => "",
                 "required" => false
               },
               "document_json" => %{
                 "id" => "dashboard_document_json",
                 "name" => "dashboard[document_json]",
                 "type" => "textarea",
                 "label" => "Dashboard document JSON",
                 "value" => "",
                 "required" => true
               },
               "submit" => %{
                 "id" => "dashboard-submit",
                 "label" => "Validate & Import"
               }
             }
           }

    assert import_vue.props == Jason.decode!(Jason.encode!(import_vue.props))

    render_hook(import_view, "save", %{
      "dashboard" => %{
        "name" => "Imported Flight Dashboard",
        "description" => "Governed import",
        "document_json" => json
      }
    })

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

  defp dashboard_new_vue(view) do
    LiveVue.Test.get_vue(view, id: "ops-dashboard-new-component")
  end

  defp signed_in_user_org_and_mission do
    user = TestFixtures.persist_user!()
    org = TestFixtures.persist_org!()
    _membership = TestFixtures.grant_membership!(user, org)
    mission = TestFixtures.persist_mission!(org, slug: "dashboard-authoring")
    {TestFixtures.member_conn(user), user, org, mission}
  end
end
