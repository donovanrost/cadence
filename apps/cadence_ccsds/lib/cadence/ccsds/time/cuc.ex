defmodule Cadence.CCSDS.Time.CUC do
  @moduledoc """
  Exact value representation for CCSDS 301.0-B-4 CUC time.

  `coarse_time` counts complete basic units. `fine_time` is the unsigned
  numerator of a binary fraction whose denominator is determined by the
  configured number of fine octets.
  """

  import Bitwise

  alias Cadence.CCSDS.Time.CUC.Configuration
  alias Cadence.CCSDS.Time.Math

  @type t :: %__MODULE__{
          coarse_time: non_neg_integer(),
          fine_time: non_neg_integer(),
          configuration: Configuration.t()
        }

  defstruct coarse_time: 0,
            fine_time: 0,
            configuration: nil

  @spec new(map() | keyword()) :: {:ok, t()} | {:error, term()}
  def new(attrs) when is_map(attrs) or is_list(attrs) do
    attrs = Map.new(attrs)
    known = Map.keys(Map.from_struct(%__MODULE__{}))

    with [] <- Map.keys(attrs) -- known,
         value = struct(__MODULE__, attrs),
         :ok <- validate(value) do
      {:ok, value}
    else
      [_unknown | _rest] -> {:error, :unknown_cuc_attribute}
      {:error, _reason} = error -> error
    end
  end

  @spec new!(map() | keyword()) :: t()
  def new!(attrs) do
    case new(attrs) do
      {:ok, value} -> value
      {:error, reason} -> raise ArgumentError, "invalid CUC value: #{inspect(reason)}"
    end
  end

  @spec validate(t()) :: :ok | {:error, term()}
  def validate(%__MODULE__{configuration: %Configuration{} = configuration} = value) do
    with :ok <- Configuration.validate(configuration),
         :ok <- validate_counter(value.coarse_time, configuration.coarse_octets, :coarse_time) do
      validate_counter(value.fine_time, configuration.fine_octets, :fine_time)
    end
  end

  def validate(%__MODULE__{configuration: value}),
    do: {:error, {:invalid_field, :configuration, value}}

  def validate(value), do: {:error, {:invalid_cuc, value}}

  @doc "Returns elapsed basic time as an exact fraction of one SI second."
  @spec elapsed_fraction(t()) :: Math.fraction()
  def elapsed_fraction(%__MODULE__{} = value) do
    fine_denominator = 1 <<< (value.configuration.fine_octets * 8)
    ticks = value.coarse_time * fine_denominator + value.fine_time
    {unit_numerator, unit_denominator} = value.configuration.basic_unit
    Math.reduce(ticks * unit_numerator, fine_denominator * unit_denominator)
  end

  @doc "Quantizes an exact elapsed-second fraction into a configured CUC value."
  @spec from_elapsed_fraction(Math.fraction(), Configuration.t(), Math.rounding()) ::
          {:ok, t(), map()} | {:error, term()}
  def from_elapsed_fraction(
        {numerator, denominator} = elapsed,
        %Configuration{} = configuration,
        rounding \\ :nearest
      )
      when is_integer(numerator) and is_integer(denominator) and denominator > 0 do
    with :ok <- Configuration.validate(configuration),
         true <- numerator >= 0,
         {unit_numerator, unit_denominator} = configuration.basic_unit,
         fine_denominator = 1 <<< (configuration.fine_octets * 8),
         exact_ticks =
           Math.reduce(
             numerator * unit_denominator * fine_denominator,
             denominator * unit_numerator
           ),
         {:ok, ticks} <- round_fraction(exact_ticks, rounding),
         coarse_time = div(ticks, fine_denominator),
         fine_time = rem(ticks, fine_denominator),
         {:ok, value} <-
           new(
             coarse_time: coarse_time,
             fine_time: fine_time,
             configuration: configuration
           ) do
      quantized = elapsed_fraction(value)

      {:ok, value,
       %{
         exact_seconds: Math.reduce(numerator, denominator),
         quantized_seconds: quantized,
         error_seconds: Math.subtract(quantized, elapsed),
         rounding: rounding
       }}
    else
      false -> {:error, :negative_cuc_elapsed_time}
      {:error, _reason} = error -> error
    end
  end

  @spec compare(t(), t()) :: :lt | :eq | :gt | {:error, :incompatible_cuc_units}
  def compare(%__MODULE__{} = left, %__MODULE__{} = right) do
    if compatible?(left, right) do
      {left_numerator, left_denominator} = elapsed_fraction(left)
      {right_numerator, right_denominator} = elapsed_fraction(right)
      comparison = left_numerator * right_denominator - right_numerator * left_denominator

      cond do
        comparison < 0 -> :lt
        comparison > 0 -> :gt
        true -> :eq
      end
    else
      {:error, :incompatible_cuc_units}
    end
  end

  @spec compatible?(t(), t()) :: boolean()
  def compatible?(%__MODULE__{} = left, %__MODULE__{} = right) do
    left.configuration.epoch == right.configuration.epoch and
      left.configuration.basic_unit == right.configuration.basic_unit
  end

  defp round_fraction(fraction, rounding) do
    if rounding in [:floor, :ceiling, :nearest, :toward_zero],
      do: {:ok, Math.round(fraction, rounding)},
      else: {:error, {:invalid_rounding, rounding}}
  end

  defp validate_counter(0, 0, _field), do: :ok

  defp validate_counter(value, octets, _field)
       when is_integer(value) and value >= 0 and octets > 0 and value < 1 <<< (octets * 8),
       do: :ok

  defp validate_counter(value, octets, field),
    do: {:error, {:invalid_cuc_counter, field, value, octets}}
end
