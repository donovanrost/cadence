defmodule Cadence.ContactPlanning.ProjectionRaceTest do
  @moduledoc """
  #279 (folded into #273): two projections of one plan's execution state could interleave so that
  an OLDER read of the items landed last: execute's final projection read an item still
  uncertain, a booking_settled projection read it reserved and wrote 'reserved', then the older
  read wrote 'partially_reserved' over it (11-20's plan: 40/40 reserved, read as 39 + 1).
  `project_plan/5` now takes the plan row lock BEFORE reading the items, in one transaction with
  the write, so the later projection always reads what the earlier one committed.

  The interleaving needs real, separate database sessions: under the test sandbox every process
  shares one connection, and a row lock never blocks its own session. So, as
  `StageConcurrencyTest` does, every database step runs in a task with its own connection OUTSIDE
  the sandbox (`Sandbox.checkout(Repo, sandbox: false)`). The fixture is committed under per-run
  unique ids and deleted in `on_exit`, which runs even when an assertion fails. The order is forced
  with a held lock and message barriers, never with sleeps.
  """
  use Cadence.DataCase, async: false

  @moduletag :unboxed_concurrency

  import Ecto.Query

  alias Cadence.ContactPlanExecutionFixtures, as: Fixtures
  alias Cadence.ContactPlanning.{ContactPlanExecutions, ContactPlans}
  alias Cadence.Control.Contacts.Store.ContactPlanExecutionItemRow
  alias Cadence.Management.Contacts.Store.ContactPlanRow
  alias Ecto.Adapters.SQL
  alias Ecto.Adapters.SQL.Sandbox

  setup do
    c = run(fn -> Fixtures.setup_plan() end)
    on_exit(fn -> delete_organization!(c.organization_id) end)
    c
  end

  test "a projection reads the items only after taking the plan lock, so an older read can't land last",
       c do
    [first, second] = items(c)
    set_state!(first, "failed")
    test_pid = self()

    # H holds the plan row lock, as a concurrent projection mid-write would.
    holder =
      independent(fn ->
        Repo.transaction(fn ->
          {:ok, _plan, _version} =
            ContactPlans.fetch_locked(c.organization_id, c.mission_id, c.plan.contact_plan_id)

          send(test_pid, {:locked, self()})

          receive do
            :release -> :ok
          end
        end)
      end)

    assert_receive {:locked, holder_pid}, 5_000

    # A projects while H holds the lock. With the fix A waits for the lock BEFORE reading the
    # items; without it A reads [failed, pending] now and only waits at its write.
    projecting =
      independent(fn ->
        ContactPlanExecutions.project_plan(
          c.organization_id,
          c.mission_id,
          c.plan.contact_plan_id,
          c.plan.approved_version,
          now: DateTime.add(Fixtures.now(), 5, :second)
        )
      end)

    assert Task.yield(projecting, 500) == nil, "the projection must wait for the plan lock"

    # The other item finishes and commits while A waits: the plan is now [failed, failed].
    set_state!(second, "failed")
    send(holder_pid, :release)
    assert {:ok, _} = Task.await(holder)

    assert {:ok, plan, projected_items} = Task.await(projecting, 10_000)
    assert Enum.map(projected_items, & &1.lifecycle_state) == [:failed, :failed]
    assert plan.lifecycle_state == :failed
    assert stored_state(c) == "failed"
  end

  defp items(c) do
    run(fn ->
      ContactPlanExecutions.list(
        c.organization_id,
        c.mission_id,
        c.plan.contact_plan_id,
        c.plan.approved_version
      )
    end)
    |> Enum.sort_by(& &1.contact_plan_execution_item_id)
  end

  defp set_state!(item, state) do
    run(fn ->
      {1, _} =
        Repo.update_all(
          from(row in ContactPlanExecutionItemRow,
            where: row.contact_plan_execution_item_id == ^item.contact_plan_execution_item_id
          ),
          set: [lifecycle_state: state, updated_at: DateTime.utc_now()]
        )
    end)
  end

  defp stored_state(c) do
    run(fn ->
      Repo.one!(
        from(row in ContactPlanRow,
          where: row.contact_plan_id == ^c.plan.contact_plan_id,
          select: row.lifecycle_state
        )
      )
    end)
  end

  # A task with its own connection OUTSIDE the sandbox (StageConcurrencyTest's pattern): what it
  # writes is committed and visible to every other session.
  defp independent(operation) do
    Task.async(fn ->
      :ok = Sandbox.checkout(Repo, sandbox: false)

      try do
        operation.()
      after
        Sandbox.checkin(Repo)
      end
    end)
  end

  defp run(operation), do: operation |> independent() |> Task.await(30_000)

  # Everything the fixture committed carries this run's unique organization id. Delete it from
  # every table with that column, retrying a table whose foreign keys still point at it until a
  # pass deletes nothing more (at most 12 passes). Each delete runs on its own connection: a
  # foreign-key refusal can drop the connection it ran on, never the cleanup.
  defp delete_organization!(organization_id) do
    tables =
      run(fn ->
        SQL.query!(
          Repo,
          "SELECT table_name FROM information_schema.columns " <>
            "WHERE table_schema = 'public' AND column_name = 'organization_id' " <>
            "AND table_name NOT LIKE 'schema_%'",
          []
        ).rows
      end)
      |> List.flatten()

    Enum.reduce_while(1..12, tables, fn _pass, remaining ->
      left = Enum.reject(remaining, &deleted?(&1, organization_id))
      if left == [] or left == remaining, do: {:halt, left}, else: {:cont, left}
    end)
    |> case do
      [] -> :ok
      left -> flunk("cleanup left rows of #{organization_id} in: #{Enum.join(left, ", ")}")
    end
  end

  # Non-raising: a foreign-key refusal is an answer ("not yet"), not an exception that would drop
  # the connection mid-cleanup.
  defp deleted?(table, organization_id) do
    run(fn ->
      match?(
        {:ok, _},
        Repo.query(~s(DELETE FROM "#{table}" WHERE organization_id = $1), [organization_id])
      )
    end)
  end
end
