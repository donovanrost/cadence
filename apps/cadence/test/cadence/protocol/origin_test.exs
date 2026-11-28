defmodule Cadence.Protocol.OriginTest do
  @moduledoc """
  #1078 P5 slice E1a: a packet's origin descriptor is built at decode, rides the packet's
  provenance and, in memory, its samples (a derived sample takes its trigger's), and enters no id.
  Provenance, never identity: existing ids and replays are unchanged, so it costs no reset, and
  the observation row gains nothing.
  """
  use Cadence.UnitCase, async: true

  alias Cadence.ApplicationDispatch.WorkItem
  alias Cadence.Ingress.RawEvidence
  alias Cadence.IngressJournal.Identity
  alias Cadence.Platform.ContentHash
  alias Cadence.Protocol.{Origin, PacketRecord, TMFrameIngress}
  alias Cadence.Protocol.RecordArchive.FileSystem
  alias Cadence.Protocol.RecordArchive.FileSystem.Index
  alias Cadence.Runtime.PartitionOwner.DerivedSamples
  alias Cadence.SemanticRuntime.Update
  alias Cadence.Telemetry.{FieldDefinition, PacketDefinition}
  alias Cadence.Telemetry.Handlers.DefinitionBoundTelemetryHandler, as: Handler
  alias Cadence.Telemetry.Storage.{ObservationEnvelope, WriteContext}
  alias Cadence.Telemetry.Storage.QuestDB.ObservationRow
  alias CCSDS.Core.SDUOctets
  alias CCSDS.SDLP.TM.Segmentation

  @frame_size 10
  @stream "origin-stream"
  @packet <<0::3, 0::1, 0::1, 42::11, 3::2, 9::14, 1::16, 7::8, 3::8>>

  describe "decode" do
    test "a TM packet's origin names its endpoint, frame facts and APID, with no relay" do
      [packet] = decode(frames())

      assert packet.provenance.origin == %{
               v: 1,
               kind: :direct,
               source_endpoint_id: "endpoint-e1a",
               scid: 11,
               vcid: 2,
               map_id: nil,
               apid: 42,
               relay: nil
             }

      assert Origin.from_provenance(packet.provenance) == packet.provenance.origin
    end

    test "a packet's origin is the same however the journal is batched" do
      bytes = frames()
      [whole] = decode(bytes)
      [first, second] = split(bytes)

      assert {:ok, %{packet_records: [], resume_offset: _}, rest, pipeline, continuity} =
               process(first, 0, <<>>)

      assert {:ok, %{packet_records: [recut]}, _rest, _pipeline, _continuity} =
               process(second, byte_size(first), rest, pipeline, continuity)

      assert recut.provenance.origin == whole.provenance.origin
      assert recut.packet_id == whole.packet_id
    end

    test "the origin reads back from an archive entry's JSON (string keys, kind a string)" do
      [packet] = decode(frames())
      [entry] = FileSystem.build_entries(evidence(frames(), 0), [], [packet])
      json = entry |> Jason.encode!() |> Jason.decode!()

      assert Origin.from_provenance(json["provenance"]) == %{
               "v" => 1,
               "kind" => "direct",
               "source_endpoint_id" => "endpoint-e1a",
               "scid" => 11,
               "vcid" => 2,
               "map_id" => nil,
               "apid" => 42,
               "relay" => nil
             }

      assert Origin.to_json(packet.provenance.origin) ==
               Origin.from_provenance(json["provenance"])
    end

    test "a packet archived before origins were recorded has none" do
      assert Origin.from_provenance(%{}) == nil
      assert Origin.from_provenance(%{"evidence_id" => "e"}) == nil
      assert Origin.from_provenance(nil) == nil
    end
  end

  describe "no identity change" do
    test "the packet id is its journal position, nothing else" do
      [packet] = decode(frames())

      # The stream and the absolute offset of the frame that completed the packet, with its bytes.
      assert {@stream, offset, _receipt} = packet.journal_frame
      assert packet.packet_data == binary_part(@packet, 6, byte_size(@packet) - 6)
      assert packet.packet_id == Identity.journal_packet_id(@stream, offset, @packet)
    end

    test "sample ids are byte-identical with and without an origin, and match the pre-E1a basis" do
      [packet] = decode(frames())
      stripped = %{packet | provenance: Map.delete(packet.provenance, :origin)}

      with_origin = samples(packet)
      without = samples(stripped)

      assert Enum.map(with_origin, & &1.sample_id) == Enum.map(without, & &1.sample_id)

      # The basis that existed before this slice: packet id, definition, field and raw value.
      expected =
        for {field, raw} <- [{"field-mode", 7}, {"field-aux", 3}] do
          "sample_" <>
            ContentHash.term_sha256({packet.packet_id, "packet-e1a", field, raw})
        end

      assert Enum.map(with_origin, & &1.sample_id) == expected
    end

    test "observation ids and the stored row are identical, and the row carries no origin" do
      [packet] = decode(frames())
      stripped = %{packet | provenance: Map.delete(packet.provenance, :origin)}

      [with_origin | _] = Enum.map(samples(packet), &envelope/1)
      [without | _] = Enum.map(samples(stripped), &envelope/1)

      assert with_origin.observation_id == without.observation_id
      assert with_origin.observation_identity_id == without.observation_identity_id
      assert with_origin.idempotency_key == without.idempotency_key

      # What the writer sends is the same, so the observation store gains nothing.
      assert ObservationRow.params(with_origin) == ObservationRow.params(without)
      refute inspect(ObservationRow.params(with_origin)) =~ "origin"
    end

    test "the archive's record identity does not cover provenance" do
      [packet] = decode(frames())
      stripped = %{packet | provenance: Map.delete(packet.provenance, :origin)}
      evidence = evidence(frames(), 0)

      [with_origin] = FileSystem.build_entries(evidence, [], [packet])
      [without] = FileSystem.build_entries(evidence, [], [stripped])

      assert Index.digest(with_origin) == Index.digest(without)
    end
  end

  describe "samples" do
    test "a decoded sample carries its packet's origin in memory, never in its provenance" do
      [packet] = decode(frames())

      for sample <- samples(packet) do
        assert sample.origin == packet.provenance.origin
        refute Map.has_key?(sample.provenance, :origin)
        refute Map.has_key?(sample.provenance, "origin")
      end
    end

    test "a packet without an origin gives samples without one" do
      [packet] = decode(frames())
      stripped = %{packet | provenance: Map.delete(packet.provenance, :origin)}

      assert Enum.all?(samples(stripped), &is_nil(&1.origin))
    end
  end

  describe "derived samples" do
    test "a derived sample takes its trigger's origin, and a timer-triggered one has none" do
      [packet] = decode(frames())
      [trigger | _] = batch = samples(packet)
      origins = DerivedSamples.origins(batch)

      assert Map.keys(origins) |> Enum.sort() == batch |> Enum.map(& &1.sample_id) |> Enum.sort()

      triggered =
        DerivedSamples.build(update(trigger.sample_id, packet.packet_id), activation(), origins)

      assert triggered.origin == packet.provenance.origin
      assert triggered.packet_id == packet.packet_id
      refute Map.has_key?(triggered.provenance, :origin)

      # No trigger sample (a timer): no packet, no origin.
      timer = DerivedSamples.build(update(nil, nil), activation(), origins)
      assert timer.origin == nil
      assert timer.packet_id == "update-e1a"
      assert DerivedSamples.build(update(nil, nil), activation()).origin == nil
    end

    test "the derived sample's id is its update id, untouched by the origin" do
      [packet] = decode(frames())
      [trigger | _] = samples(packet)
      update = update(trigger.sample_id, packet.packet_id)

      with_origin = DerivedSamples.build(update, activation(), %{trigger.sample_id => %{v: 1}})
      without = DerivedSamples.build(update, activation(), %{})

      assert with_origin.sample_id == without.sample_id
      assert with_origin.sample_id == "update-e1a"
    end
  end

  defp update(trigger_sample_id, packet_id) do
    metadata =
      Map.merge(
        %{mission_id: "mission-e1a", spacecraft_id: "sc-e1a"},
        if(trigger_sample_id,
          do: %{trigger_sample_id: trigger_sample_id, packet_id: packet_id},
          else: %{}
        )
      )

    Update.new(%{
      update_id: "update-e1a",
      parameter_id: "param-derived",
      qualified_name: "HEALTH.derived",
      value: 10,
      quality: :good,
      receipt_time: ~U[2026-11-28 12:00:00.000000Z],
      producer_kind: :algorithm,
      producer_id: "algo-e1a",
      metadata: metadata
    })
  end

  defp activation, do: %{mission_model_revision_id: "rev-e1a", runtime_plans: %{}}

  defp samples(%PacketRecord{} = packet) do
    {:ok, samples} = Handler.handle(packet, work_item())
    samples
  end

  defp envelope(sample) do
    {:ok, context} =
      WriteContext.new(
        organization_id: "org-e1a",
        mission_id: "mission-e1a",
        realm: :flight,
        data_source_id: "ds-e1a",
        binding_id: "binding-e1a",
        source_endpoint_id: "endpoint-e1a",
        recorded_at: ~U[2026-11-28 12:00:00Z],
        metadata: %{}
      )

    {:ok, envelope} = ObservationEnvelope.from_sample(context, sample)
    envelope
  end

  defp work_item do
    %WorkItem{
      binding_rule_id: "rule-e1a",
      handler_key: :definition_bound_telemetry,
      handler_configuration: %PacketDefinition{
        packet_definition_id: "packet-e1a",
        organization_id: "org-e1a",
        mission_id: "mission-e1a",
        packet_name: "HEALTH",
        apid: 42,
        version: 1,
        fields: [field("field-mode", "mode", 0, 8), field("field-aux", "aux", 8, 8)]
      }
    }
  end

  defp field(id, name, offset, size) do
    %FieldDefinition{
      field_id: id,
      name: name,
      parameter_id: "param-" <> name,
      qualified_name: "HEALTH." <> name,
      offset_bits: offset,
      size_bits: size,
      data_type: :uint,
      engineering_unit: nil,
      byte_order: :big_endian
    }
  end

  defp decode(bytes) do
    {:ok, %{packet_records: packets}, _rest, _pipeline, _continuity} = process(bytes, 0, <<>>)
    packets
  end

  defp process(bytes, offset, remainder) do
    {:ok, pipeline} = TMFrameIngress.init()
    process(bytes, offset, remainder, pipeline, %{})
  end

  defp process(bytes, offset, remainder, pipeline, continuity) do
    TMFrameIngress.process(evidence(bytes, offset), pipeline, continuity, remainder)
  end

  # The journal cut into two evidences, mid-frame (every cut a whole 2-byte record).
  defp split(bytes) do
    cut = div(byte_size(bytes), 2)
    cut = cut - rem(cut, 2)
    [binary_part(bytes, 0, cut), binary_part(bytes, cut, byte_size(bytes) - cut)]
  end

  defp evidence(bytes, offset) do
    RawEvidence.new(%{
      mission_id: "mission-e1a",
      source_endpoint_ref: "endpoint-e1a",
      spacecraft_id: "sc-e1a",
      protocol_family: :tm,
      receipt_time: ~U[2026-11-28 12:00:00.000000Z],
      receipt_times: records(offset, byte_size(bytes)),
      raw: bytes,
      metadata: %{
        "journal_stream_id" => @stream,
        "journal_start_offset" => offset,
        "journal_end_offset" => offset + byte_size(bytes),
        frame_size: @frame_size,
        ocf_length: 0
      }
    })
  end

  defp records(offset, size) do
    for start <- offset..(offset + size - 1)//2,
        do: {start, DateTime.add(~U[2026-11-28 12:00:00.000000Z], start, :millisecond)}
  end

  defp frames do
    sdu = %SDUOctets{
      profile: :tm,
      scid: 11,
      vcid: 2,
      map_id: nil,
      direction: :downlink,
      sdu_kind_hint: :space_packet,
      octets: @packet,
      quality: :good,
      source_frames: [],
      timestamp: nil,
      meta: %{}
    }

    {:ok, state} = Segmentation.init([])

    {:ok, encoded, _state} =
      Segmentation.segment_encode(sdu, %{frame_size: @frame_size, ocf_length: 0}, state, [])

    IO.iodata_to_binary(encoded)
  end
end
