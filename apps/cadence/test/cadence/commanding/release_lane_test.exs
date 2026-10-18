defmodule Cadence.Commanding.ReleaseLaneTest do
  use Cadence.DataCase, async: false
  alias Cadence.Accounts.{OrganizationMembershipRow, UserRow}

  alias Cadence.Commanding.{
    CommandQueueEntryRow,
    CommandRequestRow,
    LifecyclePolicy,
    RequestQueueStore
  }

  alias Cadence.CommandReviewFixtures
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

  test "release claim rejects a lane occupied after the caller's earlier empty-lane check", c do
    {first, second} =
      independent(fn ->
        {:ok, %{queue_entry: one}} = enqueue(c)

        request =
          CommandReviewFixtures.request!(c, %{
            lifecycle_state: :validated,
            hazardous: false,
            critical: false
          })

        {:ok, %{queue_entry: two}} = enqueue(%{c | request: request})

        {:ok, first} =
          RequestQueueStore.fetch_queue_entry_row(c.org, c.mission, one.command_queue_entry_id)

        {:ok, second} =
          RequestQueueStore.fetch_queue_entry_row(c.org, c.mission, two.command_queue_entry_id)

        {first, second}
      end)
      |> Task.await()

    parent = self()

    later =
      independent(fn ->
        :ok =
          LifecyclePolicy.ensure_queue_entry_releaseable(
            second,
            DateTime.utc_now()
          )

        :ok = RequestQueueStore.ensure_lane_not_in_flight(c.org, c.mission, second.queue_lane_key)
        send(parent, {:checked_empty, self()})

        receive do
          :continue ->
            :ok =
              RequestQueueStore.ensure_entry_is_next_release_candidate(second, DateTime.utc_now())

            RequestQueueStore.claim_for_release(second)
        after
          10_000 -> raise "release contender was not continued"
        end
      end)

    assert_receive {:checked_empty, later_pid}, 5_000

    try do
      assert {:ok, _} =
               independent(fn ->
                 :ok =
                   RequestQueueStore.ensure_lane_not_in_flight(
                     c.org,
                     c.mission,
                     first.queue_lane_key
                   )

                 :ok =
                   RequestQueueStore.ensure_entry_is_next_release_candidate(
                     first,
                     DateTime.utc_now()
                   )

                 RequestQueueStore.claim_for_release(first)
               end)
               |> Task.await()

      send(later_pid, :continue)
      result = Task.await(later, 5_000)

      entries =
        independent(fn ->
          RequestQueueStore.list_queue_entries(c.org, c.mission,
            lifecycle_state: :release_pending
          )
        end)
        |> Task.await()

      assert {:error, _} = result
      assert [%{command_queue_entry_id: id}] = entries
      assert id == first.command_queue_entry_id
    after
      send(later_pid, :continue)
      Task.shutdown(later, :brutal_kill)
    end
  end

  test "a newer eligible higher priority entry invalidates the earlier release choice", c do
    result =
      independent(fn ->
        first = queued(c)

        assert :ok ==
                 RequestQueueStore.ensure_entry_is_next_release_candidate(
                   first,
                   DateTime.utc_now()
                 )

        higher =
          CommandReviewFixtures.request!(c, %{
            lifecycle_state: :validated,
            hazardous: false,
            critical: false,
            priority: 1
          })

        second = queued(%{c | request: higher})
        {RequestQueueStore.claim_for_release(first), first, second}
      end)
      |> Task.await()

    {reply, first, second} = result
    assert {:error, {:command_queue_entry_not_next_for_release, first_id, second_id}} = reply
    assert {first_id, second_id} == {first.command_queue_entry_id, second.command_queue_entry_id}

    assert [] ==
             independent(fn ->
               RequestQueueStore.list_queue_entries(c.org, c.mission,
                 lifecycle_state: :release_pending
               )
             end)
             |> Task.await()
  end

  test "a changed prepared request cannot claim its unchanged queue entry", c do
    result =
      independent(fn ->
        queue = queued(c)
        request = Repo.get!(CommandRequestRow, c.request.command_request_id)
        Repo.update!(Ecto.Changeset.change(request, priority: request.priority + 1))
        RequestQueueStore.claim_for_release(queue, expected_request: request)
      end)
      |> Task.await()

    assert result == {:error, :command_release_basis_changed}

    assert [] ==
             independent(fn ->
               RequestQueueStore.list_queue_entries(c.org, c.mission,
                 lifecycle_state: :release_pending
               )
             end)
             |> Task.await()
  end

  test "changed queue routing cannot be claimed using an earlier queue observation", c do
    result =
      independent(fn ->
        queue = queued(c)
        Repo.update!(Ecto.Changeset.change(queue, queue_lane_key: "changed-lane"))
        RequestQueueStore.claim_for_release(queue)
      end)
      |> Task.await()

    assert result == {:error, :command_release_basis_changed}
  end

  test "two concurrent callers can claim the same entry only once", c do
    queue = independent(fn -> queued(c) end) |> Task.await()
    tasks = for _ <- 1..2, do: independent(fn -> RequestQueueStore.claim_for_release(queue) end)
    results = Enum.map(tasks, &Task.await(&1, 5_000))
    assert 1 == Enum.count(results, &match?({:ok, _}, &1))
    assert 1 == Enum.count(results, &match?({:error, _}, &1))
  end

  test "an occupied lane does not prevent a different endpoint from releasing", c do
    result =
      independent(fn ->
        first = queued(c)

        other =
          CommandReviewFixtures.request!(c, %{
            lifecycle_state: :validated,
            hazardous: false,
            critical: false,
            source_endpoint_ref: "independent-endpoint"
          })

        second = queued(%{c | request: other})
        {RequestQueueStore.claim_for_release(first), RequestQueueStore.claim_for_release(second)}
      end)
      |> Task.await()

    assert {{:ok, _}, {:ok, _}} = result
  end

  test "a request canceled behind its row lock cannot obtain a release claim", c do
    queue = independent(fn -> queued(c) end) |> Task.await()
    parent = self()

    holder =
      independent(fn ->
        Repo.transaction(fn ->
          row =
            Repo.one!(
              from(row in CommandRequestRow,
                where: row.command_request_id == ^c.request.command_request_id,
                lock: "FOR UPDATE"
              )
            )

          send(parent, {:held, self()})

          receive do
            :cancel -> Repo.update!(Ecto.Changeset.change(row, lifecycle_state: "canceled"))
          after
            10_000 -> raise "cancel not delivered"
          end
        end)
      end)

    assert_receive {:held, holder_pid}, 5_000

    claimer =
      independent(fn ->
        %{rows: [[pid]]} = SQL.query!(Repo, "SELECT pg_backend_pid()", [])
        send(parent, {:backend, pid})
        RequestQueueStore.claim_for_release(queue)
      end)

    try do
      assert_receive {:backend, pid}, 5_000
      assert wait_for_lock(pid, 300)
      send(holder_pid, :cancel)
      assert {:ok, _} = Task.await(holder, 5_000)

      assert {:error, {:command_request_not_releasable, _, "canceled"}} =
               Task.await(claimer, 5_000)

      assert [] ==
               independent(fn ->
                 RequestQueueStore.list_queue_entries(c.org, c.mission,
                   lifecycle_state: :release_pending
                 )
               end)
               |> Task.await()
    after
      send(holder_pid, :cancel)
      Enum.each([holder, claimer], &Task.shutdown(&1, :brutal_kill))
    end
  end

  defp queued(c) do
    {:ok, %{queue_entry: entry}} = enqueue(c)

    {:ok, row} =
      RequestQueueStore.fetch_queue_entry_row(c.org, c.mission, entry.command_queue_entry_id)

    row
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

  defp enqueue(c),
    do:
      RequestQueueStore.enqueue_request(
        c.org,
        c.mission,
        c.request.command_request_id,
        actor(c),
        []
      )

  defp actor(c), do: %{"actor_kind" => "user", "user_id" => c.user.user_id}

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
