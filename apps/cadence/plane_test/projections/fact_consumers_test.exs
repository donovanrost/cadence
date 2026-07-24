defmodule Cadence.Projections.FactConsumersTest do
  use ExUnit.Case, async: false

  alias Cadence.Activations.BindingSetActivation
  alias Cadence.Platform.EventBus
  alias Cadence.Projections.{DomainFactConsumer, RuntimeFactConsumer}

  alias Cadence.Runtime.{DownlinkRecordsPersisted, ManagedRecordsPersisted}

  test "projects committed facts without starting authoritative plane services" do
    assert Process.whereis(Cadence.Management.Supervisor) == nil
    assert Process.whereis(Cadence.Control.Supervisor) == nil
    assert Process.whereis(Cadence.Runtime.Supervisor) == nil
    assert Process.whereis(Cadence.Repo) == nil

    start_supervised!(EventBus)
    test_pid = self()

    start_supervised!(
      {RuntimeFactConsumer, project_records: &send(test_pid, {:runtime_records, &1})}
    )

    start_supervised!({DomainFactConsumer, project_fact: &send(test_pid, {:domain_fact, &1})})

    now = DateTime.utc_now()
    action_requests = [%{request_id: "action-1"}]

    assert :ok =
             Cadence.Runtime.Facts.publish(%ManagedRecordsPersisted{
               capability_records: [],
               action_requests: action_requests,
               timer_events: [],
               persisted_at: now
             })

    assert_receive {:runtime_records, ^action_requests}

    combined_records = [%{record_id: "combined-1"}]
    diagnostics = [%{diagnostic_id: "diagnostic-1"}]

    assert :ok =
             Cadence.Runtime.Facts.publish(%DownlinkRecordsPersisted{
               observations: [],
               combined_records: combined_records,
               diagnostics: diagnostics,
               persisted_at: now
             })

    assert_receive {:runtime_records, records}
    assert records == combined_records ++ diagnostics

    activation =
      BindingSetActivation.new(%{
        mission_id: "mission-1",
        binding_set_id: "binding-set-1",
        binding_set_version: 1
      })

    assert :ok = Cadence.Activations.Facts.publish(activation)
    assert_receive {:domain_fact, ^activation}

    assert Process.whereis(Cadence.Management.Supervisor) == nil
    assert Process.whereis(Cadence.Control.Supervisor) == nil
    assert Process.whereis(Cadence.Runtime.Supervisor) == nil
    assert Process.whereis(Cadence.Repo) == nil
  end
end
