defmodule Cadence.Runtime.Telemetry.SpacePacketFramer do
  @moduledoc """
  Stateful framer for CCSDS Space Packets in stream-based transports.
  """

  @primary_header_size 6

  @type t :: %__MODULE__{buffer: binary()}
  defstruct buffer: <<>>

  @spec new() :: t()
  def new, do: %__MODULE__{}

  @spec ingest(t(), binary()) :: {[binary()], t(), [atom()]}
  def ingest(%__MODULE__{buffer: buffer} = state, data) when is_binary(data) do
    buffer = buffer <> data
    {packets, rest, errors} = drain(buffer, [])
    {packets, %{state | buffer: rest}, errors}
  end

  defp drain(buffer, packets) do
    case next_packet(buffer) do
      {:ok, packet, rest} ->
        drain(rest, [packet | packets])

      {:error, reason, rest} ->
        {more_packets, final_rest, errors} = drain(rest, packets)
        {more_packets, final_rest, [reason | errors]}

      :more ->
        {Enum.reverse(packets), buffer, []}
    end
  end

  defp next_packet(buffer) when byte_size(buffer) < @primary_header_size, do: :more

  defp next_packet(buffer) do
    <<
      _version::3,
      _type::1,
      _secondary_header_flag::1,
      _apid::11,
      _sequence_flags::2,
      _sequence_count::14,
      packet_length::16,
      _rest::binary
    >> = buffer

    total_length = packet_length + 1 + @primary_header_size

    cond do
      total_length <= @primary_header_size ->
        drop_with_error(buffer, :invalid_length)

      byte_size(buffer) < total_length ->
        :more

      true ->
        packet = binary_part(buffer, 0, total_length)
        rest = binary_part(buffer, total_length, byte_size(buffer) - total_length)
        {:ok, packet, rest}
    end
  end

  defp drop_with_error(buffer, reason) do
    <<_::8, rest::binary>> = buffer
    {:error, reason, rest}
  end
end
