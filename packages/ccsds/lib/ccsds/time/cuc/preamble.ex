defmodule CCSDS.Time.CUC.Preamble do
  @moduledoc """
  Explicit CUC P-field codec from CCSDS 301.0-B-4 section 3.2.2.
  """

  import Bitwise

  alias CCSDS.Time.CUC.Configuration

  @spec encode(Configuration.t()) :: {:ok, binary()} | {:error, term()}
  def encode(%Configuration{} = configuration) do
    with :ok <- Configuration.validate(configuration) do
      extended? =
        configuration.coarse_octets > 4 or configuration.fine_octets > 3 or
          configuration.mission_bits > 0

      coarse_base = min(configuration.coarse_octets, 4)
      fine_base = min(configuration.fine_octets, 3)
      identifier = if(configuration.epoch == :ccsds, do: 1, else: 2)
      extension = if(extended?, do: 1, else: 0)
      first = extension <<< 7 ||| identifier <<< 4 ||| (coarse_base - 1) <<< 2 ||| fine_base

      if extended? do
        coarse_extension = configuration.coarse_octets - coarse_base
        fine_extension = configuration.fine_octets - fine_base

        second =
          coarse_extension <<< 5 ||| fine_extension <<< 2 ||| configuration.mission_bits

        {:ok, <<first, second>>}
      else
        {:ok, <<first>>}
      end
    end
  end

  @spec decode_prefix(binary(), keyword()) ::
          {:ok, Configuration.t(), binary(), binary()}
          | {:incomplete, binary()}
          | {:error, term()}
  def decode_prefix(binary, opts \\ []) when is_binary(binary) and is_list(opts) do
    case binary do
      <<first, rest::binary>> -> decode_first(first, rest, binary, opts)
      <<>> -> {:incomplete, binary}
    end
  end

  defp decode_first(first, rest, original, opts) do
    identifier = first >>> 4 &&& 0x07

    with {:ok, epoch} <- decode_epoch(identifier) do
      if (first &&& 0x80) == 0,
        do: configuration(first, nil, epoch, rest, <<first>>, opts),
        else: decode_extension(first, rest, original, epoch, opts)
    end
  end

  defp decode_extension(first, <<second, rest::binary>>, _original, epoch, opts) do
    if (second &&& 0x80) == 0,
      do: configuration(first, second, epoch, rest, <<first, second>>, opts),
      else: {:error, :unsupported_cuc_preamble_extension}
  end

  defp decode_extension(_first, <<>>, original, _epoch, _opts), do: {:incomplete, original}

  defp configuration(first, second, epoch, rest, encoded, opts) do
    coarse_base = (first >>> 2 &&& 0x03) + 1
    fine_base = first &&& 0x03
    coarse_extension = if(is_nil(second), do: 0, else: second >>> 5 &&& 0x03)
    fine_extension = if(is_nil(second), do: 0, else: second >>> 2 &&& 0x07)
    mission_bits = if(is_nil(second), do: 0, else: second &&& 0x03)

    attrs = [
      epoch: epoch,
      coarse_octets: coarse_base + coarse_extension,
      fine_octets: fine_base + fine_extension,
      basic_unit: Keyword.get(opts, :basic_unit, {1, 1}),
      mission_bits: mission_bits
    ]

    with {:ok, configuration} <- Configuration.new(attrs) do
      {:ok, configuration, rest, encoded}
    end
  end

  defp decode_epoch(1), do: {:ok, :ccsds}
  defp decode_epoch(2), do: {:ok, :agency}
  defp decode_epoch(value), do: {:error, {:invalid_cuc_time_code_identification, value}}
end
