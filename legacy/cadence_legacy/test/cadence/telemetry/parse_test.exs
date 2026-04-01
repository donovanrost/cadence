defmodule Cadence.Telemetry.ParseTest do
  use ExUnit.Case, async: true

  alias Cadence.Telemetry.{PacketEnvelope, Parse, UnknownUnit}

  defp build_space_packet(version, apid, data_field) do
    type = 0
    sec_hdr_flag = 1
    seq_flags = 3
    seq_count = 1
    length = byte_size(data_field) - 1

    <<
      version::3,
      type::1,
      sec_hdr_flag::1,
      apid::11,
      seq_flags::2,
      seq_count::14,
      length::16,
      data_field::binary
    >>
  end

  test "space packet parse success adds apid evidence" do
    raw = build_space_packet(0, 100, <<0, 0, 0, 0, 0, 0, 0, 0, 0xAA>>)
    envelope = PacketEnvelope.new("mission-1", raw, config_version_seen: 1)

    assert {:ok, {:space_packet, _packet}, updated} = Parse.run(envelope)
    assert Enum.any?(updated.evidence, &(&1.kind == :apid and &1.value == 100))
  end

  test "parse unknown for non-space-packet version" do
    raw = build_space_packet(7, 100, <<0, 0, 0, 0, 0, 0, 0, 0, 0xAA>>)
    envelope = PacketEnvelope.new("mission-1", raw, config_version_seen: 1)

    assert {:ok, {:unknown, %UnknownUnit{}}, _updated} = Parse.run(envelope)
  end

  test "parse malformed for insufficient data" do
    envelope = PacketEnvelope.new("mission-1", <<1, 2, 3>>, config_version_seen: 1)

    assert {:error, {:malformed, :insufficient_data, _context}, _updated} = Parse.run(envelope)
  end
end
