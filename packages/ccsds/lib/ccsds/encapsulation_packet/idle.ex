defmodule CCSDS.EncapsulationPacket.Idle do
  @moduledoc """
  Builds exact-size Encapsulation Idle Packets with a mission-selected pattern.
  """

  alias CCSDS.EncapsulationPacket
  alias CCSDS.EncapsulationPacket.Codec

  @spec encode(pos_integer(), keyword()) :: {:ok, binary()} | {:error, term()}
  def encode(total_octets, opts \\ []) when is_integer(total_octets) and is_list(opts) do
    pattern = Keyword.get(opts, :pattern, <<0>>)

    with {:ok, header_octets} <- header_octets(total_octets),
         :ok <- validate_pattern(pattern) do
      data = repeat_pattern(pattern, total_octets - header_octets)
      packet = EncapsulationPacket.new(protocol_id: 0, data: data, header_octets: header_octets)
      Codec.encode(packet, Keyword.put(opts, :header_octets, header_octets))
    end
  end

  @spec encode!(pos_integer(), keyword()) :: binary()
  def encode!(total_octets, opts \\ []) do
    case encode(total_octets, opts) do
      {:ok, encoded} ->
        encoded

      {:error, reason} ->
        raise ArgumentError, "invalid Encapsulation Idle Packet: #{inspect(reason)}"
    end
  end

  defp header_octets(1), do: {:ok, 1}
  defp header_octets(total) when total in 2..255, do: {:ok, 2}
  defp header_octets(total) when total in 256..65_535, do: {:ok, 4}
  defp header_octets(total) when total in 65_536..0xFFFFFFFF, do: {:ok, 8}
  defp header_octets(total), do: {:error, {:invalid_idle_packet_size, total}}

  defp validate_pattern(value) when is_binary(value) and byte_size(value) > 0, do: :ok
  defp validate_pattern(value), do: {:error, {:invalid_idle_pattern, value}}

  defp repeat_pattern(_pattern, 0), do: <<>>

  defp repeat_pattern(pattern, size) do
    repetitions = div(size + byte_size(pattern) - 1, byte_size(pattern))
    pattern |> :binary.copy(repetitions) |> binary_part(0, size)
  end
end
