defmodule Cadence.ContactsSchedulerTest do
  use Cadence.ConfigCase, async: false

  @moduletag :runtime

  alias Cadence.Contacts
  alias Cadence.Contacts.{Path, RealizedContact, ScheduledContact, TransportBinding}
  alias Cadence.Contacts.Scheduler
  alias Cadence.Control.MissionRuntime
  alias Cadence.Control.Missions, as: ControlMissions
  alias Cadence.Runtime

  @scheduler_event_prefix [:cadence, :contacts, :scheduler]
  @scheduler_events [
    [:cadence, :contacts, :scheduler, :notification],
    [:cadence, :contacts, :scheduler, :projection_rebuild],
    [:cadence, :contacts, :scheduler, :reconcile],
    [:cadence, :contacts, :scheduler, :safety_reconcile],
    [:cadence, :contacts, :scheduler, :stale_timer],
    [:cadence, :contacts, :scheduler, :timer_fired],
    [:cadence, :contacts, :scheduler, :timer_scheduled]
  ]

  setup do
    disable_contact_schedulers!()

    mission_id =
      "mission-contact-scheduler-" <> Integer.to_string(System.unique_integer([:positive]))

    %{mission_id: mission_id}
  end

  defp disable_contact_schedulers! do
    Application.put_env(:cadence, :contact_scheduler, enabled: false)
    Application.put_env(:cadence, :contact_scheduler_global_safety, enabled: false)

    on_exit(fn ->
      Application.put_env(:cadence, :contact_scheduler, enabled: false)
      Application.put_env(:cadence, :contact_scheduler_global_safety, enabled: false)
    end)
  end

  test "reconcile realizes due scheduled contacts and starts them live", %{mission_id: mission_id} do
    reference_time = DateTime.from_unix!(1_700_050_000, :second)

    due_contact =
      ScheduledContact.new(%{
        scheduled_contact_id: "due-contact",
        mission_id: mission_id,
        source_endpoint_refs: ["source-endpoint-alpha"],
        starts_at: DateTime.add(reference_time, -60, :second),
        ends_at: DateTime.add(reference_time, 300, :second),
        paths: contact_paths()
      })

    future_contact =
      ScheduledContact.new(%{
        scheduled_contact_id: "future-contact",
        mission_id: mission_id,
        source_endpoint_refs: ["source-endpoint-alpha"],
        starts_at: DateTime.add(reference_time, 600, :second),
        ends_at: DateTime.add(reference_time, 900, :second),
        paths: contact_paths()
      })

    assert {:ok, _scheduled_contact} = Cadence.Contacts.persist_scheduled_contact(due_contact)
    assert {:ok, _scheduled_contact} = Cadence.Contacts.persist_scheduled_contact(future_contact)
    refute GenServer.whereis(Scheduler)

    assert {:ok, summary} = Contacts.reconcile(mission_id, reference_time)

    assert summary.expired_scheduled_contact_ids == []
    assert summary.completed_scheduled_contact_ids == []
    assert summary.realized_scheduled_contact_ids == ["due-contact_run"]
    assert summary.completed_realized_contact_ids == []
    assert summary.restarted_realized_contact_ids == []
    assert summary.errors == []

    assert {:ok, realized_due_contact} =
             Cadence.Contacts.fetch_scheduled_contact(
               mission_id,
               due_contact.scheduled_contact_id
             )

    assert realized_due_contact.lifecycle_state == :realized
    assert realized_due_contact.realized_contact_id == "due-contact_run"

    assert {:ok, untouched_future_contact} =
             Cadence.Contacts.fetch_scheduled_contact(
               mission_id,
               future_contact.scheduled_contact_id
             )

    assert untouched_future_contact.lifecycle_state == :scheduled

    assert {:ok, realized_contact} =
             Cadence.Contacts.fetch_realized_contact(mission_id, "due-contact_run")

    assert realized_contact.lifecycle_state == :active
    assert realized_contact.clock_mode == :live

    assert {:ok, snapshot} = Cadence.realized_contact_snapshot(mission_id, "due-contact_run")
    assert snapshot.clock_mode == :live
    assert DateTime.compare(snapshot.initial_time, reference_time) == :eq
  end

  test "scheduler rehydrates persisted active realized contacts that are not running", %{
    mission_id: mission_id
  } do
    reference_time = DateTime.from_unix!(1_700_051_000, :second)

    realized_contact =
      RealizedContact.new(%{
        realized_contact_id: "restart-contact",
        mission_id: mission_id,
        source_endpoint_refs: ["source-endpoint-alpha"],
        paths: contact_paths(),
        clock_mode: :live,
        initial_time: reference_time,
        lifecycle_state: :active,
        realized_at: DateTime.add(reference_time, -30, :second),
        metadata: %{origin: "persisted"}
      })

    assert {:ok, _persisted_realized_contact} =
             Cadence.Contacts.persist_realized_contact(realized_contact)

    refute Runtime.realized_contact_running?(mission_id, realized_contact.realized_contact_id)

    scheduler_name = :"contact-scheduler-#{System.unique_integer([:positive])}"

    start_supervised!(
      {Scheduler,
       name: scheduler_name, mission_id: mission_id, auto_schedule?: false, run_on_boot?: false}
    )

    assert {:ok, summary} = Scheduler.reconcile_now(scheduler_name, reference_time)
    assert summary.expired_scheduled_contact_ids == []
    assert summary.completed_scheduled_contact_ids == []
    assert summary.realized_scheduled_contact_ids == []
    assert summary.completed_realized_contact_ids == []
    assert summary.restarted_realized_contact_ids == ["restart-contact"]
    assert summary.errors == []

    assert Runtime.realized_contact_running?(mission_id, realized_contact.realized_contact_id)

    assert {:ok, restarted_contact} =
             Cadence.Contacts.fetch_realized_contact(
               mission_id,
               realized_contact.realized_contact_id
             )

    assert restarted_contact.lifecycle_state == :active
    assert restarted_contact.metadata["reconciled_at"]
    assert restarted_contact.metadata["started_at"]
  end

  test "scheduler notification reconciles a changed mission without interval polling", %{
    mission_id: mission_id
  } do
    reference_time = DateTime.from_unix!(1_700_051_500, :second)

    scheduled_contact =
      ScheduledContact.new(%{
        scheduled_contact_id: "notified-due-contact",
        mission_id: mission_id,
        source_endpoint_refs: ["source-endpoint-alpha"],
        starts_at: DateTime.add(reference_time, -15, :second),
        ends_at: DateTime.add(reference_time, 300, :second),
        paths: contact_paths()
      })

    assert {:ok, _scheduled_contact} =
             Cadence.Contacts.persist_scheduled_contact(scheduled_contact)

    scheduler_name = :"contact-scheduler-#{System.unique_integer([:positive])}"

    start_supervised!(
      {Scheduler,
       name: scheduler_name,
       auto_schedule?: true,
       run_on_boot?: false,
       safety_poll_interval_ms: :timer.hours(1),
       reference_time_fun: fn -> reference_time end}
    )

    Scheduler.notify_contact_changed(scheduler_name, mission_id)

    assert {:ok, %{status: :settled}} = Scheduler.await_settled(scheduler_name)

    assert {:ok, realized_contact} =
             Cadence.Contacts.fetch_realized_contact(mission_id, "notified-due-contact_run")

    assert realized_contact.lifecycle_state == :active
    assert Runtime.realized_contact_running?(mission_id, realized_contact.realized_contact_id)
    assert {:ok, _summary} = Scheduler.reconcile_now(scheduler_name, reference_time)
  end

  test "default contact notifications route to the mission control scheduler", %{
    mission_id: mission_id
  } do
    previous_contact_scheduler_config = Application.get_env(:cadence, :contact_scheduler)

    Application.put_env(:cadence, :contact_scheduler,
      enabled: true,
      safety_poll_interval_ms: :timer.hours(1)
    )

    on_exit(fn ->
      Application.put_env(:cadence, :contact_scheduler, previous_contact_scheduler_config)
    end)

    reference_time = DateTime.utc_now()

    scheduled_contact =
      ScheduledContact.new(%{
        scheduled_contact_id: "mission-runtime-due-contact",
        mission_id: mission_id,
        source_endpoint_refs: ["source-endpoint-alpha"],
        starts_at: DateTime.add(reference_time, -15, :second),
        ends_at: DateTime.add(reference_time, 300, :second),
        paths: contact_paths()
      })

    refute GenServer.whereis(MissionRuntime.contact_scheduler_name(mission_id))
    refute GenServer.whereis(Scheduler)

    assert {:ok, _scheduled_contact} =
             Cadence.Contacts.persist_scheduled_contact(scheduled_contact)

    assert is_pid(GenServer.whereis(MissionRuntime.contact_scheduler_name(mission_id)))
    refute GenServer.whereis(Scheduler)

    assert {:ok, %{status: :settled}} =
             Scheduler.await_settled(MissionRuntime.contact_scheduler_name(mission_id))

    assert {:ok, _summary} =
             Scheduler.reconcile_now(
               MissionRuntime.contact_scheduler_name(mission_id),
               reference_time
             )

    assert {:ok,
            %{
              status: :settled,
              reconciler: %{status: :settled},
              contact_scheduler: %{status: :settled}
            }} = ControlMissions.await_settled(mission_id)

    assert :ok = Runtime.stop_mission(mission_id)
    assert is_pid(GenServer.whereis(MissionRuntime.contact_scheduler_name(mission_id)))

    assert :ok = ControlMissions.stop(mission_id)
    refute GenServer.whereis(MissionRuntime.contact_scheduler_name(mission_id))
  end

  test "mission scheduler updates its projection from contact change notifications", %{
    mission_id: mission_id
  } do
    reference_time = DateTime.from_unix!(1_700_051_650, :second)

    future_contact =
      ScheduledContact.new(%{
        scheduled_contact_id: "projected-future-contact",
        mission_id: mission_id,
        source_endpoint_refs: ["source-endpoint-alpha"],
        starts_at: DateTime.add(reference_time, 600, :second),
        ends_at: DateTime.add(reference_time, 900, :second),
        paths: contact_paths()
      })

    canceled_contact = %ScheduledContact{future_contact | lifecycle_state: :canceled}
    scheduler_name = :"contact-scheduler-#{System.unique_integer([:positive])}"

    start_supervised!(
      {Scheduler,
       name: scheduler_name,
       mission_id: mission_id,
       auto_schedule?: true,
       run_on_boot?: false,
       safety_poll_interval_ms: :timer.hours(1),
       reference_time_fun: fn -> reference_time end}
    )

    Scheduler.notify_contact_changed(future_contact, server: scheduler_name)

    assert %{
             scheduled_contact_ids: ["projected-future-contact"],
             mission_timer_count: 1
           } = Scheduler.snapshot(scheduler_name)

    Scheduler.notify_contact_changed(canceled_contact, server: scheduler_name)

    assert %{
             scheduled_contact_ids: [],
             mission_timer_count: 0
           } = Scheduler.snapshot(scheduler_name)
  end

  test "mission scheduler emits telemetry for projection rebuilds notifications and timers", %{
    mission_id: mission_id
  } do
    attach_scheduler_telemetry(self())
    reference_time = DateTime.from_unix!(1_700_051_660, :second)

    future_contact =
      ScheduledContact.new(%{
        scheduled_contact_id: "telemetry-projected-future-contact",
        mission_id: mission_id,
        source_endpoint_refs: ["source-endpoint-alpha"],
        starts_at: DateTime.add(reference_time, 600, :second),
        ends_at: DateTime.add(reference_time, 900, :second),
        paths: contact_paths()
      })

    scheduler_name = :"contact-scheduler-#{System.unique_integer([:positive])}"

    start_supervised!(
      {Scheduler,
       name: scheduler_name,
       mission_id: mission_id,
       auto_schedule?: true,
       run_on_boot?: false,
       safety_poll_interval_ms: :timer.hours(1),
       reference_time_fun: fn -> reference_time end}
    )

    assert_scheduler_event(:projection_rebuild, fn measurements, metadata ->
      measurements.projected_contact_count == 0 and metadata.mode == :mission and
        metadata.mission_id == mission_id
    end)

    Scheduler.notify_contact_changed(future_contact, server: scheduler_name)

    assert_scheduler_event(:notification, fn measurements, metadata ->
      measurements.count == 1 and metadata.contact_kind == :scheduled and
        metadata.scheduled_contact_id == future_contact.scheduled_contact_id and
        metadata.lifecycle_state == :scheduled and metadata.mission_id == mission_id
    end)

    assert_scheduler_event(:timer_scheduled, fn measurements, metadata ->
      measurements.count == 1 and measurements.delay_ms == 600_000 and
        metadata.mode == :mission and metadata.mission_id == mission_id and
        DateTime.compare(metadata.wake_at, future_contact.starts_at) == :eq
    end)
  end

  test "mission scheduler emits telemetry when a timer reconciles due contacts", %{
    mission_id: mission_id
  } do
    attach_scheduler_telemetry(self())
    reference_time = DateTime.from_unix!(1_700_051_675, :second)

    scheduled_contact =
      ScheduledContact.new(%{
        scheduled_contact_id: "telemetry-due-contact",
        mission_id: mission_id,
        source_endpoint_refs: ["source-endpoint-alpha"],
        starts_at: DateTime.add(reference_time, -5, :second),
        ends_at: DateTime.add(reference_time, 300, :second),
        paths: contact_paths()
      })

    assert {:ok, _scheduled_contact} =
             Cadence.Contacts.persist_scheduled_contact(scheduled_contact)

    scheduler_name = :"contact-scheduler-#{System.unique_integer([:positive])}"

    start_supervised!(
      {Scheduler,
       name: scheduler_name,
       mission_id: mission_id,
       auto_schedule?: true,
       run_on_boot?: false,
       safety_poll_interval_ms: :timer.hours(1),
       reference_time_fun: fn -> reference_time end}
    )

    assert_scheduler_event(:timer_scheduled, fn measurements, metadata ->
      measurements.delay_ms == 0 and metadata.mission_id == mission_id
    end)

    assert_scheduler_event(:timer_fired, fn measurements, metadata ->
      measurements.count == 1 and metadata.mission_id == mission_id
    end)

    assert_scheduler_event(:reconcile, fn measurements, metadata ->
      metadata.reason == :timer and metadata.mode == :mission and
        metadata.mission_id == mission_id and measurements.realized_scheduled_contact_count == 1
    end)

    assert {:ok, %{status: :settled}} = Scheduler.await_settled(scheduler_name)

    assert {:ok, %RealizedContact{lifecycle_state: :active}} =
             Cadence.Contacts.fetch_realized_contact(
               mission_id,
               "telemetry-due-contact_run"
             )
  end

  test "scheduler emits telemetry for manual safety and stale timer paths", %{
    mission_id: mission_id
  } do
    attach_scheduler_telemetry(self())
    reference_time = DateTime.from_unix!(1_700_051_690, :second)
    scheduler_name = :"contact-scheduler-#{System.unique_integer([:positive])}"

    start_supervised!(
      {Scheduler,
       name: scheduler_name,
       mission_id: mission_id,
       auto_schedule?: false,
       run_on_boot?: false,
       reference_time_fun: fn -> reference_time end}
    )

    assert {:ok, summary} = Scheduler.reconcile_now(scheduler_name, reference_time)
    assert summary.errors == []

    assert_scheduler_event(:reconcile, fn measurements, metadata ->
      metadata.reason == :manual and metadata.mode == :mission and
        metadata.mission_id == mission_id and measurements.error_count == 0
    end)

    pid = GenServer.whereis(scheduler_name)
    send(pid, {:mission_wakeup, mission_id, make_ref()})

    assert_scheduler_event(:stale_timer, fn measurements, metadata ->
      measurements.count == 1 and metadata.mission_id == mission_id
    end)

    send(pid, :safety_reconcile)

    assert_scheduler_event(:safety_reconcile, fn measurements, metadata ->
      metadata.reason == :safety and metadata.mode == :mission and
        metadata.mission_id == mission_id and measurements.error_count == 0
    end)

    assert {:ok,
            %{
              status: :settled,
              mission_timer_count: 0,
              safety_timer_scheduled?: false
            }} = Scheduler.await_settled(scheduler_name)
  end

  test "mission scheduler rebuilds its projection from durable contacts on boot", %{
    mission_id: mission_id
  } do
    reference_time = DateTime.from_unix!(1_700_051_700, :second)

    future_contact =
      ScheduledContact.new(%{
        scheduled_contact_id: "boot-projected-contact",
        mission_id: mission_id,
        source_endpoint_refs: ["source-endpoint-alpha"],
        starts_at: DateTime.add(reference_time, 600, :second),
        ends_at: DateTime.add(reference_time, 900, :second),
        paths: contact_paths()
      })

    assert {:ok, _scheduled_contact} = Cadence.Contacts.persist_scheduled_contact(future_contact)

    scheduler_name = :"contact-scheduler-#{System.unique_integer([:positive])}"

    start_supervised!(
      {Scheduler,
       name: scheduler_name,
       mission_id: mission_id,
       auto_schedule?: false,
       run_on_boot?: false,
       reference_time_fun: fn -> reference_time end}
    )

    assert %{
             scheduled_contact_ids: ["boot-projected-contact"],
             mission_timer_count: 0
           } = Scheduler.snapshot(scheduler_name)
  end

  test "scheduler wakeups are mission scoped", %{mission_id: mission_id} do
    reference_time = DateTime.from_unix!(1_700_051_800, :second)
    other_mission_id = mission_id <> "-other"

    due_contact =
      ScheduledContact.new(%{
        scheduled_contact_id: "mission-scoped-due-contact",
        mission_id: mission_id,
        source_endpoint_refs: ["source-endpoint-alpha"],
        starts_at: DateTime.add(reference_time, -10, :second),
        ends_at: DateTime.add(reference_time, 300, :second),
        paths: contact_paths()
      })

    other_contact =
      ScheduledContact.new(%{
        scheduled_contact_id: "other-mission-future-contact",
        mission_id: other_mission_id,
        source_endpoint_refs: ["source-endpoint-alpha"],
        starts_at: DateTime.add(reference_time, 900, :second),
        ends_at: DateTime.add(reference_time, 1_200, :second),
        paths: contact_paths()
      })

    assert {:ok, _scheduled_contact} = Cadence.Contacts.persist_scheduled_contact(due_contact)
    assert {:ok, _scheduled_contact} = Cadence.Contacts.persist_scheduled_contact(other_contact)

    assert Contacts.next_contact_scheduler_wakeup(mission_id, reference_time) == reference_time

    assert DateTime.compare(
             Contacts.next_contact_scheduler_wakeup(other_mission_id, reference_time),
             other_contact.starts_at
           ) == :eq

    assert {:ok, summary} = Contacts.reconcile(mission_id, reference_time)

    assert summary.realized_scheduled_contact_ids == ["mission-scoped-due-contact_run"]

    assert {:ok, untouched_other_contact} =
             Cadence.Contacts.fetch_scheduled_contact(
               other_mission_id,
               other_contact.scheduled_contact_id
             )

    assert untouched_other_contact.lifecycle_state == :scheduled
  end

  test "reconcile completes expired scheduled contacts instead of restarting them", %{
    mission_id: mission_id
  } do
    start_time = DateTime.from_unix!(1_700_052_000, :second)
    end_time = DateTime.add(start_time, 300, :second)
    reconcile_time = DateTime.add(end_time, 60, :second)

    scheduled_contact =
      ScheduledContact.new(%{
        scheduled_contact_id: "expired-contact",
        mission_id: mission_id,
        source_endpoint_refs: ["source-endpoint-alpha"],
        starts_at: start_time,
        ends_at: end_time,
        paths: contact_paths()
      })

    assert {:ok, _scheduled_contact} =
             Cadence.Contacts.persist_scheduled_contact(scheduled_contact)

    assert {:ok, realized_contact} =
             Cadence.Contacts.realize_scheduled_contact(
               mission_id,
               scheduled_contact.scheduled_contact_id,
               clock_mode: :live,
               initial_time: start_time,
               realized_at: start_time
             )

    assert Runtime.realized_contact_running?(mission_id, realized_contact.realized_contact_id)

    assert {:ok, summary} = Contacts.reconcile(mission_id, reconcile_time)

    assert summary.expired_scheduled_contact_ids == []
    assert summary.completed_scheduled_contact_ids == [scheduled_contact.scheduled_contact_id]
    assert summary.realized_scheduled_contact_ids == []
    assert summary.completed_realized_contact_ids == [realized_contact.realized_contact_id]
    assert summary.restarted_realized_contact_ids == []
    assert summary.errors == []

    refute Runtime.realized_contact_running?(mission_id, realized_contact.realized_contact_id)
  end

  test "reconcile expires missed scheduled contacts that were never realized", %{
    mission_id: mission_id
  } do
    reference_time = DateTime.from_unix!(1_700_053_000, :second)

    missed_contact =
      ScheduledContact.new(%{
        scheduled_contact_id: "missed-contact",
        mission_id: mission_id,
        source_endpoint_refs: ["source-endpoint-alpha"],
        starts_at: DateTime.add(reference_time, -600, :second),
        ends_at: DateTime.add(reference_time, -60, :second),
        paths: contact_paths()
      })

    assert {:ok, _scheduled_contact} = Cadence.Contacts.persist_scheduled_contact(missed_contact)

    assert {:ok, summary} = Contacts.reconcile(mission_id, reference_time)

    assert summary.expired_scheduled_contact_ids == [missed_contact.scheduled_contact_id]
    assert summary.completed_scheduled_contact_ids == []
    assert summary.realized_scheduled_contact_ids == []
    assert summary.completed_realized_contact_ids == []
    assert summary.restarted_realized_contact_ids == []
    assert summary.errors == []

    assert {:ok, expired_contact} =
             Cadence.Contacts.fetch_scheduled_contact(
               mission_id,
               missed_contact.scheduled_contact_id
             )

    assert expired_contact.lifecycle_state == :expired
    assert expired_contact.metadata["expired_at"]
    assert expired_contact.metadata["expired_from_schedule"]
    assert is_nil(expired_contact.realized_contact_id)
  end

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

  defp attach_scheduler_telemetry(test_pid) do
    handler_id = "contacts-scheduler-test-#{System.unique_integer([:positive])}"

    :ok =
      :telemetry.attach_many(
        handler_id,
        @scheduler_events,
        fn event, measurements, metadata, _config ->
          send(test_pid, {:scheduler_telemetry, event, measurements, metadata})
        end,
        nil
      )

    on_exit(fn -> :telemetry.detach(handler_id) end)
  end

  defp assert_scheduler_event(event_name, predicate) do
    event = @scheduler_event_prefix ++ [event_name]

    receive do
      {:scheduler_telemetry, ^event, measurements, metadata} ->
        if predicate.(measurements, metadata) do
          {measurements, metadata}
        else
          assert_scheduler_event(event_name, predicate)
        end

      {:scheduler_telemetry, _other_event, _measurements, _metadata} ->
        assert_scheduler_event(event_name, predicate)
    after
      1_000 -> flunk("expected scheduler telemetry event #{inspect(event)}")
    end
  end
end
