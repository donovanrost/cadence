defmodule CadenceWeb.CatalogUploadTest do
  use CadenceWeb.ConnCase, async: false
  import Phoenix.LiveViewTest

  alias Cadence.Catalog
  alias CadenceWeb.TestFixtures

  @yaml "packets:\n  - name: HEALTH\n    items:\n      - name: mode\n        data_type: uint\n        bit_offset: 0\n        bit_size: 8\ncommands: []\n"

  setup do
    user = TestFixtures.persist_user!()
    org = TestFixtures.persist_org!()
    TestFixtures.grant_membership!(user, org)
    mission = TestFixtures.persist_mission!(org)
    {:ok, conn: TestFixtures.member_conn(user), mission: mission}
  end

  test "native upload creates a database and immutable revision with original bytes", %{
    conn: conn,
    mission: mission
  } do
    {:ok, view, _} = live(conn, "/missions/#{mission.mission_id}/catalog/new")
    assert has_element?(view, "#catalog-native-upload-form")
    upload_ref = catalog(view)["data"]["upload"]["ref"]

    assert has_element?(
             view,
             "#catalog-native-upload-form input[id='#{upload_ref}'][name='catalog_artifact'][data-phx-upload-ref='#{upload_ref}']"
           )

    params =
      params(view, %{
        "name" => "Flight",
        "revision_label" => "Baseline",
        "revision_notes" => "First revision"
      })

    render_change(form(view, "#catalog-native-upload-form"), params)
    upload_file(view, @yaml)
    assert catalog(view)["data"]["submit_disabled"] == false
    render_submit(form(view, "#catalog-native-upload-form"), params)

    assert [database] = Catalog.list_databases(mission.organization_id, mission.mission_id)
    assert database.name == "Flight"
    assert [artifact] = Catalog.list_artifacts(mission.organization_id, mission.mission_id)
    assert artifact.source_artifact == @yaml
    assert [run] = Catalog.list_import_runs(mission.organization_id, mission.mission_id)
    assert run.catalog_database_id == database.catalog_database_id
    assert_push_event(view, "catalog:uploaded", %{href: href, path: path, token: token})
    assert href == "/missions/#{mission.mission_id}/catalog/imports/#{run.import_run_id}"
    assert path == params["catalog_upload"]["path"]
    assert token == params["catalog_upload"]["token"]

    render_hook(view, "catalog:upload:save", params)
    assert length(Catalog.list_import_runs(mission.organization_id, mission.mission_id)) == 1
    assert length(Catalog.list_databases(mission.organization_id, mission.mission_id)) == 1

    completed = TestFixtures.complete_catalog_import_run!(run)
    revision = TestFixtures.fetch_catalog_revision_for_run!(completed)
    assert revision.revision_label == "Baseline"
    assert revision.notes == "First revision"
    assert revision.artifact_id == artifact.artifact_id
  end

  test "database upload appends a revision without creating another database", %{
    conn: conn,
    mission: mission
  } do
    database = TestFixtures.persist_catalog_database!(mission)

    previous =
      database
      |> TestFixtures.start_catalog_revision_import!()
      |> TestFixtures.complete_catalog_import_run!()

    original = TestFixtures.fetch_catalog_revision_for_run!(previous)
    path = "/missions/#{mission.mission_id}/catalog/databases/#{database.catalog_database_id}"
    {:ok, view, _} = live(conn, path)

    params =
      params(view, %{
        "revision_label" => "Second",
        "name" => "Forged name",
        "catalog_database_id" => "forged"
      })

    render_change(form(view, "#catalog-native-upload-form"), params)
    upload_file(view, @yaml)
    render_submit(form(view, "#catalog-native-upload-form"), params)
    [next | _] = Catalog.list_import_runs(mission.organization_id, mission.mission_id)
    completed = TestFixtures.complete_catalog_import_run!(next)
    revision = TestFixtures.fetch_catalog_revision_for_run!(completed)
    assert revision.revision_number == 2
    assert revision.catalog_database_id == database.catalog_database_id
    assert length(Catalog.list_databases(mission.organization_id, mission.mission_id)) == 1

    assert {:ok, ^original} =
             Catalog.fetch_revision(
               mission.organization_id,
               mission.mission_id,
               original.catalog_revision_id
             )
  end

  test "invalid source rolls back database and artifact creation and keeps the upload retryable",
       %{conn: conn, mission: mission} do
    {:ok, view, _} = live(conn, "/missions/#{mission.mission_id}/catalog/new")
    params = params(view, %{"name" => "Invalid catalog"})
    render_change(form(view, "#catalog-native-upload-form"), params)
    upload_file(view, "not: a catalog")
    render_submit(form(view, "#catalog-native-upload-form"), params)
    assert catalog(view)["upload_session"]["error"]
    assert [%{"done" => true}] = catalog(view)["data"]["upload"]["entries"]
    assert Catalog.list_databases(mission.organization_id, mission.mission_id) == []
    assert Catalog.list_artifacts(mission.organization_id, mission.mission_id) == []
    assert Catalog.list_import_runs(mission.organization_id, mission.mission_id) == []
  end

  test "navigation rotates the upload token and stale submissions cannot create records", %{
    conn: conn,
    mission: mission
  } do
    path = "/missions/#{mission.mission_id}/catalog/new"
    {:ok, view, _} = live(conn, path)
    old = params(view, %{"name" => "Stale"})
    upload_file(view, @yaml)
    render_hook(view, "host:context", %{"path" => "/missions"})
    refute has_element?(view, "#catalog-native-upload-form")
    render_hook(view, "host:context", %{"path" => path})
    refute params(view)["catalog_upload"]["token"] == old["catalog_upload"]["token"]
    render_hook(view, "catalog:upload:save", old)
    assert Catalog.list_databases(mission.organization_id, mission.mission_id) == []
    assert catalog(view)["data"]["upload"]["entries"] == []
  end

  test "cancellation releases the entry and revoked sessions cannot consume an uploaded file", %{
    conn: conn,
    mission: mission
  } do
    {:ok, view, _} = live(conn, "/missions/#{mission.mission_id}/catalog/new")
    params = params(view, %{"name" => "Authorized"})
    upload_file(view, @yaml)
    [entry] = catalog(view)["data"]["upload"]["entries"]
    render_hook(view, "catalog:upload:cancel", Map.put(params, "ref", "unknown"))
    assert [_] = catalog(view)["data"]["upload"]["entries"]
    render_hook(view, "catalog:upload:cancel", Map.put(params, "ref", entry["ref"]))
    assert catalog(view)["data"]["upload"]["entries"] == []
    render_hook(view, "catalog:upload:cancel", Map.put(params, "ref", entry["ref"]))
    upload_file(view, @yaml)
    :ok = Cadence.Auth.revoke_user_session(get_session(conn, :user_session_token))
    render_submit(form(view, "#catalog-native-upload-form"), params)
    assert_redirect(view, "/sign-in")
    assert Catalog.list_databases(mission.organization_id, mission.mission_id) == []
  end

  test "unsupported files and invalid metadata cannot create partial databases", %{
    conn: conn,
    mission: mission
  } do
    {:ok, view, _} = live(conn, "/missions/#{mission.mission_id}/catalog/new")
    valid = params(view, %{"name" => "Flight"})
    render_change(form(view, "#catalog-native-upload-form"), valid)
    upload_file(view, @yaml, "mission.exe")
    assert catalog(view)["data"]["detected_importer"]["status"] == "unsupported"
    assert catalog(view)["data"]["submit_disabled"]
    render_submit(form(view, "#catalog-native-upload-form"), valid)
    assert catalog(view)["upload_session"]["error"]

    for name <- ["", String.duplicate("a", 256), %{"nested" => "not text"}] do
      invalid = params(view, %{"name" => name})
      render_hook(view, "catalog:upload:validate", invalid)
      assert catalog(view)["data"]["submit_disabled"]
      [field | _] = catalog(view)["data"]["form"]["primary_fields"]
      assert field["errors"] != []
      assert is_binary(field["value"])
      render_hook(view, "catalog:upload:save", invalid)
    end

    assert Catalog.list_databases(mission.organization_id, mission.mission_id) == []
    assert Catalog.list_artifacts(mission.organization_id, mission.mission_id) == []
    assert Catalog.list_import_runs(mission.organization_id, mission.mission_id) == []
  end

  defp catalog(view),
    do: LiveVue.Test.get_vue(view, id: "application-shell").props["snapshot"]["catalog"]

  defp params(view, values \\ %{}) do
    session = catalog(view)["upload_session"]
    %{"catalog_upload" => Map.merge(values, Map.take(session, ~w(path token)))}
  end

  defp upload_file(view, bytes, filename \\ "mission.yaml") do
    view
    |> file_input("#catalog-native-upload-form", :catalog_artifact, [
      %{
        name: filename,
        content: bytes,
        size: byte_size(bytes),
        type: "application/octet-stream"
      }
    ])
    |> render_upload(filename)
  end
end
