defmodule CCSDS.SDLP.AOS.Service.ProviderTest do
  use ExUnit.Case, async: true

  alias CCSDS.Core.LinkFrame
  alias CCSDS.SDLP.AOS.{Configuration, FrameCodec, MPDU}
  alias CCSDS.SDLP.AOS.Service.{Provider, Request}

  test "composes VCP, VC_OCF, and Insert services with one-shot synchronous SDUs" do
    %{packet: packet} = configurations = configuration_plan()
    {:ok, provider} = provider(configurations)
    packet_octets = space_packet(1, <<0xAA>>)

    assert {:error, {:insufficient_synchronous_sdus, :ocf_sdu, _, 1, 0}, ^provider} =
             Provider.request(vcp_request(packet, packet_octets), provider)

    assert {:ok, [], provider} =
             Provider.request(
               %Request{
                 service: :virtual_channel_operational_control,
                 physical_channel: "generated",
                 scid: 7,
                 vcid: 1,
                 data: <<1, 2, 3, 4>>
               },
               provider
             )

    assert {:ok, [], provider} = Provider.request(insert_request(<<5, 6>>), provider)

    assert {:ok, [frame], provider} =
             Provider.request(vcp_request(packet, packet_octets), provider)

    assert frame.ocf == <<1, 2, 3, 4>>
    assert frame.meta.insert_zone == <<5, 6>>

    assert {:ok, encoded} = FrameCodec.encode(frame, configuration: packet)

    assert {:ok, indications, [], <<0xFF>>, _provider} =
             Provider.ingest_wire(encoded <> <<0xFF>>, "generated", %{}, provider)

    assert Enum.find(indications, &(&1.service == :virtual_channel_packet)).data == packet_octets

    assert Enum.find(indications, &(&1.service == :virtual_channel_operational_control)).data ==
             <<1, 2, 3, 4>>

    assert Enum.find(indications, &(&1.service == :insert)).data == <<5, 6>>
  end

  test "composes Bitstream and VCA services" do
    %{bitstream: bitstream, access: access} = configurations = configuration_plan()
    {:ok, provider} = provider(configurations)

    assert {:ok, [], provider} = Provider.request(insert_request(<<1, 1>>), provider)

    bit_request = %Request{
      service: :bitstream,
      physical_channel: "generated",
      scid: bitstream.scid,
      vcid: bitstream.vcid,
      data: <<0xAA, 0x80>>,
      valid_bits: 9
    }

    assert {:ok, [bit_frame], provider} = Provider.request(bit_request, provider)
    assert {:ok, bit_indications, provider} = Provider.ingest(bit_frame, provider)
    bit = Enum.find(bit_indications, &(&1.service == :bitstream))
    assert bit.valid_bits == 9
    assert bit.data == <<0xAA, 0x80>>
    refute bit.bitstream_data_loss_flag

    assert {:ok, [], provider} = Provider.request(insert_request(<<2, 2>>), provider)

    access_request = %Request{
      service: :virtual_channel_access,
      physical_channel: "generated",
      scid: access.scid,
      vcid: access.vcid,
      data: :binary.copy(<<0x33>>, Configuration.payload_octets(access))
    }

    assert {:ok, [access_frame], provider} = Provider.request(access_request, provider)
    assert {:ok, access_indications, _provider} = Provider.ingest(access_frame, provider)
    delivered = Enum.find(access_indications, &(&1.service == :virtual_channel_access))
    assert delivered.data == access_request.data
    refute delivered.vca_sdu_loss_flag
  end

  test "validates and passes complete VCF and MCF frames" do
    %{vcf: vcf, mcf: mcf} = configurations = configuration_plan()
    {:ok, provider} = provider(configurations)

    vcf_frame = %LinkFrame{
      profile: :aos,
      scid: vcf.scid,
      vcid: vcf.vcid,
      frame_seq: 10,
      payload_octets: :binary.copy(<<0>>, Configuration.payload_octets(vcf)),
      quality: :good,
      meta: frame_meta(vcf, 10, %{first_header_pointer: MPDU.only_idle_data()})
    }

    vcf_request = %Request{
      service: :virtual_channel_frame,
      physical_channel: "external",
      scid: vcf.scid,
      vcid: vcf.vcid,
      frame: vcf_frame
    }

    assert {:ok, [returned_vcf], provider} = Provider.request(vcf_request, provider)
    assert %{returned_vcf | meta: Map.delete(returned_vcf.meta, :aos_service)} == vcf_frame
    assert {:ok, [vcf_indication], provider} = Provider.ingest(vcf_frame, provider)
    assert vcf_indication.service == :virtual_channel_frame
    refute vcf_indication.frame_loss_flag

    mcf_frame = %LinkFrame{
      profile: :aos,
      scid: mcf.scid,
      vcid: mcf.vcid,
      frame_seq: 3,
      payload_octets: :binary.copy(<<0x44>>, Configuration.payload_octets(mcf)),
      quality: :good,
      meta: frame_meta(mcf, 3, %{})
    }

    mcf_request = %Request{
      service: :master_channel_frame,
      physical_channel: "external",
      scid: mcf.scid,
      frame: mcf_frame
    }

    assert {:ok, [returned_mcf], provider} = Provider.request(mcf_request, provider)
    assert %{returned_mcf | meta: Map.delete(returned_mcf.meta, :aos_service)} == mcf_frame

    assert {:ok, [mcf_indication], [], _provider} =
             Provider.ingest_detailed(mcf_frame, %{frame_loss_flag: true}, provider)

    assert mcf_indication.service == :master_channel_frame
    assert mcf_indication.frame_loss_flag
    assert mcf_indication.vcid == nil
  end

  test "generates OID frames while carrying the periodic Insert service" do
    configurations = configuration_plan()
    {:ok, provider} = provider(configurations)
    assert {:ok, [], provider} = Provider.request(insert_request(<<9, 9>>), provider)
    assert {:ok, frame, provider} = Provider.only_idle("generated", 7, provider)
    assert frame.vcid == 63
    assert frame.meta.insert_zone == <<9, 9>>

    assert {:ok, [insert], _provider} = Provider.ingest(frame, provider)
    assert insert.service == :insert
    assert insert.data == <<9, 9>>
  end

  defp provider(configurations) do
    Provider.init(Map.values(configurations),
      frame_services: [
        virtual_channel: {"external", 100, 4},
        master_channel: {"external", 101}
      ],
      reassembly: [oid_validation: :strict]
    )
  end

  defp configuration_plan do
    generated = [
      physical_channel: "generated",
      frame_size: 32,
      scid: 7,
      valid_scids: [7],
      valid_vcids: [1, 2, 3, 63],
      insert_zone_length: 2
    ]

    external = [
      physical_channel: "external",
      frame_size: 32,
      valid_scids: [100, 101],
      insert_zone_length: 0
    ]

    %{
      packet: Configuration.new!(generated ++ [vcid: 1, ocf?: true, maximum_packet_octets: 128]),
      bitstream: Configuration.new!(generated ++ [vcid: 2, data_field_content: :b_pdu]),
      access: Configuration.new!(generated ++ [vcid: 3, data_field_content: :vca_sdu]),
      oid: Configuration.new!(generated ++ [vcid: 63, data_field_content: :idle_data]),
      vcf:
        Configuration.new!(
          external ++ [scid: 100, vcid: 4, valid_vcids: [4, 63], maximum_packet_octets: 128]
        ),
      mcf:
        Configuration.new!(
          external ++ [scid: 101, vcid: 5, valid_vcids: [5, 63], data_field_content: :vca_sdu]
        )
    }
  end

  defp vcp_request(configuration, packet) do
    %Request{
      service: :virtual_channel_packet,
      physical_channel: configuration.physical_channel,
      scid: configuration.scid,
      vcid: configuration.vcid,
      packet_version_number: 0,
      data: packet
    }
  end

  defp insert_request(data) do
    %Request{service: :insert, physical_channel: "generated", data: data}
  end

  defp frame_meta(configuration, vcfc, extra) do
    %{
      physical_channel: configuration.physical_channel,
      data_field_content: configuration.data_field_content,
      vcfc: vcfc,
      replay_flag: 0,
      vc_frame_count_cycle_use_flag: 0,
      vc_frame_count_cycle: 0,
      insert_zone: nil
    }
    |> Map.merge(extra)
  end

  defp space_packet(sequence_count, data) do
    <<0::3, 0::1, 0::1, 42::11, 3::2, sequence_count::14, byte_size(data) - 1::16, data::binary>>
  end
end
