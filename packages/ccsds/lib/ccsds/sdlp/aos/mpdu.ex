defmodule CCSDS.SDLP.AOS.MPDU do
  @moduledoc """
  AOS Multiplexing Protocol Data Unit value and wire codec.
  """

  @no_packet_starts 0xFFFF
  @only_idle_data 0xFFFE

  @type t :: %__MODULE__{
          first_header_pointer: 0..0xFFFF,
          packet_zone: binary()
        }

  defstruct [:first_header_pointer, :packet_zone]

  @spec no_packet_starts() :: 0xFFFF
  def no_packet_starts, do: @no_packet_starts

  @spec only_idle_data() :: 0xFFFE
  def only_idle_data, do: @only_idle_data

  @spec encode(t()) :: {:ok, binary()} | {:error, term()}
  def encode(%__MODULE__{} = mpdu) do
    with :ok <- validate_zone(mpdu.packet_zone),
         :ok <- validate_pointer(mpdu.first_header_pointer, byte_size(mpdu.packet_zone)) do
      {:ok, <<mpdu.first_header_pointer::16, mpdu.packet_zone::binary>>}
    end
  end

  def encode(value), do: {:error, {:invalid_aos_mpdu, value}}

  @spec decode(binary()) :: {:ok, t()} | {:error, term()}
  def decode(<<pointer::16, packet_zone::binary>>) do
    with :ok <- validate_zone(packet_zone),
         :ok <- validate_pointer(pointer, byte_size(packet_zone)) do
      {:ok, %__MODULE__{first_header_pointer: pointer, packet_zone: packet_zone}}
    end
  end

  def decode(value), do: {:error, {:invalid_aos_mpdu, value}}

  defp validate_zone(zone) when is_binary(zone) and byte_size(zone) > 0, do: :ok
  defp validate_zone(zone), do: {:error, {:invalid_mpdu_packet_zone, zone}}

  defp validate_pointer(pointer, _size) when pointer in [@no_packet_starts, @only_idle_data],
    do: :ok

  defp validate_pointer(pointer, size)
       when is_integer(pointer) and pointer >= 0 and pointer < size, do: :ok

  defp validate_pointer(pointer, size),
    do: {:error, {:invalid_mpdu_first_header_pointer, pointer, size}}
end
