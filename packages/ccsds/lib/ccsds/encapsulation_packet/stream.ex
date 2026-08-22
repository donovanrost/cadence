defmodule CCSDS.EncapsulationPacket.Stream do
  @moduledoc """
  Incremental Encapsulation Packet extraction from arbitrary byte chunks.
  """

  alias CCSDS.EncapsulationPacket.Codec

  @spec decode(binary(), keyword()) ::
          {:ok, [CCSDS.EncapsulationPacket.t()], binary()} | {:error, term()}
  def decode(buffer, opts \\ []) when is_binary(buffer) and is_list(opts),
    do: decode_packets(buffer, opts, [])

  @spec extract(binary(), keyword()) :: {:ok, [binary()], binary()} | {:error, term()}
  def extract(buffer, opts \\ []) when is_binary(buffer) and is_list(opts) do
    case decode(buffer, opts) do
      {:ok, packets, rest} ->
        encoded =
          Enum.map(packets, fn packet ->
            {:ok, value} = Codec.encode(packet, opts)
            value
          end)

        {:ok, encoded, rest}

      {:error, _reason} = error ->
        error
    end
  end

  defp decode_packets(buffer, opts, packets) do
    case Codec.decode_prefix(buffer, opts) do
      {:ok, packet, rest} -> decode_packets(rest, opts, [packet | packets])
      {:incomplete, rest} -> {:ok, Enum.reverse(packets), rest}
      {:error, _reason} = error -> error
    end
  end
end
