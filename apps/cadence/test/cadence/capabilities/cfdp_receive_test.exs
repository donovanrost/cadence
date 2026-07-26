defmodule Cadence.Capabilities.CFDPReceiveTest do
  use Cadence.UnitCase, async: true

  alias Cadence.Capabilities.Definitions.CFDPReceive, as: CFDPReceiveDefinition
  alias Cadence.Capabilities.ExecutionContext
  alias Cadence.Capabilities.ManagedApplications.CFDPReceive
  alias Cadence.Capabilities.ValidationContext
  alias Cadence.CCSDS.CFDP.Codec
  alias Cadence.CCSDS.CFDP.Directive.Metadata
  alias Cadence.CCSDS.CFDP.PDU
  alias Cadence.Protocol.PacketRecord

  test "declares a bounded source-endpoint managed application contract" do
    descriptor = CFDPReceiveDefinition.descriptor()

    assert descriptor.family_key == :cfdp_receive
    assert descriptor.kind == :managed_application
    assert descriptor.supported_scopes == [:source_endpoint]
    assert descriptor.input_stages == [:space_packet]
    assert descriptor.partition_affinity == :source_endpoint
    assert descriptor.emitted_record_kinds == [:cfdp_transaction_event]
    assert descriptor.emitted_action_kinds == [:schedule_timer, :cancel_timer]
  end

  test "validates bounded receive configuration without loading runtime code" do
    context =
      ValidationContext.new(%{
        mission_id: "mission-cfdp-definition",
        target_scope: :source_endpoint,
        source_endpoint_ref: "endpoint-cfdp-definition",
        input_stage: :space_packet
      })

    assert :ok =
             CFDPReceiveDefinition.validate_config(
               %{
                 "local_entity_id" => 3,
                 "check_interval_ms" => 5_000,
                 "max_in_memory_file_octets" => 4_096
               },
               context
             )

    assert {:error, {:invalid_field, :max_in_memory_file_octets, 0}} =
             CFDPReceiveDefinition.validate_config(
               %{"local_entity_id" => 3, "max_in_memory_file_octets" => 0},
               context
             )

    assert {:error, {:unknown_cfdp_receive_configuration_keys, ["filestore_path"]}} =
             CFDPReceiveDefinition.validate_config(
               %{"local_entity_id" => 3, "filestore_path" => "/tmp/unsafe"},
               context
             )
  end

  test "refuses transfers that require the not-yet-defined outbound transport boundary" do
    execution_context = %ExecutionContext{}

    assert {:ok, initialized} =
             CFDPReceive.init_instance(%{"local_entity_id" => 3}, execution_context)

    pdu = %PDU{
      direction: :toward_file_receiver,
      transmission_mode: :unacknowledged,
      source_entity_id: 1,
      transaction_sequence_number: 9,
      destination_entity_id: 3,
      entity_id_octets: 1,
      sequence_number_octets: 1,
      payload: %Metadata{closure_requested?: true, file_size: 0}
    }

    assert {:ok, packet_data} = Codec.encode(pdu)

    assert {:error, :cfdp_closure_transport_not_configured} =
             CFDPReceive.handle_record(
               %PacketRecord{packet_data: packet_data},
               initialized.state,
               execution_context
             )
  end
end
