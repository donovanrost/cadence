defmodule CCSDS.EncapsulationPacket.Codec do
  @moduledoc """
  Strict CCSDS 133.1-B-3 Encapsulation Packet wire codec.

  The streaming decoder derives total packet size from Length-of-Length and
  accepts all four normative header sizes. Encoding can use the smallest legal
  header or a managed fixed header size.
  """

  alias CCSDS.EncapsulationPacket
  alias CCSDS.EncapsulationPacket.Configuration

  @version 0b111
  @header_sizes %{0 => 1, 1 => 2, 2 => 4, 3 => 8}
  @length_octets %{1 => 0, 2 => 1, 4 => 2, 8 => 4}

  @spec encode(EncapsulationPacket.t(), keyword()) :: {:ok, binary()} | {:error, term()}
  def encode(packet, opts \\ [])

  def encode(%EncapsulationPacket{} = packet, opts) when is_list(opts) do
    with {:ok, configuration} <- configuration(opts),
         {:ok, header_octets} <- select_header_octets(packet, configuration, opts),
         :ok <- validate(packet, header_octets, configuration) do
      encode_packet(packet, header_octets)
    end
  end

  def encode(value, _opts), do: {:error, {:invalid_encapsulation_packet, value}}

  @spec decode(binary(), keyword()) :: {:ok, EncapsulationPacket.t()} | {:error, term()}
  def decode(binary, opts \\ []) when is_binary(binary) and is_list(opts) do
    case decode_prefix(binary, opts) do
      {:ok, packet, <<>>} ->
        {:ok, packet}

      {:ok, _packet, rest} ->
        {:error, {:trailing_bytes, byte_size(binary) - byte_size(rest), byte_size(binary)}}

      {:incomplete, buffer} ->
        {:error, {:truncated_packet, expected_packet_octets(buffer), byte_size(buffer)}}

      {:error, _reason} = error ->
        error
    end
  end

  @spec decode_prefix(binary(), keyword()) ::
          {:ok, EncapsulationPacket.t(), binary()} | {:incomplete, binary()} | {:error, term()}
  def decode_prefix(binary, opts \\ []) when is_binary(binary) and is_list(opts) do
    with {:ok, configuration} <- configuration(opts) do
      decode_buffer(binary, configuration)
    end
  end

  @spec packet_length(binary()) :: {:ok, pos_integer()} | {:error, term()}
  def packet_length(<<version::3, protocol_id::3, length_of_length::2, rest::binary>>) do
    with :ok <- validate_version(version),
         :ok <- validate_idle_short_header(protocol_id, length_of_length),
         header_octets <- Map.fetch!(@header_sizes, length_of_length) do
      packet_length_from_header(rest, header_octets)
    end
  end

  def packet_length(_binary), do: {:error, {:truncated_packet_length_field, 1, 0}}

  @spec header_octets_for_data(non_neg_integer(), EncapsulationPacket.t()) ::
          {:ok, EncapsulationPacket.header_octets()} | {:error, term()}
  def header_octets_for_data(data_octets, packet)
      when is_integer(data_octets) and data_octets >= 0 do
    cond do
      one_octet_idle?(packet, data_octets) ->
        {:ok, 1}

      short_header?(packet, data_octets) ->
        {:ok, 2}

      data_octets + 4 <= 0xFFFF ->
        {:ok, 4}

      data_octets + 8 <= 0xFFFFFFFF ->
        {:ok, 8}

      true ->
        {:error, {:encapsulation_packet_too_large, data_octets}}
    end
  end

  defp decode_buffer(binary, _configuration) when byte_size(binary) < 1, do: {:incomplete, binary}

  defp decode_buffer(
         <<version::3, protocol_id::3, length_of_length::2, _rest::binary>> = binary,
         configuration
       ) do
    with :ok <- validate_version(version),
         :ok <- validate_idle_short_header(protocol_id, length_of_length),
         header_octets <- Map.fetch!(@header_sizes, length_of_length),
         true <- byte_size(binary) >= header_octets,
         {:ok, total_octets} <- packet_length(binary),
         :ok <- validate_wire_length(total_octets, header_octets, configuration) do
      if byte_size(binary) >= total_octets,
        do:
          decode_complete_packet(binary, protocol_id, header_octets, total_octets, configuration),
        else: {:incomplete, binary}
    else
      false -> {:incomplete, binary}
      {:error, _reason} = error -> error
    end
  end

  defp decode_complete_packet(binary, protocol_id, header_octets, total_octets, configuration) do
    <<packet_binary::binary-size(^total_octets), rest::binary>> = binary

    with {:ok, fields, data} <- decode_fields(packet_binary, protocol_id, header_octets),
         packet <- struct(EncapsulationPacket, Map.put(fields, :data, data)),
         :ok <- validate(packet, header_octets, configuration) do
      {:ok, packet, rest}
    end
  end

  defp decode_fields(<<_first>>, protocol_id, 1) do
    {:ok, base_fields(protocol_id, 1), <<>>}
  end

  defp decode_fields(<<_first, _length, data::binary>>, protocol_id, 2) do
    {:ok, base_fields(protocol_id, 2), data}
  end

  defp decode_fields(
         <<_first, user_defined::4, extension::4, _length::16, data::binary>>,
         protocol_id,
         4
       ) do
    with :ok <- validate_wire_extension(protocol_id, extension) do
      {:ok, extended_fields(protocol_id, user_defined, extension, 0, 4), data}
    end
  end

  defp decode_fields(
         <<_first, user_defined::4, extension::4, ccsds_defined::16, _length::32, data::binary>>,
         protocol_id,
         8
       ) do
    with :ok <- validate_wire_extension(protocol_id, extension) do
      {:ok, extended_fields(protocol_id, user_defined, extension, ccsds_defined, 8), data}
    end
  end

  defp base_fields(protocol_id, header_octets) do
    %{
      version: @version,
      protocol_id: protocol_id,
      protocol_id_extension: nil,
      user_defined: 0,
      ccsds_defined: 0,
      header_octets: header_octets
    }
  end

  defp extended_fields(protocol_id, user_defined, extension, ccsds_defined, header_octets) do
    base_fields(protocol_id, header_octets)
    |> Map.put(:user_defined, user_defined)
    |> Map.put(:protocol_id_extension, if(protocol_id == 6, do: extension, else: nil))
    |> Map.put(:ccsds_defined, ccsds_defined)
  end

  defp encode_packet(packet, header_octets) do
    length_of_length = length_of_length(header_octets)
    first = <<@version::3, packet.protocol_id::3, length_of_length::2>>
    total_octets = header_octets + byte_size(packet.data)

    case header_octets do
      1 ->
        {:ok, first}

      2 ->
        {:ok, first <> <<total_octets::8>> <> packet.data}

      4 ->
        extension = packet.protocol_id_extension || 0
        {:ok, first <> <<packet.user_defined::4, extension::4, total_octets::16>> <> packet.data}

      8 ->
        extension = packet.protocol_id_extension || 0

        {:ok,
         first <>
           <<packet.user_defined::4, extension::4, packet.ccsds_defined::16, total_octets::32>> <>
           packet.data}
    end
  end

  defp select_header_octets(packet, configuration, opts) do
    requested =
      Keyword.get(opts, :header_octets, packet.header_octets || configuration.header_mode)

    case requested do
      :adaptive -> header_octets_for_data(byte_size(packet.data), packet)
      value when value in [1, 2, 4, 8] -> {:ok, value}
      value -> {:error, {:invalid_field, :header_octets, value}}
    end
  end

  defp validate(packet, header_octets, configuration) do
    checks = [
      fn -> validate_version(packet.version) end,
      fn -> validate_range(packet.protocol_id, 0, 7, :protocol_id) end,
      fn -> validate_protocol_id(packet, configuration) end,
      fn -> validate_range(packet.user_defined, 0, 15, :user_defined) end,
      fn -> validate_range(packet.ccsds_defined, 0, 0, :ccsds_defined) end,
      fn -> validate_extension(packet, header_octets, configuration) end,
      fn -> validate_data(packet, configuration) end,
      fn -> validate_header(packet, header_octets) end
    ]

    Enum.reduce_while(checks, :ok, fn check, :ok ->
      case check.() do
        :ok -> {:cont, :ok}
        {:error, _reason} = error -> {:halt, error}
      end
    end)
  end

  defp validate_protocol_id(packet, configuration) do
    if packet.protocol_id in configuration.valid_protocol_ids,
      do: :ok,
      else: {:error, {:unsupported_encapsulation_protocol_id, packet.protocol_id}}
  end

  defp validate_extension(
         %{protocol_id: 6, protocol_id_extension: extension},
         header_octets,
         configuration
       ) do
    cond do
      header_octets not in [4, 8] ->
        {:error, :extended_protocol_id_requires_long_header}

      extension not in configuration.valid_extended_protocol_ids ->
        {:error, {:unsupported_extended_protocol_id, extension}}

      true ->
        :ok
    end
  end

  defp validate_extension(%{protocol_id_extension: extension}, header_octets, _configuration) do
    cond do
      not is_nil(extension) -> {:error, {:unexpected_extended_protocol_id, extension}}
      header_octets in [1, 2] -> :ok
      true -> :ok
    end
  end

  defp validate_data(packet, configuration) when is_binary(packet.data) do
    size = byte_size(packet.data)

    cond do
      size == 0 and packet.protocol_id != 0 ->
        {:error, :empty_data_requires_idle_protocol_id}

      size < configuration.minimum_data_unit_octets and packet.protocol_id != 0 ->
        {:error, {:data_unit_below_managed_minimum, size, configuration.minimum_data_unit_octets}}

      size > configuration.maximum_data_unit_octets ->
        {:error,
         {:data_unit_exceeds_managed_maximum, size, configuration.maximum_data_unit_octets}}

      true ->
        :ok
    end
  end

  defp validate_data(packet, _configuration), do: {:error, {:invalid_field, :data, packet.data}}

  defp validate_header(packet, 1) do
    if packet.protocol_id == 0 and packet.data == <<>> and packet.user_defined == 0,
      do: :ok,
      else: {:error, :one_octet_header_requires_empty_idle_packet}
  end

  defp validate_header(packet, 2) do
    cond do
      packet.protocol_id == 6 -> {:error, :extended_protocol_id_requires_long_header}
      packet.user_defined != 0 -> {:error, :user_defined_field_requires_long_header}
      byte_size(packet.data) + 2 > 0xFF -> {:error, :packet_length_exceeds_header_capacity}
      true -> :ok
    end
  end

  defp validate_header(packet, 4) do
    if byte_size(packet.data) + 4 <= 0xFFFF,
      do: :ok,
      else: {:error, :packet_length_exceeds_header_capacity}
  end

  defp validate_header(packet, 8) do
    if byte_size(packet.data) + 8 <= 0xFFFFFFFF,
      do: :ok,
      else: {:error, :packet_length_exceeds_header_capacity}
  end

  defp validate_wire_length(total_octets, header_octets, configuration) do
    data_octets = total_octets - header_octets

    cond do
      total_octets < header_octets ->
        {:error, {:invalid_encapsulation_packet_length, total_octets, header_octets}}

      data_octets > configuration.maximum_data_unit_octets ->
        {:error,
         {:data_unit_exceeds_managed_maximum, data_octets, configuration.maximum_data_unit_octets}}

      true ->
        :ok
    end
  end

  defp packet_length_from_header(_rest, 1), do: {:ok, 1}

  defp packet_length_from_header(rest, header_octets) do
    length_octets = Map.fetch!(@length_octets, header_octets)
    prefix_octets = header_octets - length_octets - 1
    required = prefix_octets + length_octets

    if byte_size(rest) >= required do
      <<_prefix::binary-size(^prefix_octets), length::size(^length_octets * 8),
        _trailing::binary>> =
        rest

      {:ok, length}
    else
      {:error, {:truncated_packet_length_field, header_octets, byte_size(rest) + 1}}
    end
  end

  defp expected_packet_octets(buffer) do
    case packet_length(buffer) do
      {:ok, value} -> value
      {:error, _reason} -> expected_header_octets(buffer)
    end
  end

  defp expected_header_octets(<<_version::3, _protocol_id::3, length_of_length::2, _::binary>>),
    do: Map.fetch!(@header_sizes, length_of_length)

  defp expected_header_octets(_buffer), do: 1

  defp length_of_length(1), do: 0
  defp length_of_length(2), do: 1
  defp length_of_length(4), do: 2
  defp length_of_length(8), do: 3

  defp one_octet_idle?(packet, data_octets) do
    packet.protocol_id == 0 and data_octets == 0 and packet.user_defined == 0 and
      is_nil(packet.protocol_id_extension)
  end

  defp short_header?(packet, data_octets) do
    packet.protocol_id != 6 and packet.user_defined == 0 and data_octets + 2 <= 0xFF
  end

  defp configuration(opts) do
    case Keyword.get(opts, :configuration) do
      nil ->
        {:ok, %Configuration{}}

      %Configuration{} = configuration ->
        case Configuration.validate(configuration) do
          :ok -> {:ok, configuration}
          {:error, _reason} = error -> error
        end

      value ->
        {:error, {:invalid_encapsulation_configuration, value}}
    end
  end

  defp validate_idle_short_header(0, _length_of_length), do: :ok

  defp validate_idle_short_header(_protocol_id, 0),
    do: {:error, :one_octet_header_requires_idle_protocol_id}

  defp validate_idle_short_header(_protocol_id, _length_of_length), do: :ok
  defp validate_wire_extension(6, _extension), do: :ok
  defp validate_wire_extension(_protocol_id, 0), do: :ok

  defp validate_wire_extension(_protocol_id, extension),
    do: {:error, {:unexpected_extended_protocol_id, extension}}

  defp validate_version(@version), do: :ok
  defp validate_version(value), do: {:error, {:unsupported_version, value}}

  defp validate_range(value, minimum, maximum, _field)
       when is_integer(value) and value >= minimum and value <= maximum,
       do: :ok

  defp validate_range(value, _minimum, _maximum, field),
    do: {:error, {:invalid_field, field, value}}
end
