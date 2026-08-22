defmodule CCSDS.Time.Math do
  @moduledoc """
  Exact fractional arithmetic used by CCSDS time-code values.

  Fractions are normalized `{numerator, denominator}` tuples with a positive
  denominator. Keeping the representation exact prevents floating-point drift
  when CUC and CDS values are correlated with application time systems.
  """

  @type fraction :: {integer(), pos_integer()}
  @type rounding :: :floor | :ceiling | :nearest | :toward_zero

  @doc "Reduces an integer fraction to canonical form."
  @spec reduce(integer(), pos_integer()) :: fraction()
  def reduce(numerator, denominator)
      when is_integer(numerator) and is_integer(denominator) and denominator > 0 do
    divisor = Integer.gcd(abs(numerator), denominator)
    {div(numerator, divisor), div(denominator, divisor)}
  end

  @doc "Adds two exact fractions."
  @spec add(fraction(), fraction()) :: fraction()
  def add({left_numerator, left_denominator}, {right_numerator, right_denominator}) do
    reduce(
      left_numerator * right_denominator + right_numerator * left_denominator,
      left_denominator * right_denominator
    )
  end

  @doc "Subtracts the right exact fraction from the left."
  @spec subtract(fraction(), fraction()) :: fraction()
  def subtract(left, {numerator, denominator}), do: add(left, {-numerator, denominator})

  @doc "Multiplies a fraction by an integer numerator and positive denominator."
  @spec multiply(fraction(), integer(), pos_integer()) :: fraction()
  def multiply({numerator, denominator}, multiplier_numerator, multiplier_denominator \\ 1)
      when is_integer(multiplier_numerator) and is_integer(multiplier_denominator) and
             multiplier_denominator > 0 do
    reduce(numerator * multiplier_numerator, denominator * multiplier_denominator)
  end

  @doc "Rounds an exact fraction according to the requested mode."
  @spec round(fraction(), rounding()) :: integer()
  def round({numerator, denominator}, mode)
      when is_integer(numerator) and is_integer(denominator) and denominator > 0 and
             mode in [:floor, :ceiling, :nearest, :toward_zero] do
    sign = if(numerator < 0, do: -1, else: 1)
    absolute = abs(numerator)
    quotient = div(absolute, denominator)
    remainder = rem(absolute, denominator)

    sign * rounded_magnitude(mode, sign, quotient, remainder, denominator)
  end

  @doc "Returns the exact error between a rounded integer and its source fraction."
  @spec quantization_error(fraction(), integer()) :: fraction()
  def quantization_error({numerator, denominator}, rounded) do
    reduce(rounded * denominator - numerator, denominator)
  end

  defp rounded_magnitude(:toward_zero, _sign, quotient, _remainder, _denominator),
    do: quotient

  defp rounded_magnitude(:floor, -1, quotient, remainder, _denominator)
       when remainder > 0,
       do: quotient + 1

  defp rounded_magnitude(:floor, _sign, quotient, _remainder, _denominator), do: quotient

  defp rounded_magnitude(:ceiling, 1, quotient, remainder, _denominator)
       when remainder > 0,
       do: quotient + 1

  defp rounded_magnitude(:ceiling, _sign, quotient, _remainder, _denominator), do: quotient

  defp rounded_magnitude(:nearest, _sign, quotient, remainder, denominator)
       when remainder * 2 >= denominator,
       do: quotient + 1

  defp rounded_magnitude(:nearest, _sign, quotient, _remainder, _denominator), do: quotient
end
