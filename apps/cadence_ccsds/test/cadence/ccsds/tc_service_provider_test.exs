defmodule Cadence.CCSDS.TC.Service.ProviderTest do
  use ExUnit.Case, async: true

  alias Cadence.CCSDS.Core.LinkFrame
  alias Cadence.CCSDS.EncapsulationPacket
  alias Cadence.CCSDS.EncapsulationPacket.Codec, as: EncapsulationPacketCodec
  alias Cadence.CCSDS.Packet.Configuration, as: PacketConfiguration
  alias Cadence.CCSDS.Packet.Format, as: PacketFormat
  alias Cadence.CCSDS.SpacePacket
  alias Cadence.CCSDS.SpacePacket.Codec, as: SpacePacketCodec
  alias Cadence.CCSDS.TC.FrameCodec

  alias Cadence.CCSDS.TC.Service.{
    Configuration,
    Provider,
    Request
  }

  test "MAP Packet Service blocks complete Packets and segments an oversized Packet" do
    configuration = map_packet_configuration()
    assert {:ok, provider} = Provider.init([configuration], frame_sequences: %{{19, 3} => 254})

    packet_1 = space_packet(1, <<1>>)
    packet_2 = space_packet(2, <<2, 3>>)
    packet_3 = space_packet(3, :binary.copy(<<3>>, 20))

    requests = [
      packet_request(packet_1, :packet_1),
      packet_request(packet_2, :packet_2),
      packet_request(packet_3, :packet_3)
    ]

    assert {:ok, frames, sender} = Provider.request_many(requests, provider)
    assert Enum.map(frames, & &1.frame_seq) == [254, 255, 0]
    assert Enum.map(frames, & &1.meta.sequence_flag) == [:unsegmented, :first, :last]
    assert Enum.map(frames, & &1.meta.packet_count) == [2, 1, 1]
    assert Enum.all?(frames, &(&1.meta.coding_repetitions == 2))
    assert sender.frame_sequences[{19, 3}] == 1

    assert {:ok, decoded_frames} = wire_round_trip(frames, configuration)
    assert {:ok, receiver} = Provider.init([configuration], frame_sequences: %{{19, 3} => 254})

    {indications, final_receiver} = ingest_all(decoded_frames, receiver)

    assert Enum.map(indications, & &1.data) == [packet_1, packet_2, packet_3]
    assert Enum.map(indications, & &1.packet_version_number) == [0, 0, 0]
    assert Enum.map(indications, & &1.quality) == [:complete, :complete, :complete]
    assert Enum.map(indications, & &1.source_frames) == [[254], [254], [255, 0]]
    assert final_receiver.reassembly.buffers == %{}
  end

  test "Virtual Channel Packet Service blocks Packets without a Segment Header" do
    configuration = virtual_channel_packet_configuration()
    assert {:ok, provider} = Provider.init([configuration])
    packet_1 = space_packet(1, <<1>>)
    packet_2 = space_packet(2, <<2, 3>>)

    requests = [
      packet_request(packet_1, :packet_1, service: :virtual_channel_packet, map_id: nil),
      packet_request(packet_2, :packet_2, service: :virtual_channel_packet, map_id: nil)
    ]

    assert {:ok, [frame], sender} = Provider.request_many(requests, provider)
    assert frame.map_id == nil
    assert frame.meta.segment_header_flag == 0
    assert frame.payload_octets == packet_1 <> packet_2
    assert sender.frame_sequences[{19, 3}] == 1

    assert {:ok, [indication_1, indication_2], _receiver} = Provider.ingest(frame, provider)
    assert indication_1.data == packet_1
    assert indication_2.data == packet_2
  end

  test "MAP Packet Service carries adaptive Encapsulation Packets" do
    {:ok, packet_configuration} =
      PacketConfiguration.new(
        valid_packet_version_numbers: [7],
        maximum_packet_octets: 64,
        formats: %{7 => PacketFormat.encapsulation_packet()}
      )

    configuration =
      configuration(
        service: :map_packet,
        map_id: 7,
        frame_size: 22,
        segmentation?: true,
        maximum_sdu_octets: 64,
        packet: packet_configuration
      )

    packet =
      EncapsulationPacket.new(protocol_id: 4, user_defined: 3, data: :binary.copy(<<7>>, 25))
      |> EncapsulationPacketCodec.encode()
      |> elem(1)

    request = packet_request(packet, :encapsulation, packet_version_number: 7)
    assert {:ok, sender} = Provider.init([configuration])
    assert {:ok, frames, _sender} = Provider.request(request, sender)
    assert length(frames) > 1
    assert {:ok, receiver} = Provider.init([configuration])
    assert {[indication], _receiver} = ingest_all(frames, receiver)
    assert indication.data == packet
    assert indication.packet_version_number == 7
  end

  test "MAP Access permits managed segmentation while VCA rejects an oversized SDU" do
    mapa = map_access_configuration()
    vca = virtual_channel_access_configuration(vcid: 4)
    assert {:ok, provider} = Provider.init([mapa, vca])

    mapa_request = %Request{
      service: :map_access,
      data: :binary.copy(<<0xAB>>, 15),
      scid: 19,
      vcid: 3,
      map_id: 9,
      sdu_id: :mapa,
      service_type: :sequence_controlled,
      meta: %{}
    }

    assert {:ok, [first, continuation, last], provider} = Provider.request(mapa_request, provider)

    assert Enum.map([first, continuation, last], & &1.meta.sequence_flag) == [
             :first,
             :continuation,
             :last
           ]

    assert {:ok, receiver} = Provider.init([mapa, vca])

    {[%{service: :map_access, data: reassembled}], _receiver} =
      ingest_all([first, continuation, last], receiver)

    assert reassembled == mapa_request.data

    vca_request = %Request{
      service: :virtual_channel_access,
      data: :binary.copy(<<0xCD>>, 8),
      scid: 19,
      vcid: 4,
      map_id: nil,
      sdu_id: :vca,
      service_type: :expedited,
      meta: %{}
    }

    assert {:error, {:sdu_size_limit_exceeded, 8, 7}, ^provider} =
             Provider.request(vca_request, provider)
  end

  test "Virtual Channel Frame Service validates its SAP and empty FECF boundary" do
    configuration = virtual_channel_frame_configuration()
    assert {:ok, provider} = Provider.init([configuration])
    frame = frame_service_frame()

    request = %Request{
      service: :virtual_channel_frame,
      data: frame,
      scid: 19,
      vcid: 3,
      map_id: nil,
      sdu_id: :frame,
      service_type: nil,
      meta: %{}
    }

    assert {:ok, [submitted], ^provider} = Provider.request(request, provider)
    assert submitted.meta.tc_service == :virtual_channel_frame

    assert {:ok, [indication], ^provider} = Provider.ingest(submitted, provider)
    assert indication.service == :virtual_channel_frame
    assert indication.data == submitted
    assert indication.service_type == nil

    mapped_frame = %{
      submitted
      | map_id: 5,
        meta: Map.merge(submitted.meta, %{segment_header_flag: 1, sequence_flag: :unsegmented})
    }

    assert {:ok, [%{data: ^mapped_frame}], ^provider} = Provider.ingest(mapped_frame, provider)

    frame_with_fecf = put_in(frame.meta.fecf_present, true)

    assert {:error, :frame_service_fecf_must_be_empty, ^provider} =
             Provider.request(%{request | data: frame_with_fecf}, provider)
  end

  test "Master Channel Frame Service accepts only its managed VCIDs" do
    configuration = master_channel_frame_configuration()
    assert {:ok, provider} = Provider.init([configuration])

    request = %Request{
      service: :master_channel_frame,
      data: frame_service_frame(),
      scid: 19,
      vcid: nil,
      map_id: nil,
      sdu_id: :frame,
      service_type: nil,
      meta: %{}
    }

    assert {:ok, [_frame], ^provider} = Provider.request(request, provider)

    invalid_frame = %{frame_service_frame() | vcid: 8}

    assert {:error, {:frame_service_address_mismatch, 19, 8}, ^provider} =
             Provider.request(%{request | data: invalid_frame}, provider)
  end

  test "Packet Service round trips frame-boundary sizes and sequence wraparound" do
    configuration = map_packet_configuration()

    Enum.each(1..40, fn data_octets ->
      initial_sequence = rem(250 + data_octets, 256)
      packet = space_packet(data_octets, :binary.copy(<<data_octets>>, data_octets))
      request = packet_request(packet, data_octets)

      assert {:ok, sender} =
               Provider.init([configuration],
                 frame_sequences: %{{19, 3} => initial_sequence}
               )

      assert {:ok, frames, _sender} = Provider.request(request, sender)
      assert {:ok, decoded_frames} = wire_round_trip(frames, configuration)
      assert {:ok, receiver} = Provider.init([configuration])
      assert {[indication], _receiver} = ingest_all(decoded_frames, receiver)
      assert indication.data == packet
      assert indication.source_frames == Enum.map(frames, & &1.frame_seq)
    end)
  end

  defp map_packet_configuration do
    packet = packet_configuration(64)

    configuration(
      service: :map_packet,
      map_id: 7,
      frame_size: 22,
      blocking?: true,
      segmentation?: true,
      maximum_sdu_octets: 64,
      packet: packet,
      repetitions_type_a: 2
    )
  end

  defp virtual_channel_packet_configuration do
    packet = packet_configuration(16)

    configuration(
      service: :virtual_channel_packet,
      map_id: nil,
      frame_size: 21,
      blocking?: true,
      packet: packet
    )
  end

  defp map_access_configuration do
    configuration(
      service: :map_access,
      map_id: 9,
      frame_size: 12,
      segmentation?: true,
      maximum_sdu_octets: 64
    )
  end

  defp virtual_channel_access_configuration(overrides) do
    configuration(
      Keyword.merge(
        [
          service: :virtual_channel_access,
          map_id: nil,
          frame_size: 12,
          maximum_sdu_octets: 7
        ],
        overrides
      )
    )
  end

  defp virtual_channel_frame_configuration do
    configuration(
      service: :virtual_channel_frame,
      map_id: nil,
      frame_size: 22,
      cop_management?: false
    )
  end

  defp master_channel_frame_configuration do
    configuration(
      service: :master_channel_frame,
      vcid: nil,
      map_id: nil,
      valid_vcids: [3, 4],
      frame_size: 22,
      cop_management?: false
    )
  end

  defp configuration(overrides) do
    attrs = Keyword.merge([scid: 19, vcid: 3], overrides)
    {:ok, configuration} = Configuration.new(attrs)
    configuration
  end

  defp packet_configuration(maximum) do
    {:ok, configuration} = PacketConfiguration.new(maximum_packet_octets: maximum)
    configuration
  end

  defp packet_request(packet, sdu_id, overrides \\ []) do
    defaults = [
      service: :map_packet,
      scid: 19,
      vcid: 3,
      map_id: 7
    ]

    attrs = Keyword.merge(defaults, overrides)

    struct!(Request,
      service: attrs[:service],
      data: packet,
      scid: attrs[:scid],
      vcid: attrs[:vcid],
      map_id: attrs[:map_id],
      packet_version_number: Keyword.get(attrs, :packet_version_number, 0),
      sdu_id: sdu_id,
      service_type: :sequence_controlled,
      meta: %{}
    )
  end

  defp space_packet(sequence_count, data) do
    packet = %SpacePacket{
      version: 0,
      packet_type: :command,
      secondary_header?: false,
      apid: 100,
      sequence_flag: :unsegmented,
      sequence_count: sequence_count,
      data: data
    }

    {:ok, encoded} = SpacePacketCodec.encode(packet)
    encoded
  end

  defp wire_round_trip(frames, configuration) do
    encoded =
      Enum.map(frames, fn frame ->
        {:ok, bytes} =
          FrameCodec.encode(frame,
            frame_size: configuration.frame_size,
            fecf: configuration.fecf?
          )

        bytes
      end)

    case FrameCodec.decode(IO.iodata_to_binary(encoded),
           frame_size: configuration.frame_size,
           fecf: configuration.fecf?,
           segment_header_flag: 1
         ) do
      {:ok, decoded, <<>>} -> {:ok, decoded}
      other -> other
    end
  end

  defp ingest_all(frames, provider) do
    Enum.reduce(frames, {[], provider}, fn frame, {indications, state} ->
      assert {:ok, emitted, next_state} = Provider.ingest(frame, state)
      {indications ++ emitted, next_state}
    end)
  end

  defp frame_service_frame do
    %LinkFrame{
      profile: :tc,
      scid: 19,
      vcid: 3,
      map_id: nil,
      frame_seq: 4,
      payload_octets: <<1, 2, 3>>,
      quality: :good,
      ocf: nil,
      timestamp: nil,
      meta: %{
        bypass_flag: 0,
        control_command_flag: 0,
        segment_header_flag: 0,
        fecf_present: false
      }
    }
  end
end
