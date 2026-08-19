defmodule Cadence.Platform.FactPublicationIsolationTest do
  use Cadence.DataCase, async: false

  alias Cadence.DataSources.{DataSource, DataSourceEvent, SourceHealthEvent, SourceWatermarkEvent}
  alias Cadence.Management.DataSources.Store, as: DataSourceStore
  alias Cadence.Platform.EventBus
  alias Cadence.Projections.DataSources.Health, as: SourceHealth
  alias Cadence.Runtime.{ManagedRecordsPersisted, Persistence}

  alias Cadence.Telemetry.{
    CurrentValueStore,
    ObservationIdentityStateChanged,
    ObservationsCommitted,
    Sample,
    Storage
  }

  test "committed transitions for one source identity publish only to their selected bus" do
    suffix = System.unique_integer([:positive])
    organization_id = "org-fact-isolation-#{suffix}"
    mission_id = "mission-fact-isolation-#{suffix}"
    persist_mission_scope(organization_id, mission_id)

    bus_a = start_bus()
    bus_b = start_bus()

    start_fact_forwarder(:bus_a, bus_a, [Cadence.DataSources.Facts])
    start_fact_forwarder(:bus_b, bus_b, [Cadence.DataSources.Facts])

    data_source = %DataSource{
      data_source_id: "shared-source",
      organization_id: organization_id,
      mission_id: mission_id,
      isolation_level: :mission_isolated,
      kind: :projection,
      adapter: Cadence.Telemetry.Storage,
      metadata: %{revision: 1}
    }

    assert {:ok, _persisted_source} =
             DataSourceStore.persist_data_source(data_source, event_bus: bus_a)

    assert_fact(:bus_a, {:cadence, :data_sources, :facts}, DataSourceEvent)
    refute_any_fact()

    assert {:ok, _updated_source} =
             data_source
             |> Map.put(:metadata, %{revision: 2})
             |> DataSourceStore.persist_data_source(event_bus: bus_b)

    assert_fact(:bus_b, {:cadence, :data_sources, :facts}, DataSourceEvent)
    refute_any_fact()

    source_identity = %{
      organization_id: organization_id,
      mission_id: mission_id,
      logical_source: :telemetry,
      data_source_id: "shared-source",
      source_binding_id: "shared-binding",
      realm: :flight,
      dataset: "flight"
    }

    assert {:ok, %SourceHealthEvent{} = unavailable, _status} =
             source_identity
             |> Map.merge(%{
               source_health: :unavailable,
               reason: :timeout,
               observed_at: ~U[2026-08-19 12:00:00Z]
             })
             |> SourceHealth.record_source_health(event_bus: bus_a)

    assert_fact(:bus_a, {:cadence, :data_sources, :facts}, unavailable)
    refute_any_fact()

    assert {:ok, %SourceHealthEvent{} = recovered, _status} =
             source_identity
             |> Map.merge(%{
               source_health: :healthy,
               reason: :source_recovered,
               observed_at: ~U[2026-08-19 12:01:00Z]
             })
             |> SourceHealth.record_source_health(event_bus: bus_b)

    assert_fact(:bus_b, {:cadence, :data_sources, :facts}, recovered)
    refute_any_fact()

    assert [^recovered, ^unavailable] =
             SourceHealth.list_source_health_events(organization_id, mission_id)
  end

  test "captured storage policies and explicit persistence arities keep nested facts isolated" do
    suffix = System.unique_integer([:positive])
    organization_id = "org-storage-fact-isolation-#{suffix}"
    mission_id = "mission-storage-fact-isolation-#{suffix}"
    persist_mission_scope(organization_id, mission_id)

    bus_a = start_bus()
    bus_b = start_bus()

    fact_facades = [Cadence.Telemetry.Facts, Cadence.DataSources.Facts, Cadence.Runtime.Facts]
    start_fact_forwarder(:bus_a, bus_a, fact_facades)
    start_fact_forwarder(:bus_b, bus_b, fact_facades)

    current_value_store_policy =
      CurrentValueStore.policy(module: Cadence.Telemetry.CurrentValueStore.ETS)

    start_supervised!(CurrentValueStore.child_spec(current_value_store_policy))
    CurrentValueStore.reset(current_value_store_policy)

    policy_a = storage_policy(bus_a, current_value_store_policy)
    policy_b = storage_policy(bus_b, current_value_store_policy)

    assert :ok =
             Storage.persist_samples(policy_a, [sample("sample-a", mission_id, 1)],
               organization_id: organization_id,
               source_watermark_events?: true,
               publish_facts?: true
             )

    assert_fact(:bus_a, {:cadence, :telemetry, :facts}, ObservationIdentityStateChanged)
    assert_fact(:bus_a, {:cadence, :data_sources, :facts}, SourceWatermarkEvent)
    assert_fact(:bus_a, {:cadence, :telemetry, :facts}, ObservationsCommitted)
    refute_any_fact()

    assert :ok =
             Storage.persist_samples(policy_b, [sample("sample-b", mission_id, 2)],
               organization_id: organization_id,
               source_watermark_events?: true,
               publish_facts?: true
             )

    assert_fact(:bus_b, {:cadence, :telemetry, :facts}, ObservationIdentityStateChanged)
    assert_fact(:bus_b, {:cadence, :data_sources, :facts}, SourceWatermarkEvent)
    assert_fact(:bus_b, {:cadence, :telemetry, :facts}, ObservationsCommitted)
    refute_any_fact()

    assert length(Storage.list_observation_identity_states(mission_id)) == 2

    assert :ok = Persistence.persist_managed_runtime_records(bus_a, [], [], [])
    assert_fact(:bus_a, {:cadence, :runtime, :facts}, ManagedRecordsPersisted)
    refute_any_fact()

    assert :ok = Persistence.persist_managed_runtime_records(bus_b, [], [], [])
    assert_fact(:bus_b, {:cadence, :runtime, :facts}, ManagedRecordsPersisted)
    refute_any_fact()
  end

  defp storage_policy(event_bus, current_value_store_policy) do
    Storage.policy(
      [
        writer: Cadence.TestSupport.CapturingTelemetryStorageWriter,
        writer_opts: [test_pid: self()],
        organization_id: "unused-explicit-organization",
        realm: :flight,
        data_source_id: "managed_questdb_primary",
        binding_id: "default_flight_telemetry"
      ],
      current_value_store_policy: current_value_store_policy,
      event_bus: event_bus
    )
  end

  defp sample(sample_id, mission_id, minute) do
    at = DateTime.add(~U[2026-08-19 12:00:00Z], minute, :minute)

    %Sample{
      sample_id: sample_id,
      mission_id: mission_id,
      spacecraft_id: "spacecraft-1",
      point_id: "HK.counter",
      point_name: "HK.counter",
      packet_definition_id: "packet-definition-1",
      packet_definition_version: 1,
      packet_id: "packet-#{minute}",
      evidence_id: "evidence-#{minute}",
      raw_value: minute,
      engineering_value: minute,
      quality_state: :good,
      generation_time: at,
      receipt_time: DateTime.add(at, 1, :second),
      provenance: %{}
    }
  end

  defp start_fact_forwarder(bus_tag, event_bus, facades) do
    owner = self()

    forwarder =
      start_supervised!(%{
        id: {:fact_publication_forwarder, bus_tag, make_ref()},
        start:
          {Task, :start_link,
           [fn -> subscribe_and_forward_facts(owner, bus_tag, event_bus, facades) end]},
        restart: :temporary
      })

    assert_receive {:fact_forwarder_ready, ^bus_tag, ^forwarder}
    forwarder
  end

  defp subscribe_and_forward_facts(owner, bus_tag, event_bus, facades) do
    Enum.each(facades, fn facade ->
      :ok = facade.subscribe(event_bus, self())
    end)

    send(owner, {:fact_forwarder_ready, bus_tag, self()})
    forward_facts(owner, bus_tag)
  end

  defp forward_facts(owner, bus_tag) do
    receive do
      {:"$gen_cast", {:cadence_fact, topic, fact}} ->
        send(owner, {:fact_delivery, bus_tag, topic, fact})
        forward_facts(owner, bus_tag)
    end
  end

  defp start_bus do
    start_supervised!(%{
      id: {:fact_publication_event_bus, make_ref()},
      start: {EventBus, :start_link, [[name: nil, delivery: :async, before_notify: nil]]},
      restart: :temporary
    })
  end

  defp assert_fact(bus_tag, topic, expected) when is_struct(expected) do
    assert_receive {:fact_delivery, ^bus_tag, ^topic, ^expected}
  end

  defp assert_fact(bus_tag, topic, fact_module) when is_atom(fact_module) do
    assert_receive {:fact_delivery, ^bus_tag, ^topic, fact}
    assert fact.__struct__ == fact_module
  end

  defp refute_any_fact do
    refute_receive {:fact_delivery, _bus_tag, _topic, _fact}
  end
end
