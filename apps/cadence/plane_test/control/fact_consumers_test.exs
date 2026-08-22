defmodule Cadence.Control.FactConsumersTest do
  use ExUnit.Case, async: false

  alias Cadence.Contacts.RealizedContact
  alias Cadence.Control.{ContactFactConsumer, RuntimeFactConsumer}
  alias Cadence.Platform.EventBus

  alias Cadence.Runtime.{ProcessingResultsPersisted, TransportRecordsPersisted}

  test "reacts to committed runtime and contact facts without starting other planes" do
    assert Process.whereis(Cadence.Management.Supervisor) == nil
    assert Process.whereis(Cadence.Runtime.Supervisor) == nil
    assert Process.whereis(Cadence.Projections.Supervisor) == nil
    assert Process.whereis(Cadence.Repo) == nil

    start_supervised!(EventBus)
    test_pid = self()

    start_supervised!(
      {RuntimeFactConsumer,
       evaluate_telemetry: &send(test_pid, {:telemetry, &1}),
       evaluate_transport: &send(test_pid, {:transport, &1, &2})}
    )

    start_supervised!(
      {ContactFactConsumer, notify_release_target: &send(test_pid, {:contact, &1})}
    )

    now = DateTime.utc_now()
    telemetry_samples = [%{sample_id: "sample-1"}]
    capability_records = [%{record_id: "capability-1"}]
    action_requests = [%{request_id: "action-1"}]

    assert :ok =
             Cadence.Runtime.Facts.publish(%ProcessingResultsPersisted{
               batch_id: "batch-1",
               evidence_ids: [],
               telemetry_samples: telemetry_samples,
               persisted_at: now
             })

    assert_receive {:telemetry, ^telemetry_samples}

    assert :ok =
             Cadence.Runtime.Facts.publish(%TransportRecordsPersisted{
               capability_records: capability_records,
               action_requests: action_requests,
               timer_events: [],
               persisted_at: now
             })

    assert_receive {:transport, ^capability_records, ^action_requests}

    contact =
      RealizedContact.new(%{
        realized_contact_id: "contact-1",
        mission_id: "mission-1"
      })

    assert :ok = Cadence.Contacts.Facts.publish(contact)
    assert_receive {:contact, ^contact}

    assert Process.whereis(Cadence.Management.Supervisor) == nil
    assert Process.whereis(Cadence.Runtime.Supervisor) == nil
    assert Process.whereis(Cadence.Projections.Supervisor) == nil
    assert Process.whereis(Cadence.Repo) == nil
  end
end
