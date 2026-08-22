defmodule Cadence.CommandingVerifierSchedulerIsolationPeerTest do
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

  @organization_id "org-verifier-scheduler-peer-isolation"
  @mission_id "mission-verifier-scheduler-peer-isolation"
  @command_request_id "command-request-verifier-scheduler-peer-isolation"
  @command_release_attempt_id "release-attempt-verifier-scheduler-peer-isolation"
  @command_verifier_instance_id "verifier-instance-scheduler-peer-isolation"
  @scheduler_domain_id "command-verifier-scheduler-peer-isolation"
  @scheduler_name __MODULE__.Scheduler
  @primary_scheduler_name __MODULE__.PrimaryScheduler

  @projection_event [:cadence, :commanding, :verifier_scheduler, :projection_rebuild]

  @tag :runtimecase_overlap
  test "persists the same scheduler IDs after the overlapping owner rolls back", %{
    sandbox_owner_pid: sandbox_owner_pid
  } do
    attach_scheduler_telemetry()
    reference_time = DateTime.from_unix!(1_700_060_200, :second)

    scheduler_pid =
      start_gated_scheduler!(sandbox_owner_pid, @scheduler_name,
        auto_schedule?: false,
        run_on_boot?: false,
        reference_time_fun: fn -> reference_time end
      )

    primary = start_primary_owner!(reference_time)

    primary_scheduler_pid =
      start_gated_scheduler!(primary.owner_pid, @primary_scheduler_name,
        auto_schedule?: false,
        run_on_boot?: false,
        reference_time_fun: fn -> reference_time end
      )

    assert Process.alive?(sandbox_owner_pid)
    assert Process.alive?(scheduler_pid)
    assert Process.alive?(primary.owner_pid)
    assert Process.alive?(primary_scheduler_pid)
    refute primary.owner_pid == sandbox_owner_pid
    refute primary_scheduler_pid == scheduler_pid

    release_scheduler_bootstrap(primary_scheduler_pid)

    assert %{projected_verifier_count: 1} =
             VerifierScheduler.snapshot(@primary_scheduler_name)

    assert :ok = stop_supervised(@primary_scheduler_name)
    send(primary.task.pid, :release_primary_owner)
    assert :ok = Task.await(primary.task)
    refute Process.alive?(primary.owner_pid)

    persist_mission_scope(@organization_id, @mission_id)

    verifier_instance =
      persist_verifier_fixture!(timeout_at: DateTime.add(reference_time, 600, :second))

    release_scheduler_bootstrap(scheduler_pid)
    verifier_instance_id = verifier_instance.command_verifier_instance_id

    assert %{
             projected_verifier_instance_ids: [^verifier_instance_id],
             projected_verifier_count: 1,
             timeout_timer_count: 0
           } = VerifierScheduler.snapshot(@scheduler_name)

    assert_receive {
      :verifier_scheduler_projection,
      %{projected_verifier_count: 1},
      %{
        scheduler_domain_id: @scheduler_domain_id,
        scheduler_instance: @scheduler_name
      }
    }

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

    assert {:ok, persisted_verifier_instance} =
             Commanding.fetch_command_verifier_instance(
               @organization_id,
               @mission_id,
               @command_verifier_instance_id
             )

    assert command_request.verification_state == :pending
    assert command_release_attempt.verification_state == :pending
    assert persisted_verifier_instance.lifecycle_state == :pending
  end

  defp start_primary_owner!(reference_time) do
    test_pid = self()

    task =
      Task.async(fn ->
        owner_pid = Cadence.DataCase.start_sandbox_owner!(%{async: true}, shared?: false)
        send(test_pid, {:primary_owner_started, self(), owner_pid})

        try do
          persist_mission_scope(@organization_id, @mission_id)

          persist_verifier_fixture!(timeout_at: DateTime.add(reference_time, 600, :second))

          send(test_pid, {:primary_owner_ready, self(), owner_pid})

          receive do
            :release_primary_owner -> :ok
          end
        after
          stop_primary_sandbox_owner(owner_pid)
        end
      end)

    assert_receive {:primary_owner_started, task_pid, owner_pid}, 5_000
    assert task.pid == task_pid

    on_exit(fn ->
      if Process.alive?(task.pid) do
        send(task.pid, :release_primary_owner)
        Process.exit(task.pid, :shutdown)
      end

      stop_primary_sandbox_owner(owner_pid)
    end)

    assert_receive {:primary_owner_ready, ^task_pid, ^owner_pid}, 5_000

    %{owner_pid: owner_pid, task: task}
  end

  defp stop_primary_sandbox_owner(owner_pid) do
    if Process.alive?(owner_pid) do
      Cadence.DataCase.stop_sandbox_owner(owner_pid)
    end

    :ok
  catch
    :exit, _reason -> :ok
  end

  defp persist_verifier_fixture!(opts) do
    now = DateTime.from_unix!(1_700_059_000, :second)

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
        command_queue_entry_id: "queue-entry-verifier-scheduler-peer-isolation",
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

  defp start_gated_scheduler!(sandbox_owner_pid, scheduler_name, opts) do
    test_pid = self()

    child_spec =
      Supervisor.child_spec(
        {VerifierScheduler,
         Keyword.merge(opts,
           name: scheduler_name,
           bootstrap_gate_fun: fn ->
             send(test_pid, {:scheduler_bootstrap_waiting, self()})

             receive do
               :release_scheduler_bootstrap -> :ok
             end
           end,
           telemetry_metadata: %{
             scheduler_domain_id: @scheduler_domain_id,
             scheduler_instance: scheduler_name
           }
         )},
        id: scheduler_name
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
      :telemetry.attach(
        handler_id,
        @projection_event,
        fn _event, measurements, metadata, _config ->
          case metadata do
            %{
              scheduler_instance: ^scheduler_name,
              scheduler_domain_id: ^scheduler_domain_id
            } ->
              send(test_pid, {:verifier_scheduler_projection, measurements, metadata})

            _other ->
              :ok
          end
        end,
        nil
      )

    on_exit(fn -> :telemetry.detach(handler_id) end)
  end
end
