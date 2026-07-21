defmodule Cadence.CCSDS.TC.SegmentHeader do
  @moduledoc """
  Encoder and decoder for the one-octet CCSDS TC Segment Header.

  The two most-significant bits identify the segment position and the
  remaining six bits carry the Multiplexer Access Point identifier.
  """

  @type sequence_flag :: :continuation | :first | :last | :unsegmented

  @type t :: %__MODULE__{
          sequence_flag: sequence_flag(),
          map_id: 0..63
        }

  defstruct [:sequence_flag, :map_id]

  @spec encode(t()) :: {:ok, binary()} | {:error, term()}
  def encode(%__MODULE__{} = header) do
    with {:ok, sequence_flag} <- encode_sequence_flag(header.sequence_flag),
         :ok <- validate_map_id(header.map_id) do
      {:ok, <<sequence_flag::2, header.map_id::6>>}
    end
  end

  @spec decode(binary()) :: {:ok, t(), binary()} | {:error, term()}
  def decode(<<sequence_flag::2, map_id::6, rest::binary>>) do
    {:ok,
     %__MODULE__{
       sequence_flag: decode_sequence_flag(sequence_flag),
       map_id: map_id
     }, rest}
  end

  def decode(_binary), do: {:error, :segment_header_too_short}

  defp encode_sequence_flag(:continuation), do: {:ok, 0}
  defp encode_sequence_flag(:first), do: {:ok, 1}
  defp encode_sequence_flag(:last), do: {:ok, 2}
  defp encode_sequence_flag(:unsegmented), do: {:ok, 3}
  defp encode_sequence_flag(value), do: {:error, {:invalid_sequence_flag, value}}

  defp decode_sequence_flag(0), do: :continuation
  defp decode_sequence_flag(1), do: :first
  defp decode_sequence_flag(2), do: :last
  defp decode_sequence_flag(3), do: :unsegmented

  defp validate_map_id(value) when is_integer(value) and value >= 0 and value <= 63, do: :ok
  defp validate_map_id(value), do: {:error, {:invalid_map_id, value}}
end
