defmodule Cadence.Commanding.ReleaseRecoveryTest do
  use Cadence.ProcessDataCase, async: false

  alias Cadence.CommandReviewFixtures

  alias Cadence.Commanding.{
    CommandQueueEntryRow,
    CommandReleaseAttempt,
    CommandReleaseAttemptRow,
    CommandRequestRow,
    Dispatcher,
    ReleaseStore,
    RequestQueueStore
  }

  setup do
    c = CommandReviewFixtures.scope!()

    request =
      CommandReviewFixtures.request!(c, %{
        lifecycle_state: :validated,
        hazardous: false,
        critical: false
      })

    {:ok, %{queue_entry: entry}} =
      RequestQueueStore.enqueue_request(
        c.org,
        c.mission,
        request.command_request_id,
        %{"user_id" => c.user.user_id},
        []
      )

    queue = Repo.get!(CommandQueueEntryRow, entry.command_queue_entry_id)
    request = Repo.get!(CommandRequestRow, request.command_request_id)

    attempt =
      CommandReleaseAttempt.new(%{
        organization_id: c.org,
        mission_id: c.mission,
        command_queue_entry_id: queue.command_queue_entry_id,
        command_request_id: request.command_request_id,
        source_endpoint_ref: request.source_endpoint_ref,
        realized_contact_id: "recovery-contact",
        mission_model_revision_id: request.mission_model_revision_id,
        command_id: request.command_id,
        encoded_binary_base64: Base.encode64(<<1>>),
        encoded_size_bytes: 1,
        released_by: %{"user_id" => c.user.user_id},
        attempted_at: DateTime.utc_now()
      })

    {:ok, Map.merge(c, %{queue: queue, request: request, attempt: attempt})}
  end

  test "a failed attempt insert rolls back the lane claim", c do
    assert {:error, %Ecto.Changeset{}} =
             ReleaseStore.claim(c.queue, c.request, %{c.attempt | encoded_size_bytes: -1})

    assert Repo.get!(CommandQueueEntryRow, c.queue.command_queue_entry_id).lifecycle_state ==
             "pending"

    assert Repo.get(CommandReleaseAttemptRow, c.attempt.command_release_attempt_id) == nil

    assert {:ok, %{queue: queue, attempt: attempt}} =
             ReleaseStore.claim(c.queue, c.request, c.attempt)

    assert queue.active_release_attempt_id == attempt.command_release_attempt_id

    assert Repo.get!(CommandQueueEntryRow, queue.command_queue_entry_id).active_release_attempt_id ==
             attempt.command_release_attempt_id
  end

  test "duplicate attempt identity cannot claim a queue or substitute new bytes", c do
    assert {:ok, original} = ReleaseStore.persist(c.org, c.attempt)

    assert {:error, %Ecto.Changeset{}} =
             ReleaseStore.claim(c.queue, c.request, %{
               c.attempt
               | encoded_binary_base64: Base.encode64(<<2>>)
             })

    assert Repo.get!(CommandQueueEntryRow, c.queue.command_queue_entry_id).lifecycle_state ==
             "pending"

    assert {:ok, ^original} =
             ReleaseStore.fetch(c.org, c.mission, c.attempt.command_release_attempt_id)
  end

  test "an attempt must match the prepared request, queue, scope and wire basis", c do
    for change <- [
          organization_id: "foreign",
          mission_id: "foreign",
          command_request_id: "foreign",
          command_queue_entry_id: "foreign",
          source_endpoint_ref: "foreign",
          command_id: "foreign",
          mission_model_revision_id: "foreign",
          lifecycle_state: :released
        ] do
      assert {:error, :command_release_claim_mismatch} =
               ReleaseStore.claim(c.queue, c.request, struct!(c.attempt, [change]))
    end

    assert Repo.get!(CommandQueueEntryRow, c.queue.command_queue_entry_id).active_release_attempt_id ==
             nil
  end

  test "default dispatcher startup retains a bound incomplete claim and cannot reclaim it", c do
    assert {:ok, %{queue: queue, attempt: attempt}} =
             ReleaseStore.claim(c.queue, c.request, c.attempt)

    pid = start_supervised!({Dispatcher, name: nil, run_on_boot?: false, auto_schedule?: false})
    assert :sys.get_state(pid).run_on_boot? == false
    current = Repo.get!(CommandQueueEntryRow, queue.command_queue_entry_id)
    assert current.lifecycle_state == "release_pending"
    assert current.active_release_attempt_id == attempt.command_release_attempt_id
    assert {:error, _} = RequestQueueStore.claim_for_release(current)

    assert {:error, _} =
             RequestQueueStore.ensure_lane_not_in_flight(c.org, c.mission, queue.queue_lane_key)
  end

  test "legacy unbound claims remain held and cannot authorize completion", c do
    assert {:ok, queue} = RequestQueueStore.claim_for_release(c.queue)
    assert {:ok, attempt} = ReleaseStore.persist(c.org, c.attempt)
    assert RequestQueueStore.requeue_release_pending() == 0

    assert {:error, :command_release_claim_changed} =
             ReleaseStore.with_claim(queue, c.request, attempt, fn _, _, _ ->
               flunk("unbound completion")
             end)

    assert Repo.get!(CommandQueueEntryRow, queue.command_queue_entry_id).lifecycle_state ==
             "release_pending"
  end

  test "ambiguous completion preserves first evidence and holds the lane across startup", c do
    assert {:ok, %{queue: queue, attempt: attempt}} =
             ReleaseStore.claim(c.queue, c.request, c.attempt)

    assert {:ok, _} =
             ReleaseStore.mark_uncertain(queue, c.request, attempt, :provider_disconnected)

    assert {:ok, :retained} =
             ReleaseStore.mark_uncertain(queue, c.request, attempt, :late_timeout)

    pid = start_supervised!({Dispatcher, name: nil, run_on_boot?: false, auto_schedule?: false})
    :sys.get_state(pid)

    assert {:ok, stored} =
             ReleaseStore.fetch(c.org, c.mission, attempt.command_release_attempt_id)

    assert stored.lifecycle_state == :release_uncertain
    assert stored.failure_reason == ":provider_disconnected"
    assert stored.released_at == nil

    assert Repo.get!(CommandQueueEntryRow, queue.command_queue_entry_id).lifecycle_state ==
             "release_pending"

    assert Repo.get!(CommandRequestRow, c.request.command_request_id).lifecycle_state == "queued"

    assert {:error, _} =
             RequestQueueStore.ensure_lane_not_in_flight(c.org, c.mission, queue.queue_lane_key)
  end

  test "completion cannot substitute a different scoped request", c do
    assert {:ok, %{queue: queue, attempt: attempt}} =
             ReleaseStore.claim(c.queue, c.request, c.attempt)

    foreign_scope = CommandReviewFixtures.scope!()
    foreign = CommandReviewFixtures.request!(foreign_scope, %{lifecycle_state: :queued})
    foreign_row = Repo.get!(CommandRequestRow, foreign.command_request_id)

    assert {:error, :command_release_claim_changed} =
             ReleaseStore.with_claim(queue, foreign_row, attempt, fn _, _, _ ->
               flunk("foreign request completion")
             end)

    assert Repo.get!(CommandRequestRow, foreign.command_request_id) == foreign_row
  end

  test "stale results cannot finalize a changed claim or immutable attempt", c do
    assert {:ok, %{queue: queue, attempt: attempt}} =
             ReleaseStore.claim(c.queue, c.request, c.attempt)

    for change <- [
          encoded_binary_base64: Base.encode64(<<2>>),
          realized_contact_id: "other-contact"
        ] do
      assert {:error, :command_release_claim_changed} =
               ReleaseStore.with_claim(
                 queue,
                 c.request,
                 struct!(attempt, [change]),
                 fn _, _, _ -> flunk("changed attempt") end
               )
    end

    Repo.update!(Ecto.Changeset.change(queue, active_release_attempt_id: "successor"))

    assert {:error, :command_release_claim_changed} =
             ReleaseStore.mark_uncertain(queue, c.request, attempt, :late_timeout)

    assert Repo.get!(CommandQueueEntryRow, queue.command_queue_entry_id).active_release_attempt_id ==
             "successor"

    assert Repo.get!(CommandReleaseAttemptRow, attempt.command_release_attempt_id).lifecycle_state ==
             "release_pending"
  end

  test "completion rollback preserves all three records and a terminal result is idempotent", c do
    assert {:ok, %{queue: queue, attempt: attempt}} =
             ReleaseStore.claim(c.queue, c.request, c.attempt)

    assert {:error, :finalization_failed} =
             ReleaseStore.with_claim(queue, c.request, attempt, fn current_queue, _, _ ->
               Repo.update!(Ecto.Changeset.change(current_queue, lifecycle_state: "released"))
               {:error, :finalization_failed}
             end)

    assert Repo.get!(CommandQueueEntryRow, queue.command_queue_entry_id).lifecycle_state ==
             "release_pending"

    assert {:ok, :completed} =
             ReleaseStore.with_claim(queue, c.request, attempt, fn current_queue, request, row ->
               Repo.update!(
                 Ecto.Changeset.change(row,
                   lifecycle_state: "released",
                   verification_state: "satisfied"
                 )
               )

               Repo.update!(Ecto.Changeset.change(current_queue, lifecycle_state: "released"))

               Repo.update!(
                 Ecto.Changeset.change(request,
                   lifecycle_state: "released",
                   verification_state: "satisfied"
                 )
               )

               {:ok, :completed}
             end)

    assert {:ok, {:already_completed, _, _, stored}} =
             ReleaseStore.with_claim(queue, c.request, attempt, fn _, _, _ ->
               flunk("duplicate completion")
             end)

    assert stored.verification_state == "satisfied"

    assert {:ok, {:already_completed, _, _, _}} =
             ReleaseStore.mark_uncertain(queue, c.request, attempt, :late_error)

    assert Repo.get!(CommandReleaseAttemptRow, attempt.command_release_attempt_id).failure_reason ==
             nil
  end
end
