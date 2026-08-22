defmodule CCSDS.SDLP.AOS.FrameHeaderErrorControl do
  @moduledoc """
  AOS shortened Reed-Solomon Frame Header Error Control codec.

  CCSDS 732.0-B-5 uses a systematic RS(15,11) code over GF(2^4), shortened by
  five leading zero symbols, to protect the first 16 and final 8 bits of the
  six-octet AOS primary header. The transmitted RS(10,6) word corrects up to
  two four-bit symbols. The 24-bit VC frame count is intentionally outside the
  protected word.
  """

  import Bitwise

  @generator [1, 0x8, 0x2, 0x8, 1]
  @primitive_polynomial 0x13
  @alpha 0x2
  @first_root 6
  @root_count 4
  @virtual_fill_symbols 5
  @data_symbols 6
  @parity_symbols 4
  @transmitted_symbols @data_symbols + @parity_symbols

  @type decoded :: %{
          protected_header: 0..0xFFFF,
          signaling: 0..0xFF,
          error_control: 0..0xFFFF,
          status: :clean | :corrected,
          corrected_symbols: [map()]
        }

  @spec encode(0..0xFFFF, 0..0xFF) :: {:ok, 0..0xFFFF} | {:error, term()}
  def encode(protected_header, signaling)
      when is_integer(protected_header) and protected_header in 0..0xFFFF and
             is_integer(signaling) and signaling in 0..0xFF do
    parity =
      protected_header
      |> data_symbols(signaling)
      |> parity_symbols()
      |> symbols_to_integer()

    {:ok, parity}
  end

  def encode(protected_header, signaling),
    do: {:error, {:invalid_aos_header_error_control_input, protected_header, signaling}}

  @spec decode(0..0xFFFF, 0..0xFF, 0..0xFFFF) :: {:ok, decoded()} | {:error, term()}
  def decode(protected_header, signaling, error_control)
      when is_integer(protected_header) and protected_header in 0..0xFFFF and
             is_integer(signaling) and signaling in 0..0xFF and
             is_integer(error_control) and error_control in 0..0xFFFF do
    transmitted =
      data_symbols(protected_header, signaling) ++ integer_to_symbols(error_control, 4)

    syndrome = syndrome(transmitted)

    if zero_syndrome?(syndrome) do
      {:ok, decoded(transmitted, :clean, [])}
    else
      correct(transmitted, syndrome)
    end
  end

  def decode(protected_header, signaling, error_control),
    do:
      {:error,
       {:invalid_aos_header_error_control_input, protected_header, signaling, error_control}}

  defp correct(transmitted, syndrome) do
    contributions = error_contributions()

    correction =
      find_single_correction(contributions, syndrome) ||
        find_double_correction(contributions, syndrome)

    case correction do
      nil ->
        {:error, {:uncorrectable_aos_frame_header, syndrome}}

      errors ->
        {corrected, evidence} = apply_corrections(transmitted, errors)

        if zero_syndrome?(syndrome(corrected)) do
          {:ok, decoded(corrected, :corrected, evidence)}
        else
          {:error, {:uncorrectable_aos_frame_header, syndrome}}
        end
    end
  end

  defp decoded(symbols, status, corrected_symbols) do
    {data, parity} = Enum.split(symbols, @data_symbols)
    <<protected_header::16, signaling::8>> = symbols_to_binary(data)

    %{
      protected_header: protected_header,
      signaling: signaling,
      error_control: symbols_to_integer(parity),
      status: status,
      corrected_symbols: corrected_symbols
    }
  end

  defp parity_symbols(data) do
    codeword = List.duplicate(0, @virtual_fill_symbols) ++ data ++ List.duplicate(0, 4)

    divided = Enum.reduce(0..10, codeword, &eliminate_leading_symbol/2)

    Enum.take(divided, -@parity_symbols)
  end

  defp eliminate_leading_symbol(index, working) do
    eliminate_factor(working, index, Enum.at(working, index))
  end

  defp eliminate_factor(working, _index, 0), do: working

  defp eliminate_factor(working, index, factor) do
    Enum.with_index(@generator)
    |> Enum.reduce(working, fn {coefficient, offset}, acc ->
      List.update_at(acc, index + offset, &bxor(&1, gf_multiply(factor, coefficient)))
    end)
  end

  defp syndrome(transmitted) do
    full_codeword = List.duplicate(0, @virtual_fill_symbols) ++ transmitted

    for root <- @first_root..(@first_root + @root_count - 1) do
      x = gf_power(@alpha, root)
      Enum.reduce(full_codeword, 0, &bxor(gf_multiply(&2, x), &1))
    end
  end

  defp error_contributions do
    for position <- 0..(@transmitted_symbols - 1), delta <- 1..15 do
      symbols = List.duplicate(0, @transmitted_symbols) |> List.replace_at(position, delta)
      %{position: position, delta: delta, syndrome: syndrome(symbols)}
    end
  end

  defp find_single_correction(contributions, syndrome) do
    case Enum.find(contributions, &(&1.syndrome == syndrome)) do
      nil -> nil
      error -> [error]
    end
  end

  defp find_double_correction(contributions, syndrome) do
    Enum.reduce_while(contributions, nil, fn first, _acc ->
      second =
        Enum.find(contributions, fn second ->
          second.position > first.position and
            xor_syndromes(first.syndrome, second.syndrome) == syndrome
        end)

      if second, do: {:halt, [first, second]}, else: {:cont, nil}
    end)
  end

  defp apply_corrections(symbols, errors) do
    Enum.reduce(errors, {symbols, []}, fn error, {current, evidence} ->
      observed = Enum.at(current, error.position)
      corrected = bxor(observed, error.delta)

      item = %{
        symbol_index: error.position,
        observed: observed,
        corrected: corrected
      }

      {List.replace_at(current, error.position, corrected), [item | evidence]}
    end)
    |> then(fn {corrected, evidence} -> {corrected, Enum.reverse(evidence)} end)
  end

  defp data_symbols(protected_header, signaling) do
    <<protected_header::16, signaling::8>>
    |> :binary.bin_to_list()
    |> Enum.flat_map(&[&1 >>> 4, &1 &&& 0x0F])
  end

  defp integer_to_symbols(value, count) do
    for index <- (count - 1)..0//-1, do: value >>> (index * 4) &&& 0x0F
  end

  defp symbols_to_integer(symbols) do
    Enum.reduce(symbols, 0, &(&2 <<< 4 ||| &1))
  end

  defp symbols_to_binary(symbols) do
    symbols
    |> Enum.chunk_every(2)
    |> Enum.map(fn [high, low] -> high <<< 4 ||| low end)
    |> :binary.list_to_bin()
  end

  defp xor_syndromes(first, second), do: Enum.zip_with(first, second, &bxor/2)
  defp zero_syndrome?(syndrome), do: Enum.all?(syndrome, &(&1 == 0))

  defp gf_power(_value, 0), do: 1

  defp gf_power(value, exponent) do
    Enum.reduce(1..exponent, 1, fn _index, acc -> gf_multiply(acc, value) end)
  end

  defp gf_multiply(left, right), do: gf_multiply(left, right, 0)
  defp gf_multiply(_left, 0, acc), do: acc &&& 0x0F

  defp gf_multiply(left, right, acc) do
    acc = if((right &&& 1) == 1, do: bxor(acc, left), else: acc)
    shifted = left <<< 1

    reduced =
      if((shifted &&& 0x10) == 0x10, do: bxor(shifted, @primitive_polynomial), else: shifted)

    gf_multiply(reduced &&& 0x0F, right >>> 1, acc)
  end
end
