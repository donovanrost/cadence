defmodule Cadence.Telemetry.Handlers.DefinitionBoundTelemetryHandlerTest do
  @moduledoc """
  #161: a sample's id comes from its packet, never from the evidence that carried it. A journaled
  packet's id is its journal position (stream, frame offset, bytes; #71), so a replay that batches
  the journal differently re-derives the same sample ids instead of writing every sample again.
  """
  use Cadence.UnitCase, async: true

  alias Cadence.ApplicationDispatch.WorkItem
  alias Cadence.IngressJournal.Identity
  alias Cadence.Protocol.PacketRecord
  alias Cadence.Telemetry.{FieldDefinition, PacketDefinition}
  alias Cadence.Telemetry.Handlers.DefinitionBoundTelemetryHandler, as: Handler

  @bytes <<7, 1, 2>>

  test "a sample's id doesn't depend on the evidence that carried its packet" do
    packet_id = Identity.journal_packet_id("stream-a", 40, @bytes)

    first = sample_ids(packet(packet_id, Identity.evidence_id("stream-a", 0, 60)))
    rebatched = sample_ids(packet(packet_id, Identity.evidence_id("stream-a", 30, 50)))

    assert first == rebatched
  end

  test "another packet, or another field of the same packet, is another sample" do
    evidence = Identity.evidence_id("stream-a", 0, 60)

    [mode, volts] =
      sample_ids(packet(Identity.journal_packet_id("stream-a", 40, @bytes), evidence))

    # The same bytes at another offset of the stream, or in another stream (another station or
    # pass), are other receipts.
    [other_offset, _] =
      sample_ids(packet(Identity.journal_packet_id("stream-a", 50, @bytes), evidence))

    [other_stream, _] =
      sample_ids(packet(Identity.journal_packet_id("stream-b", 40, @bytes), evidence))

    assert mode != volts
    assert Enum.uniq([mode, other_offset, other_stream]) == [mode, other_offset, other_stream]
  end

  test "without a journal position, each evidence's packet stays its own sample" do
    # TM with no journal stream and direct space-packet input keep the evidence-scoped packet id,
    # so two receipts of the same bytes stay two samples.
    first = Identity.evidence_id("stream-a", 0, 60)
    second = Identity.evidence_id("stream-a", 60, 120)

    refute sample_ids(packet(Identity.packet_id(first, 0, @bytes), first)) ==
             sample_ids(packet(Identity.packet_id(second, 0, @bytes), second))
  end

  defp sample_ids(%PacketRecord{} = record) do
    {:ok, samples} = Handler.handle(record, work_item())
    Enum.map(samples, & &1.sample_id)
  end

  defp packet(packet_id, evidence_id) do
    %PacketRecord{
      packet_id: packet_id,
      evidence_id: evidence_id,
      mission_id: "mission-161",
      source_endpoint_ref: "endpoint-161",
      spacecraft_id: "sc-161",
      protocol_family: :tm,
      apid: 42,
      packet_data: @bytes,
      receipt_time: ~U[2026-11-19 21:00:00.000000Z]
    }
  end

  defp work_item do
    %WorkItem{
      binding_rule_id: "rule-161",
      handler_key: :definition_bound_telemetry,
      handler_configuration: %PacketDefinition{
        packet_definition_id: "packet-161",
        organization_id: "org-161",
        mission_id: "mission-161",
        packet_name: "HEALTH",
        apid: 42,
        version: 1,
        fields: [
          field("field-mode", "mode", 0, 8, :uint),
          field("field-volts", "volts", 8, 16, :int)
        ]
      }
    }
  end

  defp field(id, name, offset, size, type) do
    %FieldDefinition{
      field_id: id,
      name: name,
      parameter_id: "param-" <> name,
      qualified_name: "HEALTH." <> name,
      offset_bits: offset,
      size_bits: size,
      data_type: type,
      engineering_unit: nil,
      byte_order: :big_endian
    }
  end
end
