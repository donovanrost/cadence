defmodule CCSDS.SpacePacket.Stream do
  @moduledoc """
  Incremental extraction of complete Space Packets from arbitrary byte chunks.

  Complete packets are validated by the shared codec. A partial final packet
  is returned unchanged for the caller to prepend to the next chunk.
  """

  alias CCSDS.SpacePacket.Codec

  @spec decode(binary(), keyword()) ::
          {:ok, [CCSDS.SpacePacket.t()], binary()} | {:error, term()}
  def decode(buffer, opts \\ []) when is_binary(buffer) and is_list(opts) do
    decode_packets(buffer, opts, [])
  end

  @spec extract(binary(), keyword()) :: {:ok, [binary()], binary()} | {:error, term()}
  def extract(buffer, opts \\ []) when is_binary(buffer) and is_list(opts) do
    case decode(buffer, opts) do
      {:ok, packets, rest} ->
        encoded_packets =
          Enum.map(packets, fn packet ->
            {:ok, encoded} = Codec.encode(packet)
            encoded
          end)

        {:ok, encoded_packets, rest}

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp decode_packets(buffer, opts, acc) do
    case Codec.decode_prefix(buffer, opts) do
      {:ok, packet, rest} -> decode_packets(rest, opts, [packet | acc])
      {:incomplete, rest} -> {:ok, Enum.reverse(acc), rest}
      {:error, reason} -> {:error, reason}
    end
  end
end
