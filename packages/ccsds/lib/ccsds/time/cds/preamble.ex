defmodule CCSDS.Time.CDS.Preamble do
  @moduledoc """
  Explicit CDS P-field codec from CCSDS 301.0-B-4 section 3.3.2.
  """

  import Bitwise

  alias CCSDS.Time.CDS.Configuration

  @identifier 0b100

  @spec encode(Configuration.t()) :: {:ok, binary()} | {:error, term()}
  def encode(%Configuration{} = configuration) do
    with :ok <- Configuration.validate(configuration) do
      epoch = if(configuration.epoch == :agency, do: 1, else: 0)
      days = if(configuration.day_octets == 3, do: 1, else: 0)
      submilliseconds = encode_submilliseconds(configuration.submillisecond_octets)
      {:ok, <<@identifier <<< 4 ||| epoch <<< 3 ||| days <<< 2 ||| submilliseconds>>}
    end
  end

  @spec decode_prefix(binary(), keyword()) ::
          {:ok, Configuration.t(), binary(), binary()}
          | {:incomplete, binary()}
          | {:error, term()}
  def decode_prefix(binary, opts \\ []) when is_binary(binary) and is_list(opts) do
    case binary do
      <<first, rest::binary>> -> decode_first(first, rest, opts)
      <<>> -> {:incomplete, binary}
    end
  end

  defp decode_first(first, rest, opts) do
    extension? = (first &&& 0x80) != 0
    identifier = first >>> 4 &&& 0x07
    submilliseconds = first &&& 0x03

    cond do
      extension? ->
        {:error, :unsupported_cds_preamble_extension}

      identifier != @identifier ->
        {:error, {:invalid_cds_time_code_identification, identifier}}

      submilliseconds == 3 ->
        {:error, :reserved_cds_submillisecond_length}

      true ->
        attrs = [
          epoch: if((first &&& 0x08) == 0, do: :ccsds, else: :agency),
          day_octets: if((first &&& 0x04) == 0, do: 2, else: 3),
          submillisecond_octets: decode_submilliseconds(submilliseconds),
          day_length: Keyword.get(opts, :day_length, :unknown)
        ]

        with {:ok, configuration} <- Configuration.new(attrs) do
          {:ok, configuration, rest, <<first>>}
        end
    end
  end

  defp encode_submilliseconds(0), do: 0
  defp encode_submilliseconds(2), do: 1
  defp encode_submilliseconds(4), do: 2

  defp decode_submilliseconds(0), do: 0
  defp decode_submilliseconds(1), do: 2
  defp decode_submilliseconds(2), do: 4
end
