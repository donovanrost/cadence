defmodule Cadence.Telemetry.Calibration do
  @moduledoc """
  A field's engineering value from its raw value (DECISIONS #92 (c)): the calibration a catalog
  declares and the mission-model telemetry plan carries (contract 3). Applied once, at decom, so
  monitoring, verifiers, derived algorithms, storage and plots all read the same calibrated value.

  - A polynomial calibrator: `c0 + c1·raw + c2·raw² + …` (coefficients lowest order first).
  - Enumerations (a state table on the parameter's type): the matching state's label.
  - Neither (every contract-2 plan): the raw value.

  A raw value that can't be calibrated (not a number, or a result that isn't finite) keeps the
  raw value with quality `:bad`, so nothing evaluates it as engineering units. A raw value with no
  defined state keeps the raw value with quality `:suspect` (still readable as a state number).
  """

  alias Cadence.Telemetry.FieldDefinition

  @type outcome :: %{
          engineering_value: term(),
          quality_state: :good | :suspect | :bad,
          calibration: nil | %{required(String.t()) => term()}
        }

  @doc "The engineering value, its quality and what calibrated it (for provenance; nil if none)."
  @spec apply(FieldDefinition.t(), term()) :: outcome()
  def apply(%FieldDefinition{calibrator: %{type: :polynomial, coefficients: coefficients}}, raw) do
    polynomial(coefficients, raw)
  end

  def apply(%FieldDefinition{enumerations: [_ | _] = enumerations}, raw) do
    enumeration(enumerations, raw)
  end

  def apply(%FieldDefinition{}, raw),
    do: %{engineering_value: raw, quality_state: :good, calibration: nil}

  @doc "`c0 + c1·x + c2·x² + …` by Horner's rule, or `:error` when it isn't a finite number."
  @spec polynomial_value([number()], number()) :: {:ok, float() | integer()} | :error
  def polynomial_value(coefficients, x) when is_list(coefficients) and is_number(x) do
    coefficients
    |> Enum.reverse()
    |> Enum.reduce(0, fn coefficient, acc -> acc * x + coefficient end)
    |> finite()
  rescue
    ArithmeticError -> :error
  end

  defp polynomial(coefficients, raw) when is_number(raw) do
    case polynomial_value(coefficients, raw) do
      {:ok, value} ->
        %{
          engineering_value: value,
          quality_state: :good,
          calibration: %{"kind" => "polynomial", "coefficients" => coefficients}
        }

      :error ->
        uncalibrated(raw, :bad, "polynomial_not_finite")
    end
  end

  defp polynomial(_coefficients, raw), do: uncalibrated(raw, :bad, "raw_not_numeric")

  defp enumeration(enumerations, raw) when is_integer(raw) do
    case Enum.find(enumerations, &(&1.value == raw)) do
      %{label: label} ->
        %{
          engineering_value: label,
          quality_state: :good,
          calibration: %{"kind" => "enumeration"}
        }

      nil ->
        uncalibrated(raw, :suspect, "state_not_defined")
    end
  end

  defp enumeration(_enumerations, raw), do: uncalibrated(raw, :bad, "raw_not_integer")

  defp uncalibrated(raw, quality, reason),
    do: %{
      engineering_value: raw,
      quality_state: quality,
      calibration: %{"kind" => "uncalibrated", "reason" => reason}
    }

  # Floats can't hold NaN or infinity in the BEAM (arithmetic raises instead), so a finite check is
  # a magnitude guard against results no store or plot can carry.
  @max_finite 1.0e300
  defp finite(value) when is_integer(value), do: {:ok, value}
  defp finite(value) when is_float(value) and abs(value) < @max_finite, do: {:ok, value}
  defp finite(_value), do: :error
end
