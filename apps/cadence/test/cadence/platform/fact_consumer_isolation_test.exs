defmodule Cadence.Platform.FactConsumerIsolationTest do
  use ExUnit.Case, async: false

  alias Cadence.Activations.BindingSetActivation
  alias Cadence.Contacts.RealizedContact
  alias Cadence.Control.ContactFactConsumer
  alias Cadence.Control.RuntimeFactConsumer, as: ControlRuntimeFactConsumer
  alias Cadence.Platform.EventBus
  alias Cadence.Projections.DomainFactConsumer
  alias Cadence.Projections.RuntimeFactConsumer, as: ProjectionsRuntimeFactConsumer
  alias Cadence.Projections.TelemetryFactConsumer
  alias Cadence.Runtime.DownlinkRecordsPersisted
  alias Cadence.Runtime.ManagedRecordsPersisted
  alias Cadence.Runtime.ProcessingResultsPersisted
  alias Cadence.Telemetry.ObservationIdentitySelectionChanged

  @bus_names %{
    a: __MODULE__.BusA,
    b: __MODULE__.BusB
  }

  @consumer_names %{
    a: %{
      contact: __MODULE__.SetAContact,
      control_runtime: __MODULE__.SetAControlRuntime,
      domain: __MODULE__.SetADomain,
      projections_runtime: __MODULE__.SetAProjectionsRuntime,
      telemetry: __MODULE__.SetATelemetry
    },
    b: %{
      contact: __MODULE__.SetBContact,
      control_runtime: __MODULE__.SetBControlRuntime,
      domain: __MODULE__.SetBDomain,
      projections_runtime: __MODULE__.SetBProjectionsRuntime,
      telemetry: __MODULE__.SetBTelemetry
    }
  }

  @consumer_keys [
    :contact,
    :control_runtime,
    :domain,
    :projections_runtime,
    :telemetry
  ]

  test "named consumer sets remain isolated when one event bus and set stop and restart" do
    bus_a = start_event_bus(:a)
    bus_b = start_event_bus(:b)
    consumers_a = start_consumer_set(:a, bus_a)
    consumers_b = start_consumer_set(:b, bus_b)

    assert_set_liveness(:a, bus_a, consumers_a)
    assert_set_liveness(:b, bus_b, consumers_b)

    publish_and_assert_set(bus_a, :a, :initial)
    refute_consumed(:b)

    publish_and_assert_set(bus_b, :b, :initial)
    refute_consumed(:a)

    stop_consumer_set(:a, bus_a, consumers_a)

    assert_set_liveness(:b, bus_b, consumers_b)
    publish_and_assert_set(bus_b, :b, :while_a_stopped)
    refute_consumed(:a)

    restarted_bus_a = start_event_bus(:a)
    restarted_consumers_a = start_consumer_set(:a, restarted_bus_a)

    refute restarted_bus_a == bus_a

    Enum.each(@consumer_keys, fn key ->
      refute Map.fetch!(restarted_consumers_a, key) == Map.fetch!(consumers_a, key)
    end)

    assert_set_liveness(:a, restarted_bus_a, restarted_consumers_a)
    assert_set_liveness(:b, bus_b, consumers_b)

    publish_and_assert_set(restarted_bus_a, :a, :after_restart)
    refute_consumed(:b)

    publish_and_assert_set(bus_b, :b, :after_a_restart)
    refute_consumed(:a)
  end

  defp start_event_bus(set) do
    name = bus_name(set)

    pid =
      start_supervised!(%{
        id: event_bus_child_id(set),
        start: {EventBus, :start_link, [[name: name, delivery: :sync, before_notify: nil]]},
        restart: :temporary
      })

    assert Process.whereis(name) == pid
    pid
  end

  defp start_consumer_set(set, event_bus) do
    owner = self()

    %{
      contact:
        start_consumer(
          set,
          :contact,
          ContactFactConsumer,
          event_bus,
          notify_release_target: fn contact ->
            send(owner, {:consumed, set, :contact, contact.realized_contact_id})
          end
        ),
      control_runtime:
        start_consumer(
          set,
          :control_runtime,
          ControlRuntimeFactConsumer,
          event_bus,
          evaluate_telemetry: fn samples ->
            send(owner, {:consumed, set, :control_runtime, samples})
          end,
          evaluate_transport: fn _capability_records, _action_requests -> :ok end
        ),
      domain:
        start_consumer(
          set,
          :domain,
          DomainFactConsumer,
          event_bus,
          project_fact: fn fact ->
            send(owner, {:consumed, set, :domain, fact.activation_id})
          end
        ),
      projections_runtime:
        start_consumer(
          set,
          :projections_runtime,
          ProjectionsRuntimeFactConsumer,
          event_bus,
          project_records: fn records ->
            send(owner, {:consumed, set, :projections_runtime, records})
          end
        ),
      telemetry:
        start_consumer(
          set,
          :telemetry,
          TelemetryFactConsumer,
          event_bus,
          refresh_point: fn mission_id, point_id, opts ->
            send(owner, {:consumed, set, :telemetry, {mission_id, point_id, opts}})
            {:ok, nil}
          end
        )
    }
  end

  defp start_consumer(set, key, module, event_bus, collaborator_opts) do
    name = consumer_name(set, key)
    opts = [name: name, event_bus: event_bus] ++ collaborator_opts

    pid =
      start_supervised!(%{
        id: consumer_child_id(set, key),
        start: {module, :start_link, [opts]},
        restart: :temporary
      })

    assert Process.whereis(name) == pid
    pid
  end

  defp stop_consumer_set(set, event_bus, consumers) do
    consumer_monitors =
      Map.new(consumers, fn {key, pid} ->
        {key, Process.monitor(pid)}
      end)

    Enum.each(@consumer_keys, fn key ->
      assert :ok = stop_supervised(consumer_child_id(set, key))
    end)

    Enum.each(@consumer_keys, fn key ->
      pid = Map.fetch!(consumers, key)
      monitor = Map.fetch!(consumer_monitors, key)
      assert_receive {:DOWN, ^monitor, :process, ^pid, _reason}
      assert Process.whereis(consumer_name(set, key)) == nil
    end)

    event_bus_monitor = Process.monitor(event_bus)
    assert :ok = stop_supervised(event_bus_child_id(set))
    assert_receive {:DOWN, ^event_bus_monitor, :process, ^event_bus, _reason}
    assert Process.whereis(bus_name(set)) == nil
  end

  defp assert_set_liveness(set, event_bus, consumers) do
    assert Process.alive?(event_bus)
    assert Process.whereis(bus_name(set)) == event_bus

    Enum.each(@consumer_keys, fn key ->
      consumer = Map.fetch!(consumers, key)
      assert Process.alive?(consumer)
      assert Process.whereis(consumer_name(set, key)) == consumer
    end)
  end

  defp publish_and_assert_set(event_bus, set, phase) do
    token = "#{set}-#{phase}"
    now = DateTime.utc_now()
    contact_id = "contact-#{token}"
    telemetry_samples = [%{sample_id: "sample-#{token}"}]
    action_requests = [%{request_id: "action-#{token}"}]
    activation_id = "activation-#{token}"
    mission_id = "mission-#{token}"
    point_id = "HK.#{token}"

    selection_opts = [
      organization_id: "organization-#{token}",
      spacecraft_id: "spacecraft-#{token}",
      realm: :replay,
      replay_run_id: "replay-#{token}",
      data_source_id: "source-#{token}",
      binding_id: "binding-#{token}"
    ]

    contact =
      RealizedContact.new(%{
        realized_contact_id: contact_id,
        mission_id: mission_id
      })

    assert :ok = Cadence.Contacts.Facts.publish(event_bus, contact)
    assert_received {:consumed, ^set, :contact, ^contact_id}

    assert :ok =
             Cadence.Runtime.Facts.publish(event_bus, %ProcessingResultsPersisted{
               batch_id: "batch-#{token}",
               evidence_ids: [],
               telemetry_samples: telemetry_samples,
               persisted_at: now
             })

    assert_received {:consumed, ^set, :control_runtime, ^telemetry_samples}

    assert :ok =
             Cadence.Runtime.Facts.publish(event_bus, %ManagedRecordsPersisted{
               capability_records: [],
               action_requests: action_requests,
               timer_events: [],
               persisted_at: now
             })

    assert_received {:consumed, ^set, :projections_runtime, ^action_requests}

    combined_records = [%{merged_record_id: "merged-#{token}"}]
    diagnostics = [%{diagnostic_id: "diagnostic-#{token}"}]
    projected_downlink_records = combined_records ++ diagnostics

    assert :ok =
             Cadence.Runtime.Facts.publish(event_bus, %DownlinkRecordsPersisted{
               observations: [],
               combined_records: combined_records,
               diagnostics: diagnostics,
               persisted_at: now
             })

    assert_received {:consumed, ^set, :projections_runtime, ^projected_downlink_records}

    activation =
      BindingSetActivation.new(%{
        activation_id: activation_id,
        mission_id: mission_id,
        binding_set_id: "binding-set-#{token}",
        binding_set_version: 1
      })

    assert :ok = Cadence.Activations.Facts.publish(event_bus, activation)
    assert_received {:consumed, ^set, :domain, ^activation_id}

    telemetry_fact = %ObservationIdentitySelectionChanged{
      observation_identity_id: "observation-#{token}",
      organization_id: "organization-#{token}",
      mission_id: mission_id,
      point_id: point_id,
      spacecraft_id: "spacecraft-#{token}",
      realm: :replay,
      replay_run_id: "replay-#{token}",
      data_source_id: "source-#{token}",
      binding_id: "binding-#{token}",
      committed_at: now
    }

    assert :ok = Cadence.Telemetry.Facts.publish(event_bus, telemetry_fact)

    assert_received {:consumed, ^set, :telemetry, {^mission_id, ^point_id, ^selection_opts}}
  end

  defp refute_consumed(set) do
    refute_received {:consumed, ^set, _consumer, _payload}
  end

  defp bus_name(set), do: Map.fetch!(@bus_names, set)

  defp consumer_name(set, key) do
    @consumer_names
    |> Map.fetch!(set)
    |> Map.fetch!(key)
  end

  defp event_bus_child_id(set), do: {__MODULE__, :event_bus, set}
  defp consumer_child_id(set, key), do: {__MODULE__, :consumer, set, key}
end
