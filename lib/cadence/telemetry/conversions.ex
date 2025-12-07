defmodule Cadence.Telemetry.Conversions do
  @moduledoc """
  Telemetry value conversions from RAW to CONVERTED values.

  Supports multiple conversion types:
  - **Polynomial** - y = c0 + c1*x + c2*x^2 + c3*x^3 + ...
  - **State** - Maps numeric values to state strings (e.g., 0 => "OFF", 1 => "ON")
  - **Segmented Polynomial** - Different polynomials for different ranges
  - **Linear** - Simple y = mx + b (special case of polynomial)

  ## Examples

      # Polynomial conversion (ADC to voltage)
      config = %{coefficients: [0.0, 0.00488]} # V = 0 + 0.00488 * ADC
      {:ok, 12.2} = Conversions.convert(2500, :polynomial, config)

      # State conversion
      config = %{states: %{0 => "OFF", 1 => "ON", 2 => "ERROR"}}
      {:ok, "ON"} = Conversions.convert(1, :state, config)
  """

  @type conversion_type :: :polynomial | :state | :segmented_polynomial | :linear | :none
  @type conversion_config :: map()

  @doc """
  Converts a raw value to a converted value based on the conversion type.

  Returns `{:ok, converted_value}` or `{:error, reason}`.
  """
  @spec convert(any(), conversion_type(), conversion_config()) ::
          {:ok, any()} | {:error, term()}
  def convert(value, conversion_type, config \\ %{})

  def convert(value, :none, _config), do: {:ok, value}
  def convert(nil, _type, _config), do: {:ok, nil}

  def convert(value, :polynomial, config) when is_number(value) do
    coefficients = Map.get(config, :coefficients, [])

    result =
      coefficients
      |> Enum.with_index()
      |> Enum.reduce(0.0, fn {coef, power}, acc ->
        acc + coef * :math.pow(value, power)
      end)

    {:ok, result}
  end

  def convert(value, :linear, config) when is_number(value) do
    m = Map.get(config, :slope, 1.0)
    b = Map.get(config, :intercept, 0.0)
    {:ok, m * value + b}
  end

  def convert(value, :state, config) do
    states = Map.get(config, :states, %{})

    # Try direct lookup first
    case Map.get(states, value) do
      nil ->
        # Try converting value to string key
        case Map.get(states, to_string(value)) do
          # Return raw value if no mapping
          nil -> {:ok, value}
          state_string -> {:ok, state_string}
        end

      state_string ->
        {:ok, state_string}
    end
  end

  def convert(value, :segmented_polynomial, config) when is_number(value) do
    segments = Map.get(config, :segments, [])

    # Find the segment that contains this value
    segment =
      Enum.find(segments, fn seg ->
        min = Map.get(seg, :min, :neg_infinity)
        max = Map.get(seg, :max, :infinity)

        in_range?(value, min, max)
      end)

    case segment do
      nil ->
        {:error, :no_segment_found}

      seg ->
        coefficients = Map.get(seg, :coefficients, [])
        convert(value, :polynomial, %{coefficients: coefficients})
    end
  end

  def convert(_value, type, _config) do
    {:error, {:unsupported_conversion_type, type}}
  end

  @doc """
  Applies multiple conversions in sequence.

  Useful for complex conversions like RAW -> CALIBRATED -> ENGINEERING units.
  """
  @spec convert_chain(any(), [{conversion_type(), conversion_config()}]) ::
          {:ok, any()} | {:error, term()}
  def convert_chain(value, conversions) do
    Enum.reduce_while(conversions, {:ok, value}, fn {type, config}, {:ok, current_value} ->
      case convert(current_value, type, config) do
        {:ok, new_value} -> {:cont, {:ok, new_value}}
        error -> {:halt, error}
      end
    end)
  end

  @doc """
  Formats a converted value with units for display.

  ## Examples

      format_value(12.2, "V", "%.2f") #=> "12.20 V"
      format_value(25.5, "°C", "%.1f") #=> "25.5 °C"
  """
  @spec format_value(any(), String.t() | nil, String.t() | nil) :: String.t()
  def format_value(value, units \\ nil, format_string \\ nil)

  def format_value(nil, _units, _format_string), do: "N/A"

  def format_value(value, units, format_string) when is_number(value) do
    formatted =
      if format_string do
        :io_lib.format(format_string, [value]) |> to_string()
      else
        to_string(value)
      end

    if units do
      "#{formatted} #{units}"
    else
      formatted
    end
  end

  def format_value(value, units, _format_string) do
    str = to_string(value)

    if units do
      "#{str} #{units}"
    else
      str
    end
  end

  ## Private Helpers

  defp in_range?(value, :neg_infinity, max), do: value <= max
  defp in_range?(value, min, :infinity), do: value >= min
  defp in_range?(value, min, max), do: value >= min and value <= max

  @doc """
  Validates a conversion configuration.
  """
  @spec validate_config(conversion_type(), conversion_config()) :: :ok | {:error, term()}
  def validate_config(:polynomial, config) do
    if Map.has_key?(config, :coefficients) and is_list(config.coefficients) do
      :ok
    else
      {:error, :missing_coefficients}
    end
  end

  def validate_config(:linear, config) do
    if Map.has_key?(config, :slope) and Map.has_key?(config, :intercept) do
      :ok
    else
      {:error, :missing_linear_parameters}
    end
  end

  def validate_config(:state, config) do
    if Map.has_key?(config, :states) and is_map(config.states) do
      :ok
    else
      {:error, :missing_states}
    end
  end

  def validate_config(:segmented_polynomial, config) do
    if Map.has_key?(config, :segments) and is_list(config.segments) do
      :ok
    else
      {:error, :missing_segments}
    end
  end

  def validate_config(:none, _config), do: :ok

  def validate_config(type, _config), do: {:error, {:unknown_type, type}}

  ## Database-Backed Conversions (Phase 4)

  import Ecto.Query
  require Logger

  alias Cadence.Repo

  alias Cadence.Telemetry.Conversions.{
    Conversion,
    PolynomialConversion,
    PolynomialConverter,
    StateTableConversion,
    StateTableConverter
  }

  @doc """
  Applies a database-backed conversion to a raw value.

  Accepts a conversion schema loaded from the database and applies it.
  Returns {:ok, converted_value} or {:error, reason}.
  """
  def apply_db_conversion(raw_value, nil), do: {:ok, raw_value}

  def apply_db_conversion(raw_value, %Conversion{conversion_type: "polynomial"} = conversion) do
    conversion = Repo.preload(conversion, :polynomial_conversion)
    config = %{coefficients: conversion.polynomial_conversion.coefficients}
    PolynomialConverter.convert(raw_value, config)
  end

  def apply_db_conversion(raw_value, %Conversion{conversion_type: "state_table"} = conversion) do
    conversion = Repo.preload(conversion, :state_table_conversion)

    config = %{
      states: conversion.state_table_conversion.states,
      default_state: conversion.state_table_conversion.default_state
    }

    StateTableConverter.convert(raw_value, config)
  end

  def apply_db_conversion(raw_value, %Conversion{conversion_type: "generic"}) do
    # TODO: Implement generic converter support
    {:ok, raw_value}
  end

  def apply_db_conversion(raw_value, _), do: {:ok, raw_value}

  @doc """
  Creates a polynomial conversion in the database.
  """
  def create_polynomial_conversion(attrs) do
    Repo.transaction(fn ->
      # Create base conversion
      conversion =
        %Conversion{}
        |> Conversion.changeset(Map.put(attrs, :conversion_type, "polynomial"))
        |> Repo.insert!()

      # Create polynomial-specific data
      %PolynomialConversion{}
      |> PolynomialConversion.changeset(%{
        conversion_id: conversion.id,
        coefficients: attrs.coefficients
      })
      |> Repo.insert!()

      Repo.preload(conversion, :polynomial_conversion)
    end)
  end

  @doc """
  Creates a state table conversion in the database.
  """
  def create_state_table_conversion(attrs) do
    Repo.transaction(fn ->
      # Create base conversion
      conversion =
        %Conversion{}
        |> Conversion.changeset(Map.put(attrs, :conversion_type, "state_table"))
        |> Repo.insert!()

      # Create state table-specific data
      %StateTableConversion{}
      |> StateTableConversion.changeset(%{
        conversion_id: conversion.id,
        states: attrs.states,
        default_state: Map.get(attrs, :default_state)
      })
      |> Repo.insert!()

      Repo.preload(conversion, :state_table_conversion)
    end)
  end

  @doc """
  Loads all conversions for a mission into a map for fast lookup.
  """
  def load_conversions_for_mission(mission_id) do
    Conversion
    |> where([c], c.mission_id == ^mission_id)
    |> preload([:polynomial_conversion, :state_table_conversion, :generic_conversion])
    |> Repo.all()
    |> Enum.map(fn conversion -> {conversion.id, conversion} end)
    |> Enum.into(%{})
  end
end
