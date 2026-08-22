defmodule CCSDS.CFDP.Stream do
  @moduledoc """
  Incremental extraction of CFDP PDUs from arbitrary byte chunks.
  """

  alias CCSDS.CFDP.Codec
  alias CCSDS.CFDP.PDU

  @spec decode(binary(), keyword()) :: {:ok, [PDU.t()], binary()} | {:error, term()}
  def decode(buffer, opts \\ []) when is_binary(buffer) and is_list(opts),
    do: decode_pdus(buffer, opts, [])

  @spec extract(binary(), keyword()) :: {:ok, [binary()], binary()} | {:error, term()}
  def extract(buffer, opts \\ []) when is_binary(buffer) and is_list(opts) do
    extract_pdus(buffer, opts, [])
  end

  defp decode_pdus(buffer, opts, pdus) do
    case Codec.decode_prefix(buffer, opts) do
      {:ok, pdu, rest} -> decode_pdus(rest, opts, [pdu | pdus])
      {:incomplete, rest} -> {:ok, Enum.reverse(pdus), rest}
      {:error, _reason} = error -> error
    end
  end

  defp extract_pdus(buffer, opts, encoded) do
    case Codec.pdu_length(buffer) do
      {:ok, length} when byte_size(buffer) >= length ->
        <<pdu::binary-size(^length), rest::binary>> = buffer

        case Codec.decode(pdu, opts) do
          {:ok, _decoded} -> extract_pdus(rest, opts, [pdu | encoded])
          {:error, _reason} = error -> error
        end

      {:ok, _length} ->
        {:ok, Enum.reverse(encoded), buffer}

      {:error, {:truncated_cfdp_fixed_header, _expected, _actual}} ->
        {:ok, Enum.reverse(encoded), buffer}
    end
  end
end
