defmodule CCSDS.SpacePacket.Codec do
  @moduledoc """
  Strict encoder and decoder for CCSDS 133.0-B-2 Space Packets.

  `decode/2` requires exactly one complete packet. `decode_prefix/2` is the
  streaming primitive and leaves any following octets untouched.
  """

  alias CCSDS.SpacePacket

  @type decode_error ::
          :invalid_packet
          | {:invalid_field, atom(), term()}
          | {:packet_too_short, non_neg_integer()}
          | {:truncated_packet, pos_integer(), non_neg_integer()}
          | {:trailing_bytes, pos_integer(), pos_integer()}
          | {:unsupported_version, non_neg_integer()}
          | {:packet_size_exceeds_managed_maximum, pos_integer(), pos_integer()}

  @spec encode(SpacePacket.t()) :: {:ok, binary()} | {:error, term()}
  def encode(%SpacePacket{} = packet) do
    with :ok <- validate(packet) do
      packet_type = packet_type_value(packet.packet_type)
      secondary_header_flag = if(packet.secondary_header?, do: 1, else: 0)
      sequence_flag = SpacePacket.sequence_flag_value(packet.sequence_flag)
      data_length = byte_size(packet.data) - 1

      {:ok,
       <<
         packet.version::3,
         packet_type::1,
         secondary_header_flag::1,
         packet.apid::11,
         sequence_flag::2,
         packet.sequence_count::14,
         data_length::16,
         packet.data::binary
       >>}
    end
  end

  @spec decode(binary(), keyword()) :: {:ok, SpacePacket.t()} | {:error, decode_error()}
  def decode(binary, opts \\ []) when is_binary(binary) and is_list(opts) do
    case decode_prefix(binary, opts) do
      {:ok, packet, <<>>} ->
        {:ok, packet}

      {:ok, _packet, rest} ->
        {:error, {:trailing_bytes, byte_size(binary) - byte_size(rest), byte_size(binary)}}

      {:incomplete, buffer} ->
        expected_size = expected_size(buffer)
        {:error, {:truncated_packet, expected_size, byte_size(buffer)}}

      {:error, reason} ->
        {:error, reason}
    end
  end

  @spec decode_prefix(binary(), keyword()) ::
          {:ok, SpacePacket.t(), binary()}
          | {:incomplete, binary()}
          | {:error, decode_error()}
  def decode_prefix(binary, opts \\ []) when is_binary(binary) and is_list(opts) do
    primary_header_size = SpacePacket.primary_header_size()

    if byte_size(binary) < primary_header_size do
      {:incomplete, binary}
    else
      decode_header_and_data(binary, opts)
    end
  end

  defp decode_header_and_data(
         <<
           version::3,
           packet_type::1,
           secondary_header_flag::1,
           apid::11,
           sequence_flag::2,
           sequence_count::14,
           data_length::16,
           rest::binary
         >> = buffer,
         opts
       ) do
    data_size = data_length + 1
    total_size = SpacePacket.primary_header_size() + data_size
    managed_maximum = Keyword.get(opts, :max_packet_size, SpacePacket.maximum_size())

    cond do
      version != 0 ->
        {:error, {:unsupported_version, version}}

      not valid_managed_maximum?(managed_maximum) ->
        {:error, {:invalid_field, :max_packet_size, managed_maximum}}

      total_size > managed_maximum ->
        {:error, {:packet_size_exceeds_managed_maximum, total_size, managed_maximum}}

      byte_size(buffer) < total_size ->
        {:incomplete, buffer}

      true ->
        <<data::binary-size(^data_size), trailing::binary>> = rest

        packet = %SpacePacket{
          version: version,
          packet_type: packet_type_from_value(packet_type),
          secondary_header?: secondary_header_flag == 1,
          apid: apid,
          sequence_flag: SpacePacket.sequence_flag_from_value(sequence_flag),
          sequence_count: sequence_count,
          data: data
        }

        with :ok <- validate(packet) do
          {:ok, packet, trailing}
        end
    end
  end

  defp expected_size(buffer) when byte_size(buffer) < 6, do: 6

  defp expected_size(<<_header::binary-size(4), data_length::16, _rest::binary>>) do
    SpacePacket.primary_header_size() + data_length + 1
  end

  defp validate(%SpacePacket{} = packet) do
    checks = [
      fn -> validate_version(packet.version) end,
      fn -> validate_member(packet.packet_type, [:telemetry, :command], :packet_type) end,
      fn -> validate_boolean(packet.secondary_header?, :secondary_header?) end,
      fn -> validate_range(packet.apid, 0, 0x7FF, :apid) end,
      fn ->
        validate_member(
          packet.sequence_flag,
          [:continuation, :first, :last, :unsegmented],
          :sequence_flag
        )
      end,
      fn -> validate_range(packet.sequence_count, 0, 0x3FFF, :sequence_count) end,
      fn -> validate_data(packet.data) end,
      fn -> validate_idle_packet(packet) end
    ]

    Enum.reduce_while(checks, :ok, fn check, _acc ->
      case check.() do
        :ok -> {:cont, :ok}
        {:error, _reason} = error -> {:halt, error}
      end
    end)
  end

  defp validate_version(0), do: :ok
  defp validate_version(value), do: {:error, {:unsupported_version, value}}

  defp validate_boolean(value, _field) when is_boolean(value), do: :ok
  defp validate_boolean(value, field), do: {:error, {:invalid_field, field, value}}

  defp validate_member(value, allowed, field) do
    if value in allowed do
      :ok
    else
      {:error, {:invalid_field, field, value}}
    end
  end

  defp validate_range(value, min, max, _field)
       when is_integer(value) and value >= min and value <= max,
       do: :ok

  defp validate_range(value, _min, _max, field),
    do: {:error, {:invalid_field, field, value}}

  defp validate_data(data)
       when is_binary(data) and byte_size(data) >= 1 and byte_size(data) <= 65_536,
       do: :ok

  defp validate_data(data), do: {:error, {:invalid_field, :data, data}}

  defp validate_idle_packet(%SpacePacket{} = packet) do
    if SpacePacket.idle?(packet) and packet.secondary_header? do
      {:error, {:invalid_field, :secondary_header?, true}}
    else
      :ok
    end
  end

  defp valid_managed_maximum?(value) do
    is_integer(value) and value >= SpacePacket.minimum_size() and
      value <= SpacePacket.maximum_size()
  end

  defp packet_type_value(:telemetry), do: 0
  defp packet_type_value(:command), do: 1

  defp packet_type_from_value(0), do: :telemetry
  defp packet_type_from_value(1), do: :command
end
