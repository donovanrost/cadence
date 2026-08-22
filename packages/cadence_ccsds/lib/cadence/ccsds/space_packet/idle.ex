defmodule Cadence.CCSDS.SpacePacket.Idle do
  @moduledoc """
  Builds standards-shaped Idle Packets with a mission-selected repeating pattern.
  """

  alias Cadence.CCSDS.SpacePacket
  alias Cadence.CCSDS.SpacePacket.Codec

  @spec new(pos_integer(), keyword()) :: {:ok, SpacePacket.t()} | {:error, term()}
  def new(total_size, opts \\ []) when is_integer(total_size) and is_list(opts) do
    pattern = Keyword.get(opts, :pattern, <<0>>)

    cond do
      total_size < SpacePacket.minimum_size() or total_size > SpacePacket.maximum_size() ->
        {:error, {:invalid_idle_packet_size, total_size}}

      not is_binary(pattern) or pattern == <<>> ->
        {:error, {:invalid_idle_pattern, pattern}}

      true ->
        data_size = total_size - SpacePacket.primary_header_size()

        {:ok,
         SpacePacket.new(%{
           packet_type: :telemetry,
           secondary_header?: false,
           apid: SpacePacket.idle_apid(),
           sequence_flag: :unsegmented,
           sequence_count: Keyword.get(opts, :sequence_count, 0),
           data: repeat_pattern(pattern, data_size)
         })}
    end
  end

  @spec encode(pos_integer(), keyword()) :: {:ok, binary()} | {:error, term()}
  def encode(total_size, opts \\ []) do
    with {:ok, packet} <- new(total_size, opts) do
      Codec.encode(packet)
    end
  end

  @spec encode!(pos_integer(), keyword()) :: binary()
  def encode!(total_size, opts \\ []) do
    case encode(total_size, opts) do
      {:ok, encoded} -> encoded
      {:error, reason} -> raise ArgumentError, "invalid Idle Packet: #{inspect(reason)}"
    end
  end

  defp repeat_pattern(pattern, size) do
    repetitions = div(size + byte_size(pattern) - 1, byte_size(pattern))

    pattern
    |> :binary.copy(repetitions)
    |> binary_part(0, size)
  end
end
