defmodule Cadence.IngressJournal.EvidenceContactContextTest do
  @moduledoc """
  qa issue 61 (11-14): journaled evidence keeps the contact, path and binding the TCP receiver
  journals, so protocol archive rows name their contact (they were all NULL) and #88's quarantine
  items can group by contact and join their pass.
  """
  use ExUnit.Case, async: true

  alias Cadence.IngressJournal.{Evidence, FileSystem}
  alias Cadence.Protocol.RecordArchive.FileSystem, as: RecordArchive
  alias Cadence.Protocol.TransferFrameRecord

  @tag :tmp_dir
  test "merged journal evidence carries the contact, path and binding into the archive entry", %{
    tmp_dir: tmp_dir
  } do
    name = :"evidence_contact_#{System.unique_integer([:positive])}"

    start_supervised!(
      {FileSystem,
       name: name,
       mission_id: "mission-61",
       realized_contact_id: "contact-61",
       path_id: "route-61:downlink",
       provider_binding_id: "binding-61",
       base_path: tmp_dir,
       durability: :sync,
       max_bytes: 64 * 1_024,
       segment_bytes: 32 * 1_024,
       checkpoint_interval_ms: 60_000}
    )

    # What the TCP receiver journals (tcp_socket.ex journal_metadata/1).
    metadata = %{
      mission_id: "mission-61",
      realized_contact_id: "contact-61",
      path_id: "route-61:downlink",
      provider_binding_id: "binding-61",
      protocol_family: :tm,
      direction: :downlink,
      ingress_metadata: %{frame_size: 14, ocf_length: 0}
    }

    entries =
      for i <- 1..2 do
        {:ok, [entry]} =
          FileSystem.append_stream(name, :binary.copy(<<i>>, 14), DateTime.utc_now(), metadata)

        entry
      end

    assert {:ok, evidence} = Evidence.from_contiguous_entries(entries)

    assert %{
             "realized_contact_id" => "contact-61",
             "path_id" => "route-61:downlink",
             "provider_binding_id" => "binding-61",
             frame_size: 14
           } = evidence.metadata

    frame =
      TransferFrameRecord.new(%{
        frame_record_id: "frame-61",
        evidence_id: evidence.evidence_id,
        mission_id: "mission-61",
        protocol_family: :tm,
        direction: :downlink,
        scid: 1,
        vcid: 0,
        frame_seq: 1,
        raw_frame_offset_bytes: 0,
        raw_frame_length_bytes: 14,
        payload_length_bytes: 8,
        first_header_pointer: 0,
        quality: :good,
        receipt_time: evidence.receipt_time
      })

    assert [entry] = RecordArchive.build_entries(evidence, [frame], [])
    assert get_in(entry, ["metadata", "realized_contact_id"]) == "contact-61"
    assert get_in(entry, ["metadata", "path_id"]) == "route-61:downlink"
    assert get_in(entry, ["metadata", "provider_binding_id"]) == "binding-61"
  end
end
