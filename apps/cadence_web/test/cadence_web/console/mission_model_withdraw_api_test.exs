defmodule CadenceWeb.Console.MissionModelWithdrawAPITest do
  @moduledoc """
  E2 (#546; U109 "Withdrawing an approval"): `POST …/mission-model-revisions/:id/withdraw
  {reason, operation_id}` answers the revision read (console's contract on #546): `status:
  "withdrawn"`, `decision: {kind: "withdrawn", by, at, report_id: null, reason}`, and
  `viewer_can_withdraw` on every revision read.
  """
  use CadenceWeb.ConnCase, async: false

  import Ecto.Query

  alias Cadence.Applications.TelemetryDecomFixtures, as: Fixtures
  alias Cadence.MissionModels.RevisionRow
  alias Cadence.Repo
  alias CadenceWeb.TestFixtures

  setup do
    org = TestFixtures.persist_org!()
    admin = TestFixtures.persist_user!(display_name: "Ana R.")
    member = TestFixtures.persist_user!(display_name: "Bea T.")
    TestFixtures.grant_membership!(admin, org, role: :organization_admin)
    TestFixtures.grant_membership!(member, org)
    mission = TestFixtures.persist_mission!(org)

    revision =
      Fixtures.persist_imported_revision!(org.organization_id, mission.mission_id, approve: true)

    path =
      "/api/v1/missions/#{mission.mission_id}/mission-model-revisions/#{revision.mission_model_revision_id}"

    %{admin: admin, member: member, mission: mission, revision: revision, path: path}
  end

  defp withdraw(user, c, body),
    do: user |> TestFixtures.member_conn() |> post(c.path <> "/withdraw", body)

  defp read(user, c),
    do:
      user
      |> TestFixtures.member_conn()
      |> get(c.path)
      |> json_response(200)
      |> Map.fetch!("data")

  test "an admin sees Withdraw on an approved revision; a member doesn't", c do
    assert %{"status" => "approved", "viewer_can_withdraw" => true} = read(c.admin, c)
    assert %{"viewer_can_withdraw" => false} = read(c.member, c)
  end

  test "withdrawing answers the revision read with the withdrawn decision; a retry replays", c do
    body = %{"reason" => "Limits were wrong", "operation_id" => "op-1"}
    data = c.admin |> withdraw(c, body) |> json_response(200) |> Map.fetch!("data")

    assert %{
             "status" => "withdrawn",
             "viewer_can_withdraw" => false,
             "replayed" => false,
             "decision" => %{
               "kind" => "withdrawn",
               "by" => %{"id" => admin_id},
               "at" => at,
               "report_id" => nil,
               "reason" => "Limits were wrong"
             }
           } = data

    assert admin_id == c.admin.user_id
    assert is_binary(at)

    assert %{"replayed" => true, "status" => "withdrawn"} =
             c.admin |> withdraw(c, body) |> json_response(200) |> Map.fetch!("data")

    assert %{"error" => %{"code" => "mission_model_revision_not_withdrawable"}} =
             c.admin
             |> withdraw(c, %{body | "operation_id" => "op-2"})
             |> json_response(409)
  end

  test "refusals: no reason, not an admin, not approved", c do
    assert %{"error" => %{"code" => "mission_model_decision_reason_required"}} =
             c.admin |> withdraw(c, %{"reason" => "  "}) |> json_response(422)

    assert %{"error" => %{"code" => "forbidden"}} =
             c.member |> withdraw(c, %{"reason" => "Not mine"}) |> json_response(403)

    Repo.update_all(
      where(RevisionRow, revision_id: ^c.revision.mission_model_revision_id),
      set: [status: "candidate"]
    )

    assert %{"error" => %{"code" => "mission_model_revision_not_withdrawable"}} =
             c.admin |> withdraw(c, %{"reason" => "Too early"}) |> json_response(409)
  end
end
