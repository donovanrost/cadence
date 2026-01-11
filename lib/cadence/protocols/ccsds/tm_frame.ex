defmodule Cadence.Protocols.CCSDS.TMFrame do
  @moduledoc """
  Minimal CCSDS TM transfer frame encoder for simulator output.

  This encoder assumes:
  - One space packet per frame (no segmentation)
  - Fixed frame size with idle packet padding
  - No secondary header or OCF
  - Counters are provided by the caller (defaults to 0)
  """

  import Bitwise

  @primary_header_size 6
  @min_idle_packet_size @primary_header_size + 1
  @idle_apid 0x7FF
  @oid_seed 0xFFFFFFFF

  @doc """
  Encodes a CCSDS space packet into a TM transfer frame.

  Required options:
  - `:frame_size` - Total frame size in bytes

  Optional options:
  - `:scid` - Spacecraft ID (default: 0)
  - `:vcid` - Virtual channel ID (default: 0)
  - `:mcfc` - Master channel frame count (default: 0)
  - `:vcfc` - Virtual channel frame count (default: 0)
  """
  @spec encode(binary(), keyword()) :: binary()
  def encode(packet, opts) when is_binary(packet) do
    frame_size = Keyword.fetch!(opts, :frame_size)
    scid = Keyword.get(opts, :scid, 0)
    vcid = Keyword.get(opts, :vcid, 0)
    mcfc = Keyword.get(opts, :mcfc, 0)
    vcfc = Keyword.get(opts, :vcfc, 0)

    validate_frame_opts!(frame_size, scid, vcid, mcfc, vcfc)

    fhp = 0
    version = 0
    ocf_flag = 0
    sec_hdr_flag = 0
    sync_flag = 0
    packet_order_flag = 0
    segment_len_id = 3

    primary_header =
      <<
        version::2,
        scid::10,
        vcid::3,
        ocf_flag::1,
        mcfc::8,
        vcfc::8,
        sec_hdr_flag::1,
        sync_flag::1,
        packet_order_flag::1,
        segment_len_id::2,
        fhp::11
      >>

    max_payload = frame_size - @primary_header_size

    if byte_size(packet) > max_payload do
      raise ArgumentError,
            "Packet size #{byte_size(packet)} exceeds TM frame payload #{max_payload}"
    end

    padding_size = max_payload - byte_size(packet)
    padding = build_idle_padding(padding_size)

    primary_header <> packet <> padding
  end

  @doc """
  Encodes an OID (Only Idle Data) TM frame.

  Returns `{frame_binary, next_pn_state}` where `next_pn_state` should be used
  for subsequent OID frames on the same VCID.
  """
  @spec encode_oid(keyword()) :: {binary(), non_neg_integer()}
  def encode_oid(opts) do
    frame_size = Keyword.fetch!(opts, :frame_size)
    scid = Keyword.get(opts, :scid, 0)
    vcid = Keyword.get(opts, :vcid, 0)
    mcfc = Keyword.get(opts, :mcfc, 0)
    vcfc = Keyword.get(opts, :vcfc, 0)
    pn_state = Keyword.get(opts, :pn_state, @oid_seed)

    validate_frame_opts!(frame_size, scid, vcid, mcfc, vcfc)

    fhp = 2046
    version = 0
    ocf_flag = 0
    sec_hdr_flag = 0
    sync_flag = 0
    packet_order_flag = 0
    segment_len_id = 3

    primary_header =
      <<
        version::2,
        scid::10,
        vcid::3,
        ocf_flag::1,
        mcfc::8,
        vcfc::8,
        sec_hdr_flag::1,
        sync_flag::1,
        packet_order_flag::1,
        segment_len_id::2,
        fhp::11
      >>

    data_field_size = frame_size - @primary_header_size
    {data_field, next_state} = oid_pn_bytes(data_field_size, pn_state)

    {primary_header <> data_field, next_state}
  end

  defp validate_frame_opts!(frame_size, scid, vcid, mcfc, vcfc) do
    validate_frame_size!(frame_size)
    validate_scid!(scid)
    validate_vcid!(vcid)
    validate_counter!(mcfc, "mcfc")
    validate_counter!(vcfc, "vcfc")
  end

  defp validate_frame_size!(frame_size) when frame_size < @primary_header_size do
    raise ArgumentError, "frame_size must be at least #{@primary_header_size} bytes"
  end

  defp validate_frame_size!(_frame_size), do: :ok

  defp validate_scid!(scid) when scid < 0 or scid > 1023 do
    raise ArgumentError, "scid must be between 0 and 1023"
  end

  defp validate_scid!(_scid), do: :ok

  defp validate_vcid!(vcid) when vcid < 0 or vcid > 7 do
    raise ArgumentError, "vcid must be between 0 and 7"
  end

  defp validate_vcid!(_vcid), do: :ok

  defp validate_counter!(value, name) when value < 0 or value > 255 do
    raise ArgumentError, "#{name} must be between 0 and 255"
  end

  defp validate_counter!(_value, _name), do: :ok

  defp build_idle_padding(0), do: <<>>

  defp build_idle_padding(padding_size) when padding_size < @min_idle_packet_size do
    raise ArgumentError,
          "TM frame padding #{padding_size} bytes is too small for an idle packet; " <>
            "increase frame_size or adjust packet size"
  end

  defp build_idle_padding(padding_size) do
    build_idle_packet(padding_size)
  end

  defp build_idle_packet(size) do
    payload_size = size - @primary_header_size
    packet_length = payload_size - 1
    payload = :binary.copy(<<0>>, payload_size)

    <<
      0::3,
      0::1,
      0::1,
      @idle_apid::11,
      3::2,
      0::14,
      packet_length::16,
      payload::binary
    >>
  end

  defp oid_pn_bytes(length, lfsr_state) do
    {bits, next_state} = generate_oid_bits(length * 8, lfsr_state)

    bytes =
      bits
      |> Enum.chunk_every(8)
      |> Enum.map(fn chunk ->
        Enum.reduce(chunk, 0, fn bit, acc -> (acc <<< 1) ||| bit end)
      end)
      |> :binary.list_to_bin()

    {bytes, next_state}
  end

  defp generate_oid_bits(count, lfsr_state) do
    Enum.reduce(1..count, {[], lfsr_state}, fn _, {acc, state} ->
      {bit, next_state} = next_oid_bit(state)
      {[bit | acc], next_state}
    end)
    |> then(fn {bits, next_state} -> {Enum.reverse(bits), next_state} end)
  end

  defp next_oid_bit(state) do
    output = (state >>> 31) &&& 1

    feedback =
      output
      |> bxor((state >>> 21) &&& 1)
      |> bxor((state >>> 1) &&& 1)
      |> bxor(state &&& 1)

    next_state = ((state <<< 1) &&& 0xFFFFFFFF) ||| feedback
    {output, next_state}
  end
end
