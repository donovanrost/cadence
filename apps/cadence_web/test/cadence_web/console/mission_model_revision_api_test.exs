defmodule CadenceWeb.Console.MissionModelRevisionAPITest do
  @moduledoc """
  U65, the model approval gate over HTTP: a candidate is listed and read by its catalog revision,
  a comparison runs on demand, an organization admin approves against it, a member can't, and
  the decision shows in the organization audit and on the catalog's revision rows.
  """
  use CadenceWeb.ConnCase, async: false

  alias Cadence.Applications.TelemetryDecomFixtures, as: Fixtures
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

    assert [%{"model" => %{"revision_id" => id, "status" => "candidate"}} | _] = revisions
    assert id == c.revision
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
