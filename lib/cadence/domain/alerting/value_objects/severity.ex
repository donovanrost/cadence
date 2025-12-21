defmodule Cadence.Domain.Alerting.ValueObjects.Severity do
  @moduledoc """
  Value object representing alarm severity levels.

  Severity indicates the urgency and impact of an alarm condition:
  - `:info` - Informational, no immediate action required
  - `:warning` - Potential issue, should be monitored
  - `:critical` - Serious condition requiring immediate attention

  ## Usage

      iex> Severity.valid?(:warning)
      true

      iex> Severity.valid?(:unknown)
      false

      iex> Severity.compare(:critical, :warning)
      :gt

  ## Ordering

  Severities are ordered by urgency: info < warning < critical
  """

  @type t :: :info | :warning | :critical

  @values [:info, :warning, :critical]

  # Numeric values for comparison (higher = more severe)
  @severity_order %{
    info: 1,
    warning: 2,
    critical: 3
  }

  @doc """
  Returns all valid severity values.
  """
  @spec values() :: [t()]
  def values, do: @values

  @doc """
  Returns true if the given value is a valid severity.
  """
  @spec valid?(term()) :: boolean()
  def valid?(value) when value in @values, do: true
  def valid?(_), do: false

  @doc """
  Validates a severity value.

  Returns `:ok` if valid, `{:error, :invalid_severity}` otherwise.
  """
  @spec validate(term()) :: :ok | {:error, :invalid_severity}
  def validate(value) when value in @values, do: :ok
  def validate(_), do: {:error, :invalid_severity}

  @doc """
  Parses a string or atom into a severity.

  Returns `{:ok, severity}` or `{:error, :invalid_severity}`.
  """
  @spec parse(String.t() | atom()) :: {:ok, t()} | {:error, :invalid_severity}
  def parse(value) when is_atom(value) and value in @values, do: {:ok, value}

  def parse(value) when is_binary(value) do
    case String.downcase(value) do
      "info" -> {:ok, :info}
      "warning" -> {:ok, :warning}
      "critical" -> {:ok, :critical}
      _ -> {:error, :invalid_severity}
    end
  end

  def parse(_), do: {:error, :invalid_severity}

  @doc """
  Compares two severity levels.

  Returns `:lt`, `:eq`, or `:gt`.

  ## Examples

      iex> Severity.compare(:info, :warning)
      :lt

      iex> Severity.compare(:critical, :warning)
      :gt

      iex> Severity.compare(:warning, :warning)
      :eq
  """
  @spec compare(t(), t()) :: :lt | :eq | :gt
  def compare(a, b) when a in @values and b in @values do
    order_a = Map.fetch!(@severity_order, a)
    order_b = Map.fetch!(@severity_order, b)

    cond do
      order_a < order_b -> :lt
      order_a > order_b -> :gt
      true -> :eq
    end
  end

  @doc """
  Returns true if the first severity is more severe than the second.
  """
  @spec more_severe?(t(), t()) :: boolean()
  def more_severe?(a, b), do: compare(a, b) == :gt

  @doc """
  Returns true if the first severity is at least as severe as the second.
  """
  @spec at_least?(t(), t()) :: boolean()
  def at_least?(a, b), do: compare(a, b) in [:gt, :eq]

  @doc """
  Returns the maximum (most severe) of two severities.
  """
  @spec max(t(), t()) :: t()
  def max(a, b) do
    if more_severe?(a, b), do: a, else: b
  end

  @doc """
  Returns the display name for a severity level.
  """
  @spec display_name(t()) :: String.t()
  def display_name(:info), do: "Info"
  def display_name(:warning), do: "Warning"
  def display_name(:critical), do: "Critical"

  @doc """
  Returns a color associated with the severity (for UI).
  """
  @spec color(t()) :: String.t()
  def color(:info), do: "blue"
  def color(:warning), do: "yellow"
  def color(:critical), do: "red"
end
