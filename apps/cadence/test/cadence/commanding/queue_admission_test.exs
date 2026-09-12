defmodule Cadence.Commanding.QueueAdmissionTest do
  use Cadence.DataCase, async: false
  alias Ecto.Adapters.SQL
  alias Ecto.Adapters.SQL.Sandbox

  alias Cadence.Accounts.{OrganizationMembershipRow, UserRow}

  alias Cadence.Commanding.{
    CommandQueueEntry,
    CommandQueueEntryRow,
    CommandRequestRow,
    ProcessNamespace,
    RequestQueueStore
  }

  alias Cadence.CommandReviewFixtures
  alias Cadence.Control.Commanding, as: ControlCommanding
  alias Cadence.Management.Commanding.ApprovedCommand
  alias Cadence.Missions.MissionRow
  alias Cadence.OperationalEvents.EventRow
  alias Cadence.Organizations.OrganizationRow
  alias Cadence.Projections.MissionEvents.Store.MissionEventRow

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

  test "cancellation committed while enqueue waits cannot be overwritten by a stale queue decision",
       c do
    parent = self()

    holder =
      independent(fn ->
        Repo.transaction(fn ->
          row =
            Repo.one!(
              from(row in CommandRequestRow,
                where:
                  row.organization_id == ^c.org and row.mission_id == ^c.mission and
                    row.command_request_id == ^c.request.command_request_id,
                lock: "FOR UPDATE"
              )
            )

          send(parent, {:held, self()})

          receive do
            :cancel -> Repo.update!(CommandRequestRow.lifecycle_changeset(row, :canceled))
          after
            10_000 -> raise "request lock release not delivered"
          end
        end)
      end)

    assert_receive {:held, holder_pid}, 5_000

    enqueuer =
      independent(fn ->
        %{rows: [[pid]]} = SQL.query!(Repo, "SELECT pg_backend_pid()", [])
        send(parent, {:backend, pid})
        enqueue(c)
      end)

    try do
      assert_receive {:backend, pid}, 5_000
      assert wait_for_lock(pid, 300)
      send(holder_pid, :cancel)
      assert {:ok, %{lifecycle_state: "canceled"}} = Task.await(holder, 10_000)
      reply = Task.await(enqueuer, 10_000)

      result =
        independent(fn ->
          {Repo.get!(CommandRequestRow, c.request.command_request_id).lifecycle_state,
           Repo.aggregate(
             from(row in CommandQueueEntryRow, where: row.organization_id == ^c.org),
             :count
           )}
        end)
        |> Task.await()

      assert {:error, _} = reply
      assert result == {"canceled", 0}
    after
      send(holder_pid, :cancel)
      Task.shutdown(holder, :brutal_kill)
      Task.shutdown(enqueuer, :brutal_kill)
    end
  end

  test "an earlier persisted sequence from another process stays ahead of a new equal-priority enqueue",
       c do
    {old, result, order} =
      independent(fn ->
        older =
          CommandReviewFixtures.request!(c, %{
            lifecycle_state: :queued,
            hazardous: false,
            critical: false
          })

        entry =
          CommandQueueEntry.new(%{
            organization_id: c.org,
            mission_id: c.mission,
            command_request_id: older.command_request_id,
            source_endpoint_ref: older.source_endpoint_ref,
            queue_lane_key: older.source_endpoint_ref,
            priority: older.priority,
            queue_sequence: 2_000_000_000,
            lifecycle_state: :pending,
            enqueued_by: actor(c),
            enqueued_at: DateTime.add(DateTime.utc_now(), -60, :second)
          })

        row = entry |> CommandQueueEntryRow.changeset() |> Repo.insert!()
        result = enqueue(c)

        order =
          RequestQueueStore.list_queue_entries(c.org, c.mission, [])
          |> Enum.map(& &1.command_request_id)

        {row, result, order}
      end)
      |> Task.await(10_000)

    assert {:ok, %{queue_entry: queued}} = result
    assert queued.queue_sequence > old.queue_sequence
    assert order == [old.command_request_id, c.request.command_request_id]
  end

  test "approved content changed behind the enqueue lock cannot enter the queue", c do
    {:ok, approved} =
      ApprovedCommand.from_automatic_policy(c.request)

    parent = self()

    holder =
      independent(fn ->
        Repo.transaction(fn ->
          row =
            Repo.one!(
              from(row in CommandRequestRow,
                where:
                  row.organization_id == ^c.org and row.mission_id == ^c.mission and
                    row.command_request_id == ^c.request.command_request_id,
                lock: "FOR UPDATE"
              )
            )

          send(parent, {:held, self()})

          receive do
            :change -> Repo.update!(Ecto.Changeset.change(row, priority: row.priority + 1))
          after
            10_000 -> raise "request lock release not delivered"
          end
        end)
      end)

    assert_receive {:held, holder_pid}, 5_000

    enqueuer =
      independent(fn ->
        %{rows: [[pid]]} = SQL.query!(Repo, "SELECT pg_backend_pid()", [])
        send(parent, {:backend, pid})

        namespace = %{
          ProcessNamespace.default()
          | registry: Cadence.QueueAdmissionAbsentRegistry,
            dispatcher: Cadence.QueueAdmissionAbsentDispatcher
        }

        ControlCommanding.enqueue(approved, actor(c), process_namespace: namespace)
      end)

    try do
      assert_receive {:backend, pid}, 5_000
      assert wait_for_lock(pid, 300)
      send(holder_pid, :change)
      assert {:ok, _} = Task.await(holder, 10_000)
      reply = Task.await(enqueuer, 10_000)

      result =
        independent(fn ->
          {Repo.get!(CommandRequestRow, c.request.command_request_id).lifecycle_state,
           Repo.aggregate(
             from(row in CommandQueueEntryRow, where: row.organization_id == ^c.org),
             :count
           )}
        end)
        |> Task.await()

      assert {:error, :approved_command_basis_changed} = reply
      assert result == {"validated", 0}
    after
      send(holder_pid, :change)
      Task.shutdown(holder, :brutal_kill)
      Task.shutdown(enqueuer, :brutal_kill)
    end
  end

  test "concurrent admissions of one request create exactly one entry", c do
    parent = self()

    first =
      independent(fn ->
        RequestQueueStore.enqueue_request(
          c.org,
          c.mission,
          c.request.command_request_id,
          actor(c),
          before_enqueue: fn _ ->
            send(parent, {:admitting, self()})

            receive do
              :continue -> :ok
            after
              10_000 -> {:error, :test_timeout}
            end
          end
        )
      end)

    assert_receive {:admitting, first_pid}, 5_000

    second =
      independent(fn ->
        %{rows: [[pid]]} = SQL.query!(Repo, "SELECT pg_backend_pid()", [])
        send(parent, {:backend, pid})
        enqueue(c)
      end)

    try do
      assert_receive {:backend, pid}, 5_000
      assert wait_for_lock(pid, 300)
      send(first_pid, :continue)
      assert {:ok, _} = Task.await(first, 10_000)
      assert {:error, {:command_request_not_queueable, _, "queued"}} = Task.await(second, 10_000)

      entries =
        independent(fn -> RequestQueueStore.list_queue_entries(c.org, c.mission, []) end)
        |> Task.await()

      assert [%{command_request_id: request_id}] = entries
      assert request_id == c.request.command_request_id
    after
      send(first_pid, :continue)
      Enum.each([first, second], &Task.shutdown(&1, :brutal_kill))
    end
  end

  test "equal-priority lane admissions cannot overtake an uncommitted predecessor", c do
    next =
      independent(fn ->
        CommandReviewFixtures.request!(c, %{
          lifecycle_state: :validated,
          hazardous: false,
          critical: false
        })
      end)
      |> Task.await()

    parent = self()

    first =
      independent(fn ->
        RequestQueueStore.enqueue_request(
          c.org,
          c.mission,
          c.request.command_request_id,
          actor(c),
          before_enqueue: fn _ ->
            send(parent, {:admitting, self()})

            receive do
              :continue -> :ok
            after
              10_000 -> {:error, :test_timeout}
            end
          end
        )
      end)

    assert_receive {:admitting, first_pid}, 5_000

    second =
      independent(fn ->
        %{rows: [[pid]]} = SQL.query!(Repo, "SELECT pg_backend_pid()", [])
        send(parent, {:backend, pid})
        enqueue(%{c | request: next})
      end)

    try do
      assert_receive {:backend, pid}, 5_000
      assert wait_for_lock(pid, 300)

      assert [] ==
               independent(fn -> RequestQueueStore.list_queue_entries(c.org, c.mission, []) end)
               |> Task.await()

      send(first_pid, :continue)
      assert {:ok, %{queue_entry: %{queue_sequence: 1}}} = Task.await(first, 10_000)
      assert {:ok, %{queue_entry: %{queue_sequence: 2}}} = Task.await(second, 10_000)

      order =
        independent(fn ->
          RequestQueueStore.list_queue_entries(c.org, c.mission, [])
          |> Enum.map(& &1.command_request_id)
        end)
        |> Task.await()

      assert order == [c.request.command_request_id, next.command_request_id]
    after
      send(first_pid, :continue)
      Enum.each([first, second], &Task.shutdown(&1, :brutal_kill))
    end
  end

  test "a waiting lane does not stop an independent endpoint lane", c do
    next =
      independent(fn ->
        CommandReviewFixtures.request!(c, %{
          lifecycle_state: :validated,
          hazardous: false,
          critical: false,
          source_endpoint_ref: "independent_endpoint"
        })
      end)
      |> Task.await()

    parent = self()

    first =
      independent(fn ->
        RequestQueueStore.enqueue_request(
          c.org,
          c.mission,
          c.request.command_request_id,
          actor(c),
          before_enqueue: fn _ ->
            send(parent, {:admitting, self()})

            receive do
              :continue -> :ok
            after
              10_000 -> {:error, :test_timeout}
            end
          end
        )
      end)

    assert_receive {:admitting, first_pid}, 5_000

    try do
      assert {:ok, %{queue_entry: %{queue_sequence: 1}}} =
               independent(fn -> enqueue(%{c | request: next}) end) |> Task.await(3_000)

      send(first_pid, :continue)
      assert {:ok, %{queue_entry: %{queue_sequence: 1}}} = Task.await(first, 10_000)
    after
      send(first_pid, :continue)
      Task.shutdown(first, :brutal_kill)
    end
  end

  test "a rejected locked precondition leaves the request and queue unchanged", c do
    result =
      independent(fn ->
        RequestQueueStore.enqueue_request(
          c.org,
          c.mission,
          c.request.command_request_id,
          actor(c),
          before_enqueue: fn _ -> {:error, :access_revoked} end
        )
      end)
      |> Task.await()

    assert result == {:error, :access_revoked}

    assert {"validated", []} ==
             independent(fn ->
               {Repo.get!(CommandRequestRow, c.request.command_request_id).lifecycle_state,
                RequestQueueStore.list_queue_entries(c.org, c.mission, [])}
             end)
             |> Task.await()
  end

  test "a full persisted bigint sequence fails without a partial admission", c do
    result =
      independent(fn ->
        older =
          CommandReviewFixtures.request!(c, %{
            lifecycle_state: :queued,
            hazardous: false,
            critical: false
          })

        CommandQueueEntry.new(%{
          organization_id: c.org,
          mission_id: c.mission,
          command_request_id: older.command_request_id,
          source_endpoint_ref: older.source_endpoint_ref,
          queue_lane_key: older.source_endpoint_ref,
          priority: older.priority,
          queue_sequence: 9_223_372_036_854_775_807,
          lifecycle_state: :pending,
          enqueued_by: actor(c),
          enqueued_at: DateTime.utc_now()
        })
        |> CommandQueueEntryRow.changeset()
        |> Repo.insert!()

        enqueue(c)
      end)
      |> Task.await()

    assert result == {:error, :command_queue_sequence_exhausted}

    assert {"validated", 1} ==
             independent(fn ->
               {Repo.get!(CommandRequestRow, c.request.command_request_id).lifecycle_state,
                Repo.aggregate(
                  from(row in CommandQueueEntryRow, where: row.organization_id == ^c.org),
                  :count
                )}
             end)
             |> Task.await()
  end

  test "dispatch observes committed admission through its independent database connection", c do
    parent = self()
    identity = {__MODULE__, c.org}

    dispatcher =
      independent(fn ->
        :yes = :global.register_name(identity, self())
        send(parent, :dispatcher_ready)

        receive do
          {:"$gen_call", caller, {:drain_lane, org, mission, lane, []}} ->
            assert {org, mission, lane} == {c.org, c.mission, c.request.source_endpoint_ref}
            entries = RequestQueueStore.list_queue_entries(org, mission, [])
            state = Repo.get!(CommandRequestRow, c.request.command_request_id).lifecycle_state
            GenServer.reply(caller, {:ok, %{status: :empty}})
            {state, entries}
        after
          5_000 -> raise "dispatch was not scheduled"
        end
      end)

    try do
      assert_receive :dispatcher_ready, 5_000

      {:ok, approved} =
        ApprovedCommand.from_automatic_policy(c.request)

      namespace = %{
        ProcessNamespace.default()
        | registry: Cadence.QueueAdmissionAbsentRegistry,
          dispatcher: {:global, identity}
      }

      result =
        independent(fn ->
          ControlCommanding.enqueue(approved, actor(c), process_namespace: namespace)
        end)
        |> Task.await(5_000)

      assert {:ok, %{queue_entry: queued}} = result
      assert {"queued", [observed]} = Task.await(dispatcher, 5_000)
      assert observed.command_queue_entry_id == queued.command_queue_entry_id
      assert observed.enqueued_by == actor(c)
      assert observed.metadata["approved_content_sha256"] == approved.content_sha256
    after
      Task.shutdown(dispatcher, :brutal_kill)
    end
  end

  test "a request that expires while waiting for the lane is rejected after the wait", c do
    next =
      independent(fn ->
        CommandReviewFixtures.request!(c, %{
          lifecycle_state: :validated,
          hazardous: false,
          critical: false,
          expires_at: DateTime.add(DateTime.utc_now(), 2, :second)
        })
      end)
      |> Task.await()

    parent = self()

    first =
      independent(fn ->
        RequestQueueStore.enqueue_request(
          c.org,
          c.mission,
          c.request.command_request_id,
          actor(c),
          before_enqueue: fn _ ->
            send(parent, {:admitting, self()})

            receive do
              :continue -> :ok
            after
              10_000 -> {:error, :test_timeout}
            end
          end
        )
      end)

    assert_receive {:admitting, first_pid}, 5_000

    second =
      independent(fn ->
        %{rows: [[pid]]} = SQL.query!(Repo, "SELECT pg_backend_pid()", [])
        send(parent, {:backend, pid})
        enqueue(%{c | request: next})
      end)

    try do
      assert_receive {:backend, pid}, 5_000
      assert wait_for_lock(pid, 300)
      Process.sleep(max(1, DateTime.diff(next.expires_at, DateTime.utc_now(), :millisecond) + 10))
      send(first_pid, :continue)
      assert {:ok, _} = Task.await(first, 10_000)
      assert {:error, {:command_request_expired, request_id}} = Task.await(second, 10_000)
      assert request_id == next.command_request_id

      assert {"validated", 1} ==
               independent(fn ->
                 {Repo.get!(CommandRequestRow, next.command_request_id).lifecycle_state,
                  Repo.aggregate(
                    from(row in CommandQueueEntryRow, where: row.organization_id == ^c.org),
                    :count
                  )}
               end)
               |> Task.await()
    after
      send(first_pid, :continue)
      Enum.each([first, second], &Task.shutdown(&1, :brutal_kill))
    end
  end

  test "the real request uniqueness constraint returns a changeset rejection", c do
    result =
      independent(fn ->
        {:ok, %{queue_entry: entry}} = enqueue(c)

        %{entry | command_queue_entry_id: Cadence.Ids.new("command_queue_entry")}
        |> CommandQueueEntryRow.changeset()
        |> Repo.insert()
      end)
      |> Task.await()

    assert {:error, %Ecto.Changeset{valid?: false}} = result
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
  defp wait_for_lock(_, 0), do: false

  defp wait_for_lock(pid, remaining) do
    %{rows: [[count]]} =
      SQL.query!(Repo, "SELECT count(*) FROM pg_locks WHERE pid = $1 AND NOT granted", [pid])

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
