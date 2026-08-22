defmodule CadenceWeb.API.TelemetryJSON do
  @moduledoc "Telemetry and data-plane ingress response serialization boundary."

  alias Cadence.ApplicationDispatch.{DispatchDecision, WorkItem}
  alias Cadence.Ingress.RawEvidence
  alias Cadence.Persistence.JsonDocument
  alias Cadence.Protocol.{PacketRecord, ProtocolAnomaly, TransferFrameRecord}
  alias Cadence.Telemetry.Sample

  @spec telemetry_sample(Sample.t()) :: map()
  def telemetry_sample(%Sample{} = sample) do
    %{
      sample_id: sample.sample_id,
      mission_id: sample.mission_id,
      spacecraft_id: sample.spacecraft_id,
      point_id: sample.point_id,
      point_name: sample.point_name,
      packet_definition_id: sample.packet_definition_id,
      packet_definition_version: sample.packet_definition_version,
      packet_id: sample.packet_id,
      evidence_id: sample.evidence_id,
      raw_value: JsonDocument.encode(sample.raw_value),
      engineering_value: JsonDocument.encode(sample.engineering_value),
      quality_state: Atom.to_string(sample.quality_state),
      generation_time: iso8601(sample.generation_time),
      receipt_time: iso8601(sample.receipt_time),
      provenance: JsonDocument.encode(sample.provenance)
    }
  end

  @spec dev_ingress_result(map()) :: map()
  def dev_ingress_result(%{
        raw_evidence: %RawEvidence{} = raw_evidence,
        packet_records: packet_records,
        transfer_frame_records: transfer_frame_records,
        protocol_anomalies: protocol_anomalies,
        dispatch_decisions: dispatch_decisions,
        outputs: outputs
      }) do
    %{
      raw_evidence: raw_evidence(raw_evidence),
      packet_records: Enum.map(packet_records, &packet_record/1),
      transfer_frame_records: Enum.map(transfer_frame_records, &transfer_frame_record/1),
      protocol_anomalies: Enum.map(protocol_anomalies, &protocol_anomaly/1),
      dispatch_decisions: Enum.map(dispatch_decisions, &dispatch_decision/1),
      outputs: Enum.map(outputs, &runtime_output/1)
    }
  end

  defp raw_evidence(%RawEvidence{} = raw_evidence) do
    %{
      evidence_id: raw_evidence.evidence_id,
      mission_id: raw_evidence.mission_id,
      source_endpoint_ref: raw_evidence.source_endpoint_ref,
      spacecraft_id: raw_evidence.spacecraft_id,
      protocol_family: Atom.to_string(raw_evidence.protocol_family),
      direction: Atom.to_string(raw_evidence.direction),
      source_time: iso8601(raw_evidence.source_time),
      receipt_time: iso8601(raw_evidence.receipt_time),
      source_ref: raw_evidence.source_ref,
      raw_hex: hex(raw_evidence.raw),
      raw_size_bytes: byte_size(raw_evidence.raw),
      metadata: raw_evidence.metadata
    }
  end

  defp packet_record(%PacketRecord{} = packet_record) do
    %{
      packet_id: packet_record.packet_id,
      evidence_id: packet_record.evidence_id,
      mission_id: packet_record.mission_id,
      source_endpoint_ref: packet_record.source_endpoint_ref,
      spacecraft_id: packet_record.spacecraft_id,
      protocol_family: Atom.to_string(packet_record.protocol_family),
      packet_kind: Atom.to_string(packet_record.packet_kind),
      apid: packet_record.apid,
      sequence_flags: packet_record.sequence_flags,
      sequence_count: packet_record.sequence_count,
      secondary_header: packet_record.secondary_header?,
      packet_data_hex: hex(packet_record.packet_data),
      packet_data_size_bytes: byte_size(packet_record.packet_data),
      source_time: iso8601(packet_record.source_time),
      receipt_time: iso8601(packet_record.receipt_time),
      provenance: JsonDocument.encode(packet_record.provenance)
    }
  end

  defp transfer_frame_record(%TransferFrameRecord{} = transfer_frame_record) do
    %{
      frame_record_id: transfer_frame_record.frame_record_id,
      evidence_id: transfer_frame_record.evidence_id,
      mission_id: transfer_frame_record.mission_id,
      source_endpoint_ref: transfer_frame_record.source_endpoint_ref,
      spacecraft_id: transfer_frame_record.spacecraft_id,
      protocol_family: Atom.to_string(transfer_frame_record.protocol_family),
      direction: Atom.to_string(transfer_frame_record.direction),
      scid: transfer_frame_record.scid,
      vcid: transfer_frame_record.vcid,
      map_id: transfer_frame_record.map_id,
      frame_seq: transfer_frame_record.frame_seq,
      raw_frame_offset_bytes: transfer_frame_record.raw_frame_offset_bytes,
      raw_frame_length_bytes: transfer_frame_record.raw_frame_length_bytes,
      payload_length_bytes: transfer_frame_record.payload_length_bytes,
      first_header_pointer: transfer_frame_record.first_header_pointer,
      quality: maybe_atom_to_string(transfer_frame_record.quality),
      source_time: iso8601(transfer_frame_record.source_time),
      receipt_time: iso8601(transfer_frame_record.receipt_time),
      metadata: JsonDocument.encode(transfer_frame_record.metadata)
    }
  end

  defp protocol_anomaly(%ProtocolAnomaly{} = protocol_anomaly) do
    %{
      anomaly_id: protocol_anomaly.anomaly_id,
      evidence_id: protocol_anomaly.evidence_id,
      mission_id: protocol_anomaly.mission_id,
      source_endpoint_ref: protocol_anomaly.source_endpoint_ref,
      spacecraft_id: protocol_anomaly.spacecraft_id,
      protocol_family: Atom.to_string(protocol_anomaly.protocol_family),
      direction: Atom.to_string(protocol_anomaly.direction),
      anomaly_kind: Atom.to_string(protocol_anomaly.anomaly_kind),
      scid: protocol_anomaly.scid,
      vcid: protocol_anomaly.vcid,
      map_id: protocol_anomaly.map_id,
      frame_seq: protocol_anomaly.frame_seq,
      raw_frame_offset_bytes: protocol_anomaly.raw_frame_offset_bytes,
      raw_frame_length_bytes: protocol_anomaly.raw_frame_length_bytes,
      recorded_at: iso8601(protocol_anomaly.recorded_at),
      metadata: JsonDocument.encode(protocol_anomaly.metadata)
    }
  end

  defp dispatch_decision(%DispatchDecision{} = dispatch_decision) do
    %{
      dispatch_decision_id: dispatch_decision.dispatch_decision_id,
      packet_id: dispatch_decision.packet_id,
      evidence_id: dispatch_decision.evidence_id,
      binding_set_id: dispatch_decision.binding_set_id,
      binding_set_version: dispatch_decision.binding_set_version,
      status: Atom.to_string(dispatch_decision.status),
      matched_rule_ids: dispatch_decision.matched_rule_ids,
      anomalies: JsonDocument.encode(dispatch_decision.anomalies),
      work_items: Enum.map(dispatch_decision.work_items, &work_item/1)
    }
  end

  defp work_item(%WorkItem{} = work_item) do
    %{
      binding_rule_id: work_item.binding_rule_id,
      capability_instance_id: work_item.capability_instance_id,
      handler_key: Atom.to_string(work_item.handler_key)
    }
  end

  defp runtime_output(%Sample{} = sample) do
    telemetry_sample(sample)
    |> Map.put(:output_kind, "telemetry_sample")
  end

  defp runtime_output(output) do
    %{
      output_kind: "generic",
      output_document: JsonDocument.encode(output)
    }
  end

  defp maybe_atom_to_string(nil), do: nil
  defp maybe_atom_to_string(value) when is_atom(value), do: Atom.to_string(value)
  defp maybe_atom_to_string(value), do: value

  defp hex(binary) when is_binary(binary), do: Base.encode16(binary, case: :lower)

  defp iso8601(nil), do: nil
  defp iso8601(%DateTime{} = datetime), do: DateTime.to_iso8601(datetime)
end
