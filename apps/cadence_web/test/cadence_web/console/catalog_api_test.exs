defmodule CadenceWeb.Console.CatalogAPITest do
  use CadenceWeb.ConnCase, async: false

  alias CadenceWeb.TestFixtures

  setup do
    org = TestFixtures.persist_org!()
    user = TestFixtures.persist_user!()
    TestFixtures.grant_membership!(user, org)
    mission = TestFixtures.persist_mission!(org)

    %{
      user: user,
      mission: mission,
      base: "/api/console/v1/missions/#{mission.mission_id}/catalog"
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

  test "an unknown import run is not found", c do
    conn = c.user |> TestFixtures.member_conn() |> get("#{c.base}/imports/nope")
    assert json_response(conn, 404)["error"]["code"] == "import_run_not_found"
  end
end
