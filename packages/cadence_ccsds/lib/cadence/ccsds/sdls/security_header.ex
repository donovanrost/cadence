defmodule Cadence.CCSDS.SDLS.SecurityHeader do
  @moduledoc """
  CCSDS 355.0-B-2 Security Header value and managed-length codec.
  """

  import Bitwise

  alias Cadence.CCSDS.SDLS.SecurityAssociation

  @type t :: %__MODULE__{
          spi: 1..65_534,
          initialization_vector: binary(),
          sequence_number: non_neg_integer() | nil,
          pad_length: non_neg_integer()
        }

  defstruct spi: nil,
            initialization_vector: <<>>,
            sequence_number: nil,
            pad_length: 0

  @spec encode(t(), SecurityAssociation.t()) :: {:ok, binary()} | {:error, term()}
  def encode(%__MODULE__{} = header, %SecurityAssociation{} = association) do
    with :ok <- validate_spi(header.spi, association.spi),
         :ok <-
           validate_iv(header.initialization_vector, association.initialization_vector_length),
         {:ok, sequence_number} <-
           encode_integer(
             header.sequence_number,
             association.sequence_number_length,
             :sequence_number
           ),
         {:ok, pad_length} <-
           encode_integer(header.pad_length, association.pad_length_length, :pad_length) do
      {:ok,
       <<header.spi::16, header.initialization_vector::binary, sequence_number::binary,
         pad_length::binary>>}
    end
  end

  @spec decode_prefix(binary(), SecurityAssociation.t()) ::
          {:ok, t(), binary(), binary()} | {:error, term()}
  def decode_prefix(binary, %SecurityAssociation{} = association) when is_binary(binary) do
    header_octets = SecurityAssociation.header_length(association)

    if byte_size(binary) >= header_octets do
      <<encoded::binary-size(^header_octets), rest::binary>> = binary
      decode_complete(encoded, rest, association)
    else
      {:error, {:truncated_security_header, header_octets, byte_size(binary)}}
    end
  end

  defp decode_complete(<<spi::16, fields::binary>> = encoded, rest, association) do
    iv_octets = association.initialization_vector_length
    sequence_octets = association.sequence_number_length
    pad_octets = association.pad_length_length

    with :ok <- validate_spi(spi, association.spi) do
      <<iv::binary-size(^iv_octets), sequence::binary-size(^sequence_octets),
        pad::binary-size(^pad_octets)>> = fields

      {:ok,
       %__MODULE__{
         spi: spi,
         initialization_vector: iv,
         sequence_number: decode_integer(sequence),
         pad_length: decode_integer(pad) || 0
       }, rest, encoded}
    end
  end

  defp encode_integer(value, 0, _field) when value in [nil, 0], do: {:ok, <<>>}

  defp encode_integer(value, octets, _field)
       when is_integer(value) and value >= 0 and value < 1 <<< (octets * 8),
       do: {:ok, <<value::unsigned-big-integer-size(octets * 8)>>}

  defp encode_integer(value, octets, field),
    do: {:error, {:invalid_security_header_field, field, value, octets}}

  defp decode_integer(<<>>), do: nil
  defp decode_integer(value), do: :binary.decode_unsigned(value)

  defp validate_spi(spi, spi), do: :ok

  defp validate_spi(actual, expected),
    do: {:error, {:security_parameter_index_mismatch, actual, expected}}

  defp validate_iv(value, expected) when is_binary(value) and byte_size(value) == expected,
    do: :ok

  defp validate_iv(value, expected),
    do: {:error, {:initialization_vector_length_mismatch, byte_size_safe(value), expected}}

  defp byte_size_safe(value) when is_binary(value), do: byte_size(value)
  defp byte_size_safe(_value), do: :invalid
end
