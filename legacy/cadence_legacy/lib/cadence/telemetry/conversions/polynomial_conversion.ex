defmodule Cadence.Telemetry.Conversions.PolynomialConversion do
  @moduledoc """
  Polynomial conversion: y = c0 + c1*x + c2*x^2 + c3*x^3 + ...

  Common for sensor calibrations where raw ADC counts or digital values
  need to be converted to physical units.

  ## Examples

      # Linear conversion: Celsius = -50 + 0.1 * ADC_counts
      %PolynomialConversion{
        coefficients: [-50.0, 0.1]
      }

      # Quadratic: Voltage = 0.0 + 0.001*x + 0.000001*x^2
      %PolynomialConversion{
        coefficients: [0.0, 0.001, 0.000001]
      }

  ## Coefficient Ordering

  Coefficients are ordered from lowest to highest degree:
  - coefficients[0] = c0 (constant term)
  - coefficients[1] = c1 (linear term)
  - coefficients[2] = c2 (quadratic term)
  - etc.
  """

  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  schema "polynomial_conversions" do
    # Stored as JSON array: [c0, c1, c2, ...]
    field :coefficients, {:array, :float}

    belongs_to :conversion, Cadence.Telemetry.Conversions.Conversion

    timestamps()
  end

  @doc """
  Creates a changeset for a polynomial conversion.
  """
  def changeset(polynomial_conversion, attrs) do
    polynomial_conversion
    |> cast(attrs, [:conversion_id, :coefficients])
    |> validate_required([:conversion_id, :coefficients])
    |> validate_coefficients()
    |> unique_constraint(:conversion_id)
  end

  defp validate_coefficients(changeset) do
    case get_field(changeset, :coefficients) do
      nil ->
        changeset

      coefficients when is_list(coefficients) ->
        validate_coefficients_list(changeset, coefficients)

      _ ->
        add_error(changeset, :coefficients, "must be a list of numbers")
    end
  end

  defp validate_coefficients_list(changeset, coefficients) do
    cond do
      Enum.empty?(coefficients) ->
        add_error(changeset, :coefficients, "must have at least one coefficient")

      Enum.all?(coefficients, &is_number/1) ->
        changeset

      true ->
        add_error(changeset, :coefficients, "all coefficients must be numbers")
    end
  end
end
