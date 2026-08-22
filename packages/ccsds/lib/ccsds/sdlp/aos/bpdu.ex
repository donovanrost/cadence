defmodule CCSDS.SDLP.AOS.BPDU do
  @moduledoc """
  AOS Bitstream Protocol Data Unit value and wire codec.
  """

  @all_valid 0x3FFF
  @only_idle_data 0x3FFE
  @largest_explicit_pointer 0x3FFD

  @type t :: %__MODULE__{
          bitstream_data_pointer: 0..0x3FFF,
          data_zone: binary()
        }

  defstruct [:bitstream_data_pointer, :data_zone]

  @spec all_valid() :: 0x3FFF
  def all_valid, do: @all_valid

  @spec only_idle_data() :: 0x3FFE
  def only_idle_data, do: @only_idle_data

  @spec encode(t()) :: {:ok, binary()} | {:error, term()}
  def encode(%__MODULE__{} = bpdu) do
    with :ok <- validate_zone(bpdu.data_zone),
         :ok <- validate_pointer(bpdu.bitstream_data_pointer, bit_size(bpdu.data_zone)) do
      {:ok, <<0::2, bpdu.bitstream_data_pointer::14, bpdu.data_zone::binary>>}
    end
  end

  def encode(value), do: {:error, {:invalid_aos_bpdu, value}}

  @spec decode(binary()) :: {:ok, t()} | {:error, term()}
  def decode(<<spare::2, pointer::14, data_zone::binary>>) do
    with :ok <- validate_spare(spare),
         :ok <- validate_zone(data_zone),
         :ok <- validate_pointer(pointer, bit_size(data_zone)) do
      {:ok, %__MODULE__{bitstream_data_pointer: pointer, data_zone: data_zone}}
    end
  end

  def decode(value), do: {:error, {:invalid_aos_bpdu, value}}

  @spec valid_bits(t()) :: {:ok, non_neg_integer()} | {:error, term()}
  def valid_bits(%__MODULE__{bitstream_data_pointer: @all_valid, data_zone: zone}),
    do: {:ok, bit_size(zone)}

  def valid_bits(%__MODULE__{bitstream_data_pointer: @only_idle_data}), do: {:ok, 0}

  def valid_bits(%__MODULE__{bitstream_data_pointer: pointer, data_zone: zone}) do
    if pointer <= @largest_explicit_pointer and pointer < bit_size(zone),
      do: {:ok, pointer + 1},
      else: {:error, {:invalid_bpdu_bitstream_data_pointer, pointer, bit_size(zone)}}
  end

  defp validate_zone(zone)
       when is_binary(zone) and byte_size(zone) > 0 and bit_size(zone) <= 16_384,
       do: :ok

  defp validate_zone(zone), do: {:error, {:invalid_bpdu_data_zone, zone}}
  defp validate_spare(0), do: :ok
  defp validate_spare(value), do: {:error, {:reserved_bpdu_spare_not_zero, value}}

  defp validate_pointer(pointer, _bits) when pointer in [@all_valid, @only_idle_data], do: :ok

  defp validate_pointer(pointer, bits)
       when is_integer(pointer) and pointer >= 0 and pointer <= @largest_explicit_pointer and
              pointer < bits,
       do: :ok

  defp validate_pointer(pointer, bits),
    do: {:error, {:invalid_bpdu_bitstream_data_pointer, pointer, bits}}
end
