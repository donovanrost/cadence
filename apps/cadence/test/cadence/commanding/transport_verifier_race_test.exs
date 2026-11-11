defmodule Cadence.Commanding.TransportVerifierRaceTest do
  @moduledoc """
  DECISIONS #72: a COP-1 acknowledgement can be stored before the release commits its
  verifiers. Each ordering resolves the verifier at once, a pending verifier resolves only once,
  and a timeout first re-reads the stored evidence.
  """
  use Cadence.DataCase, async: false

  alias Cadence.Catalog.Command.MatchCriteria

  alias Cadence.Commanding.{
    CommandQueueEntryRow,
    CommandReleaseAttempt,
    CommandReleaseAttemptRow,
    CommandRequest,
    CommandRequestRow,
    CommandVerifierInstance,
    CommandVerifierInstanceRow,
    ReleaseAttemptLock,
    VerifierStore
  }

  alias Cadence.Repo
  alias Cadence.Runtime.{TransportCapabilityRecord, TransportRecords}
  alias Cadence.Runtime.TransportRecords.TransportCapabilityRecordRow
  alias Ecto.Adapters.SQL.Sandbox

  @org "org-race"
  @mission "mission-race"
  @request "command_request_race"
  @attempt "command_release_attempt_race"
  @released_at ~U[2026-11-11 21:07:00.250000Z]
  @timeout_at ~U[2026-11-11 21:07:30.250000Z]

  setup do
    persist_mission_scope(@org, @mission)

    Repo.insert!(
      CommandRequestRow.changeset(
        CommandRequest.new(%{
          command_request_id: @request,
          mission_id: @mission,
          source_endpoint_ref: "spacecraft_runtime:sc-race",
          mission_model_revision_id: "revision-race",
          command_id: "command:noop",
          command_name: "NOOP",
          lifecycle_state: :released,
          verification_state: :pending,
          requested_by: %{"user_id" => "user-race"},
          requested_at: @released_at
        })
      )
    )

    Repo.insert!(
      CommandReleaseAttemptRow.changeset(
        CommandReleaseAttempt.new(%{
          command_release_attempt_id: @attempt,
          mission_id: @mission,
          command_queue_entry_id: "entry-race",
          command_request_id: @request,
          source_endpoint_ref: "spacecraft_runtime:sc-race",
          realized_contact_id: "contact-race",
          mission_model_revision_id: "revision-race",
          command_id: "command:noop",
          lifecycle_state: :released,
          verification_state: :pending,
          released_by: %{"user_id" => "user-race"},
          attempted_at: @released_at,
          released_at: @released_at
        })
      )
    )

    :ok
  end

  defp verifiers! do
    for {phase, subject} <- [start: "transport:started", completion: "transport:completed"] do
      Repo.insert!(
        CommandVerifierInstanceRow.changeset(
          CommandVerifierInstance.new(%{
            command_verifier_instance_id: "verifier_race_#{phase}",
            organization_id: @org,
            mission_id: @mission,
            command_request_id: @request,
            command_release_attempt_id: @attempt,
            source_endpoint_ref: "spacecraft_runtime:sc-race",
            mission_model_revision_id: "revision-race",
            command_id: "command:noop",
            command_name: "NOOP",
            verifier_id: "verifier:#{phase}",
            verifier_name: "#{phase}",
            phase: phase,
            success_criteria:
              MatchCriteria.new(%{
                criteria_type: :comparison,
                subject_ref: subject,
                comparison: :equal,
                value: true
              }),
            timeout_at: @timeout_at,
            lifecycle_state: :pending
          })
        )
      )
    end
  end

  # What the uplink gateway stores for the release's start and its COP-1 acknowledgement.
  defp record!(phase, offset_ms) do
    record = record(phase, offset_ms)
    Repo.insert!(TransportCapabilityRecordRow.changeset(record))
    record
  end

  defp record(phase, offset_ms) do
    %TransportCapabilityRecord{
      transport_record_id: "transport_record_race_#{phase}",
      mission_id: @mission,
      realized_contact_id: "contact-race",
      path_id: "path-race",
      capability_instance_id: "uplink-gateway:race",
      family_key: :uplink_gateway,
      activation_id: "activation-race",
      binding_set_id: "binding-set-race",
      binding_set_version: 1,
      partition_affinity: :path,
      partition_value: "path-race",
      event_kind: if(phase == :start, do: :control_input_handled, else: :transport_event_handled),
      emitted_record_kinds: [],
      emitted_record_count: 0,
      action_request_count: 0,
      state_snapshot: %{last_release_attempt_id: @attempt, last_command_request_id: @request},
      recorded_at: DateTime.add(@released_at, offset_ms, :millisecond),
      metadata: %{
        signal_phase: phase,
        command_release_attempt_id: @attempt,
        command_request_id: @request,
        command_name: "NOOP"
      }
    }
  end

  defp states do
    @org
    |> Cadence.Commanding.list_command_verifier_instances(@mission, command_request_id: @request)
    |> Map.new(&{&1.phase, &1.lifecycle_state})
  end

  defp request_state do
    {:ok, request} = Cadence.Commanding.fetch_command_request(@org, @mission, @request)
    request.verification_state
  end

  # The release transaction's catch-up from the attempt's stored records.
  defp release_catch_up do
    {records, action_requests} =
      TransportRecords.for_command_release_attempt(Repo, @org, @mission, @attempt)

    Cadence.Commanding.evaluate_transport_command_verifiers(Repo, records, action_requests)
  end

  test "verifiers committed first: evaluating the acknowledgement resolves them at once" do
    verifiers!()
    records = [record!(:start, 130), record!(:completion, 145)]

    assert {:ok, resolved} =
             Cadence.Commanding.evaluate_transport_command_verifiers(Repo, records, [])

    assert length(resolved) == 2
    assert states() == %{start: :satisfied, completion: :satisfied}
    assert request_state() == :satisfied
  end

  test "acknowledgement committed first (tonight's 13 ms ack): the release catch-up matches it" do
    record!(:start, 130)
    record!(:completion, 145)
    verifiers!()

    assert {:ok, [_start, _completion]} = release_catch_up()
    assert states() == %{start: :satisfied, completion: :satisfied}
  end

  test "both reads before either commit can't happen: the second locker waits for the first" do
    test_pid = self()

    holder =
      Task.async(fn ->
        Sandbox.unboxed_run(Repo, fn ->
          Repo.transaction(fn ->
            :ok = ReleaseAttemptLock.acquire(Repo, @mission, [@attempt])
            send(test_pid, :release_locked)
            receive do: (:commit -> :ok)
          end)
        end)
      end)

    assert_receive :release_locked, 2_000

    waiter =
      Task.async(fn ->
        Sandbox.unboxed_run(Repo, fn ->
          Repo.transaction(fn ->
            # The consumer locks every attempt in its batch, in sorted order.
            :ok = ReleaseAttemptLock.acquire(Repo, @mission, ["z-other", @attempt])
            send(test_pid, :evaluation_locked)
          end)
        end)
      end)

    refute_receive :evaluation_locked, 300
    send(holder.pid, :commit)
    assert_receive :evaluation_locked, 2_000
    Task.await(holder)
    Task.await(waiter)
  end

  # Holds the attempt's lock in a real (unboxed) transaction until told to commit.
  defp hold_lock(mission \\ @mission) do
    test_pid = self()

    holder = Task.async(fn -> Sandbox.unboxed_run(Repo, fn -> hold(mission, test_pid) end) end)
    assert_receive :held, 2_000
    holder
  end

  defp hold(mission, test_pid) do
    Repo.transaction(fn ->
      :ok = ReleaseAttemptLock.acquire(Repo, mission, [@attempt])
      send(test_pid, :held)
      receive do: (:commit -> :ok)
    end)
  end

  # `fun` (on its own real connection) must not finish until the holder commits.
  defp assert_waits_for(holder, fun) do
    test_pid = self()

    waiter =
      Task.async(fn ->
        Sandbox.unboxed_run(Repo, fn ->
          result =
            try do
              fun.()
            rescue
              error -> error
            end

          send(test_pid, :waiter_done)
          result
        end)
      end)

    refute_receive :waiter_done, 300
    send(holder.pid, :commit)
    assert_receive :waiter_done, 2_000
    Task.await(holder)
    Task.await(waiter)
  end

  test "call site: evaluating a transport record waits for the release holding its attempt" do
    # Its own mission, made inside the waiter's transaction and rolled back: the sandbox's
    # mission isn't visible on that connection, and evaluation skips unknown missions.
    mission = "mission-race-unboxed"
    holder = hold_lock(mission)

    assert_waits_for(holder, fn ->
      Repo.transaction(fn ->
        persist_mission_scope("org-race-unboxed", mission)

        Cadence.Commanding.evaluate_transport_command_verifiers(
          Repo,
          [%{record(:completion, 145) | mission_id: mission}],
          []
        )

        Repo.rollback(:checked)
      end)
    end)
  end

  test "call site: the release transaction locks its attempt before writing verifiers" do
    attempt_row = Repo.get_by!(CommandReleaseAttemptRow, command_release_attempt_id: @attempt)
    request_row = Repo.get_by!(CommandRequestRow, command_request_id: @request)

    queue_row = %CommandQueueEntryRow{
      organization_id: @org,
      mission_id: @mission,
      command_queue_entry_id: "entry-race",
      command_request_id: @request
    }

    multi =
      Cadence.Commanding.release_success_multi(
        attempt_row,
        queue_row,
        request_row,
        CommandReleaseAttemptRow.to_domain(attempt_row),
        [],
        :pending
      )

    assert [{:release_attempt_lock, _} | _] = Ecto.Multi.to_list(multi)

    # Its writes then fail on this connection (the rows live in the sandbox); only the wait matters.
    assert_waits_for(hold_lock(), fn -> Repo.transaction(multi) end)
  end

  test "a double match resolves once and the second is a no-op" do
    verifiers!()
    records = [record!(:start, 130), record!(:completion, 145)]

    assert {:ok, [_, _]} =
             Cadence.Commanding.evaluate_transport_command_verifiers(Repo, records, [])

    assert {:ok, []} = release_catch_up()
    assert states() == %{start: :satisfied, completion: :satisfied}
  end

  test "a timeout sweep and a match never overwrite each other, in either order" do
    [start_row, completion_row] = verifiers!()

    timed_out =
      &(&1
        |> CommandVerifierInstanceRow.to_domain()
        |> Map.merge(%{lifecycle_state: :timed_out, failure_reason: "timed_out"}))

    # Matched first; a sweep that read the row while it was pending can't time it out.
    record!(:completion, 145)
    assert {:ok, [_]} = release_catch_up()

    assert {:ok, []} =
             VerifierStore.apply_updates(Repo, [{completion_row, timed_out.(completion_row)}])

    assert states().completion == :satisfied

    # Timed out first; a late match that read it pending can't satisfy it.
    assert {:ok, [_]} = VerifierStore.apply_updates(Repo, [{start_row, timed_out.(start_row)}])

    satisfied =
      start_row
      |> CommandVerifierInstanceRow.to_domain()
      |> Map.put(:lifecycle_state, :satisfied)

    assert {:ok, []} = VerifierStore.apply_updates(Repo, [{start_row, satisfied}])
    assert states().start == :timed_out
  end

  test "at timeout the stored acknowledgement an evaluation missed still satisfies the verifier" do
    verifiers!()
    # Neither the consumer nor the catch-up saw these (tonight's 023 pass).
    record!(:start, 130)
    record!(:completion, 145)

    assert {:ok, resolved} =
             Cadence.Commanding.timeout_command_verifier_instances(
               Repo,
               DateTime.add(@timeout_at, 1)
             )

    assert Enum.map(resolved, & &1.lifecycle_state) == [:satisfied, :satisfied]
    assert states() == %{start: :satisfied, completion: :satisfied}
    assert request_state() == :satisfied
  end

  test "at timeout a verifier with no stored evidence still times out" do
    verifiers!()
    record!(:start, 130)

    assert {:ok, resolved} =
             Cadence.Commanding.timeout_command_verifier_instances(
               Repo,
               DateTime.add(@timeout_at, 1)
             )

    assert resolved |> Enum.map(&{&1.phase, &1.lifecycle_state}) |> Enum.sort() ==
             [completion: :timed_out, start: :satisfied]

    assert request_state() == :timed_out
  end
end
