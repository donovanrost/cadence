defmodule Cadence.CommandingVerifierSchedulerTest do
  use Cadence.RuntimeCase, async: true, isolated: true

  alias Ecto.Adapters.SQL.Sandbox

  alias Cadence.Commanding

  alias Cadence.Commanding.{
    CommandReleaseAttempt,
    CommandReleaseAttemptRow,
    CommandRequest,
    CommandRequestRow,
    CommandVerifierInstance,
    CommandVerifierInstanceRow,
    VerifierScheduler
  }

  @organization_id "org-verifier-scheduler-isolation"
  @mission_id "mission-verifier-scheduler-isolation"
  @command_request_id "command-request-verifier-scheduler-isolation"
  @command_release_attempt_id "release-attempt-verifier-scheduler-isolation"
  @command_verifier_instance_id "verifier-instance-scheduler-isolation"
  @scheduler_domain_id "command-verifier-scheduler-isolation"
  @scheduler_name __MODULE__.Scheduler

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

  test "rebuilds pending verifier timeout projection on boot", %{
    sandbox_owner_pid: sandbox_owner_pid
  } do
    attach_scheduler_telemetry()
    persist_mission_scope(@organization_id, @mission_id)
    reference_time = DateTime.from_unix!(1_700_060_000, :second)

    verifier_instance =
      persist_verifier_fixture!(timeout_at: DateTime.add(reference_time, 600, :second))

    scheduler_pid =
      start_gated_scheduler!(sandbox_owner_pid,
        auto_schedule?: false,
        run_on_boot?: false,
        reference_time_fun: fn -> reference_time end
      )

    release_scheduler_bootstrap(scheduler_pid)

    assert_scheduler_event(:projection_rebuild, fn measurements, metadata ->
      measurements.projected_verifier_count == 1 and metadata.projected_verifier_count == 0
    end)

    verifier_instance_id = verifier_instance.command_verifier_instance_id

    assert %{
             projected_verifier_instance_ids: [^verifier_instance_id],
             projected_verifier_count: 1,
             timeout_timer_count: 0
           } = VerifierScheduler.snapshot(@scheduler_name)
  end

  test "notification updates projection and schedules the next timeout", %{
    sandbox_owner_pid: sandbox_owner_pid
  } do
    attach_scheduler_telemetry()
    persist_mission_scope(@organization_id, @mission_id)
    reference_time = DateTime.from_unix!(1_700_060_100, :second)

    verifier_instance =
      persist_verifier_fixture!(timeout_at: DateTime.add(reference_time, 600, :second))

    scheduler_pid =
      start_gated_scheduler!(sandbox_owner_pid,
        auto_schedule?: true,
        run_on_boot?: false,
        safety_poll_interval_ms: :timer.hours(1),
        reference_time_fun: fn -> reference_time end
      )

    release_scheduler_bootstrap(scheduler_pid)
    assert_scheduler_event(:projection_rebuild, fn _measurements, _metadata -> true end)

    VerifierScheduler.notify_verifier_instances_changed(verifier_instance, @scheduler_name)

    assert_scheduler_event(:notification, fn measurements, _metadata ->
      measurements.count == 1
    end)

    assert_scheduler_event(:timer_scheduled, fn measurements, metadata ->
      measurements.delay_ms == 600_000 and
        metadata.command_verifier_instance_id ==
          verifier_instance.command_verifier_instance_id and
        metadata.mission_id == @mission_id and
        DateTime.compare(metadata.timeout_at, verifier_instance.timeout_at) == :eq
    end)

    satisfied_instance = %CommandVerifierInstance{
      verifier_instance
      | lifecycle_state: :satisfied
    }

    VerifierScheduler.notify_verifier_instances_changed(satisfied_instance, @scheduler_name)

    assert %{
             projected_verifier_instance_ids: [],
             projected_verifier_count: 0,
             timeout_timer_count: 0
           } = VerifierScheduler.snapshot(@scheduler_name)
  end

  test "timer reconciles due verifier timeouts and rolls up verification state", %{
    sandbox_owner_pid: sandbox_owner_pid
  } do
    attach_scheduler_telemetry()
    reference_time = DateTime.from_unix!(1_700_060_200, :second)

    scheduler_pid =
      start_gated_scheduler!(sandbox_owner_pid,
        auto_schedule?: true,
        run_on_boot?: false,
        safety_poll_interval_ms: :timer.hours(1),
        reference_time_fun: fn -> reference_time end
      )

    assert Process.alive?(sandbox_owner_pid)
    assert Process.alive?(scheduler_pid)

    persist_mission_scope(@organization_id, @mission_id)

    verifier_instance =
      persist_verifier_fixture!(timeout_at: DateTime.add(reference_time, -5, :second))

    release_scheduler_bootstrap(scheduler_pid)

    {_, metadata} =
      assert_scheduler_event(:timer_scheduled, fn measurements, event_metadata ->
        measurements.delay_ms == 0 and
          event_metadata.command_verifier_instance_id ==
            verifier_instance.command_verifier_instance_id
      end)

    assert metadata.scheduler_instance == @scheduler_name
    assert metadata.scheduler_domain_id == @scheduler_domain_id

    assert_scheduler_event(:timer_fired, fn measurements, _metadata ->
      measurements.count == 1
    end)

    assert_scheduler_event(:reconcile, fn measurements, event_metadata ->
      event_metadata.reason == :timer and measurements.timed_out_verifier_count == 1 and
        measurements.error_count == 0
    end)

    assert {:ok, timed_out_verifier_instance} =
             Commanding.fetch_command_verifier_instance(
               @organization_id,
               @mission_id,
               @command_verifier_instance_id
             )

    assert timed_out_verifier_instance.lifecycle_state == :timed_out
    assert timed_out_verifier_instance.failure_reason == "timed_out"

    assert {:ok, command_request} =
             Commanding.fetch_command_request(
               @organization_id,
               @mission_id,
               @command_request_id
             )

    assert {:ok, command_release_attempt} =
             Commanding.fetch_command_release_attempt(
               @organization_id,
               @mission_id,
               @command_release_attempt_id
             )

    assert command_request.verification_state == :timed_out
    assert command_release_attempt.verification_state == :timed_out
  end

  test "emits telemetry for manual safety and stale timer paths", %{
    sandbox_owner_pid: sandbox_owner_pid
  } do
    attach_scheduler_telemetry()
    reference_time = DateTime.from_unix!(1_700_060_300, :second)

    scheduler_pid =
      start_gated_scheduler!(sandbox_owner_pid,
        auto_schedule?: false,
        run_on_boot?: false,
        reference_time_fun: fn -> reference_time end
      )

    release_scheduler_bootstrap(scheduler_pid)
    assert_scheduler_event(:projection_rebuild, fn _measurements, _metadata -> true end)

    assert {:ok, []} = VerifierScheduler.reconcile_now(@scheduler_name, reference_time)

    assert_scheduler_event(:reconcile, fn measurements, metadata ->
      metadata.reason == :manual and measurements.timed_out_verifier_count == 0 and
        measurements.error_count == 0
    end)

    send(scheduler_pid, {:timeout_wakeup, make_ref()})

    assert_scheduler_event(:stale_timer, fn measurements, _metadata ->
      measurements.count == 1
    end)

    send(scheduler_pid, :safety_reconcile)

    assert_scheduler_event(:safety_reconcile, fn measurements, metadata ->
      metadata.reason == :safety and measurements.timed_out_verifier_count == 0 and
        measurements.error_count == 0
    end)

    assert %{
             projected_verifier_count: 0,
             projected_verifier_instance_ids: [],
             timeout_timer_count: 0
           } = VerifierScheduler.snapshot(@scheduler_name)
  end

  defp persist_verifier_fixture!(opts) do
    now = Keyword.get(opts, :now, DateTime.from_unix!(1_700_059_000, :second))

    command_request =
      CommandRequest.new(%{
        organization_id: @organization_id,
        mission_id: @mission_id,
        command_request_id: @command_request_id,
        source_endpoint_ref: "source-endpoint-alpha",
        mission_model_revision_id: "mission-model-alpha",
        command_id: "cmd-test",
        command_name: "Test Command",
        lifecycle_state: :released,
        verification_state: :pending,
        requested_by: %{"user_id" => "scheduler-test"},
        requested_at: now
      })

    command_release_attempt =
      CommandReleaseAttempt.new(%{
        organization_id: @organization_id,
        mission_id: @mission_id,
        command_release_attempt_id: @command_release_attempt_id,
        command_queue_entry_id: "queue-entry-verifier-scheduler-isolation",
        command_request_id: @command_request_id,
        source_endpoint_ref: command_request.source_endpoint_ref,
        realized_contact_id: "realized-contact-alpha",
        mission_model_revision_id: command_request.mission_model_revision_id,
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
        organization_id: @organization_id,
        mission_id: @mission_id,
        command_verifier_instance_id: @command_verifier_instance_id,
        command_request_id: @command_request_id,
        command_release_attempt_id: @command_release_attempt_id,
        source_endpoint_ref: command_request.source_endpoint_ref,
        mission_model_revision_id: command_request.mission_model_revision_id,
        command_id: command_request.command_id,
        command_name: command_request.command_name,
        verifier_id: "verifier-timeout",
        verifier_name: "Timeout Verifier",
        phase: :completion,
        timeout_at: Keyword.fetch!(opts, :timeout_at),
        lifecycle_state: :pending
      })

    Repo.insert!(CommandRequestRow.changeset(command_request))
    Repo.insert!(CommandReleaseAttemptRow.changeset(command_release_attempt))
    Repo.insert!(CommandVerifierInstanceRow.changeset(verifier_instance))

    verifier_instance
  end

  defp start_gated_scheduler!(sandbox_owner_pid, opts) do
    test_pid = self()

    child_spec =
      Supervisor.child_spec(
        {VerifierScheduler,
         Keyword.merge(opts,
           name: @scheduler_name,
           bootstrap_gate_fun: fn ->
             send(test_pid, {:scheduler_bootstrap_waiting, self()})

             receive do
               :release_scheduler_bootstrap -> :ok
             end
           end,
           telemetry_metadata: %{
             scheduler_domain_id: @scheduler_domain_id,
             scheduler_instance: @scheduler_name
           }
         )},
        id: @scheduler_name
      )

    scheduler_pid = start_supervised!(child_spec)

    assert_receive {:scheduler_bootstrap_waiting, ^scheduler_pid}
    assert :ok = Sandbox.allow(Repo, sandbox_owner_pid, scheduler_pid)
    scheduler_pid
  end

  defp release_scheduler_bootstrap(scheduler_pid) do
    send(scheduler_pid, :release_scheduler_bootstrap)
  end

  defp attach_scheduler_telemetry do
    test_pid = self()
    handler_id = {__MODULE__, test_pid, make_ref()}
    scheduler_name = @scheduler_name
    scheduler_domain_id = @scheduler_domain_id

    :ok =
      :telemetry.attach_many(
        handler_id,
        @scheduler_events,
        fn event, measurements, metadata, _config ->
          case metadata do
            %{
              scheduler_instance: ^scheduler_name,
              scheduler_domain_id: ^scheduler_domain_id
            } ->
              send(test_pid, {:verifier_scheduler_telemetry, event, measurements, metadata})

            _other ->
              :ok
          end
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
