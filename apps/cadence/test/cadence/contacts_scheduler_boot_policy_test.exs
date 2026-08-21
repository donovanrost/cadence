defmodule Cadence.ContactsSchedulerBootPolicyTest do
  use Cadence.ConfigCase, async: false

  @moduletag :runtime

  alias Cadence.Contacts.{Path, ScheduledContact, TransportBinding}
  alias Cadence.Contacts.Scheduler
  alias Cadence.Control.MissionRuntime
  alias Cadence.Control.Missions, as: ControlMissions
  alias Cadence.Control.ProcessNamespace, as: ControlProcessNamespace
  alias Cadence.Control.Supervisor, as: ControlSupervisor
  alias Cadence.Runtime
  alias Cadence.Runtime.ProcessNamespace, as: RuntimeProcessNamespace

  setup do
    mission_id =
      "mission-contact-scheduler-" <> Integer.to_string(System.unique_integer([:positive]))

    %{mission_id: mission_id}
  end

  test "legacy control startup captures scheduler config before mission children start", %{
    mission_id: mission_id
  } do
    previous_contact_scheduler_config = Application.fetch_env(:cadence, :contact_scheduler)
    reference_time = DateTime.utc_now()

    Application.put_env(:cadence, :contact_scheduler,
      enabled: true,
      auto_schedule?: false,
      run_on_boot?: false,
      safety_poll_interval_ms: :timer.hours(1),
      reference_time_fun: fn -> reference_time end
    )

    on_exit(fn ->
      restore_application_env(:contact_scheduler, previous_contact_scheduler_config)
    end)

    process_namespace = legacy_control_process_namespace()

    start_supervised!(
      {ControlSupervisor,
       process_namespace: process_namespace,
       runtime_process_namespace: RuntimeProcessNamespace.default(),
       start_mission_recovery?: false,
       start_fact_consumers?: false,
       start_shared_resources?: false,
       mission_runtime_opts: [
         reconciler_opts: [reconcile_on_start?: false, safety_poll?: false]
       ]}
    )

    Application.put_env(:cadence, :contact_scheduler, enabled: false)

    assert {:ok, _mission_control} = ControlMissions.ensure_started(process_namespace, mission_id)

    scheduler = MissionRuntime.contact_scheduler_name(process_namespace, mission_id)
    assert is_pid(GenServer.whereis(scheduler))
    refute GenServer.whereis(Scheduler)

    scheduled_contact =
      ScheduledContact.new(%{
        scheduled_contact_id: "mission-runtime-due-contact",
        mission_id: mission_id,
        source_endpoint_refs: ["source-endpoint-alpha"],
        starts_at: DateTime.add(reference_time, -15, :second),
        ends_at: DateTime.add(reference_time, 300, :second),
        paths: contact_paths()
      })

    assert {:ok, _scheduled_contact} =
             Cadence.Contacts.persist_scheduled_contact(scheduled_contact)

    Scheduler.notify_contact_changed(scheduler, mission_id)

    assert {:ok, %{status: :settled}} = Scheduler.await_settled(scheduler)

    assert {:ok, _summary} = Scheduler.reconcile_now(scheduler, reference_time)

    assert {:ok,
            %{
              status: :settled,
              reconciler: %{status: :settled},
              contact_scheduler: %{status: :settled}
            }} = ControlMissions.await_settled(process_namespace, mission_id)

    assert :ok = Runtime.stop_mission(mission_id)
    assert is_pid(GenServer.whereis(scheduler))

    assert :ok = ControlMissions.stop(process_namespace, mission_id)
    refute GenServer.whereis(scheduler)

    assert :ok = ControlMissions.stop(mission_id)
  end

  defp legacy_control_process_namespace do
    ControlProcessNamespace.new!(
      root_supervisor: __MODULE__.LegacyControlSupervisor,
      registry: __MODULE__.LegacyControlRegistry,
      mission_supervisor: __MODULE__.LegacyControlMissionSupervisor,
      mission_recovery: __MODULE__.LegacyMissionRecovery,
      contact_fact_consumer: __MODULE__.LegacyContactFactConsumer,
      runtime_fact_consumer: __MODULE__.LegacyRuntimeFactConsumer
    )
  end

  defp restore_application_env(key, {:ok, value}),
    do: Application.put_env(:cadence, key, value)

  defp restore_application_env(key, :error), do: Application.delete_env(:cadence, key)

  defp contact_paths do
    [
      Path.new(%{
        path_id: "uplink-path-alpha",
        direction: :uplink,
        selection_role: :selected,
        source_endpoint_ref: "source-endpoint-alpha",
        transport_bindings: [
          TransportBinding.new(%{
            transport_binding_id: "uplink-heartbeat",
            family_key: :heartbeat_monitor,
            target_scope: :path,
            configuration: %{"heartbeat_interval_ms" => 25}
          })
        ]
      }),
      Path.new(%{
        path_id: "downlink-path-alpha",
        direction: :downlink,
        selection_role: :selected,
        source_endpoint_ref: "source-endpoint-alpha",
        transport_bindings: [
          TransportBinding.new(%{
            transport_binding_id: "downlink-heartbeat",
            family_key: :heartbeat_monitor,
            target_scope: :transport,
            configuration: %{"heartbeat_interval_ms" => 25}
          })
        ]
      })
    ]
  end
end
