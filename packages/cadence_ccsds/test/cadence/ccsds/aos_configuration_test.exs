defmodule Cadence.CCSDS.SDLP.AOS.ConfigurationTest do
  use ExUnit.Case, async: true

  alias Cadence.CCSDS.SDLP.AOS.Configuration

  test "derives non-Packet defaults and enforces physical and master channel consistency" do
    bitstream =
      Configuration.new!(
        physical_channel: "x-band",
        frame_size: 64,
        scid: 700,
        vcid: 2,
        valid_vcids: [2, 3, 63],
        data_field_content: :b_pdu
      )

    access =
      Configuration.new!(
        physical_channel: "x-band",
        frame_size: 64,
        scid: 700,
        vcid: 3,
        valid_vcids: [2, 3, 63],
        data_field_content: :vca_sdu
      )

    assert bitstream.valid_packet_version_numbers == []
    assert bitstream.maximum_packet_octets == nil
    assert :ok = Configuration.validate_plan([bitstream, access])
  end

  test "reserves VCID 63 for OID and forbids an OCF there" do
    assert {:error, :idle_vcid_requires_idle_data} =
             Configuration.new(frame_size: 32, scid: 1, vcid: 63)

    assert {:error, :idle_vcid_forbids_ocf} =
             Configuration.new(
               frame_size: 32,
               scid: 1,
               vcid: 63,
               data_field_content: :idle_data,
               ocf?: true
             )
  end
end
