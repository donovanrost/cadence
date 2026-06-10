defmodule Cadence.CommandingVerifierSchedulerTest do
  use Cadence.DataCase, async: false

  alias Cadence.Commanding

  alias Cadence.Commanding.{
    CommandReleaseAttempt,
    CommandRequest,
    CommandVerifierInstance,
    VerifierScheduler
  }

  alias Cadence.Persistence.Schemas.{
    CommandReleaseAttemptRow,
    CommandRequestRow,
    CommandVerifierInstanceRow
  }

  @scheduler_event_prefix [:cadence, :commanding, :verifier_scheduler]
  @scheduler_events [
    [:cadence, :commanding, :verifier_scheduler, :notification],
    [:cadence, :commanding, :verifier_scheduler, :projection_rebuild],
    [:cadence, :commanding, :verifier_scheduler, :reconcile],
    [:cadence, :commanding, :verifier_scheduler, :safety_reconcile],
    [:cadence, :commanding, :verifier_scheduler, :stale_timer],
    [:cadence, :commanding, :verifier_scheduler, :timer_fired],
    [:cadence, :commanding, :verifier_scheduler, :timer_scheduled]
  ]

  setup do
    unique = System.unique_integer([:positive])
    organization_id = "org-verifier-scheduler-#{unique}"
    mission_id = "mission-verifier-scheduler-#{unique}"

    persist_mission_scope(organization_id, mission_id)

    %{organization_id: organization_id, mission_id: mission_id}
  end

  test "rebuilds pending verifier timeout projection on boot", %{
    organization_id: organization_id,
    mission_id: mission_id
  } do
    attach_scheduler_telemetry(self())
    reference_time = DateTime.from_unix!(1_700_060_000, :second)

    verifier_instance =
      persist_verifier_fixture!(organization_id, mission_id,
        command_verifier_instance_id: "boot-verifier",
        timeout_at: DateTime.add(reference_time, 600, :second)
      )

    scheduler_name = :"verifier-scheduler-#{System.unique_integer([:positive])}"

    start_supervised!(
      {VerifierScheduler,
       name: scheduler_name,
       auto_schedule?: false,
       run_on_boot?: false,
       reference_time_fun: fn -> reference_time end}
    )

    assert_scheduler_event(:projection_rebuild, fn measurements, metadata ->
      measurements.projected_verifier_count == 1 and metadata.projected_verifier_count == 0
    end)

    verifier_instance_id = verifier_instance.command_verifier_instance_id

    assert %{
             projected_verifier_instance_ids: [^verifier_instance_id],
             projected_verifier_count: 1,
             timeout_timer_count: 0
           } = VerifierScheduler.snapshot(scheduler_name)
  end

  test "notification updates projection and schedules the next timeout", %{
    organization_id: organization_id,
    mission_id: mission_id
  } do
    attach_scheduler_telemetry(self())
    reference_time = DateTime.from_unix!(1_700_060_100, :second)

    verifier_instance =
      persist_verifier_fixture!(organization_id, mission_id,
        command_verifier_instance_id: "notified-verifier",
        timeout_at: DateTime.add(reference_time, 600, :second)
      )

    scheduler_name = :"verifier-scheduler-#{System.unique_integer([:positive])}"

    start_supervised!(
      {VerifierScheduler,
       name: scheduler_name,
       auto_schedule?: true,
       run_on_boot?: false,
       safety_poll_interval_ms: :timer.hours(1),
       reference_time_fun: fn -> reference_time end}
    )

    assert_scheduler_event(:projection_rebuild, fn _measurements, _metadata -> true end)

    VerifierScheduler.notify_verifier_instances_changed(verifier_instance, scheduler_name)

    assert_scheduler_event(:notification, fn measurements, _metadata ->
      measurements.count == 1
    end)

    assert_scheduler_event(:timer_scheduled, fn measurements, metadata ->
      measurements.delay_ms == 600_000 and
        metadata.command_verifier_instance_id ==
          verifier_instance.command_verifier_instance_id and
        metadata.mission_id == mission_id and
        DateTime.compare(metadata.timeout_at, verifier_instance.timeout_at) == :eq
    end)

    satisfied_instance = %CommandVerifierInstance{
      verifier_instance
      | lifecycle_state: :satisfied
    }

    VerifierScheduler.notify_verifier_instances_changed(satisfied_instance, scheduler_name)

    assert %{
             projected_verifier_instance_ids: [],
             projected_verifier_count: 0,
             timeout_timer_count: 0
           } = VerifierScheduler.snapshot(scheduler_name)
  end

  test "timer reconciles due verifier timeouts and rolls up verification state", %{
    organization_id: organization_id,
    mission_id: mission_id
  } do
    attach_scheduler_telemetry(self())
    reference_time = DateTime.from_unix!(1_700_060_200, :second)

    verifier_instance =
      persist_verifier_fixture!(organization_id, mission_id,
        command_verifier_instance_id: "due-verifier",
        command_request_id: "due-request",
        command_release_attempt_id: "due-release-attempt",
        timeout_at: DateTime.add(reference_time, -5, :second)
      )

    scheduler_name = :"verifier-scheduler-#{System.unique_integer([:positive])}"

    start_supervised!(
      {VerifierScheduler,
       name: scheduler_name,
       auto_schedule?: true,
       run_on_boot?: false,
       safety_poll_interval_ms: :timer.hours(1),
       reference_time_fun: fn -> reference_time end}
    )

    assert_scheduler_event(:timer_scheduled, fn measurements, metadata ->
      measurements.delay_ms == 0 and
        metadata.command_verifier_instance_id ==
          verifier_instance.command_verifier_instance_id
    end)

    assert_scheduler_event(:timer_fired, fn measurements, _metadata ->
      measurements.count == 1
    end)

    assert_scheduler_event(:reconcile, fn measurements, metadata ->
      metadata.reason == :timer and measurements.timed_out_verifier_count == 1 and
        measurements.error_count == 0
    end)

    assert {:ok, timed_out_verifier_instance} =
             Commanding.fetch_command_verifier_instance(
               organization_id,
               mission_id,
               verifier_instance.command_verifier_instance_id
             )

    assert timed_out_verifier_instance.lifecycle_state == :timed_out
    assert timed_out_verifier_instance.failure_reason == "timed_out"

    assert {:ok, command_request} =
             Commanding.fetch_command_request(
               organization_id,
               mission_id,
               verifier_instance.command_request_id
             )

    assert {:ok, command_release_attempt} =
             Commanding.fetch_command_release_attempt(
               organization_id,
               mission_id,
               verifier_instance.command_release_attempt_id
             )

    assert command_request.verification_state == :timed_out
    assert command_release_attempt.verification_state == :timed_out
  end

  test "emits telemetry for manual safety and stale timer paths" do
    attach_scheduler_telemetry(self())
    reference_time = DateTime.from_unix!(1_700_060_300, :second)
    scheduler_name = :"verifier-scheduler-#{System.unique_integer([:positive])}"

    start_supervised!(
      {VerifierScheduler,
       name: scheduler_name,
       auto_schedule?: false,
       run_on_boot?: false,
       reference_time_fun: fn -> reference_time end}
    )

    assert {:ok, []} = VerifierScheduler.reconcile_now(scheduler_name, reference_time)

    assert_scheduler_event(:reconcile, fn measurements, metadata ->
      metadata.reason == :manual and measurements.timed_out_verifier_count == 0 and
        measurements.error_count == 0
    end)

    pid = GenServer.whereis(scheduler_name)
    send(pid, {:timeout_wakeup, make_ref()})

    assert_scheduler_event(:stale_timer, fn measurements, _metadata ->
      measurements.count == 1
    end)

    send(pid, :safety_reconcile)

    assert_scheduler_event(:safety_reconcile, fn measurements, metadata ->
      metadata.reason == :safety and measurements.timed_out_verifier_count == 0 and
        measurements.error_count == 0
    end)

    assert %{
             projected_verifier_count: 0,
             projected_verifier_instance_ids: [],
             timeout_timer_count: 0
           } = VerifierScheduler.snapshot(scheduler_name)
  end

  defp persist_verifier_fixture!(organization_id, mission_id, opts) do
    now = Keyword.get(opts, :now, DateTime.from_unix!(1_700_059_000, :second))

    command_request_id =
      Keyword.get(opts, :command_request_id, "request-#{System.unique_integer([:positive])}")

    command_release_attempt_id =
      Keyword.get(
        opts,
        :command_release_attempt_id,
        "release-attempt-#{System.unique_integer([:positive])}"
      )

    command_request =
      CommandRequest.new(%{
        organization_id: organization_id,
        mission_id: mission_id,
        command_request_id: command_request_id,
        source_endpoint_ref: "source-endpoint-alpha",
        command_snapshot_id: "command-snapshot-alpha",
        command_id: "cmd-test",
        command_name: "Test Command",
        lifecycle_state: :released,
        verification_state: :pending,
        requested_by: %{"user_id" => "scheduler-test"},
        requested_at: now
      })

    command_release_attempt =
      CommandReleaseAttempt.new(%{
        organization_id: organization_id,
        mission_id: mission_id,
        command_release_attempt_id: command_release_attempt_id,
        command_queue_entry_id: "queue-entry-#{System.unique_integer([:positive])}",
        command_request_id: command_request.command_request_id,
        source_endpoint_ref: command_request.source_endpoint_ref,
        realized_contact_id: "realized-contact-alpha",
        command_snapshot_id: command_request.command_snapshot_id,
        command_id: command_request.command_id,
        command_name: command_request.command_name,
        lifecycle_state: :released,
        verification_state: :pending,
        released_by: %{"user_id" => "scheduler-test"},
        attempted_at: now,
        released_at: now
      })

    verifier_instance =
      CommandVerifierInstance.new(%{
        organization_id: organization_id,
        mission_id: mission_id,
        command_verifier_instance_id:
          Keyword.get(
            opts,
            :command_verifier_instance_id,
            "verifier-#{System.unique_integer([:positive])}"
          ),
        command_request_id: command_request.command_request_id,
        command_release_attempt_id: command_release_attempt.command_release_attempt_id,
        source_endpoint_ref: command_request.source_endpoint_ref,
        command_snapshot_id: command_request.command_snapshot_id,
        command_id: command_request.command_id,
        command_name: command_request.command_name,
        verifier_id: "verifier-timeout",
        verifier_name: "Timeout Verifier",
        phase: :completion,
        timeout_at: Keyword.fetch!(opts, :timeout_at),
        lifecycle_state: Keyword.get(opts, :lifecycle_state, :pending)
      })

    Repo.insert!(CommandRequestRow.changeset(command_request))
    Repo.insert!(CommandReleaseAttemptRow.changeset(command_release_attempt))
    Repo.insert!(CommandVerifierInstanceRow.changeset(verifier_instance))

    verifier_instance
  end

  defp attach_scheduler_telemetry(test_pid) do
    handler_id = "command-verifier-scheduler-test-#{System.unique_integer([:positive])}"

    :ok =
      :telemetry.attach_many(
        handler_id,
        @scheduler_events,
        fn event, measurements, metadata, _config ->
          send(test_pid, {:verifier_scheduler_telemetry, event, measurements, metadata})
        end,
        nil
      )

    on_exit(fn -> :telemetry.detach(handler_id) end)
  end

  defp assert_scheduler_event(event_name, predicate) do
    event = @scheduler_event_prefix ++ [event_name]

    receive do
      {:verifier_scheduler_telemetry, ^event, measurements, metadata} ->
        if predicate.(measurements, metadata) do
          {measurements, metadata}
        else
          assert_scheduler_event(event_name, predicate)
        end

      {:verifier_scheduler_telemetry, _other_event, _measurements, _metadata} ->
        assert_scheduler_event(event_name, predicate)
    after
      1_000 -> flunk("expected verifier scheduler telemetry event #{inspect(event)}")
    end
  end
end
