defmodule CCSDS.SDLP.TM.SecondaryHeader do
  @moduledoc """
  Value codec for the optional TM Transfer Frame Secondary Header.

  CCSDS 132.0-B-3 defines a one-octet identification field followed by one
  through 63 octets of mission-defined data. The only standardized wire
  version is binary `00`; the six-bit length field contains the total header
  length minus one.
  """

  @type t :: %__MODULE__{version_number: 0, data: binary()}

  defstruct version_number: 0, data: <<>>

  @minimum_data_octets 1
  @maximum_data_octets 63

  @spec new(binary()) :: {:ok, t()} | {:error, term()}
  def new(data) when is_binary(data) do
    case byte_size(data) do
      size when size in @minimum_data_octets..@maximum_data_octets ->
        {:ok, %__MODULE__{data: data}}

      size ->
        {:error, {:invalid_secondary_header_data_length, size}}
    end
  end

  def new(value), do: {:error, {:invalid_secondary_header_data, value}}

  @spec encoded_length(t()) :: 2..64
  def encoded_length(%__MODULE__{data: data}), do: byte_size(data) + 1

  @spec encode(t()) :: {:ok, binary()} | {:error, term()}
  def encode(%__MODULE__{version_number: 0, data: data} = header) do
    with {:ok, _validated} <- new(data) do
      total_length = encoded_length(header)
      {:ok, <<0::2, total_length - 1::6, data::binary>>}
    end
  end

  def encode(%__MODULE__{version_number: version_number}),
    do: {:error, {:unsupported_secondary_header_version, version_number}}

  def encode(value), do: {:error, {:invalid_secondary_header, value}}

  @spec decode(binary()) :: {:ok, t(), binary()} | {:error, term()}
  def decode(<<version_number::2, encoded_length_minus_one::6, rest::binary>>) do
    total_length = encoded_length_minus_one + 1
    data_length = total_length - 1

    cond do
      version_number != 0 ->
        {:error, {:unsupported_secondary_header_version, version_number}}

      data_length < @minimum_data_octets ->
        {:error, {:invalid_secondary_header_length, total_length}}

      byte_size(rest) < data_length ->
        {:error, {:incomplete_secondary_header, total_length, byte_size(rest) + 1}}

      true ->
        <<data::binary-size(^data_length), remaining::binary>> = rest
        {:ok, %__MODULE__{version_number: version_number, data: data}, remaining}
    end
  end

  def decode(binary) when is_binary(binary),
    do: {:error, {:incomplete_secondary_header, 2, byte_size(binary)}}

  def decode(value), do: {:error, {:invalid_secondary_header, value}}

  @spec decode_exact(binary()) :: {:ok, t()} | {:error, term()}
  def decode_exact(binary) when is_binary(binary) do
    case decode(binary) do
      {:ok, header, <<>>} -> {:ok, header}
      {:ok, _header, rest} -> {:error, {:secondary_header_trailing_octets, byte_size(rest)}}
      {:error, _reason} = error -> error
    end
  end
end
