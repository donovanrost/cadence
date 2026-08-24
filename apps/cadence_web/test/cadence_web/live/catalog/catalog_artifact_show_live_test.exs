defmodule CadenceWeb.CatalogArtifactShowLiveTest do
  use CadenceWeb.ConnCase, async: false

  import Phoenix.LiveViewTest

  use Phoenix.VerifiedRoutes,
    endpoint: CadenceWeb.Endpoint,
    router: CadenceWeb.Router,
    statics: CadenceWeb.static_paths()

  alias CadenceWeb.{CatalogArtifactShowLive, TestFixtures}
  alias Phoenix.LiveView.JS

  defp signed_in_org_and_mission do
    user = TestFixtures.persist_user!()
    org = TestFixtures.persist_org!()
    _ = TestFixtures.grant_membership!(user, org)
    mission = TestFixtures.persist_mission!(org, slug: "primary")
    {TestFixtures.member_conn(user), org, mission}
  end

  defp artifact_show_vue(view) do
    assert has_element?(view, "#catalog-artifact-show-page-component")
    assert has_element?(view, "#catalog-artifact-show-page-component.contents")

    vue = LiveVue.Test.get_vue(view, id: "catalog-artifact-show-page-component")

    assert vue.component == "CatalogArtifactShowPage"
    assert vue.ssr == false
    assert is_binary(Jason.encode!(vue.props))

    vue
  end

  test "renders artifact metadata and its import runs" do
    {conn, _org, mission} = signed_in_org_and_mission()
    artifact = TestFixtures.persist_catalog_artifact!(mission, artifact_name: "mission.yaml")
    run = TestFixtures.persist_catalog_import_run!(artifact)
    completed = TestFixtures.complete_catalog_import_run!(run)

    {:ok, view, _html} =
      live(
        conn,
        ~p"/missions/#{mission.mission_id}/catalog/artifacts/#{artifact.artifact_id}"
      )

    assert artifact_show_presentation(view)["header"]["title"]["text"] == "mission.yaml"

    vue = artifact_show_vue(view)

    assert vue.props["presentation"]["artifact_show"] == %{
             "artifact" => %{
               "format_key" => artifact.format_key,
               "media_type" => artifact.media_type,
               "content_sha256" => artifact.content_sha256,
               "uploaded_at" => Calendar.strftime(artifact.uploaded_at, "%Y-%m-%d %H:%M:%S UTC"),
               "download_href" =>
                 "/missions/#{mission.mission_id}/catalog/artifacts/#{artifact.artifact_id}/download"
             },
             "runs" => [
               %{
                 "id" => "catalog-artifact-run-#{completed.import_run_id}",
                 "actions_id" => "#{completed.import_run_id}-actions",
                 "status" => "ready",
                 "status_label" => "Completed",
                 "started_at" => Calendar.strftime(completed.started_at, "%Y-%m-%d %H:%M:%S"),
                 "completed_at" => Calendar.strftime(completed.completed_at, "%Y-%m-%d %H:%M:%S"),
                 "href" =>
                   "/missions/#{mission.mission_id}/catalog/imports/#{completed.import_run_id}"
               }
             ]
           }
  end

  test "represents the no-runs state without leaking domain structs" do
    {conn, _org, mission} = signed_in_org_and_mission()
    artifact = TestFixtures.persist_catalog_artifact!(mission, media_type: nil)

    {:ok, view, _html} =
      live(
        conn,
        ~p"/missions/#{mission.mission_id}/catalog/artifacts/#{artifact.artifact_id}"
      )

    props = artifact_show_presentation(view)["artifact_show"]

    assert props["artifact"]["media_type"] == "—"
    assert props["runs"] == []
  end

  test "re-import action starts a new run and navigates to it" do
    {conn, _org, mission} = signed_in_org_and_mission()
    artifact = TestFixtures.persist_catalog_artifact!(mission, artifact_name: "mission.yaml")

    {:ok, view, _html} =
      live(
        conn,
        ~p"/missions/#{mission.mission_id}/catalog/artifacts/#{artifact.artifact_id}"
      )

    vue = artifact_show_vue(view)
    assert vue.handlers == %{"reimport" => JS.push("reimport")}

    result =
      view
      |> element("#catalog-artifact-show-page-component")
      |> render_hook("reimport", %{})

    assert {:error, {:live_redirect, %{to: to}}} = result
    assert to =~ ~r"/catalog/imports/"
    assert String.starts_with?(to, "/missions/#{mission.mission_id}/catalog/imports/")
  end

  test "updates matching runs from PubSub and ignores events for another artifact" do
    {conn, _org, mission} = signed_in_org_and_mission()
    artifact = TestFixtures.persist_catalog_artifact!(mission, artifact_name: "mission.yaml")
    run = TestFixtures.persist_catalog_import_run!(artifact)
    other_artifact = TestFixtures.persist_catalog_artifact!(mission, artifact_name: "other.yaml")

    {:ok, view, _html} =
      live(
        conn,
        ~p"/missions/#{mission.mission_id}/catalog/artifacts/#{artifact.artifact_id}"
      )

    assert [%{"status" => "info", "status_label" => "Running"}] =
             artifact_show_presentation(view)["artifact_show"]["runs"]

    completed = TestFixtures.complete_catalog_import_run!(run)
    _ = render(view)

    assert [completed_props] = artifact_show_presentation(view)["artifact_show"]["runs"]
    assert completed_props["status"] == "ready"
    assert completed_props["status_label"] == "Completed"

    assert completed_props["completed_at"] ==
             Calendar.strftime(completed.completed_at, "%Y-%m-%d %H:%M:%S")

    other_run = TestFixtures.persist_catalog_import_run!(other_artifact)
    send(view.pid, {:import_run_started, other_run})
    _ = render(view)

    assert Enum.map(artifact_show_presentation(view)["artifact_show"]["runs"], & &1["id"]) == [
             "catalog-artifact-run-#{completed.import_run_id}"
           ]
  end

  test "missing artifact redirects to the catalog index" do
    {conn, _org, mission} = signed_in_org_and_mission()

    assert {:error, {:redirect, %{to: to, flash: flash}}} =
             live(conn, ~p"/missions/#{mission.mission_id}/catalog/artifacts/missing")

    assert to == ~p"/missions/#{mission.mission_id}/catalog"
    assert flash["error"] == "Artifact not found."
  end

  test "does not load an artifact outside the current mission scope" do
    {conn, org, mission} = signed_in_org_and_mission()
    other_mission = TestFixtures.persist_mission!(org, slug: "secondary")
    other_artifact = TestFixtures.persist_catalog_artifact!(other_mission)

    assert {:error, {:redirect, %{to: to, flash: flash}}} =
             live(
               conn,
               ~p"/missions/#{mission.mission_id}/catalog/artifacts/#{other_artifact.artifact_id}"
             )

    assert to == ~p"/missions/#{mission.mission_id}/catalog"
    assert flash["error"] == "Artifact not found."
  end

  test "projects the complete page through one JSON-safe non-SSR parent host" do
    {conn, _org, mission} = signed_in_org_and_mission()
    artifact = TestFixtures.persist_catalog_artifact!(mission, artifact_name: "mission.yaml")

    {:ok, view, _html} =
      live(
        conn,
        ~p"/missions/#{mission.mission_id}/catalog/artifacts/#{artifact.artifact_id}"
      )

    vue = artifact_show_vue(view)

    assert vue.class == "contents"
    assert Map.keys(vue.props) == ["presentation"]
    assert vue.handlers == %{"reimport" => JS.push("reimport")}

    presentation = vue.props["presentation"]
    assert presentation == Jason.decode!(Jason.encode!(presentation))

    assert presentation["root"] == %{
             "attrs" => %{
               "class" => "space-y-6",
               "id" => "catalog-artifact-show-page"
             }
           }

    assert presentation["header"] == %{
             "attrs" => %{"class" => "border-b border-primary/20 pb-4"},
             "body" => %{"attrs" => %{}},
             "content" => %{"attrs" => %{}},
             "breadcrumbs" => %{
               "attrs" => %{
                 "aria-label" => "Breadcrumb",
                 "class" =>
                   "flex flex-wrap items-center gap-2 text-[0.7rem] font-semibold uppercase tracking-[0.12em] text-base-content/60"
               },
               "items" => [
                 %{
                   "key" => "mission",
                   "separator" => nil,
                   "link" => %{
                     "attrs" => %{
                       "class" => "hover:text-primary transition-colors",
                       "data-phx-link" => "redirect",
                       "data-phx-link-state" => "push",
                       "href" => "/missions/#{mission.mission_id}"
                     },
                     "text" => mission.display_name
                   },
                   "current" => nil
                 },
                 %{
                   "key" => "catalog",
                   "separator" => %{
                     "attrs" => %{
                       "aria-hidden" => "true",
                       "class" => "text-base-content/20"
                     },
                     "text" => "/"
                   },
                   "link" => %{
                     "attrs" => %{
                       "class" => "hover:text-primary transition-colors",
                       "data-phx-link" => "redirect",
                       "data-phx-link-state" => "push",
                       "href" => "/missions/#{mission.mission_id}/catalog"
                     },
                     "text" => "Catalog"
                   },
                   "current" => nil
                 },
                 %{
                   "key" => "artifact",
                   "separator" => %{
                     "attrs" => %{
                       "aria-hidden" => "true",
                       "class" => "text-base-content/20"
                     },
                     "text" => "/"
                   },
                   "link" => nil,
                   "current" => %{
                     "attrs" => %{"class" => "text-primary/90"},
                     "text" => "mission.yaml"
                   }
                 }
               ]
             },
             "title" => %{
               "attrs" => %{
                 "class" => "mt-2 text-2xl font-bold text-base-content tracking-tight"
               },
               "text" => "mission.yaml"
             }
           }

    assert presentation["child_wrapper"] == %{
             "attrs" => %{"id" => "catalog-artifact-show-component"}
           }
  end

  test "raw attrs preserve HEEx nil false true empty string string and number semantics" do
    attrs =
      CatalogArtifactShowLive.presentation_attrs(%{
        "nil" => nil,
        "false" => false,
        "true" => true,
        "empty" => "",
        "string" => "retained",
        "number" => 7
      })

    assert attrs == %{
             "true" => "",
             "empty" => "",
             "string" => "retained",
             "number" => "7"
           }
  end

  defp artifact_show_presentation(view), do: artifact_show_vue(view).props["presentation"]
end
