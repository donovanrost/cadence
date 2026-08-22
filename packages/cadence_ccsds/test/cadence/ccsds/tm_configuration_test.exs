defmodule Cadence.CCSDS.SDLP.TM.ConfigurationTest do
  use ExUnit.Case, async: true

  alias Cadence.CCSDS.SDLP.TM.Configuration

  test "validates a managed Packet Virtual Channel" do
    assert {:ok, configuration} =
             Configuration.new(
               physical_channel: "S-band downlink",
               frame_size: 128,
               scid: 42,
               vcid: 3,
               fecf?: true,
               secondary_header_source: :virtual_channel,
               secondary_header_length: 8,
               ocf_source: :virtual_channel,
               valid_packet_version_numbers: [0],
               maximum_packet_octets: 1024
             )

    assert configuration.valid_scids == [42]
    assert configuration.valid_vcids == [3]
    assert Configuration.maximum_data_field_octets(configuration) == 108
  end

  test "requires fixed secondary-header presence and length to agree" do
    assert {:error, {:secondary_header_length_without_source, 8}} =
             Configuration.new(
               frame_size: 64,
               scid: 1,
               vcid: 2,
               secondary_header_length: 8
             )

    assert {:error, {:invalid_secondary_header_length, 1}} =
             Configuration.new(
               frame_size: 64,
               scid: 1,
               vcid: 2,
               secondary_header_source: :virtual_channel,
               secondary_header_length: 1
             )
  end

  test "separates VCA and Packet managed parameters" do
    assert {:ok, configuration} =
             Configuration.new(
               frame_size: 32,
               scid: 1,
               vcid: 2,
               data_field_content: :vca_sdu,
               valid_packet_version_numbers: [],
               maximum_packet_octets: nil
             )

    assert Configuration.maximum_data_field_octets(configuration) == 26

    assert {:error, {:field_must_be_empty, :valid_packet_version_numbers, [0]}} =
             Configuration.new(
               frame_size: 32,
               scid: 1,
               vcid: 2,
               data_field_content: :vca_sdu,
               maximum_packet_octets: nil
             )
  end

  test "keeps Master Channel secondary-header settings static across Virtual Channels" do
    common = [
      physical_channel: "downlink-a",
      frame_size: 64,
      scid: 7,
      valid_scids: [7],
      valid_vcids: [1, 2],
      secondary_header_source: :master_channel,
      secondary_header_length: 4,
      maximum_packet_octets: 128
    ]

    assert {:ok, vc1} = Configuration.new(Keyword.put(common, :vcid, 1))
    assert {:ok, vc2} = Configuration.new(Keyword.put(common, :vcid, 2))
    assert :ok = Configuration.validate_plan([vc1, vc2])

    assert {:ok, inconsistent} =
             Configuration.new(
               common
               |> Keyword.put(:vcid, 2)
               |> Keyword.put(:secondary_header_length, 5)
             )

    assert {:error,
            {{"downlink-a", 7}, {:inconsistent_master_channel_setting, :secondary_header_length}}} =
             Configuration.validate_plan([vc1, inconsistent])
  end
end
