defmodule CadenceWeb.Console.MissionModelRevisionAPITest do
  @moduledoc """
  U65, the model approval gate over HTTP: a candidate is listed and read by its catalog revision,
  a comparison runs on demand, an organization admin approves against it, a member can't, and
  the decision shows in the organization audit and on the catalog's revision rows.
  """
  use CadenceWeb.ConnCase, async: false

  alias Cadence.Applications.TelemetryDecomFixtures, as: Fixtures
  alias Cadence.TestSupport.CatalogTestActor
  alias CadenceWeb.Console.Problem
  alias CadenceWeb.TestFixtures

  setup do
    org = TestFixtures.persist_org!()
    admin = TestFixtures.persist_user!(display_name: "Ana R.")
    member = TestFixtures.persist_user!(display_name: "Mira K.")
    TestFixtures.grant_membership!(admin, org, role: :organization_admin)
    TestFixtures.grant_membership!(member, org, role: :member)
    mission = TestFixtures.persist_mission!(org)

    {:ok, _activation} =
      Cadence.Activations.record_binding_set_activation(
        org.organization_id,
        mission.mission_id,
        "gate-binding",
        1,
        binding_set_content_sha256: String.duplicate("0", 64)
      )

    revision =
      Fixtures.persist_imported_revision!(org.organization_id, mission.mission_id, approve: false)

    %{
      org: org,
      admin: admin,
      member: member,
      mission: mission,
      revision: revision.mission_model_revision_id,
      artifact_id: revision.artifact_id,
      base: "/api/console/v1/missions/#{mission.mission_id}"
    }
  end

  defp get_as(c, user, path), do: user |> TestFixtures.member_conn() |> get(c.base <> path)

  defp post_as(c, user, path, body),
    do: user |> TestFixtures.member_conn() |> post(c.base <> path, body)

  test "a candidate is listed and read by its catalog revision; the admin may decide", c do
    assert [
             %{"id" => id, "status" => "candidate", "catalog_revision" => %{"number" => number}} =
               row
           ] =
             c
             |> get_as(c.admin, "/mission-model-revisions")
             |> json_response(200)
             |> get_in(["data", "revisions"])

    assert id == c.revision
    assert is_integer(number)
    assert row["latest_comparison_status"] == nil

    read =
      c
      |> get_as(c.admin, "/mission-model-revisions/#{id}")
      |> json_response(200)
      |> Map.fetch!("data")

    assert %{
             "status" => "candidate",
             "comparison" => nil,
             "decision" => nil,
             "catalog_revision" => %{"number" => ^number, "database_id" => _}
           } = read

    assert read["viewer_can_decide"] == read["plans_ready"]
    assert read["cannot_decide_because"] in [nil, "plans_not_ready"]
    assert read["cannot_approve_because"] == nil
  end

  test "U88: a model revision no catalog revision names can't be approved; Reject stays", c do
    # A second run of the file makes its own model revision and no catalog revision (domain).
    {:ok, run} =
      Cadence.Catalog.start_import_run(
        c.org.organization_id,
        c.mission.mission_id,
        c.artifact_id,
        "cadence_yaml",
        requested_by: CatalogTestActor.system()
      )

    {:ok, %{result_document: %{"mission_model" => %{"revision_id" => orphan}}}} =
      Cadence.Catalog.execute_enqueued_run(run.import_run_id)

    read =
      c
      |> get_as(c.admin, "/mission-model-revisions/#{orphan}")
      |> json_response(200)
      |> Map.fetch!("data")

    assert %{"catalog_revision" => nil, "cannot_approve_because" => "not_in_catalog"} = read
    assert read["cannot_decide_because"] in [nil, "plans_not_ready"]

    assert %{
             "error" => %{
               "code" => "mission_model_revision_not_in_catalog",
               "message" =>
                 "Not approved: the catalog doesn't list this revision. To approve it, import its file as a new catalog revision."
             }
           } =
             build_conn()
             |> Problem.respond(:mission_model_revision_not_in_catalog)
             |> json_response(409)
  end

  test "compare, then approve against it; the decision reads back and reaches the audit", c do
    path = "/mission-model-revisions/#{c.revision}"

    cmp =
      c
      |> post_as(c.admin, path <> "/comparison", %{})
      |> json_response(201)
      |> Map.fetch!("data")

    assert %{
             "report_id" => report_id,
             "passed" => true,
             "replay" => %{"status" => replay, "cases" => 0, "failed_cases" => []},
             "totals" => %{"added" => added},
             "sections" => [_ | _]
           } = cmp

    assert replay in ["not_run", "not_required"]
    assert added > 0

    read = c |> get_as(c.admin, path) |> json_response(200) |> Map.fetch!("data")
    assert read["comparison"]["report_id"] == report_id

    assert read["plans_ready"] == true

    approved =
      c
      |> post_as(c.admin, path <> "/approve", %{"comparison_report_id" => report_id})
      |> json_response(200)
      |> Map.fetch!("data")

    assert %{
             "status" => "approved",
             "decision" => %{"kind" => "approved", "report_id" => ^report_id}
           } =
             approved

    assert approved["decision"]["by"]["id"] == c.admin.user_id

    actions =
      c.admin
      |> TestFixtures.member_conn()
      |> get("/api/console/v1/organizations/#{c.org.organization_id}/audit")
      |> json_response(200)
      |> get_in(["data", "events"])
      |> Enum.map(& &1["action"])

    assert Enum.any?(actions, &String.starts_with?(&1, "Approved catalog rev "))
  end

  test "U90: a mission's first revision compares with nothing earlier and can be approved", c do
    # No activation in this mission: nothing runs yet, so there's no binding set (domain/lead 11-17).
    mission = TestFixtures.persist_mission!(c.org)
    importer = TestFixtures.persist_user!(display_name: "Ivo P.")
    TestFixtures.grant_membership!(importer, c.org, role: :organization_admin)

    revision =
      Fixtures.persist_imported_revision!(c.org.organization_id, mission.mission_id,
        approve: false,
        requested_by: %{"actor_kind" => "user", "user_id" => importer.user_id, "name" => "Ivo P."}
      ).mission_model_revision_id

    path = "/api/console/v1/missions/#{mission.mission_id}/mission-model-revisions/#{revision}"

    post_to = fn user, suffix, body ->
      user |> TestFixtures.member_conn() |> post(path <> suffix, body)
    end

    cmp = c.admin |> post_to.("/comparison", %{}) |> json_response(201) |> Map.fetch!("data")

    assert %{"report_id" => report_id, "against" => nil, "replay" => %{"status" => "not_run"}} =
             cmp

    assert cmp["totals"]["added"] > 0

    assert %{"error" => %{"code" => "mission_model_self_approval_forbidden"}} =
             importer
             |> post_to.("/approve", %{"comparison_report_id" => report_id})
             |> json_response(403)

    assert %{"status" => "approved"} =
             c.admin
             |> post_to.("/approve", %{"comparison_report_id" => report_id})
             |> json_response(200)
             |> Map.fetch!("data")

    actions =
      c.admin
      |> TestFixtures.member_conn()
      |> get("/api/console/v1/organizations/#{c.org.organization_id}/audit")
      |> json_response(200)
      |> get_in(["data", "events"])
      |> Enum.map(& &1["action"])

    assert Enum.any?(
             actions,
             &(&1 =~
                 ~r/^Approved catalog rev \d+ \(not compared: no earlier configuration; replay not run\)$/)
           )
  end

  test "a member reads but can't decide; approve needs a report that exists", c do
    path = "/mission-model-revisions/#{c.revision}"
    read = c |> get_as(c.member, path) |> json_response(200) |> Map.fetch!("data")
    assert %{"viewer_can_decide" => false, "cannot_decide_because" => "not_admin"} = read

    assert %{"error" => %{"code" => "forbidden"}} =
             c
             |> post_as(c.member, path <> "/approve", %{"comparison_report_id" => "x"})
             |> json_response(403)

    assert %{"error" => %{"code" => "invalid_params"}} =
             c |> post_as(c.admin, path <> "/approve", %{}) |> json_response(422)

    assert %{"error" => %{"code" => code}} =
             c
             |> post_as(c.admin, path <> "/approve", %{"comparison_report_id" => "nope"})
             |> json_response(404)

    assert code == "mission_model_comparison_report_not_found"

    assert %{"error" => %{"code" => "mission_model_revision_not_found"}} =
             c |> get_as(c.admin, "/mission-model-revisions/nope") |> json_response(404)
  end

  test "the catalog's revision rows carry their model and its approval status (row tag)", c do
    read =
      c
      |> get_as(c.admin, "/mission-model-revisions/#{c.revision}")
      |> json_response(200)
      |> Map.fetch!("data")

    db = read["catalog_revision"]["database_id"]

    revisions =
      c
      |> get_as(c.admin, "/catalog?database_id=#{db}")
      |> json_response(200)
      |> get_in(["data", "database", "revisions"])

    assert [%{"model" => %{"revision_id" => id, "status" => "candidate"}} = row | _] = revisions
    assert id == c.revision
    # D2 (#543): and the id of the composition behind that model (the import's own).
    assert %{"composition_id" => "mission_model_composition:" <> _} = row
  end

  test "reject needs a reason, records it, reaches the audit, and only a candidate can be rejected",
       c do
    path = "/mission-model-revisions/#{c.revision}/reject"

    assert %{"error" => %{"code" => "mission_model_decision_reason_required"}} =
             c |> post_as(c.admin, path, %{"reason" => "  "}) |> json_response(422)

    rejected =
      c
      |> post_as(c.admin, path, %{"reason" => "Wrong FSW build."})
      |> json_response(200)
      |> Map.fetch!("data")

    assert %{
             "status" => "rejected",
             "decision" => %{"kind" => "rejected", "reason" => "Wrong FSW build."}
           } = rejected

    assert %{"error" => %{"code" => "mission_model_revision_not_approvable"}} =
             c |> post_as(c.admin, path, %{"reason" => "Again"}) |> json_response(409)

    events =
      c.admin
      |> TestFixtures.member_conn()
      |> get("/api/console/v1/organizations/#{c.org.organization_id}/audit")
      |> json_response(200)
      |> get_in(["data", "events"])

    assert %{"reason" => "Wrong FSW build.", "target" => %{"kind" => "mission_model_revision"}} =
             Enum.find(events, &String.starts_with?(&1["action"], "Rejected catalog rev "))
  end
end
