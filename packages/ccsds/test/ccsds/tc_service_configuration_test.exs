defmodule CCSDS.TC.Service.ConfigurationTest do
  use ExUnit.Case, async: true

  alias CCSDS.Packet.Configuration, as: PacketConfiguration
  alias CCSDS.TC.Service.Configuration

  test "validates managed MAP Packet parameters and derived frame capacity" do
    assert {:ok, packet} = PacketConfiguration.new(maximum_packet_octets: 64)

    assert {:ok, configuration} =
             Configuration.new(
               service: :map_packet,
               scid: 19,
               vcid: 3,
               map_id: 7,
               frame_size: 22,
               fecf?: false,
               blocking?: true,
               segmentation?: true,
               maximum_sdu_octets: 64,
               packet: packet
             )

    assert Configuration.segment_header?(configuration)
    assert Configuration.maximum_data_field_octets(configuration) == 16
    assert Configuration.key(configuration) == {:map_packet, 19, 3, 7}
  end

  test "requires Packet Service segmentation when the managed packet maximum exceeds a MAP FDU" do
    assert {:ok, packet} = PacketConfiguration.new(maximum_packet_octets: 64)

    assert {:error, {:packet_exceeds_unsegmented_map_capacity, 64, 16}} =
             Configuration.new(
               service: :map_packet,
               scid: 19,
               vcid: 3,
               map_id: 7,
               frame_size: 22,
               blocking?: false,
               segmentation?: false,
               packet: packet
             )
  end

  test "enforces service exclusivity on Virtual and MAP Channels" do
    packet = packet_configuration()
    mapp = configuration(:map_packet, map_id: 1, packet: packet, segmentation?: true)
    mapa = configuration(:map_access, map_id: 2, segmentation?: true)

    assert :ok = Configuration.validate_plan([mapp, mapa])

    conflicting_map = configuration(:map_access, map_id: 1, segmentation?: true)

    assert {:error, {{19, 3}, {:mutually_exclusive_map_services, 1}}} =
             Configuration.validate_plan([mapp, conflicting_map])

    vca = configuration(:virtual_channel_access)

    assert {:error, {{19, 3}, {:mutually_exclusive_virtual_channel_services, services}}} =
             Configuration.validate_plan([mapp, vca])

    assert Enum.sort(services) == [:map_packet, :virtual_channel_access]
  end

  test "Master Channel Frame Service excludes other services on the Master Channel" do
    mcf =
      configuration(:master_channel_frame,
        vcid: nil,
        valid_vcids: [1, 3],
        cop_management?: false
      )

    assert {:error, {:master_channel_frame_service_conflict, 19}} =
             Configuration.validate_plan([mcf, configuration(:virtual_channel_access)])
  end

  test "Virtual Channel Frame Service prohibits COP Management on the same VC" do
    assert {:error, {:invalid_field, :cop_management?, true}} =
             Configuration.new(
               service: :virtual_channel_frame,
               scid: 19,
               vcid: 3,
               frame_size: 22,
               cop_management?: true
             )
  end

  defp configuration(service, overrides \\ []) do
    attrs =
      [
        service: service,
        scid: 19,
        vcid: 3,
        frame_size: 22,
        maximum_sdu_octets: 64
      ]
      |> Keyword.merge(overrides)
      |> normalize_configuration_attrs(service)

    {:ok, configuration} = Configuration.new(attrs)
    configuration
  end

  defp normalize_configuration_attrs(attrs, service)
       when service in [:virtual_channel_access, :virtual_channel_frame, :master_channel_frame] do
    Keyword.delete(attrs, :maximum_sdu_octets)
  end

  defp normalize_configuration_attrs(attrs, _service), do: attrs

  defp packet_configuration do
    {:ok, packet} = PacketConfiguration.new(maximum_packet_octets: 64)
    packet
  end
end
