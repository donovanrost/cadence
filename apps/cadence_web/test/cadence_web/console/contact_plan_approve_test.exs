defmodule CadenceWeb.Console.ContactPlanApproveTest do
  @moduledoc """
  #257 (director 11-19): the explicit approve action. Submit only submits; approve is the only
  console path that approves, separation is enforced there, and a request that changes nothing
  answers an error code. A retry of the same request (same operation id, actor and normalized
  body) gets the original answer back with `replayed: true`; anything else on a known operation
  id is refused.
  """

  use CadenceWeb.ConnCase, async: false

  import Ecto.Query

  alias Cadence.ContactPlanning.{ContactPlanApprovals, PlanOperations}
  alias Cadence.Management.Contacts.Store.{ContactOpportunitySnapshotRow, ContactPlanApprovalRow}
  alias Cadence.Repo
  alias CadenceWeb.Console.SchedulingRunner
  alias CadenceWeb.{ContactPlanningFixtures, TestFixtures}

  setup do
    org = TestFixtures.persist_org!()
    admin = TestFixtures.persist_user!(display_name: "Ada")
    second_admin = TestFixtures.persist_user!(display_name: "Bea")
    member = TestFixtures.persist_user!(display_name: "Mira")
    admin_membership = TestFixtures.grant_membership!(admin, org, role: :organization_admin)
    _second = TestFixtures.grant_membership!(second_admin, org, role: :organization_admin)
    member_membership = TestFixtures.grant_membership!(member, org, role: :member)
    mission = TestFixtures.persist_mission!(org)
    :ok = SchedulingRunner.subscribe(mission.mission_id)

    %{
      org: org,
      mission: mission,
      admin: admin,
      second_admin: second_admin,
      member: member,
      admin_membership: admin_membership,
      member_membership: member_membership,
      base: "/api/console/v1/missions/#{mission.mission_id}/contact-plans"
    }
  end

  describe "under 'independent' approval (the default)" do
    test "the 11-19 sequence: a second admin's submit on a member's pending plan is refused " <>
           "and records nothing; approve records the approval",
         c do
      plan_id = member_plan(c)
      submitted = submit!(c, c.member, plan_id, "op-member")
      member_id = c.member.user_id

      # Was a silent 200 with nothing recorded (#257).
      conn = post_as(c, c.admin, plan_id, "submit", %{"operation_id" => "op-admin-submit"})

      assert %{
               "code" => "plan_already_submitted",
               "details" => %{
                 "submitted_by" => %{"id" => ^member_id, "name" => "Mira"},
                 "submitted_at" => submitted_at
               }
             } = json_response(conn, 409)["error"]

      assert is_binary(submitted_at)
      assert approvals(c, plan_id) == []

      conn =
        post_as(c, c.admin, plan_id, "approve", %{
          "expected_version" => submitted["version"],
          "operation_id" => "op-approve",
          "decision_note" => "  Checked the gaps  "
        })

      assert %{"state" => "executing", "outcome" => "approved", "replayed" => false} =
               json_response(conn, 202)["data"]

      await_execution(plan_id)
      admin_id = c.admin.user_id

      assert [%{decision: :approved, actor_id: ^admin_id, reason: "Checked the gaps"}] =
               approvals(c, plan_id)

      # #226(b): the approval records the policy it was decided under.
      assert %{"separation_of_duties" => true} = policy_document(c, plan_id)
    end

    test "the submitter's approve is refused (because: submitted) and records nothing", c do
      plan_id = admin_plan(c)
      submit!(c, c.admin, plan_id, "op-self")

      conn = post_as(c, c.admin, plan_id, "approve", %{"operation_id" => "op-self-approve"})

      assert %{"code" => "contact_plan_self_approval_forbidden", "details" => details} =
               json_response(conn, 403)["error"]

      assert details == %{"because" => "submitted"}
      assert approvals(c, plan_id) == []
      assert plan_state(c, plan_id) == "pending_approval"
    end

    test "the version's author is refused (because: edited) when someone else submitted it", c do
      plan_id = admin_plan(c)
      submit!(c, c.member, plan_id, "op-member")

      conn = post_as(c, c.admin, plan_id, "approve", %{"operation_id" => "op-author"})

      assert %{"code" => "contact_plan_self_approval_forbidden", "details" => details} =
               json_response(conn, 403)["error"]

      assert details == %{"because" => "edited"}
      assert approvals(c, plan_id) == []
    end

    test "a new operation on a decided plan answers 409 plan_not_pending with who and when", c do
      plan_id = member_plan(c)
      submit!(c, c.member, plan_id, "op-member")
      approve!(c, c.admin, plan_id, "op-first")
      admin_id = c.admin.user_id

      conn = post_as(c, c.second_admin, plan_id, "approve", %{"operation_id" => "op-second"})

      assert %{
               "code" => "plan_not_pending",
               "details" => %{
                 "decided_by" => %{"id" => ^admin_id, "name" => "Ada"},
                 "decided_at" => decided_at,
                 "state" => state
               }
             } = json_response(conn, 409)["error"]

      assert is_binary(decided_at)
      refute state in ["draft", "pending_approval"]
      assert length(approvals(c, plan_id)) == 1
    end
  end

  describe "under 'direct' approval" do
    setup c do
      ContactPlanningFixtures.approve_directly!(c.org, c.admin, c.admin_membership, c.mission)
      :ok
    end

    test "an admin's submit only submits (breaking); their own approve then approves", c do
      plan_id = admin_plan(c)
      assert %{"state" => "pending_approval"} = submit!(c, c.admin, plan_id, "op-submit")
      assert approvals(c, plan_id) == []

      approve!(c, c.admin, plan_id, "op-approve")
      assert [%{decision: :approved}] = approvals(c, plan_id)
    end

    test "the plan detail and the plans list say the mission's approval setting", c do
      plan_id = admin_plan(c)
      assert %{"approval_setting" => "direct"} = get_as(c, c.admin, "/#{plan_id}")["data"]

      assert %{"plans" => [%{"approval_setting" => "direct"} | _]} =
               get_as(c, c.admin, "")["data"]
    end
  end

  test "the plan detail reads 'independent' by default", c do
    plan_id = member_plan(c)
    assert %{"approval_setting" => "independent"} = get_as(c, c.member, "/#{plan_id}")["data"]
  end

  describe "replays (director 11-19)" do
    setup c do
      plan_id = member_plan(c)
      submitted = submit!(c, c.member, plan_id, "op-member")
      %{plan_id: plan_id, version: submitted["version"]}
    end

    test "the same request again gets the original answer with replayed: true; " <>
           "whitespace in the note is the same request",
         c do
      body = %{"expected_version" => c.version, "operation_id" => "op-r", "decision_note" => "Ok"}
      first = json_response(post_as(c, c.admin, c.plan_id, "approve", body), 202)["data"]
      await_execution(c.plan_id)

      retry = Map.put(body, "decision_note", "  Ok  ")
      again = json_response(post_as(c, c.admin, c.plan_id, "approve", retry), 202)["data"]

      assert again["replayed"] == true
      assert Map.delete(again, "replayed") == Map.delete(first, "replayed")
      assert length(approvals(c, c.plan_id)) == 1
    end

    test "a different request, or another actor, on a known operation id is 409", c do
      body = %{"expected_version" => c.version, "operation_id" => "op-d", "decision_note" => "Ok"}
      assert json_response(post_as(c, c.admin, c.plan_id, "approve", body), 202)
      await_execution(c.plan_id)

      changed = Map.put(body, "decision_note", "Something else")
      plan_id = c.plan_id

      assert %{"code" => "duplicate_operation", "details" => %{"plan_id" => ^plan_id}} =
               json_response(post_as(c, c.admin, c.plan_id, "approve", changed), 409)["error"]

      assert %{"code" => "duplicate_operation"} =
               json_response(post_as(c, c.second_admin, c.plan_id, "approve", body), 409)["error"]

      # The other action on the same id is a different request too.
      submit_body = Map.delete(body, "decision_note")

      assert %{"code" => "duplicate_operation"} =
               json_response(post_as(c, c.member, c.plan_id, "submit", submit_body), 409)["error"]

      assert length(approvals(c, c.plan_id)) == 1
    end

    test "two concurrent identical approves: one approves, the other replays it", c do
      body = %{"expected_version" => c.version, "operation_id" => "op-c"}

      results =
        [c.admin, c.admin]
        |> Enum.map(fn user ->
          Task.async(fn -> post_as(c, user, c.plan_id, "approve", body) end)
        end)
        |> Enum.map(&Task.await(&1, 30_000))
        |> Enum.map(&{&1.status, json_response(&1, &1.status)["data"]["replayed"]})
        |> Enum.sort()

      assert results == [{202, false}, {202, true}]
      await_execution(c.plan_id)
      assert length(approvals(c, c.plan_id)) == 1
    end

    test "two concurrent different requests on one operation id: one result and one 409", c do
      bodies =
        for note <- ["First", "Second"],
            do: %{
              "expected_version" => c.version,
              "operation_id" => "op-x",
              "decision_note" => note
            }

      statuses =
        bodies
        |> Enum.map(fn body ->
          Task.async(fn -> post_as(c, c.admin, c.plan_id, "approve", body) end)
        end)
        |> Enum.map(&Task.await(&1, 30_000))
        |> Enum.map(& &1.status)
        |> Enum.sort()

      assert statuses == [202, 409]
      await_execution(c.plan_id)
      assert length(approvals(c, c.plan_id)) == 1
    end
  end

  describe "who may approve, and operation ids across plans (api-ops' review)" do
    test "a member's approve is 403 forbidden and records neither an approval nor an operation",
         c do
      plan_id = member_plan(c)
      submit!(c, c.member, plan_id, "op-member")

      conn = post_as(c, c.member, plan_id, "approve", %{"operation_id" => "op-member-approve"})

      assert %{"code" => "forbidden"} = json_response(conn, 403)["error"]
      assert approvals(c, plan_id) == []
      assert operations(c, "op-member-approve") == []
      assert plan_state(c, plan_id) == "pending_approval"
    end

    test "an operation id already used on another plan is 409 operation_conflict", c do
      first = member_plan(c)
      second = member_plan(c)
      submit!(c, c.member, first, "op-shared")

      conn = post_as(c, c.member, second, "submit", %{"operation_id" => "op-shared"})

      assert %{"code" => "operation_conflict"} = json_response(conn, 409)["error"]
      assert [%{contact_plan_id: ^first}] = operations(c, "op-shared")
    end
  end

  describe "closed booking windows (#273)" do
    setup c do
      fixture =
        ContactPlanningFixtures.plan_fixture(c.org, c.member, c.member_membership, c.mission,
          opportunities: 2
        )

      plan_id = fixture.plan.contact_plan_id
      submit!(c, c.member, plan_id, "op-member")
      passes = get_as(c, c.admin, "/#{plan_id}")["data"]["passes"]
      assert length(passes) == 2
      %{plan_id: plan_id, closed: hd(passes)["snapshot_id"]}
    end

    test "the plan read gives the closed set, its digest and when it next changes", c do
      open = get_as(c, c.admin, "/#{c.plan_id}")["data"]

      assert %{"expired" => nil, "expiry_margin_seconds" => 60} = open
      assert open["expired_digest"] =~ ~r/^[0-9a-f]{64}$/
      assert is_binary(open["next_expiry_at"])

      close!(c.closed)
      after_close = get_as(c, c.admin, "/#{c.plan_id}")["data"]
      closed = c.closed

      assert %{
               "count" => 1,
               "reservable_count" => 1,
               "items" => [%{"snapshot_id" => ^closed, "reason" => "opportunity_expired"} = item]
             } = after_close["expired"]

      assert %{"spacecraft" => %{"id" => _}, "aos" => _, "expires_at" => _} = item
      refute after_close["expired_digest"] == open["expired_digest"]
    end

    test "approving with the read's digest leaves the closed pass out, records it and answers it; a replay answers the same",
         c do
      close!(c.closed)
      digest = get_as(c, c.admin, "/#{c.plan_id}")["data"]["expired_digest"]

      body = %{"operation_id" => "op-skip", "expected_expired_digest" => digest}

      data =
        c
        |> post_as(c.admin, c.plan_id, "approve", body)
        |> json_response(202)
        |> Map.fetch!("data")

      await_execution(c.plan_id)
      closed = c.closed

      assert %{"count" => 1, "reservable_count" => 1, "items" => [%{"snapshot_id" => ^closed}]} =
               data["expired"]

      # The decision records exactly that set (the director's condition 1).
      assert [%{decision: :approved, skipped: [%{"snapshot_id" => ^closed}]}] =
               approvals(c, c.plan_id)

      assert %{"skipped" => %{"count" => 1, "items" => [%{"snapshot_id" => ^closed}]}} =
               approved_history_entry(c, c.plan_id)

      replay =
        c
        |> post_as(c.admin, c.plan_id, "approve", body)
        |> json_response(202)
        |> Map.fetch!("data")

      assert replay["replayed"] == true
      assert replay["expired"] == data["expired"]
    end

    test "an older client that sends no digest is refused when a pass has closed, recording nothing",
         c do
      close!(c.closed)
      conn = post_as(c, c.admin, c.plan_id, "approve", %{"operation_id" => "op-old"})

      assert %{
               "code" => "contact_plan_expired_passes_changed",
               "details" => %{"expired" => %{"count" => 1}, "expired_digest" => digest}
             } = json_response(conn, 409)["error"]

      assert digest =~ ~r/^[0-9a-f]{64}$/
      assert approvals(c, c.plan_id) == []
    end

    test "a decision with nothing skipped shows no skipped set in the history", c do
      approve!(c, c.admin, c.plan_id, "op-none")
      assert %{"skipped" => nil} = approved_history_entry(c, c.plan_id)
    end
  end

  test "when every pass's booking window has closed, that refusal comes first (#273)", c do
    plan_id = member_plan(c)
    submit!(c, c.member, plan_id, "op-member")
    [%{"snapshot_id" => only}] = get_as(c, c.admin, "/#{plan_id}")["data"]["passes"]
    close!(only)

    conn = post_as(c, c.admin, plan_id, "approve", %{"operation_id" => "op-all"})

    assert %{
             "code" => "contact_plan_all_opportunities_expired",
             "details" => %{"expired" => %{"count" => 1, "reservable_count" => 0}}
           } = json_response(conn, 409)["error"]

    assert approvals(c, plan_id) == []
  end

  describe "params" do
    test "submit refuses a decision_note (422): approving is its own action", c do
      plan_id = member_plan(c)

      conn =
        post_as(c, c.member, plan_id, "submit", %{
          "operation_id" => "op-note",
          "decision_note" => "Approve it"
        })

      assert %{"code" => "invalid_params", "details" => %{"decision_note" => _}} =
               json_response(conn, 422)["error"]
    end

    test "approve caps the decision note at 2,000 characters", c do
      plan_id = member_plan(c)
      submit!(c, c.member, plan_id, "op-member")

      conn =
        post_as(c, c.admin, plan_id, "approve", %{
          "operation_id" => "op-long",
          "decision_note" => String.duplicate("a", 2_001)
        })

      assert %{"details" => %{"decision_note" => "Keep the note under 2,000 characters."}} =
               json_response(conn, 422)["error"]

      assert approvals(c, plan_id) == []
    end
  end

  defp member_plan(c),
    do:
      ContactPlanningFixtures.plan_fixture(c.org, c.member, c.member_membership, c.mission).plan.contact_plan_id

  defp admin_plan(c),
    do:
      ContactPlanningFixtures.plan_fixture(c.org, c.admin, c.admin_membership, c.mission).plan.contact_plan_id

  defp submit!(c, user, plan_id, operation_id) do
    c
    |> post_as(user, plan_id, "submit", %{"operation_id" => operation_id})
    |> json_response(200)
    |> Map.fetch!("data")
  end

  defp approve!(c, user, plan_id, operation_id) do
    data =
      c
      |> post_as(user, plan_id, "approve", %{"operation_id" => operation_id})
      |> json_response(202)
      |> Map.fetch!("data")

    await_execution(plan_id)
    data
  end

  defp post_as(c, user, plan_id, action, body) do
    body = Map.put_new(body, "expected_version", current_version(c, plan_id))
    user |> TestFixtures.member_conn() |> post("#{c.base}/#{plan_id}/#{action}", body)
  end

  defp get_as(c, user, path),
    do: user |> TestFixtures.member_conn() |> get("#{c.base}#{path}") |> json_response(200)

  defp current_version(c, plan_id), do: get_as(c, c.admin, "/#{plan_id}")["data"]["version"]
  defp plan_state(c, plan_id), do: get_as(c, c.admin, "/#{plan_id}")["data"]["state"]

  defp operations(c, operation_id) do
    PlanOperations
    |> where(
      [o],
      o.organization_id == ^c.org.organization_id and o.mission_id == ^c.mission.mission_id and
        o.operation_id == ^operation_id
    )
    |> Repo.all()
  end

  # #273: the snapshot's offer has expired (before the 60 s margin too).
  defp close!(snapshot_id) do
    past = DateTime.utc_now() |> DateTime.add(-120) |> DateTime.truncate(:microsecond)

    Repo.update_all(
      from(s in ContactOpportunitySnapshotRow,
        where: s.contact_opportunity_snapshot_id == ^snapshot_id
      ),
      set: [expires_at: past]
    )
  end

  defp approved_history_entry(c, plan_id) do
    get_as(c, c.admin, "/#{plan_id}/history")["data"]["decisions"]
    |> Enum.find(&(&1["kind"] == "approved"))
  end

  defp approvals(c, plan_id),
    do: ContactPlanApprovals.list(c.org.organization_id, c.mission.mission_id, plan_id)

  defp policy_document(c, plan_id) do
    ContactPlanApprovalRow
    |> where([a], a.organization_id == ^c.org.organization_id and a.contact_plan_id == ^plan_id)
    |> select([a], a.policy_document)
    |> Repo.one()
  end

  # The fixture route isn't bookable, so execution ends failed, but off the request; await it so
  # nothing outlives the test.
  defp await_execution(plan_id) do
    assert_receive {:scheduling_progress, %{kind: :execute, id: ^plan_id, state: final}}
                   when final in [:finished, :failed],
                   30_000
  end
end
