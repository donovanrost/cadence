defmodule CadenceWeb.Console.ContactPlanApproveHardeningTest do
  @moduledoc """
  #278 (ca-security's #257 post-landing review). F2: the approver is authorized before the
  operation check, so only someone who may approve now gets an approval's answer, a replay
  included. F3: the plans update is published once, after the commit, and only for a new
  approval. (F4, no email in refusal details, is #466's: `contact_plan_old_actor_rows_test.exs`.)
  """

  use CadenceWeb.ConnCase, async: false

  import Ecto.Query

  alias Cadence.Accounts.OrganizationMembershipRow
  alias Cadence.Auth.Scope
  alias Cadence.ContactPlanning.{ContactPlanApprovals, ContactPlans, PlanOperations}
  alias Cadence.Control.Scheduling
  alias Cadence.Platform.ScopedReadUpdates
  alias Cadence.Repo
  alias CadenceWeb.Console.SchedulingRunner
  alias CadenceWeb.{ContactPlanningFixtures, TestFixtures}

  setup do
    org = TestFixtures.persist_org!()
    admin = TestFixtures.persist_user!(display_name: "Ada")
    member = TestFixtures.persist_user!(display_name: "Mira")
    admin_membership = TestFixtures.grant_membership!(admin, org, role: :organization_admin)
    member_membership = TestFixtures.grant_membership!(member, org, role: :member)
    mission = TestFixtures.persist_mission!(org)
    :ok = SchedulingRunner.subscribe(mission.mission_id)

    plan_id =
      ContactPlanningFixtures.plan_fixture(org, member, member_membership, mission).plan.contact_plan_id

    c = %{
      org: org,
      mission: mission,
      admin: admin,
      member: member,
      admin_membership: admin_membership,
      plan_id: plan_id,
      base: "/api/v1/missions/#{mission.mission_id}/contact-plans"
    }

    post_as(c, member, "submit", %{"operation_id" => "op-submit", "expected_version" => 1})
    |> json_response(200)

    c
  end

  describe "F2: authorized before the operation check" do
    test "an admin demoted after approving gets 403 on a replay, not their earlier 202", c do
      body = %{"operation_id" => "op-approve", "expected_version" => 1}
      assert json_response(post_as(c, c.admin, "approve", body), 202)
      await_execution(c.plan_id)

      demote!(c.admin, c.org)

      conn = post_as(c, c.admin, "approve", body)
      assert %{"code" => "forbidden"} = json_response(conn, 403)["error"]
      assert length(approvals(c)) == 1
      assert length(operations(c, "op-approve")) == 1
    end

    test "a member reusing a known operation id gets 403, not 409", c do
      body = %{"operation_id" => "op-approve", "expected_version" => 1}
      assert json_response(post_as(c, c.admin, "approve", body), 202)
      await_execution(c.plan_id)

      conn = post_as(c, c.member, "approve", %{body | "operation_id" => "op-approve"})
      assert %{"code" => "forbidden"} = json_response(conn, 403)["error"]
    end
  end

  describe "F3: the update goes out after the commit, once" do
    setup c do
      ScopedReadUpdates.subscribe(
        :contact_plans_changed,
        c.org.organization_id,
        c.mission.mission_id
      )

      # The setup's submit publishes once more ~1 s later (from inside its transaction); let it pass.
      settle()
      :ok
    end

    test "a new approval publishes right after the commit; a replay publishes nothing", c do
      # Straight to the Control path, so no execution starts (its own updates would mask this).
      params = %{operation_id: "op-approve", expected_version: 1}

      assert {:ok, {:approved, _answer, 1, _sha}} =
               Scheduling.approve_plan(admin_scope(c), c.mission.mission_id, c.plan_id, params)

      # From inside the approve's transaction the publish was only scheduled (1 s later); after the
      # commit it goes straight out.
      assert_receive {:contact_plans_changed, _, _}, 500
      settle()

      assert {:ok, {:replayed, _answer}} =
               Scheduling.approve_plan(admin_scope(c), c.mission.mission_id, c.plan_id, params)

      refute_receive {:contact_plans_changed, _, _}, 1_500
    end

    test "a replay through the console publishes nothing", c do
      body = %{"operation_id" => "op-approve", "expected_version" => 1}
      assert json_response(post_as(c, c.admin, "approve", body), 202)
      await_execution(c.plan_id)
      settle()

      assert json_response(post_as(c, c.admin, "approve", body), 202)["data"]["replayed"]
      refute_receive {:contact_plans_changed, _, _}, 1_500
    end

    test "an approve deferred with publish: false announces nothing when its transaction rolls back",
         c do
      {:ok, _plan, version} =
        ContactPlans.fetch(c.org.organization_id, c.mission.mission_id, c.plan_id)

      assert {:error, :rolled_back} =
               Repo.transaction(fn ->
                 assert {:ok, _plan, _version, _approval} =
                          ContactPlanApprovals.approve(
                            admin_scope(c),
                            c.mission.mission_id,
                            c.plan_id,
                            version.version,
                            version.content_sha256,
                            "Checked",
                            publish: false
                          )

                 Repo.rollback(:rolled_back)
               end)

      refute_receive {:contact_plans_changed, _, _}, 1_500
      assert approvals(c) == []
    end
  end

  defp admin_scope(c) do
    Scope.new(%{
      user: c.admin,
      organization_id: c.org.organization_id,
      organization_membership: c.admin_membership
    })
  end

  defp demote!(user, org) do
    {1, _} =
      Repo.update_all(
        from(m in OrganizationMembershipRow,
          where: m.user_id == ^user.user_id and m.organization_id == ^org.organization_id
        ),
        set: [role: "member"]
      )
  end

  defp post_as(c, user, action, body),
    do: user |> TestFixtures.member_conn() |> post("#{c.base}/#{c.plan_id}/#{action}", body)

  defp approvals(c),
    do: ContactPlanApprovals.list(c.org.organization_id, c.mission.mission_id, c.plan_id)

  defp operations(c, operation_id) do
    PlanOperations
    |> where(
      [o],
      o.organization_id == ^c.org.organization_id and o.operation_id == ^operation_id
    )
    |> Repo.all()
  end

  # Until no plan update has come for 1.5 s (past PlanUpdates' 1 s in-transaction delay).
  defp settle do
    receive do
      {:contact_plans_changed, _, _} -> settle()
    after
      1_500 -> :ok
    end
  end

  # The fixture route isn't bookable, so execution ends failed, off the request; await it so
  # nothing outlives the test.
  defp await_execution(plan_id) do
    assert_receive {:scheduling_progress, %{kind: :execute, id: ^plan_id, state: final}}
                   when final in [:finished, :failed],
                   30_000
  end
end
