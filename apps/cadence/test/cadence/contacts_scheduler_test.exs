defmodule Cadence.ContactsSchedulerTest do
  use Cadence.DataCase, async: false

  alias Cadence.Contacts.{Path, RealizedContact, ScheduledContact, TransportBinding}
  alias Cadence.Contacts.Scheduler
  alias Cadence.Runtime

  setup do
    mission_id =
      "mission-contact-scheduler-" <> Integer.to_string(System.unique_integer([:positive]))

    on_exit(fn ->
      Cadence.stop_realized_contact(mission_id, "due-contact_run")
      Cadence.stop_realized_contact(mission_id, "restart-contact")
      Runtime.stop_mission(mission_id)
    end)

    %{mission_id: mission_id}
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

    assert {:ok, _scheduled_contact} = Cadence.persist_scheduled_contact(due_contact)
    assert {:ok, _scheduled_contact} = Cadence.persist_scheduled_contact(future_contact)

    assert {:ok, summary} = Cadence.reconcile_contact_lifecycle(reference_time)

    assert summary.expired_scheduled_contact_ids == []
    assert summary.completed_scheduled_contact_ids == []
    assert summary.realized_scheduled_contact_ids == ["due-contact_run"]
    assert summary.completed_realized_contact_ids == []
    assert summary.restarted_realized_contact_ids == []
    assert summary.errors == []

    assert {:ok, realized_due_contact} =
             Cadence.fetch_scheduled_contact(mission_id, due_contact.scheduled_contact_id)

    assert realized_due_contact.lifecycle_state == :realized
    assert realized_due_contact.realized_contact_id == "due-contact_run"

    assert {:ok, untouched_future_contact} =
             Cadence.fetch_scheduled_contact(mission_id, future_contact.scheduled_contact_id)

    assert untouched_future_contact.lifecycle_state == :scheduled

    assert {:ok, realized_contact} = Cadence.fetch_realized_contact(mission_id, "due-contact_run")
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

    assert {:ok, _persisted_realized_contact} = Cadence.persist_realized_contact(realized_contact)
    refute Runtime.realized_contact_running?(mission_id, realized_contact.realized_contact_id)

    scheduler_name = :"contact-scheduler-#{System.unique_integer([:positive])}"

    start_supervised!(
      {Scheduler, name: scheduler_name, auto_schedule?: false, run_on_boot?: false}
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
             Cadence.fetch_realized_contact(mission_id, realized_contact.realized_contact_id)

    assert restarted_contact.lifecycle_state == :active
    assert restarted_contact.metadata["reconciled_at"]
    assert restarted_contact.metadata["started_at"]
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

    assert {:ok, _scheduled_contact} = Cadence.persist_scheduled_contact(scheduled_contact)

    assert {:ok, realized_contact} =
             Cadence.realize_scheduled_contact(
               mission_id,
               scheduled_contact.scheduled_contact_id,
               clock_mode: :live,
               initial_time: start_time,
               realized_at: start_time
             )

    assert Runtime.realized_contact_running?(mission_id, realized_contact.realized_contact_id)

    assert {:ok, summary} = Cadence.reconcile_contact_lifecycle(reconcile_time)

    assert summary.expired_scheduled_contact_ids == []
    assert summary.completed_scheduled_contact_ids == [scheduled_contact.scheduled_contact_id]
    assert summary.realized_scheduled_contact_ids == []
    assert summary.completed_realized_contact_ids == [realized_contact.realized_contact_id]
    assert summary.restarted_realized_contact_ids == []
    assert summary.errors == []

    refute Runtime.realized_contact_running?(mission_id, realized_contact.realized_contact_id)

    assert {:ok, completed_contact} =
             Cadence.fetch_realized_contact(mission_id, realized_contact.realized_contact_id)

    assert {:ok, completed_scheduled_contact} =
             Cadence.fetch_scheduled_contact(mission_id, scheduled_contact.scheduled_contact_id)

    assert completed_scheduled_contact.lifecycle_state == :completed
    assert completed_scheduled_contact.metadata["completed_at"]
    assert completed_scheduled_contact.metadata["completed_from_schedule"]

    assert completed_contact.lifecycle_state == :completed
    assert completed_contact.metadata["completed_at"]
    assert completed_contact.metadata["completed_from_schedule"]
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

    assert {:ok, _scheduled_contact} = Cadence.persist_scheduled_contact(missed_contact)

    assert {:ok, summary} = Cadence.reconcile_contact_lifecycle(reference_time)

    assert summary.expired_scheduled_contact_ids == [missed_contact.scheduled_contact_id]
    assert summary.completed_scheduled_contact_ids == []
    assert summary.realized_scheduled_contact_ids == []
    assert summary.completed_realized_contact_ids == []
    assert summary.restarted_realized_contact_ids == []
    assert summary.errors == []

    assert {:ok, expired_contact} =
             Cadence.fetch_scheduled_contact(mission_id, missed_contact.scheduled_contact_id)

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
end
