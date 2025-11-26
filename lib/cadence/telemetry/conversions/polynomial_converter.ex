defmodule Cadence.Telemetry.Conversions.PolynomialConverter do
  @moduledoc """
  Polynomial converter: y = c0 + c1*x + c2*x^2 + c3*x^3 + ...

  Evaluates a polynomial equation to convert raw values to engineering units.
  Commonly used for sensor calibrations.

  ## Examples

      # Linear: °C = -50 + 0.1 * raw
      config = %{coefficients: [-50.0, 0.1]}
      convert(1000, config)  # => {:ok, 50.0}

      # Quadratic: V = 0.0 + 0.001*x + 0.000001*x^2
      config = %{coefficients: [0.0, 0.001, 0.000001]}
      convert(1000, config)  # => {:ok, 2.0}

  ## Algorithm

  Uses Horner's method for efficient polynomial evaluation:
  - Fewer multiplications than naive approach
  - Better numerical stability
  - O(n) complexity where n = number of coefficients
  """

  @behaviour Cadence.Telemetry.Conversions.ConverterBehaviour

  @impl true
  def convert(raw_value, %{coefficients: coefficients})
      when is_number(raw_value) and is_list(coefficients) do
    if Enum.empty?(coefficients) do
      {:error, :empty_coefficients}
    else
      result = evaluate_polynomial(raw_value, coefficients)
      {:ok, result}
    end
  rescue
    ArithmeticError -> {:error, :arithmetic_error}
  end

  def convert(_raw_value, %{coefficients: _}) do
    {:error, :invalid_raw_value}
  end

  def convert(_raw_value, _config) do
    {:error, :missing_coefficients}
  end

  ## Private Functions

  # Evaluate polynomial using Horner's method
  # For [c0, c1, c2, c3], computes: c0 + x*(c1 + x*(c2 + x*c3))
  defp evaluate_polynomial(x, coefficients) do
    coefficients
    |> Enum.reverse()
    |> Enum.reduce(0.0, fn coeff, acc ->
      acc * x + coeff
    end)
  end
end
