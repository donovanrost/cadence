defmodule Cadence.Runtime.ManagedApplicationRuntimeTest do
  use Cadence.RuntimeCase, async: false

  import Ecto.Query

  alias Cadence.ApplicationDispatch.{
    BindingRule,
    BindingSet,
    CapabilityConfig,
    CapabilityInstance
  }

  alias Cadence.Ingress.RawEvidence

  alias Cadence.Persistence.Schemas.{
    ManagedActionRequestRow,
    ManagedCapabilityRecordRow,
    ManagedTimerEventRow
  }

  alias Cadence.Runtime
  alias Cadence.SourceEndpoints.SourceEndpoint
  alias Cadence.Spacecraft
  alias Cadence.Telemetry.PacketDefinition

  setup do
    mission_id =
      "mission-managed-runtime-" <> Integer.to_string(System.unique_integer([:positive]))

    on_exit(fn ->
      Runtime.stop_mission(mission_id)
    end)

    %{mission_id: mission_id}
  end

  test "runs a managed application inside the active partition and executes its timer", %{
    mission_id: mission_id
  } do
    source_endpoint = persist_source_endpoint(mission_id)

    binding_set =
      packet_counter_binding_set(mission_id, source_endpoint.source_endpoint_id, 1,
        flush_interval_ms: 250
      )

    assert {:ok, ^binding_set} = Cadence.Governance.persist_binding_set(binding_set)

    assert {:ok, _activation} =
             Cadence.activate_binding_set(
               mission_id,
               binding_set.binding_set_id,
               binding_set.version
             )

    raw_evidence =
      RawEvidence.new(%{
        mission_id: mission_id,
        source_ref: "provider/station-a",
        raw: build_space_packet(42, 1, <<0, 7>>)
      })

    assert {:ok, result} = Cadence.process_telemetry_ingress(raw_evidence)
    assert result.outputs == []

    assert Repo.aggregate(ManagedCapabilityRecordRow, :count, :capability_record_id) == 2
    assert Repo.aggregate(ManagedActionRequestRow, :count, :action_request_id) == 1
    assert Repo.aggregate(ManagedTimerEventRow, :count, :timer_event_id) == 1

    assert {:ok, snapshot_before_flush} =
             Runtime.partition_snapshot(mission_id, source_endpoint.source_endpoint_id)

    assert snapshot_before_flush.managed_application_count == 1
    assert snapshot_before_flush.timer_count == 1

    [managed_application] = snapshot_before_flush.managed_applications
    assert managed_application.capability_instance_id == "packet-counter-instance-v1"
    assert managed_application.family_key == :packet_counter
    assert managed_application.state.packet_count == 1
    assert managed_application.state.flush_count == 0
    assert managed_application.state.timer_armed?

    assert {:ok, snapshot_after_flush} =
             await_snapshot(
               mission_id,
               source_endpoint.source_endpoint_id,
               fn snapshot ->
                 [managed_application] = snapshot.managed_applications

                 snapshot.timer_count == 0 and
                   managed_application.state.packet_count == 0 and
                   managed_application.state.flush_count == 1 and
                   managed_application.state.last_flushed_count == 1 and
                   not managed_application.state.timer_armed?
               end,
               50
             )

    [managed_application] = snapshot_after_flush.managed_applications
    assert managed_application.state.metric_name == "packet_window"

    assert Repo.aggregate(ManagedCapabilityRecordRow, :count, :capability_record_id) == 3
    assert Repo.aggregate(ManagedActionRequestRow, :count, :action_request_id) == 1
    assert Repo.aggregate(ManagedTimerEventRow, :count, :timer_event_id) == 2

    capability_events =
      ManagedCapabilityRecordRow
      |> where([row], row.mission_id == ^mission_id)
      |> order_by([row], asc: row.recorded_at, asc: row.capability_record_id)
      |> Repo.all()

    assert Enum.map(capability_events, & &1.event_kind) == [
             "initialized",
             "record_handled",
             "timer_handled"
           ]

    timer_events =
      ManagedTimerEventRow
      |> where([row], row.mission_id == ^mission_id)
      |> order_by([row], asc: row.occurred_at, asc: row.timer_event_id)
      |> Repo.all()

    assert Enum.map(timer_events, & &1.event_kind) == ["scheduled", "fired"]
  end

  test "reconciliation removes managed application timers when a new basis replaces them", %{
    mission_id: mission_id
  } do
    source_endpoint = persist_source_endpoint(mission_id)

    packet_counter_binding_set =
      packet_counter_binding_set(mission_id, source_endpoint.source_endpoint_id, 1,
        flush_interval_ms: 250
      )

    telemetry_binding_set = telemetry_binding_set(mission_id, 2)

    assert {:ok, ^packet_counter_binding_set} =
             Cadence.Governance.persist_binding_set(packet_counter_binding_set)

    assert {:ok, ^telemetry_binding_set} =
             Cadence.Governance.persist_binding_set(telemetry_binding_set)

    assert {:ok, _activation} =
             Cadence.activate_binding_set(
               mission_id,
               packet_counter_binding_set.binding_set_id,
               packet_counter_binding_set.version
             )

    raw_evidence =
      RawEvidence.new(%{
        mission_id: mission_id,
        source_ref: "provider/station-a",
        raw: build_space_packet(42, 1, <<0, 9>>)
      })

    assert {:ok, first_result} = Cadence.process_telemetry_ingress(raw_evidence)
    assert first_result.outputs == []

    assert {:ok, armed_snapshot} =
             Runtime.partition_snapshot(mission_id, source_endpoint.source_endpoint_id)

    assert armed_snapshot.timer_count == 1
    assert Repo.aggregate(ManagedTimerEventRow, :count, :timer_event_id) == 1

    assert {:ok, _activation} =
             Cadence.activate_binding_set(
               mission_id,
               telemetry_binding_set.binding_set_id,
               telemetry_binding_set.version
             )

    assert {:ok, reconciled_snapshot} =
             await_snapshot(
               mission_id,
               source_endpoint.source_endpoint_id,
               fn snapshot ->
                 snapshot.managed_application_count == 0 and snapshot.timer_count == 0
               end
             )

    assert reconciled_snapshot.handler_keys == [:definition_bound_telemetry]
    assert reconciled_snapshot.timer_count == 0

    timer_events =
      ManagedTimerEventRow
      |> where([row], row.mission_id == ^mission_id)
      |> order_by([row], asc: row.occurred_at, asc: row.timer_event_id)
      |> Repo.all()

    assert Enum.any?(timer_events, &(&1.event_kind == "canceled"))

    assert {:ok, second_result} = Cadence.process_telemetry_ingress(raw_evidence)
    assert Enum.map(second_result.outputs, & &1.point_name) == ["HK.counter"]
  end

  defp packet_counter_binding_set(mission_id, source_endpoint_ref, version, opts) do
    BindingSet.new(%{
      mission_id: mission_id,
      binding_set_id: "managed-runtime-basis",
      version: version,
      capability_instances: [
        CapabilityInstance.new(%{
          capability_instance_id: "packet-counter-instance-v" <> Integer.to_string(version),
          family_key: :packet_counter,
          target_scope: :source_endpoint,
          source_endpoint_ref: source_endpoint_ref,
          capability_config:
            CapabilityConfig.inline(%{
              "metric_name" => "packet_window",
              "flush_interval_ms" => Keyword.get(opts, :flush_interval_ms, 25)
            })
        })
      ],
      rules: [
        BindingRule.new(%{
          binding_rule_id: "packet-counter-rule-v" <> Integer.to_string(version),
          capability_instance_id: "packet-counter-instance-v" <> Integer.to_string(version),
          selector: %{
            scope: %{target_scope: :source_endpoint, source_endpoint_ref: source_endpoint_ref},
            match: %{packet_kind: :space_packet, apid: 42}
          },
          fanout_mode: :multi,
          priority: 10
        })
      ]
    })
  end

  defp telemetry_binding_set(mission_id, version) do
    packet_definition =
      PacketDefinition.new(%{
        mission_id: mission_id,
        packet_definition_id: "hk-packet-v" <> Integer.to_string(version),
        packet_name: "HK",
        apid: 42,
        version: version,
        fields: [
          %{field_id: "counter", name: "counter", offset_bits: 0, size_bits: 16, data_type: :uint}
        ]
      })

    BindingSet.new(%{
      mission_id: mission_id,
      binding_set_id: "managed-runtime-basis",
      version: version,
      rules: [
        BindingRule.new(%{
          binding_rule_id: "telemetry-rule-v" <> Integer.to_string(version),
          handler_key: :definition_bound_telemetry,
          packet_kind: :space_packet,
          apid: 42,
          priority: 10,
          handler_configuration: packet_definition
        })
      ]
    })
  end

  defp persist_source_endpoint(mission_id) do
    spacecraft =
      Spacecraft.new(%{
        spacecraft_id: "sc-alpha",
        mission_id: mission_id,
        display_name: "SC Alpha"
      })

    assert {:ok, _persisted_spacecraft} = Cadence.SpacecraftStore.persist_spacecraft(spacecraft)

    source_endpoint =
      SourceEndpoint.new(%{
        source_endpoint_id: "endpoint-sc-alpha",
        mission_id: mission_id,
        spacecraft_id: "sc-alpha",
        source_ref: "provider/station-a"
      })

    assert {:ok, persisted_source_endpoint} =
             Cadence.SourceEndpoints.persist_source_endpoint(source_endpoint)

    persisted_source_endpoint
  end

  defp await_snapshot(mission_id, source_endpoint_ref, predicate, attempts \\ 20)

  defp await_snapshot(_mission_id, _source_endpoint_ref, _predicate, 0) do
    flunk("snapshot condition was not reached in time")
  end

  defp await_snapshot(mission_id, source_endpoint_ref, predicate, attempts) do
    assert {:ok, snapshot} = Runtime.partition_snapshot(mission_id, source_endpoint_ref)

    if predicate.(snapshot) do
      {:ok, snapshot}
    else
      Process.sleep(10)
      await_snapshot(mission_id, source_endpoint_ref, predicate, attempts - 1)
    end
  end

  defp build_space_packet(apid, sequence_count, packet_data) do
    packet_length = byte_size(packet_data) - 1

    <<
      0::3,
      0::1,
      0::1,
      apid::11,
      3::2,
      sequence_count::14,
      packet_length::16,
      packet_data::binary
    >>
  end
end
