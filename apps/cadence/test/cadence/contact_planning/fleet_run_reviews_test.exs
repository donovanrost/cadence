defmodule Cadence.ContactPlanning.FleetRunReviewsTest do
  use Cadence.DataCase, async: false

  alias Cadence.ContactPlanning.{
    ContactRequirements,
    FleetPlanningPolicies,
    FleetPlanningRuns,
    FleetRunActions,
    FleetRunLock,
    FleetRunRepairs,
    FleetRunReviews
  }

  alias Cadence.FleetRunFixtures, as: Fixtures
  alias Cadence.Repo
  setup do: Fixtures.setup_run()

  test "scoped review is read-only and continuation requires exact observed evidence", c do
    id = c.run.fleet_planning_run_id
    assert {:ok, review} = FleetRunReviews.load(c.scope, c.mission_id, id)
    assert review.run.phase == :queued
    assert [ref] = review.refs
    assert ref.contact_requirement_id == c.requirement.contact_requirement_id
    params = %{"fleet_planning_run_id" => id, "evidence" => review.evidence}

    assert {:error, :fleet_run_action_invalid} =
             FleetRunActions.execute(
               c.scope,
               c.mission_id,
               :continue,
               Map.delete(params, "evidence")
             )

    assert {:error, :fleet_run_review_changed} =
             FleetRunActions.execute(
               c.scope,
               c.mission_id,
               :continue,
               put_in(params, ["evidence", "sha256"], String.duplicate("a", 64))
             )

    assert {:error, :forbidden} =
             FleetRunActions.execute(
               %{c.scope | organization_membership: nil},
               c.mission_id,
               :continue,
               params
             )

    assert {:ok, unchanged} = FleetPlanningRuns.fetch(c.organization_id, c.mission_id, id)
    assert unchanged == review.run
    assert {:ok, receipt} = FleetRunActions.execute(c.scope, c.mission_id, :continue, params)
    assert receipt["evidence"] == review.evidence
    assert receipt["phase"] == "finished"

    assert {:error, :fleet_run_review_changed} =
             FleetRunActions.execute(c.scope, c.mission_id, :continue, params)
  end

  test "one orchestration session owns a run and releases on callback failure", c do
    parent = self()
    id = c.run.fleet_planning_run_id

    task =
      Task.async(fn ->
        FleetRunLock.with_run(c.organization_id, c.mission_id, id, fn ->
          send(parent, {:locked, self()})

          receive do
            :release -> :released
          end
        end)
      end)

    assert_receive {:locked, owner}, 5000

    assert {:error, :fleet_planning_run_busy} =
             FleetRunLock.with_run(c.organization_id, c.mission_id, id, fn ->
               flunk("A second worker entered")
             end)

    send(owner, :release)
    assert Task.await(task, 5000) == :released

    assert_raise RuntimeError, "release this lock", fn ->
      FleetRunLock.with_run(c.organization_id, c.mission_id, id, fn ->
        raise "release this lock"
      end)
    end

    assert FleetRunLock.with_run(c.organization_id, c.mission_id, id, fn -> :available end) ==
             :available
  end

  test "repair preserves exact commitments and rejects changed execution evidence", c do
    c = Fixtures.repairable(c)
    id = c.run.fleet_planning_run_id
    assert {:ok, snapshot} = FleetRunReviews.load(c.scope, c.mission_id, id)
    assert {:ok, review} = FleetRunRepairs.review(c.scope, snapshot)
    assert length(review.source.locked_commitments) == 1

    params = %{
      "fleet_planning_run_id" => id,
      "evidence" => review.evidence,
      "repair" => %{
        "horizon_start" => "2026-07-17T04:00:00.000Z",
        "horizon_end" => "2026-07-17T08:00:00.000Z"
      }
    }

    Repo.update!(Ecto.Changeset.change(c.execution, lifecycle_state: "reserved"))

    assert {:error, :fleet_repair_review_changed} =
             FleetRunActions.execute(c.scope, c.mission_id, :repair, params)

    assert [_] = FleetPlanningRuns.list(c.organization_id, c.mission_id)
    assert {:ok, updated} = FleetRunRepairs.review(c.scope, snapshot)

    assert {:ok, receipt} =
             FleetRunActions.execute(
               c.scope,
               c.mission_id,
               :repair,
               Map.put(params, "evidence", updated.evidence)
             )

    assert receipt["phase"] == "queued"

    assert {:ok, successor} =
             FleetPlanningRuns.fetch(
               c.organization_id,
               c.mission_id,
               receipt["fleetPlanningRunId"]
             )

    assert successor.source_contact_plan_version == c.result.plan_version.version

    assert [%{"contact_opportunity_snapshot_id" => locked}] =
             successor.input_document["repair"]["locked_commitments"]

    assert locked == c.snapshot_id
    assert successor.input_document["creation_review"] == updated.evidence
  end

  test "changed requirement input prevents continuation before the phase advances", c do
    assert {:ok, review} =
             FleetRunReviews.load(c.scope, c.mission_id, c.run.fleet_planning_run_id)

    assert {:ok, _, _} =
             ContactRequirements.version(
               c.scope,
               c.mission_id,
               c.requirement.contact_requirement_id,
               1,
               %{priority: :critical}
             )

    assert {:error, :fleet_planning_input_drift} =
             FleetRunActions.execute(c.scope, c.mission_id, :continue, %{
               "fleet_planning_run_id" => c.run.fleet_planning_run_id,
               "evidence" => review.evidence
             })

    assert {:ok, run} =
             FleetPlanningRuns.fetch(c.organization_id, c.mission_id, c.run.fleet_planning_run_id)

    assert run.phase == :queued
  end

  test "repair rejects changed active policy and subsecond excess without a successor", c do
    c = Fixtures.repairable(c)
    id = c.run.fleet_planning_run_id
    assert {:ok, snapshot} = FleetRunReviews.load(c.scope, c.mission_id, id)
    assert {:ok, review} = FleetRunRepairs.review(c.scope, snapshot)

    params = %{
      "fleet_planning_run_id" => id,
      "evidence" => review.evidence,
      "repair" => %{
        "horizon_start" => "2026-07-17T04:00:00.000000Z",
        "horizon_end" => "2026-07-17T16:00:00.000001Z"
      }
    }

    assert {:error, :fleet_repair_horizon_exceeded} =
             FleetRunActions.execute(c.scope, c.mission_id, :repair, params)

    attrs = %{
      automation_repair_document:
        Map.put(c.policy_version.automation_repair_document, "max_repair_attempts", 0)
    }

    assert {:ok, _, version} =
             FleetPlanningPolicies.version(
               c.admin,
               c.mission_id,
               c.policy.fleet_planning_policy_id,
               1,
               attrs
             )

    assert {:ok, _, _, _} =
             FleetPlanningPolicies.approve(
               c.admin,
               c.mission_id,
               c.policy.fleet_planning_policy_id,
               version.version,
               version.content_sha256,
               "Pause repair creation"
             )

    params = put_in(params, ["repair", "horizon_end"], "2026-07-17T08:00:00.000000Z")

    assert {:error, :fleet_repair_review_changed} =
             FleetRunActions.execute(c.scope, c.mission_id, :repair, params)

    assert {:ok, current} = FleetRunRepairs.review(c.scope, snapshot)
    refute current.allowed
    assert current.policy.version == 2
    assert [_] = FleetPlanningRuns.list(c.organization_id, c.mission_id)
  end

  test "an exited orchestration owner releases its dedicated session lock", c do
    parent = self()
    id = c.run.fleet_planning_run_id

    owner =
      spawn(fn ->
        FleetRunLock.with_run(c.organization_id, c.mission_id, id, fn ->
          send(parent, :owner_locked)

          receive do
            :never -> :ok
          end
        end)
      end)

    monitor = Process.monitor(owner)
    assert_receive :owner_locked, 5000

    assert FleetRunLock.with_run(c.organization_id, "different-mission", id, fn ->
             :other_scope
           end) == :other_scope

    Process.exit(owner, :kill)
    assert_receive {:DOWN, ^monitor, :process, ^owner, :killed}, 5000
    assert reacquire(c, id, 50) == :released
  end

  defp reacquire(_, _, 0), do: :timed_out

  defp reacquire(c, id, remaining) do
    case FleetRunLock.with_run(c.organization_id, c.mission_id, id, fn -> :released end) do
      :released ->
        :released

      {:error, :fleet_planning_run_busy} ->
        Process.sleep(10)
        reacquire(c, id, remaining - 1)
    end
  end
end
