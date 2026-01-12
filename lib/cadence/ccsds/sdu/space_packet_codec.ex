defmodule Cadence.CCSDS.SDU.SpacePacketCodec do
  @moduledoc """
  Space Packet SDU codec.
  """

  @behaviour Cadence.CCSDS.SDU.CodecBehaviour

  alias Cadence.CCSDS.Core.{PDU, SDUOctets}
  alias Cadence.CCSDS.SDU.SpacePacket

  @secondary_header_size 8

  @impl true
  def id, do: :space_packet

  @impl true
  def decode(%SDUOctets{octets: octets, timestamp: timestamp}, _opts) do
    with {:ok, packet} <- parse_space_packet(octets, timestamp) do
      {:ok,
       %PDU{
         type: :space_packet,
         value: packet,
         quality: :good,
         timestamp: timestamp,
         meta: %{}
       }}
    end
  end

  @impl true
  def encode(%PDU{type: :space_packet, value: %SpacePacket{} = packet}, opts) do
    profile = Keyword.get(opts, :profile, :tm)
    direction = Keyword.get(opts, :direction, :uplink)

    raw =
      case packet.raw do
        raw when is_binary(raw) -> raw
        _ -> build_space_packet(packet)
      end

    {:ok,
     %SDUOctets{
       profile: profile,
       scid: Keyword.get(opts, :scid),
       vcid: Keyword.get(opts, :vcid),
       map_id: Keyword.get(opts, :map_id),
       direction: direction,
       sdu_kind_hint: :space_packet,
       octets: raw,
       quality: :good,
       source_frames: [],
       timestamp: packet.timestamp,
       meta: %{}
     }}
  end

  def encode(_pdu, _opts), do: {:error, :invalid_pdu}

  defp parse_space_packet(
         <<
           version::3,
           type::1,
           secondary_header_flag::1,
           apid::11,
           sequence_flags::2,
           sequence_count::14,
           packet_length::16,
           rest::binary
         >> = raw,
         timestamp
       ) do
    if byte_size(rest) < @secondary_header_size do
      {:error, :missing_secondary_header}
    else
      <<timestamp_bytes::binary-size(6), target_hash::16, user_data::binary>> = rest

      {:ok,
       %SpacePacket{
         apid: apid,
         sequence_flags: sequence_flags,
         sequence_count: sequence_count,
         packet_length: packet_length,
         version: version,
         type: type,
         secondary_header_flag: secondary_header_flag,
         timestamp: timestamp || parse_ccsds_timestamp(timestamp_bytes),
         target_hash: target_hash,
         user_data: user_data,
         raw: raw
       }}
    end
  end

  defp parse_space_packet(_data, _timestamp), do: {:error, :insufficient_data}

  defp parse_ccsds_timestamp(<<days::16, ms_of_day::32>>) do
    epoch = ~U[1958-01-01 00:00:00Z]
    DateTime.add(epoch, days * 86_400 + div(ms_of_day, 1000), :second)
  end

  defp parse_ccsds_timestamp(_), do: nil

  defp build_space_packet(%SpacePacket{} = packet) do
    user_data = packet.user_data || <<>>
    {sec_hdr, sec_flag} = build_secondary_header(packet)
    packet_length = byte_size(sec_hdr <> user_data) - 1

    <<
      packet.version || 0::3,
      packet.type || 0::1,
      sec_flag::1,
      packet.apid::11,
      packet.sequence_flags || 3::2,
      packet.sequence_count || 0::14,
      packet_length::16,
      sec_hdr::binary,
      user_data::binary
    >>
  end

  defp build_secondary_header(%SpacePacket{} = packet) do
    if packet.secondary_header_flag == 0 do
      {<<>>, 0}
    else
      timestamp = packet.timestamp || ~U[1958-01-01 00:00:00Z]
      target_hash = packet.target_hash || 0
      {encode_ccsds_timestamp(timestamp) <> <<target_hash::16>>, 1}
    end
  end

  defp encode_ccsds_timestamp(%DateTime{} = timestamp) do
    epoch = ~U[1958-01-01 00:00:00Z]
    seconds = DateTime.diff(timestamp, epoch, :second)
    days = div(seconds, 86_400)
    ms_of_day = rem(seconds, 86_400) * 1000
    <<days::16, ms_of_day::32>>
  end
end
