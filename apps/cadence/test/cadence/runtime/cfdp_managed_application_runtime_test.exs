defmodule Cadence.Runtime.CFDPManagedApplicationRuntimeTest do
  use Cadence.RuntimeCase, async: false

  alias Cadence.ApplicationDispatch.{
    BindingRule,
    BindingSet,
    CapabilityConfig,
    CapabilityInstance
  }

  alias Cadence.CCSDS.CFDP.Class1.Sender
  alias Cadence.CCSDS.CFDP.Codec
  alias Cadence.CFDP.TransactionEvent
  alias Cadence.Ingress.RawEvidence
  alias Cadence.Runtime
  alias Cadence.Runtime.ManagedRecords.ManagedCapabilityRecordRow
  alias Cadence.SourceEndpoints.SourceEndpoint
  alias Cadence.Spacecraft

  setup do
    mission_id = "mission-cfdp-runtime-#{System.unique_integer([:positive])}"

    on_exit(fn -> Runtime.stop_mission(mission_id) end)

    %{mission_id: mission_id}
  end

  test "runs a bounded CFDP receiver across records and platform-owned timers", context do
    source_endpoint = persist_source_endpoint(context.mission_id)
    binding_set = cfdp_binding_set(context.mission_id, source_endpoint.source_endpoint_id)

    assert {:ok, ^binding_set} = Cadence.Governance.persist_binding_set(binding_set)

    assert {:ok, _activation} =
             Cadence.ActivationFixtures.activate_binding_set(
               context.mission_id,
               binding_set.binding_set_id,
               binding_set.version
             )

    {metadata, file_data, eof} = transfer_pdus()

    assert {:ok, eof_result} = process_pdu(context.mission_id, eof, 1)

    assert Enum.any?(eof_result.outputs, fn
             %TransactionEvent{event_type: :eof_received} -> true
             _other -> false
           end)

    assert {:ok, checking_snapshot} =
             Runtime.partition_snapshot(context.mission_id, source_endpoint.source_endpoint_id)

    assert checking_snapshot.managed_application_count == 1
    assert checking_snapshot.timer_count == 1

    [checking_application] = checking_snapshot.managed_applications
    assert checking_application.family_key == :cfdp_receive
    assert checking_application.state.active_transaction_count == 1
    assert checking_application.state.pdu_count == 1
    assert [%{phase: :checking, progress_octets: 0}] = checking_application.state.transactions

    assert {:ok, _data_result} = process_pdu(context.mission_id, file_data, 2)
    assert {:ok, metadata_result} = process_pdu(context.mission_id, metadata, 3)

    assert Enum.any?(metadata_result.outputs, fn
             %TransactionEvent{
               event_type: :transaction_finished,
               details: %{received_file_octets: 3}
             } ->
               true

             _other ->
               false
           end)

    assert {:ok, completed_snapshot} =
             Runtime.partition_snapshot(context.mission_id, source_endpoint.source_endpoint_id)

    [completed_application] = completed_snapshot.managed_applications
    assert completed_snapshot.timer_count == 0
    assert completed_application.state.active_transaction_count == 0
    assert completed_application.state.completed_count == 1
    assert completed_application.state.faulted_count == 0
    assert completed_application.state.pdu_count == 3

    persisted_snapshots =
      ManagedCapabilityRecordRow
      |> where([row], row.family_key == "cfdp_receive")
      |> order_by([row], asc: row.recorded_at, asc: row.capability_record_id)
      |> Repo.all()

    assert length(persisted_snapshots) == 4

    assert Enum.all?(persisted_snapshots, fn row ->
             get_in(row.state_snapshot, ["value", "transactions"]) |> is_list()
           end)
  end

  defp cfdp_binding_set(mission_id, source_endpoint_ref) do
    BindingSet.new(%{
      mission_id: mission_id,
      binding_set_id: "cfdp-runtime-basis",
      version: 1,
      capability_instances: [
        CapabilityInstance.new(%{
          capability_instance_id: "cfdp-receiver-instance",
          family_key: :cfdp_receive,
          target_scope: :source_endpoint,
          source_endpoint_ref: source_endpoint_ref,
          capability_config:
            CapabilityConfig.inline(%{
              "local_entity_id" => 3,
              "check_interval_ms" => 5_000,
              "max_in_memory_file_octets" => 4_096
            })
        })
      ],
      rules: [
        BindingRule.new(%{
          binding_rule_id: "cfdp-receiver-rule",
          capability_instance_id: "cfdp-receiver-instance",
          selector: %{
            scope: %{target_scope: :source_endpoint, source_endpoint_ref: source_endpoint_ref},
            match: %{packet_kind: :space_packet, apid: 88}
          },
          fanout_mode: :multi,
          priority: 10
        })
      ]
    })
  end

  defp transfer_pdus do
    assert {:ok, sender} =
             Sender.new(
               source_entity_id: 1,
               transaction_sequence_number: 7,
               destination_entity_id: 3,
               source_file_name: "source.bin",
               destination_file_name: "received.bin",
               file: <<1, 2, 3>>,
               closure_requested?: false
             )

    assert {:ok, metadata} = Sender.next(sender)
    assert {:ok, file_data} = Sender.next(metadata.state)
    assert {:ok, eof} = Sender.next(file_data.state)

    {List.first(metadata.pdus), List.first(file_data.pdus), List.first(eof.pdus)}
  end

  defp process_pdu(mission_id, pdu, sequence_count) do
    assert {:ok, encoded_pdu} = Codec.encode(pdu)

    raw_evidence =
      RawEvidence.new(%{
        mission_id: mission_id,
        source_ref: "provider/cfdp-station",
        raw: build_space_packet(88, sequence_count, encoded_pdu)
      })

    Cadence.process_telemetry_ingress(raw_evidence)
  end

  defp persist_source_endpoint(mission_id) do
    spacecraft =
      Spacecraft.new(%{
        spacecraft_id: "cfdp-spacecraft",
        mission_id: mission_id,
        display_name: "CFDP Spacecraft"
      })

    assert {:ok, _spacecraft} = Cadence.SpacecraftStore.persist_spacecraft(spacecraft)

    source_endpoint =
      SourceEndpoint.new(%{
        source_endpoint_id: "cfdp-endpoint",
        mission_id: mission_id,
        spacecraft_id: spacecraft.spacecraft_id,
        source_ref: "provider/cfdp-station"
      })

    assert {:ok, persisted} = Cadence.SourceEndpoints.persist_source_endpoint(source_endpoint)
    persisted
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
