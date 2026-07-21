defmodule Cadence.CCSDS.TC.Service.PacketFormat do
  @moduledoc """
  Managed description of the Packet Version Number and length field of a TC
  Packet Service data unit.

  Packet blocking requires the service provider to know the position and size
  of each packet length field. `:length_adjustment` converts the unsigned wire
  value into the total packet length in octets. Encapsulation Packets use a
  dedicated dynamic resolver because their length field moves with the
  Length-of-Length value in the first octet.
  """

  alias Cadence.CCSDS.EncapsulationPacket.Codec, as: EncapsulationPacketCodec

  @type kind :: :fixed | :encapsulation_packet

  @type t :: %__MODULE__{
          kind: kind(),
          packet_version_number: 0..7,
          minimum_packet_octets: pos_integer(),
          length_field_offset_bits: non_neg_integer(),
          length_field_bits: pos_integer(),
          length_adjustment: integer()
        }

  defstruct kind: :fixed,
            packet_version_number: 0,
            minimum_packet_octets: 7,
            length_field_offset_bits: 32,
            length_field_bits: 16,
            length_adjustment: 7

  @spec space_packet() :: t()
  def space_packet, do: %__MODULE__{}

  @spec encapsulation_packet() :: t()
  def encapsulation_packet do
    %__MODULE__{
      kind: :encapsulation_packet,
      packet_version_number: 7,
      minimum_packet_octets: 1,
      length_field_offset_bits: 0,
      length_field_bits: 1,
      length_adjustment: 0
    }
  end

  @spec new(map() | keyword()) :: {:ok, t()} | {:error, term()}
  def new(attrs \\ %{}) when is_map(attrs) or is_list(attrs) do
    attrs = Map.new(attrs)
    known_fields = Map.keys(Map.from_struct(%__MODULE__{}))

    with [] <- Map.keys(attrs) -- known_fields,
         format = struct(__MODULE__, attrs),
         :ok <- validate(format) do
      {:ok, format}
    else
      [_unknown | _rest] -> {:error, :unknown_packet_format_attribute}
      {:error, _reason} = error -> error
    end
  end

  @spec validate(t()) :: :ok | {:error, term()}
  def validate(%__MODULE__{kind: :encapsulation_packet} = format) do
    with :ok <- validate_encapsulation_pvn(format.packet_version_number) do
      validate_encapsulation_minimum(format.minimum_packet_octets)
    end
  end

  def validate(%__MODULE__{} = format) do
    with :ok <- validate_fixed_kind(format.kind),
         :ok <- validate_range(format.packet_version_number, 0, 7, :packet_version_number),
         :ok <- validate_positive(format.minimum_packet_octets, :minimum_packet_octets),
         :ok <- validate_non_negative(format.length_field_offset_bits, :length_field_offset_bits),
         :ok <- validate_range(format.length_field_bits, 1, 32, :length_field_bits),
         :ok <- validate_integer(format.length_adjustment, :length_adjustment) do
      validate_header_capacity(format)
    end
  end

  @spec packet_version_number(binary()) :: {:ok, 0..7} | {:error, :truncated_packet}
  def packet_version_number(<<packet_version_number::3, _rest::bitstring>>),
    do: {:ok, packet_version_number}

  def packet_version_number(_packet), do: {:error, :truncated_packet}

  @spec total_packet_octets(binary(), t()) ::
          {:ok, pos_integer()} | {:error, term()}
  def total_packet_octets(packet, %__MODULE__{kind: :encapsulation_packet} = format)
      when is_binary(packet) do
    with {:ok, total_octets} <- EncapsulationPacketCodec.packet_length(packet),
         true <- total_octets >= format.minimum_packet_octets do
      {:ok, total_octets}
    else
      false -> {:error, {:invalid_packet_length, 0, format.minimum_packet_octets}}
      {:error, _reason} = error -> error
    end
  end

  def total_packet_octets(packet, %__MODULE__{} = format) when is_binary(packet) do
    offset_bits = format.length_field_offset_bits
    length_bits = format.length_field_bits
    required_bits = offset_bits + length_bits

    if bit_size(packet) >= required_bits do
      <<_prefix::size(^offset_bits), length_value::size(^length_bits), _rest::bitstring>> = packet

      total_octets = length_value + format.length_adjustment

      if total_octets >= format.minimum_packet_octets do
        {:ok, total_octets}
      else
        {:error, {:invalid_packet_length, total_octets, format.minimum_packet_octets}}
      end
    else
      {:error, {:truncated_packet_length_field, div(required_bits + 7, 8), byte_size(packet)}}
    end
  end

  defp validate_header_capacity(format) do
    required_octets = div(format.length_field_offset_bits + format.length_field_bits + 7, 8)

    if format.minimum_packet_octets >= required_octets do
      :ok
    else
      {:error,
       {:length_field_outside_minimum_packet, required_octets, format.minimum_packet_octets}}
    end
  end

  defp validate_fixed_kind(:fixed), do: :ok
  defp validate_fixed_kind(value), do: {:error, {:invalid_field, :kind, value}}

  defp validate_encapsulation_pvn(7), do: :ok

  defp validate_encapsulation_pvn(value),
    do: {:error, {:invalid_encapsulation_packet_version_number, value}}

  defp validate_encapsulation_minimum(1), do: :ok

  defp validate_encapsulation_minimum(value),
    do: {:error, {:invalid_encapsulation_packet_minimum, value}}

  defp validate_positive(value, _field) when is_integer(value) and value > 0, do: :ok
  defp validate_positive(value, field), do: {:error, {:invalid_field, field, value}}

  defp validate_non_negative(value, _field) when is_integer(value) and value >= 0, do: :ok
  defp validate_non_negative(value, field), do: {:error, {:invalid_field, field, value}}

  defp validate_integer(value, _field) when is_integer(value), do: :ok
  defp validate_integer(value, field), do: {:error, {:invalid_field, field, value}}

  defp validate_range(value, minimum, maximum, _field)
       when is_integer(value) and value >= minimum and value <= maximum,
       do: :ok

  defp validate_range(value, _minimum, _maximum, field),
    do: {:error, {:invalid_field, field, value}}
end
