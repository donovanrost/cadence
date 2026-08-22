defmodule Cadence.CCSDS.ChannelCoding.CLTU do
  @moduledoc """
  Communications Link Transmission Unit codec for CCSDS 231.0-B-4 Corrigendum 1.

  A CLTU contains one or more transfer frames as opaque octets. Frame
  delimiting and removal of alternating fill remain responsibilities of the
  data-link sublayer; callers may supply `:expected_data_octets` while decoding
  when the service boundary already knows the exact data length.
  """

  import Bitwise

  alias Cadence.CCSDS.ChannelCoding.{BCH, Configuration, LDPC, Randomizer}

  @bch_start <<0xEB, 0x90>>
  @bch_tail <<0xC5, 0xC5, 0xC5, 0xC5, 0xC5, 0xC5, 0xC5, 0x79>>
  @ldpc_start <<0x03, 0x47, 0x76, 0xC7, 0x27, 0x28, 0x95, 0xB0>>

  @ldpc_128_tail <<
    0x63,
    0xA1,
    0xED,
    0x72,
    0xC6,
    0xAC,
    0x79,
    0xE2,
    0x55,
    0x55,
    0x55,
    0x55,
    0x55,
    0x55,
    0x55,
    0x55
  >>

  @type encoded_metadata :: %{
          code: Configuration.code(),
          codeword_count: pos_integer(),
          data_octets: pos_integer(),
          fill_octets: non_neg_integer(),
          cltu_octets: pos_integer(),
          randomized?: boolean(),
          tail?: boolean()
        }

  @type decoded :: %{
          code: Configuration.code(),
          data: binary(),
          decoded_octets: binary(),
          trailing_fill: binary() | nil,
          codeword_count: pos_integer(),
          quality: map()
        }

  @spec encode(binary() | [binary()], Configuration.t()) ::
          {:ok, binary(), encoded_metadata()} | {:error, term()}
  def encode(frames, %Configuration{} = configuration) do
    with :ok <- Configuration.validate(configuration),
         {:ok, data} <- normalize_frames(frames),
         {:ok, encoded_data, fill_octets, codeword_count} <-
           encode_data(data, configuration) do
      cltu = start_sequence(configuration.code) <> encoded_data <> tail_sequence(configuration)

      with :ok <- validate_maximum_length(cltu, configuration.max_cltu_octets) do
        {:ok, cltu,
         %{
           code: configuration.code,
           codeword_count: codeword_count,
           data_octets: byte_size(data),
           fill_octets: fill_octets,
           cltu_octets: byte_size(cltu),
           randomized?: configuration.randomize?,
           tail?: tail_sequence(configuration) != <<>>
         }}
      end
    end
  end

  @spec decode(binary(), Configuration.t(), keyword()) ::
          {:ok, decoded()} | {:error, term()}
  def decode(cltu, %Configuration{} = configuration, opts \\ []) when is_binary(cltu) do
    expected_data_octets = Keyword.get(opts, :expected_data_octets)

    with :ok <- Configuration.validate(configuration),
         :ok <- validate_maximum_length(cltu, configuration.max_cltu_octets),
         {:ok, normalized_cltu, start_quality} <- normalize_start(cltu, configuration),
         {:ok, encoded_data} <- remove_envelope(normalized_cltu, configuration),
         {:ok, decoded_octets, codeword_quality} <- decode_data(encoded_data, configuration),
         {:ok, data, trailing_fill, fill_valid?} <-
           split_expected_data(decoded_octets, expected_data_octets) do
      {:ok,
       %{
         code: configuration.code,
         data: data,
         decoded_octets: decoded_octets,
         trailing_fill: trailing_fill,
         codeword_count: length(codeword_quality),
         quality: %{
           status: overall_status(codeword_quality),
           inverted?: start_quality.inverted?,
           start_errors: start_quality.errors,
           fill_valid?: fill_valid?,
           corrected_codewords: Enum.count(codeword_quality, &(&1.status == :corrected)),
           codewords: codeword_quality
         }
       }}
    end
  end

  @spec start_sequence(Configuration.code()) :: binary()
  def start_sequence(:bch), do: @bch_start
  def start_sequence(code) when code in [:ldpc_128_64, :ldpc_512_256], do: @ldpc_start

  @spec tail_sequence(Configuration.t()) :: binary()
  def tail_sequence(%Configuration{code: :bch}), do: @bch_tail
  def tail_sequence(%Configuration{code: :ldpc_128_64, ldpc_tail?: true}), do: @ldpc_128_tail
  def tail_sequence(%Configuration{}), do: <<>>

  defp encode_data(data, %Configuration{code: :bch} = configuration) do
    {padded, fill_octets} = pad(data, BCH.information_octets())
    information = if configuration.randomize?, do: Randomizer.apply(padded), else: padded

    with {:ok, encoded} <- encode_blocks(information, BCH.information_octets(), &BCH.encode/1) do
      {:ok, encoded, fill_octets, div(byte_size(information), BCH.information_octets())}
    end
  end

  defp encode_data(data, %Configuration{code: code}) do
    information_octets = LDPC.information_octets(code)
    {padded, fill_octets} = pad(data, information_octets)

    encoder = fn information ->
      with {:ok, codeword} <- LDPC.encode(information, code) do
        {:ok, Randomizer.apply(codeword)}
      end
    end

    with {:ok, encoded} <- encode_blocks(padded, information_octets, encoder) do
      {:ok, encoded, fill_octets, div(byte_size(padded), information_octets)}
    end
  end

  defp decode_data(encoded, %Configuration{code: :bch} = configuration) do
    decoder = fn codeword -> BCH.decode(codeword, configuration.bch_decoding_mode) end

    with {:ok, information, quality} <-
           decode_blocks(encoded, BCH.codeword_octets(), decoder) do
      decoded = if configuration.randomize?, do: Randomizer.apply(information), else: information
      {:ok, decoded, quality}
    end
  end

  defp decode_data(encoded, %Configuration{code: code}) do
    decoder = fn randomized_codeword ->
      randomized_codeword
      |> Randomizer.apply()
      |> LDPC.decode(code)
    end

    decode_blocks(encoded, LDPC.codeword_octets(code), decoder)
  end

  defp encode_blocks(information, block_octets, encoder) do
    information
    |> chunk_exact(block_octets)
    |> Enum.reduce_while({:ok, []}, fn block, {:ok, acc} ->
      case encoder.(block) do
        {:ok, codeword} -> {:cont, {:ok, [codeword | acc]}}
        {:error, reason} -> {:halt, {:error, reason}}
      end
    end)
    |> case do
      {:ok, codewords} -> {:ok, codewords |> Enum.reverse() |> IO.iodata_to_binary()}
      {:error, _reason} = error -> error
    end
  end

  defp decode_blocks(encoded, codeword_octets, decoder) do
    if byte_size(encoded) > 0 and rem(byte_size(encoded), codeword_octets) == 0 do
      encoded
      |> chunk_exact(codeword_octets)
      |> Enum.with_index()
      |> Enum.reduce_while({:ok, [], []}, &decode_codeword(&1, &2, decoder))
      |> case do
        {:ok, data, quality} ->
          {:ok, data |> Enum.reverse() |> IO.iodata_to_binary(), Enum.reverse(quality)}

        {:error, _reason} = error ->
          error
      end
    else
      {:error, {:invalid_encoded_data_length, byte_size(encoded), codeword_octets}}
    end
  end

  defp decode_codeword({codeword, index}, {:ok, data_acc, quality_acc}, decoder) do
    case decoder.(codeword) do
      {:ok, information, quality} ->
        evidence = Map.put(quality, :codeword_index, index)
        {:cont, {:ok, [information | data_acc], [evidence | quality_acc]}}

      {:error, reason} ->
        {:halt, {:error, {:cltu_codeword_rejected, index, reason}}}
    end
  end

  defp normalize_start(cltu, %Configuration{} = configuration) do
    start = start_sequence(configuration.code)

    if byte_size(cltu) >= byte_size(start) do
      candidate = binary_part(cltu, 0, byte_size(start))
      normal_errors = bit_errors(candidate, start)
      inverted_errors = bit_errors(candidate, invert(start))
      tolerance = start_tolerance(configuration)

      cond do
        normal_errors <= tolerance ->
          {:ok, cltu, %{inverted?: false, errors: normal_errors}}

        inverted_errors <= tolerance ->
          {:ok, invert(cltu), %{inverted?: true, errors: inverted_errors}}

        true ->
          {:error, {:start_sequence_not_found, normal_errors, inverted_errors}}
      end
    else
      {:error, :truncated_cltu_start_sequence}
    end
  end

  defp remove_envelope(cltu, %Configuration{} = configuration) do
    start_octets = byte_size(start_sequence(configuration.code))
    tail = tail_sequence(configuration)
    tail_octets = byte_size(tail)

    if byte_size(cltu) > start_octets + tail_octets do
      encoded_octets = byte_size(cltu) - start_octets - tail_octets

      <<_start::binary-size(^start_octets), encoded::binary-size(^encoded_octets),
        actual_tail::binary>> =
        cltu

      if actual_tail == tail do
        {:ok, encoded}
      else
        {:error, {:invalid_tail_sequence, actual_tail}}
      end
    else
      {:error, :truncated_cltu}
    end
  end

  defp split_expected_data(decoded, nil), do: {:ok, decoded, nil, nil}

  defp split_expected_data(decoded, expected_octets)
       when is_integer(expected_octets) and expected_octets > 0 and
              expected_octets <= byte_size(decoded) do
    <<data::binary-size(^expected_octets), fill::binary>> = decoded
    fill_valid? = fill == :binary.copy(<<0x55>>, byte_size(fill))

    if fill_valid? do
      {:ok, data, fill, true}
    else
      {:error, {:invalid_fill_data, fill}}
    end
  end

  defp split_expected_data(decoded, expected_octets),
    do: {:error, {:invalid_expected_data_octets, expected_octets, byte_size(decoded)}}

  defp normalize_frames(frame) when is_binary(frame) and byte_size(frame) > 0, do: {:ok, frame}

  defp normalize_frames(frames) when is_list(frames) and frames != [] do
    if Enum.all?(frames, &(is_binary(&1) and byte_size(&1) > 0)) do
      {:ok, IO.iodata_to_binary(frames)}
    else
      {:error, :invalid_cltu_frames}
    end
  end

  defp normalize_frames(_frames), do: {:error, :empty_cltu_frames}

  defp pad(data, information_octets) do
    fill_octets = Integer.mod(-byte_size(data), information_octets)
    {data <> :binary.copy(<<0x55>>, fill_octets), fill_octets}
  end

  defp chunk_exact(data, octets) do
    for <<chunk::binary-size(^octets) <- data>>, do: chunk
  end

  defp validate_maximum_length(_cltu, nil), do: :ok

  defp validate_maximum_length(cltu, maximum) when byte_size(cltu) <= maximum, do: :ok

  defp validate_maximum_length(cltu, maximum),
    do: {:error, {:maximum_cltu_length_exceeded, byte_size(cltu), maximum}}

  defp start_tolerance(%Configuration{code: :bch, allowed_start_errors: tolerance}),
    do: tolerance

  defp start_tolerance(%Configuration{}), do: 0

  defp overall_status(quality) do
    if Enum.any?(quality, &(&1.status == :corrected)), do: :corrected, else: :clean
  end

  defp bit_errors(left, right) do
    left
    |> :binary.bin_to_list()
    |> Enum.zip(:binary.bin_to_list(right))
    |> Enum.reduce(0, fn {left_octet, right_octet}, count ->
      count + popcount(bxor(left_octet, right_octet))
    end)
  end

  defp popcount(value), do: popcount(value, 0)
  defp popcount(0, count), do: count
  defp popcount(value, count), do: popcount(band(value, value - 1), count + 1)

  defp invert(binary) do
    for <<octet <- binary>>, into: <<>>, do: <<bxor(octet, 0xFF)>>
  end
end
