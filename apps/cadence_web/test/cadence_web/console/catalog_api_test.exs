defmodule CadenceWeb.Console.CatalogAPITest do
  use CadenceWeb.ConnCase, async: false
  @moduletag :tmp_dir

  alias CadenceWeb.TestFixtures

  setup do
    org = TestFixtures.persist_org!()
    user = TestFixtures.persist_user!()
    TestFixtures.grant_membership!(user, org)
    mission = TestFixtures.persist_mission!(org)

    %{
      user: user,
      mission: mission,
      base: "/api/v1/missions/#{mission.mission_id}/catalog"
    }
  end

  defp get_data(c, path),
    do:
      c.user
      |> TestFixtures.member_conn()
      |> get(path)
      |> json_response(200)
      |> Map.fetch!("data")

  test "a mission without a catalog has no database", c do
    assert get_data(c, c.base) == %{"databases" => [], "database" => nil}
  end

  test "lists revisions and import runs, and shows a run's detail", c do
    database = TestFixtures.persist_catalog_database!(c.mission)

    run =
      database
      |> TestFixtures.start_catalog_revision_import!(revision_label: "FSW 3.1.0")
      |> TestFixtures.complete_catalog_import_run!()

    data = get_data(c, c.base)
    assert [%{"id" => db_id}] = data["databases"]
    assert data["database"]["id"] == db_id

    assert [
             %{
               "number" => 1,
               "label" => "FSW 3.1.0",
               "artifact" => %{"file_name" => "mission.yaml"}
             } = revision
           ] =
             data["database"]["revisions"]

    assert is_binary(revision["imported_at"])
    assert data["database"]["current_revision"]["number"] == 1

    assert [
             %{
               "id" => run_id,
               "status" => "succeeded",
               "revision_number" => 1,
               "diagnostic_counts" => %{"error" => errors}
             }
           ] =
             data["database"]["import_runs"]

    assert run_id == run.import_run_id
    assert is_integer(errors)

    detail = get_data(c, "#{c.base}/imports/#{run_id}")
    assert detail["status"] == "succeeded"
    assert detail["file"]["name"] == "mission.yaml"
    assert is_integer(detail["file"]["size_bytes"])
    assert detail["revision"]["number"] == 1
    assert detail["diff"] == nil
    assert length(detail["diagnostics"]) >= errors

    for diagnostic <- detail["diagnostics"] do
      assert diagnostic["severity"] in ~w(error warning info)
      assert Map.has_key?(diagnostic, "path")
    end
  end

  defp upload(c, file_name, contents, fields) do
    path = Path.join(c.tmp_dir, "#{System.unique_integer([:positive])}-#{file_name}")
    File.write!(path, contents)

    c.user
    |> TestFixtures.member_conn()
    |> post(
      "#{c.base}/imports",
      Map.put(fields, "file", %Plug.Upload{
        path: path,
        filename: file_name,
        content_type: "application/octet-stream"
      })
    )
  end

  @yaml """
  packets:
    - name: HEALTH
      items:
        - name: mode
          data_type: uint
          bit_offset: 0
          bit_size: 8
  commands: []
  """

  test "lists accepted importers with extensions and the size limit", c do
    data = get_data(c, "#{c.base}/importers")
    assert data["max_bytes"] == 52_428_800
    assert [_ | _] = data["importers"]
    assert Enum.any?(data["importers"], &(".yaml" in &1["extensions"]))
  end

  test "a multipart upload creates a database and starts an import run", c do
    conn =
      upload(c, "mission.yaml", @yaml, %{"name" => "Earendil FSW", "revision_label" => "FSW 1"})

    assert %{"import_run_id" => run_id} = json_response(conn, 202)["data"]
    assert [%{"name" => "Earendil FSW"}] = get_data(c, c.base)["databases"]
    assert get_data(c, "#{c.base}/imports/#{run_id}")["file"]["name"] == "mission.yaml"

    # lead 11-14: the import records who ran it (before, every upload stored %{}).
    org_id = c.mission.organization_id
    user_id = c.user.user_id

    {:ok, run} = Cadence.Catalog.fetch_import_run(org_id, c.mission.mission_id, run_id)
    assert %{"actor_kind" => "user", "user_id" => ^user_id} = run.requested_by

    {:ok, artifact} =
      Cadence.Catalog.fetch_artifact(org_id, c.mission.mission_id, run.artifact_id)

    # #471: the stored document names the person by id and display name, never by email.
    assert %{"actor_kind" => "user", "user_id" => ^user_id} = artifact.uploaded_by
    refute Map.has_key?(artifact.uploaded_by, "email")
  end

  test "upload rejects an unsupported format, missing fields and a missing file", c do
    conn = upload(c, "notes.pdf", "%PDF", %{"name" => "X"})

    assert %{"code" => "unsupported_format", "details" => %{"accepted" => [_ | _]}} =
             json_response(conn, 422)["error"]

    conn = upload(c, "mission.yaml", @yaml, %{})

    assert %{"code" => "invalid_params", "details" => %{"name" => _}} =
             json_response(conn, 422)["error"]

    conn = c.user |> TestFixtures.member_conn() |> post("#{c.base}/imports", %{})

    assert %{"code" => "invalid_params", "details" => %{"file" => _}} =
             json_response(conn, 422)["error"]
  end

  test "an unknown import run is not found", c do
    conn = c.user |> TestFixtures.member_conn() |> get("#{c.base}/imports/nope")
    assert json_response(conn, 404)["error"]["code"] == "import_run_not_found"
  end

  test "C3 rollout: a revision's per-profile effect counts; an unknown revision is 404", c do
    run =
      c.mission
      |> TestFixtures.persist_catalog_database!()
      |> TestFixtures.start_catalog_revision_import!(revision_label: "FSW 3.1.0")
      |> TestFixtures.complete_catalog_import_run!()

    detail = get_data(c, "#{c.base}/imports/#{run.import_run_id}")
    revision_id = detail["revision"]["id"]

    rollout = get_data(c, "#{c.base}/revisions/#{revision_id}/rollout")

    assert %{"revision" => %{"id" => ^revision_id, "number" => 1, "label" => "rev 1"}} = rollout
    assert is_list(rollout["profiles"]) and is_integer(rollout["unprofiled_count"])

    conn = c.user |> TestFixtures.member_conn() |> get("#{c.base}/revisions/nope/rollout")
    assert json_response(conn, 404)["error"]["code"] == "catalog_revision_not_found"
  end

  test "L18: a source file's page, its download, and importing it again", c do
    database = TestFixtures.persist_catalog_database!(c.mission)

    database
    |> TestFixtures.start_catalog_revision_import!(revision_label: "FSW 3.1.0")
    |> TestFixtures.complete_catalog_import_run!()

    [revision] = get_data(c, c.base)["database"]["revisions"]
    artifact_id = revision["artifact"]["id"]
    assert revision["artifact"]["download_url"] == "#{c.base}/artifacts/#{artifact_id}/download"

    page = get_data(c, "#{c.base}/artifacts/#{artifact_id}")

    assert %{"file_name" => "mission.yaml", "sha256" => _, "database" => %{"id" => _}} =
             page["artifact"]

    assert [%{"number" => 1, "label" => "FSW 3.1.0"}] = page["revisions"]
    assert [%{"status" => "succeeded"}] = page["import_runs"]
    assert page["permissions"] == ["catalog.import"]

    download =
      c.user |> TestFixtures.member_conn() |> get("#{c.base}/artifacts/#{artifact_id}/download")

    assert download.status == 200
    assert [disposition] = get_resp_header(download, "content-disposition")
    assert disposition =~ "mission.yaml"

    conn =
      c.user
      |> TestFixtures.member_conn()
      |> post("#{c.base}/artifacts/#{artifact_id}/reimport", %{})

    assert %{"import_run" => %{"id" => run_id}} = json_response(conn, 202)["data"]
    assert is_binary(run_id)

    missing = c.user |> TestFixtures.member_conn() |> get("#{c.base}/artifacts/nope")
    assert json_response(missing, 404)["error"]["code"] == "artifact_not_found"
  end
end
