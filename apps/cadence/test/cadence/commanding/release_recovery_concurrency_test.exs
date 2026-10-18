defmodule Cadence.Commanding.ReleaseRecoveryConcurrencyTest do
  use Cadence.DataCase, async: false
  alias Cadence.Accounts.{OrganizationMembershipRow, UserRow}

  alias Cadence.Commanding.{
    CommandQueueEntryRow,
    CommandReleaseAttempt,
    CommandReleaseAttemptRow,
    CommandRequestRow,
    ReleaseStore,
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

  test "independent completion transactions serialize and late failure cannot rewrite success",
       c do
    {queue, request, attempt} =
      independent(fn ->
        {:ok, %{queue_entry: entry}} = enqueue(c)
        queue = Repo.get!(CommandQueueEntryRow, entry.command_queue_entry_id)
        request = Repo.get!(CommandRequestRow, c.request.command_request_id)

        pending =
          CommandReleaseAttempt.new(%{
            organization_id: c.org,
            mission_id: c.mission,
            command_queue_entry_id: queue.command_queue_entry_id,
            command_request_id: request.command_request_id,
            source_endpoint_ref: request.source_endpoint_ref,
            realized_contact_id: "concurrent-recovery-contact",
            mission_model_revision_id: request.mission_model_revision_id,
            command_id: request.command_id,
            encoded_binary_base64: Base.encode64(<<1>>),
            encoded_size_bytes: 1,
            released_by: actor(c),
            attempted_at: DateTime.utc_now()
          })

        {:ok, %{queue: claimed, attempt: attempt}} = ReleaseStore.claim(queue, request, pending)
        {claimed, request, attempt}
      end)
      |> Task.await(10_000)

    parent = self()

    winner =
      independent(fn ->
        ReleaseStore.with_claim(queue, request, attempt, fn current_queue, current_request, row ->
          send(parent, {:completion_held, self()})

          receive do
            :complete ->
              Repo.update!(
                Ecto.Changeset.change(row,
                  lifecycle_state: "released",
                  verification_state: "satisfied"
                )
              )

              Repo.update!(
                Ecto.Changeset.change(current_request,
                  lifecycle_state: "released",
                  verification_state: "satisfied"
                )
              )

              Repo.update!(Ecto.Changeset.change(current_queue, lifecycle_state: "released"))
              {:ok, :completed}
          after
            10_000 -> raise "completion was not continued"
          end
        end)
      end)

    assert_receive {:completion_held, holder}, 5_000

    late =
      independent(fn ->
        %{rows: [[pid]]} = SQL.query!(Repo, "SELECT pg_backend_pid()", [])
        send(parent, {:late_backend, pid})
        ReleaseStore.mark_uncertain(queue, request, attempt, :late_timeout)
      end)

    try do
      assert_receive {:late_backend, pid}, 5_000
      assert wait_for_lock(pid, 300)
      send(holder, :complete)
      assert {:ok, :completed} = Task.await(winner, 5_000)
      assert {:ok, {:already_completed, _, _, stored}} = Task.await(late, 5_000)
      assert stored.lifecycle_state == "released"
      assert stored.verification_state == "satisfied"
      assert stored.failure_reason == nil

      assert :ok ==
               independent(fn ->
                 assert Repo.get!(CommandQueueEntryRow, queue.command_queue_entry_id).lifecycle_state ==
                          "released"

                 assert Repo.get!(CommandRequestRow, request.command_request_id).verification_state ==
                          "satisfied"

                 assert {:ok, {:already_completed, _, _, _}} =
                          ReleaseStore.with_claim(queue, request, attempt, fn _, _, _ ->
                            flunk("duplicate finalizer ran")
                          end)

                 :ok
               end)
               |> Task.await(5_000)
    after
      send(holder, :complete)
      Enum.each([winner, late], &Task.shutdown(&1, :brutal_kill))
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
    for schema <- [
          CommandReleaseAttemptRow,
          CommandQueueEntryRow,
          CommandRequestRow,
          EventRow,
          MissionEventRow,
          MissionRow
        ] do
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
