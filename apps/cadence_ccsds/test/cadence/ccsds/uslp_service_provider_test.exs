defmodule Cadence.CCSDS.USLPServiceProviderTest do
  use ExUnit.Case, async: true

  alias Cadence.CCSDS.Core.LinkFrame
  alias Cadence.CCSDS.EncapsulationPacket
  alias Cadence.CCSDS.EncapsulationPacket.Codec, as: EncapsulationPacketCodec
  alias Cadence.CCSDS.SDLP.USLP.Configuration
  alias Cadence.CCSDS.SDLP.USLP.FrameCodec
  alias Cadence.CCSDS.SDLP.USLP.Service.{Indication, Provider, Request}
  alias Cadence.CCSDS.SpacePacket
  alias Cadence.CCSDS.SpacePacket.Codec, as: SpacePacketCodec
  alias Cadence.CCSDS.TC.Service.{PacketConfiguration, PacketFormat}

  test "composes all five primary data services through generation and reception" do
    configurations = [
      configuration(1, 1, :packets, packet_service: :map),
      configuration(2, 0, :packets, packet_service: :virtual_channel),
      configuration(3, 2, :mapa_sdu),
      configuration(4, 0, :vca_sdu),
      configuration(5, 3, :octet_stream)
    ]

    {:ok, provider} = Provider.init(configurations)

    requests = [
      request(:map_packet, Enum.at(configurations, 0), space_packet(20),
        packet_version_number: 0
      ),
      request(:virtual_channel_packet, Enum.at(configurations, 1), space_packet(19),
        packet_version_number: 0
      ),
      request(:map_access, Enum.at(configurations, 2), :binary.copy(<<3>>, 30)),
      request(:virtual_channel_access, Enum.at(configurations, 3), :binary.copy(<<4>>, 29)),
      request(:map_octet_stream, Enum.at(configurations, 4), :binary.copy(<<5>>, 28))
    ]

    {frames_by_service, provider} =
      Enum.map_reduce(requests, provider, fn request, state ->
        assert {:ok, frames, next_state} = Provider.request(request, state)
        assert frames != []
        {frames, next_state}
      end)

    {indications, _provider} =
      frames_by_service
      |> List.flatten()
      |> Enum.reduce({[], provider}, fn frame, {indications, state} ->
        assert {:ok, emitted, next_state} = Provider.ingest(frame, state)
        {indications ++ emitted, next_state}
      end)

    assert indications |> Enum.map(& &1.service) |> Enum.uniq() == [
             :map_packet,
             :virtual_channel_packet,
             :map_access,
             :virtual_channel_access,
             :map_octet_stream
           ]

    assert Enum.all?(indications, &match?(%Indication{quality: :complete}, &1))
  end

  test "queues synchronous Master Channel OCF and Insert service data" do
    ocf_configuration = configuration(6, 1, :mapa_sdu, ocf?: true)
    {:ok, provider} = Provider.init([ocf_configuration])

    assert {:ok, [], provider} =
             Provider.request(
               %Request{
                 service: :master_channel_operational_control,
                 data: <<1, 2, 3, 4>>,
                 physical_channel: ocf_configuration.physical_channel,
                 scid: ocf_configuration.scid,
                 vcid: ocf_configuration.vcid,
                 map_id: ocf_configuration.map_id
               },
               provider
             )

    assert {:ok, [frame], provider} =
             Provider.request(request(:map_access, ocf_configuration, <<9>>), provider)

    assert frame.ocf == <<1, 2, 3, 4>>
    assert {:ok, indications, _provider} = Provider.ingest(frame, provider)

    assert Enum.map(indications, & &1.service) == [
             :map_access,
             :master_channel_operational_control
           ]

    insert_configuration =
      configuration(7, 1, :mapa_sdu,
        frame_type: :fixed,
        frame_size: 32,
        insert_zone_length: 2
      )

    {:ok, provider} = Provider.init([insert_configuration])

    assert {:ok, [], provider} =
             Provider.request(
               %Request{service: :insert, physical_channel: "forward", data: <<7, 8>>},
               provider
             )

    assert {:ok, [frame], provider} =
             Provider.request(request(:map_access, insert_configuration, <<6>>), provider)

    assert frame.meta.insert_zone == <<7, 8>>
    assert {:ok, indications, _provider} = Provider.ingest(frame, provider)
    assert Enum.map(indications, & &1.service) == [:map_access, :insert]
  end

  test "MAP Packet Service carries adaptive Encapsulation Packets" do
    {:ok, packet_configuration} =
      PacketConfiguration.new(
        valid_packet_version_numbers: [7],
        maximum_packet_octets: 64,
        formats: %{7 => PacketFormat.encapsulation_packet()}
      )

    configuration =
      configuration(6, 1, :packets,
        packet_service: :map,
        packet_configuration: packet_configuration
      )

    packet =
      EncapsulationPacket.new(protocol_id: 1, user_defined: 2, data: :binary.copy(<<9>>, 40))
      |> EncapsulationPacketCodec.encode()
      |> elem(1)

    request =
      request(:map_packet, configuration, packet,
        packet_version_number: 7,
        sdu_id: :encapsulation
      )

    assert {:ok, sender} = Provider.init([configuration])
    assert {:ok, frames, _sender} = Provider.request(request, sender)
    assert length(frames) > 1
    assert {:ok, receiver} = Provider.init([configuration])

    {indications, _receiver} =
      Enum.reduce(frames, {[], receiver}, fn frame, {indications, state} ->
        assert {:ok, emitted, next_state} = Provider.ingest(frame, state)
        {indications ++ emitted, next_state}
      end)

    assert [%Indication{data: ^packet, packet_version_number: 7}] = indications
  end

  test "exposes COP management directives without owning the COP engine" do
    configuration = configuration(8, 1, :mapa_sdu, cop: :cop1)
    {:ok, provider} = Provider.init([configuration])

    cop_request = %Request{
      service: :cops_management,
      physical_channel: configuration.physical_channel,
      scid: configuration.scid,
      vcid: configuration.vcid,
      map_id: configuration.map_id,
      directive: {:initiate_ad_service, :without_clcw}
    }

    assert {:ok, [], provider} = Provider.request(cop_request, provider)
    assert {[directive], provider} = Provider.take_cop_directives(provider)
    assert directive.cop == :cop1
    assert directive.directive == {:initiate_ad_service, :without_clcw}
    assert {[], _provider} = Provider.take_cop_directives(provider)
  end

  test "enforces the managed coding repetition maximum" do
    configuration =
      configuration(8, 1, :mapa_sdu,
        maximum_repetitions: 2,
        sequence_repetitions: 1
      )

    {:ok, provider} = Provider.init([configuration])
    request = request(:map_access, configuration, <<1>>, repetitions: 3)

    assert {:error, {:invalid_repetitions, 3, 2}, ^provider} =
             Provider.request(request, provider)
  end

  test "VCF and MCF services validate external frames and enforce hierarchy exclusivity" do
    configuration = configuration(9, 1, :mapa_sdu)

    assert {:ok, virtual_provider} =
             Provider.init([configuration],
               frame_services: [
                 {:virtual_channel,
                  {configuration.physical_channel, configuration.scid, configuration.vcid}}
               ]
             )

    frame = link_frame(configuration, <<1, 2, 3>>)

    request = %Request{
      service: :virtual_channel_frame,
      frame: frame,
      physical_channel: configuration.physical_channel,
      scid: configuration.scid,
      vcid: configuration.vcid,
      map_id: configuration.map_id
    }

    assert {:ok, [accepted], ^virtual_provider} = Provider.request(request, virtual_provider)

    assert {:ok, [%Indication{service: :virtual_channel_frame}], _provider} =
             Provider.ingest(accepted, virtual_provider)

    assert {:error, {:virtual_channel_reserved_for_frame_service, _address}, ^virtual_provider} =
             Provider.request(request(:map_access, configuration, <<1>>), virtual_provider)

    assert {:ok, master_provider} =
             Provider.init([configuration],
               frame_services: [
                 {:master_channel, {configuration.physical_channel, configuration.scid}}
               ]
             )

    master_request = %{request | service: :master_channel_frame}
    assert {:ok, [accepted], ^master_provider} = Provider.request(master_request, master_provider)

    assert {:ok, [%Indication{service: :master_channel_frame}], _provider} =
             Provider.ingest(accepted, master_provider)
  end

  test "wire ingestion routes and reassembles concatenated frames" do
    configuration = configuration(10, 1, :mapa_sdu)
    {:ok, provider} = Provider.init([configuration])
    data = :binary.copy(<<0xCC>>, 70)
    request = request(:map_access, configuration, data)

    assert {:ok, frames, provider} = Provider.request(request, provider)

    wire =
      frames
      |> Enum.map(fn frame ->
        {:ok, encoded} = FrameCodec.encode(frame, configuration: configuration)

        encoded
      end)
      |> IO.iodata_to_binary()

    assert {:ok, [%Indication{service: :map_access, data: ^data}], [], <<>>, _provider} =
             Provider.ingest_wire(wire, "forward", %{}, provider)
  end

  defp configuration(vcid, map_id, content, overrides \\ []) do
    base = [
      physical_channel: "forward",
      frame_type: :variable,
      frame_size: 32,
      scid: 42,
      vcid: vcid,
      map_id: map_id,
      valid_vcids: Enum.to_list(1..10) ++ [63],
      data_field_content: content
    ]

    Configuration.new!(Keyword.merge(base, overrides))
  end

  defp request(service, configuration, data, overrides \\ []) do
    struct!(
      Request,
      Keyword.merge(
        [
          service: service,
          data: data,
          physical_channel: configuration.physical_channel,
          scid: configuration.scid,
          vcid: configuration.vcid,
          map_id: configuration.map_id,
          qos: :sequence_controlled
        ],
        overrides
      )
    )
  end

  defp link_frame(configuration, data) do
    %LinkFrame{
      profile: :uslp,
      scid: configuration.scid,
      vcid: configuration.vcid,
      map_id: configuration.map_id,
      frame_seq: 0,
      payload_octets: data,
      quality: :good,
      meta: %{
        physical_channel: configuration.physical_channel,
        qos: :sequence_controlled,
        vcf_count: 0,
        vcf_count_length: 1,
        construction_rule: :unsegmented,
        upid: configuration.upid,
        insert_zone: nil,
        protocol_control?: false
      }
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
