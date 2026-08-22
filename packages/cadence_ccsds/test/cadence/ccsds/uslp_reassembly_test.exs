defmodule Cadence.CCSDS.USLPReassemblyTest do
  use ExUnit.Case, async: true

  alias Cadence.CCSDS.Core.SDUOctets
  alias Cadence.CCSDS.SDLP.USLP.{Configuration, Reassembly, Segmentation}
  alias Cadence.CCSDS.SpacePacket
  alias Cadence.CCSDS.SpacePacket.Codec, as: SpacePacketCodec

  test "reassembles segmented variable MAPA and VCA SDUs" do
    for content <- [:mapa_sdu, :vca_sdu] do
      configuration = variable_configuration(content)
      kind = if(content == :mapa_sdu, do: :mapa_sdu, else: :vca_sdu)
      data = :binary.copy(<<0xA5>>, 30)

      {:ok, generation} = Segmentation.init()

      {:ok, frames, _generation} =
        Segmentation.segment(
          sdu(kind, data, configuration),
          %{configuration: configuration},
          generation
        )

      {:ok, reception} = Reassembly.init(configurations: [configuration])

      {delivered, anomalies, _reception} =
        Enum.reduce(frames, {[], [], reception}, fn frame, {sdus, anomalies, state} ->
          assert {:ok, emitted, frame_anomalies, next_state} =
                   Reassembly.ingest_detailed(frame, %{direction: :uplink}, state)

          {sdus ++ emitted, anomalies ++ frame_anomalies, next_state}
        end)

      assert anomalies == []
      assert [%SDUOctets{sdu_kind_hint: ^kind, octets: ^data, quality: :good}] = delivered
      assert hd(delivered).source_frames == Enum.to_list(0..(length(frames) - 1))
    end
  end

  test "extracts a segmented variable packet through managed packet formats" do
    configuration =
      Configuration.new!(
        frame_type: :variable,
        frame_size: 15,
        scid: 10,
        vcid: 3,
        map_id: 4
      )

    packet = space_packet(25)
    {:ok, generation} = Segmentation.init()

    {:ok, frames, _generation} =
      Segmentation.segment(
        sdu(:space_packet, packet, configuration),
        %{configuration: configuration},
        generation
      )

    {:ok, reception} = Reassembly.init(configurations: [configuration])

    {delivered, _state} =
      Enum.reduce(frames, {[], reception}, fn frame, {sdus, state} ->
        assert {:ok, emitted, [], next_state} = Reassembly.ingest_detailed(frame, %{}, state)
        {sdus ++ emitted, next_state}
      end)

    assert [%SDUOctets{sdu_kind_hint: :map_packet, octets: ^packet}] = delivered
    assert hd(delivered).meta.packet_version_number == 0
    assert hd(delivered).meta.packet_quality_indicator
  end

  test "extracts a fixed-frame packet and consumes the spanning Idle Packet" do
    configuration =
      Configuration.new!(
        frame_type: :fixed,
        frame_size: 24,
        scid: 10,
        vcid: 3,
        map_id: 4
      )

    packet = space_packet(20)
    {:ok, generation} = Segmentation.init()

    {:ok, frames, _generation} =
      Segmentation.segment(
        sdu(:space_packet, packet, configuration),
        %{configuration: configuration},
        generation
      )

    {:ok, reception} = Reassembly.init(configurations: [configuration])

    {delivered, reception} =
      Enum.reduce(frames, {[], reception}, fn frame, {sdus, state} ->
        assert {:ok, emitted, [], next_state} = Reassembly.ingest_detailed(frame, %{}, state)
        {sdus ++ emitted, next_state}
      end)

    assert [%SDUOctets{octets: ^packet, sdu_kind_hint: :map_packet}] = delivered
    assert Reassembly.stats(reception).buffered_packets == 0
  end

  test "uses fixed-frame LVO and emits synchronous Insert and OCF SDUs" do
    configuration =
      Configuration.new!(
        frame_type: :fixed,
        frame_size: 28,
        scid: 1,
        vcid: 2,
        map_id: 3,
        insert_zone_length: 2,
        ocf?: true,
        data_field_content: :mapa_sdu
      )

    data = :binary.copy(<<0x44>>, 15)
    {:ok, generation} = Segmentation.init()

    assert {:ok, frames, _generation} =
             Segmentation.segment(
               sdu(:mapa_sdu, data, configuration),
               %{
                 configuration: configuration,
                 insert_zone_sdus: [<<1, 2>>, <<3, 4>>],
                 ocf_sdus: [<<5, 6, 7, 8>>, <<9, 10, 11, 12>>]
               },
               generation
             )

    {:ok, reception} = Reassembly.init(configurations: [configuration])

    {delivered, _state} =
      Enum.reduce(frames, {[], reception}, fn frame, {sdus, state} ->
        assert {:ok, emitted, [], next_state} = Reassembly.ingest_detailed(frame, %{}, state)
        {sdus ++ emitted, next_state}
      end)

    assert Enum.map(delivered, & &1.sdu_kind_hint) == [
             :insert,
             :operational_control,
             :mapa_sdu,
             :insert,
             :operational_control
           ]

    assert Enum.find(delivered, &(&1.sdu_kind_hint == :mapa_sdu)).octets == data
  end

  test "validates the continuous OID stream and rejects corruption" do
    configuration =
      Configuration.new!(
        frame_type: :fixed,
        frame_size: 20,
        scid: 1,
        vcid: 63,
        map_id: 0,
        data_field_content: :idle_data
      )

    {:ok, generation} = Segmentation.init()
    {:ok, first, generation} = Segmentation.only_idle(%{configuration: configuration}, generation)

    {:ok, second, _generation} =
      Segmentation.only_idle(%{configuration: configuration}, generation)

    {:ok, reception} = Reassembly.init(configurations: [configuration])

    assert {:ok, [], [], reception} = Reassembly.ingest_detailed(first, %{}, reception)
    assert {:ok, [], [], _reception} = Reassembly.ingest_detailed(second, %{}, reception)

    <<octet, rest::binary>> = second.payload_octets
    corrupt = %{second | payload_octets: <<Bitwise.bxor(octet, 1), rest::binary>>}

    assert {:error, {:invalid_uslp_only_idle_data, 0}, [%{anomaly_kind: :invalid_only_idle_data}],
            _state} =
             Reassembly.ingest_detailed(corrupt, %{}, reception)
  end

  test "flags octet-stream loss from the expedited counter independently" do
    configuration =
      Configuration.new!(
        frame_type: :variable,
        frame_size: 32,
        scid: 1,
        vcid: 2,
        map_id: 3,
        data_field_content: :octet_stream
      )

    {:ok, generation} = Segmentation.init(expedited_count: 4)

    {:ok, [first], generation} =
      Segmentation.segment(
        sdu(:octet_stream, <<1>>, configuration),
        %{configuration: configuration, qos: :expedited},
        generation
      )

    {:ok, [second], _generation} =
      Segmentation.segment(
        sdu(:octet_stream, <<2>>, configuration),
        %{configuration: configuration, qos: :expedited},
        generation
      )

    second = %{second | frame_seq: 8, meta: %{second.meta | vcf_count: 8}}
    {:ok, reception} = Reassembly.init(configurations: [configuration])
    assert {:ok, [_first], [], reception} = Reassembly.ingest_detailed(first, %{}, reception)

    assert {:ok, [delivered], [%{anomaly_kind: :virtual_channel_frame_count_discontinuity}],
            _state} =
             Reassembly.ingest_detailed(second, %{}, reception)

    assert delivered.meta.octet_stream_data_loss_flag
    assert delivered.quality == :suspect
  end

  defp variable_configuration(content) do
    Configuration.new!(
      frame_type: :variable,
      frame_size: 16,
      scid: 100,
      vcid: 4,
      map_id: 2,
      data_field_content: content
    )
  end

  defp sdu(kind, octets, configuration) do
    %SDUOctets{
      profile: :uslp,
      scid: configuration.scid,
      vcid: configuration.vcid,
      map_id: configuration.map_id,
      direction: :uplink,
      sdu_kind_hint: kind,
      octets: octets,
      quality: :good,
      source_frames: [],
      meta: %{}
    }
  end

  defp space_packet(total_octets) do
    packet =
      SpacePacket.new(%{
        packet_type: :command,
        secondary_header?: false,
        apid: 7,
        sequence_flag: :unsegmented,
        sequence_count: 1,
        data: :binary.copy(<<0xAB>>, total_octets - 6)
      })

    {:ok, encoded} = SpacePacketCodec.encode(packet)
    encoded
  end
end
