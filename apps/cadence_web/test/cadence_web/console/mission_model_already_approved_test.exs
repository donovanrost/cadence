defmodule CadenceWeb.Console.MissionModelAlreadyApprovedTest do
  @moduledoc """
  #260: approving an already approved mission-model revision records nothing and says so. The
  separation check runs first (the importer gets its refusal); the same operation by the same
  approver against the same report replays the original 200 with `replayed: true`; anything else
  answers `409 mission_model_revision_already_approved {decided_by, decided_at}` (both or neither;
  the decider named by C1, never an email).
  """
  use CadenceWeb.ConnCase, async: false

  import Ecto.Query

  alias Cadence.Accounts.OrganizationMembershipRow
  alias Cadence.Applications.TelemetryDecomFixtures, as: Fixtures
  alias Cadence.Auth.Scope
  alias Cadence.Governance.ActivationPolicy
  alias Cadence.MissionModels.RevisionRow
  alias Cadence.Repo
  alias CadenceWeb.TestFixtures

  setup do
    org = TestFixtures.persist_org!()
    importer = TestFixtures.persist_user!(display_name: "Ivo P.")
    approver = TestFixtures.persist_user!(display_name: "Ana R.")
    third = TestFixtures.persist_user!(display_name: "Bea T.")

    memberships =
      for user <- [importer, approver, third],
          do: TestFixtures.grant_membership!(user, org, role: :organization_admin)

    # No activation: a mission's first revision compares with nothing earlier (U90).
    mission = TestFixtures.persist_mission!(org)

    revision =
      Fixtures.persist_imported_revision!(org.organization_id, mission.mission_id,
        approve: false,
        requested_by: %{"actor_kind" => "user", "user_id" => importer.user_id, "name" => "Ivo P."}
      )

    c = %{
      org: org,
      importer: importer,
      importer_membership: hd(memberships),
      approver: approver,
      third: third,
      mission: mission,
      revision: revision.mission_model_revision_id,
      path:
        "/api/v1/missions/#{mission.mission_id}/mission-model-revisions/#{revision.mission_model_revision_id}"
    }

    Map.put(c, :report_id, compare!(c, approver))
  end

  describe "an approved revision (the approver's op-1)" do
    setup c do
      body = %{"comparison_report_id" => c.report_id, "operation_id" => "op-1"}
      first = c |> approve(c.approver, body) |> json_response(200) |> Map.fetch!("data")
      assert %{"status" => "approved", "replayed" => false} = first
      %{body: body, first: first, stored: stored(c)}
    end

    test "the importer approving again is refused as the importer, never told who approved", c do
      conn = approve(c, c.importer, %{"comparison_report_id" => c.report_id})
      error = json_response(conn, 403)["error"]
      assert error["code"] == "mission_model_self_approval_forbidden"
      refute inspect(error) =~ c.approver.user_id
      assert stored(c) == c.stored
    end

    test "another admin gets 409 with who decided (C1) and when, and nothing is written", c do
      conn = approve(c, c.third, %{c.body | "operation_id" => "op-third"})

      assert %{
               "code" => "mission_model_revision_already_approved",
               "details" => %{"decided_by" => decided_by, "decided_at" => decided_at}
             } = json_response(conn, 409)["error"]

      assert decided_by == %{"id" => c.approver.user_id, "name" => "Ana R."}
      assert decided_at == DateTime.to_iso8601(c.stored.approved_at)
      refute inspect(json_response(conn, 409)) =~ c.approver.email
      assert stored(c) == c.stored
    end

    test "the same operation, approver and report replay the 200 with replayed: true", c do
      again = c |> approve(c.approver, c.body) |> json_response(200) |> Map.fetch!("data")

      assert again["replayed"] == true
      assert Map.delete(again, "replayed") == Map.delete(c.first, "replayed")
      assert stored(c) == c.stored
    end

    test "anything else is 409: the op id from another admin, a new op id, or none", c do
      for {user, body} <- [
            {c.third, c.body},
            {c.approver, %{c.body | "operation_id" => "op-2"}},
            {c.approver, Map.delete(c.body, "operation_id")},
            {c.approver, %{c.body | "comparison_report_id" => "another-report"}}
          ] do
        assert json_response(approve(c, user, body), 409)["error"]["code"] ==
                 "mission_model_revision_already_approved"
      end

      assert stored(c) == c.stored
    end

    test "an approver no longer a member reads with no id or name; the time stays", c do
      {1, _} =
        Repo.update_all(
          from(m in OrganizationMembershipRow, where: m.user_id == ^c.approver.user_id),
          set: [lifecycle_state: "removed"]
        )

      details = json_response(approve(c, c.third, c.body), 409)["error"]["details"]
      assert details["decided_by"] == %{"id" => nil, "name" => nil}
      assert is_binary(details["decided_at"])
      refute inspect(details) =~ c.approver.email
    end

    test "an approval with no approver on record: both fields null", c do
      {1, _} =
        Repo.update_all(
          from(r in RevisionRow, where: r.revision_id == ^c.revision),
          set: [approved_by: %{}]
        )

      details = json_response(approve(c, c.third, c.body), 409)["error"]["details"]
      assert details == %{"decided_by" => nil, "decided_at" => nil}
    end
  end

  test "an op id is matched only against this revision's own approval", c do
    body = %{"comparison_report_id" => c.report_id, "operation_id" => "op-1"}
    assert json_response(approve(c, c.approver, body), 200)

    # Another revision (another mission's), already approved: op-1 is this revision's, not its.
    mission = TestFixtures.persist_mission!(c.org)
    other = Fixtures.persist_imported_revision!(c.org.organization_id, mission.mission_id)

    other_path =
      "/api/v1/missions/#{mission.mission_id}/mission-model-revisions/" <>
        other.mission_model_revision_id

    conn = c.approver |> TestFixtures.member_conn() |> post(other_path <> "/approve", body)
    assert json_response(conn, 409)["error"]["code"] == "mission_model_revision_already_approved"
  end

  test "the importer's own approval under 'direct' isn't replayed once the mission is independent",
       c do
    set_requirement!(c, "direct")
    body = %{"comparison_report_id" => c.report_id, "operation_id" => "op-own"}
    assert json_response(approve(c, c.importer, body), 200)

    set_requirement!(c, "independent")

    assert json_response(approve(c, c.importer, body), 403)["error"]["code"] ==
             "mission_model_self_approval_forbidden"
  end

  test "a junk operation id is 422, not stored", c do
    body = %{"comparison_report_id" => c.report_id, "operation_id" => String.duplicate("x", 121)}
    assert json_response(approve(c, c.approver, body), 422)["error"]["code"] == "invalid_params"
    assert stored(c).approved_by == nil
  end

  defp approve(c, user, body),
    do: user |> TestFixtures.member_conn() |> post(c.path <> "/approve", body)

  defp compare!(c, user) do
    user
    |> TestFixtures.member_conn()
    |> post(c.path <> "/comparison", %{})
    |> json_response(201)
    |> get_in(["data", "report_id"])
  end

  defp stored(c) do
    Repo.one(
      from(r in RevisionRow,
        where: r.revision_id == ^c.revision,
        select: %{status: r.status, approved_by: r.approved_by, approved_at: r.approved_at}
      )
    )
  end

  defp set_requirement!(c, requirement) do
    scope =
      Scope.new(%{
        user: c.importer,
        organization_id: c.org.organization_id,
        organization_membership: c.importer_membership
      })

    policy = ActivationPolicy.load(c.org.organization_id, c.mission.mission_id)

    {:ok, _saved} =
      ActivationPolicy.save(scope, c.mission.mission_id, policy.token, %{
        "value" => %{"approval_requirement" => requirement}
      })
  end
end
