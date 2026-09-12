defmodule Cadence.Control.Commanding.QueueSubmissionConcurrencyTest do
  use Cadence.DataCase, async: false
  alias Cadence.Accounts.{OrganizationMembershipRow, UserRow}
  alias Cadence.Commanding.{CommandQueueEntryRow, CommandRequestRow, RequestQueueStore}
  alias Cadence.CommandReviewFixtures
  alias Cadence.Control.Commanding.QueueSubmission
  alias Cadence.Missions.MissionRow
  alias Cadence.OperationalEvents.EventRow
  alias Cadence.Organizations.OrganizationRow
  alias Cadence.Projections.MissionEvents.Store.MissionEventRow
  alias Ecto.Adapters.SQL
  alias Ecto.Adapters.SQL.Sandbox

  setup do
    c =
      independent(fn ->
        c = CommandReviewFixtures.scope!()

        request =
          CommandReviewFixtures.request!(c, %{
            lifecycle_state: :validated,
            hazardous: false,
            critical: false
          })

        Map.put(c, :request, request)
      end)
      |> Task.await(10_000)

    on_exit(fn -> independent(fn -> cleanup(c) end) |> Task.await(10_000) end)
    {:ok, c}
  end

  test "queue authorization is refreshed after waiting for the request lock", c do
    {:ok, %{held: held}} =
      independent(fn ->
        QueueSubmission.load(
          c.scope,
          c.mission,
          c.request.command_request_id
        )
      end)
      |> Task.await()

    parent = self()

    holder =
      independent(fn ->
        Repo.transaction(fn ->
          Repo.one!(
            from(row in CommandRequestRow,
              where: row.command_request_id == ^c.request.command_request_id,
              lock: "FOR UPDATE"
            )
          )

          send(parent, {:held, self()})

          receive do
            :release -> :ok
          after
            10_000 -> raise "request lock release missing"
          end
        end)
      end)

    assert_receive {:held, holder_pid}, 5_000

    contender =
      independent(fn ->
        %{rows: [[pid]]} = SQL.query!(Repo, "SELECT pg_backend_pid()", [])
        send(parent, {:backend, pid})

        QueueSubmission.submit(c.scope, c.mission, held, %{
          "expected_queue" => held.token
        })
      end)

    try do
      assert_receive {:backend, pid}, 5_000
      assert wait_for_lock(pid, 300)

      independent(fn ->
        Repo.update_all(
          from(row in OrganizationMembershipRow,
            where: row.organization_id == ^c.org and row.user_id == ^c.user.user_id
          ),
          set: [role: "member"]
        )
      end)
      |> Task.await()

      send(holder_pid, :release)
      assert {:ok, :ok} = Task.await(holder, 5_000)
      assert {:error, :unavailable} = Task.await(contender, 5_000)

      assert [] ==
               independent(fn -> RequestQueueStore.list_queue_entries(c.org, c.mission, []) end)
               |> Task.await()
    after
      send(holder_pid, :release)
      Enum.each([holder, contender], &Task.shutdown(&1, :brutal_kill))
    end
  end

  defp wait_for_lock(_, 0), do: false

  defp wait_for_lock(pid, remaining) do
    %{rows: [[count]]} =
      SQL.query!(
        Repo,
        "SELECT count(*) FROM pg_locks WHERE pid = $1 AND NOT granted",
        [pid]
      )

    if count > 0,
      do: true,
      else:
        (
          Process.sleep(10)
          wait_for_lock(pid, remaining - 1)
        )
  end

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

  defp cleanup(c) do
    for schema <- [CommandQueueEntryRow, CommandRequestRow, EventRow, MissionEventRow, MissionRow] do
      Repo.delete_all(
        from(row in schema, where: row.organization_id == ^c.org and row.mission_id == ^c.mission)
      )
    end

    Repo.delete_all(
      from(row in OrganizationMembershipRow,
        where: row.organization_id == ^c.org and row.user_id == ^c.user.user_id
      )
    )

    Repo.delete_all(from(row in UserRow, where: row.user_id == ^c.user.user_id))
    Repo.delete_all(from(row in OrganizationRow, where: row.organization_id == ^c.org))
  end
end
