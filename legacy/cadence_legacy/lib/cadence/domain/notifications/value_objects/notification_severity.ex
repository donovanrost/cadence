defmodule Cadence.Domain.Notifications.ValueObjects.NotificationSeverity do
  @moduledoc """
  Value object representing the severity level of a notification.

  ## Severity Levels

  - `:info` - Informational notification (default)
  - `:warning` - Warning that may require attention
  - `:critical` - Critical notification requiring immediate attention
  """

  @type t :: :info | :warning | :critical

  @values [:info, :warning, :critical]

  @doc """
  Returns all valid severity values.
  """
  @spec values() :: [t()]
  def values, do: @values

  @doc """
  Returns the default severity.
  """
  @spec default() :: t()
  def default, do: :info

  @doc """
  Returns true if the given value is a valid severity.
  """
  @spec valid?(term()) :: boolean()
  def valid?(value) when value in @values, do: true
  def valid?(_), do: false

  @doc """
  Validates a severity value.
  """
  @spec validate(term()) :: :ok | {:error, :invalid_severity}
  def validate(value) when value in @values, do: :ok
  def validate(_), do: {:error, :invalid_severity}

  @doc """
  Parses a string or atom into a severity.
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
  Returns the database string representation.
  """
  @spec to_string(t()) :: String.t()
  def to_string(severity) when is_atom(severity), do: Atom.to_string(severity)

  @doc """
  Returns the display name for a severity.
  """
  @spec display_name(t()) :: String.t()
  def display_name(:info), do: "Info"
  def display_name(:warning), do: "Warning"
  def display_name(:critical), do: "Critical"

  @doc """
  Returns a color for the severity (for UI).
  """
  @spec color(t()) :: String.t()
  def color(:info), do: "blue"
  def color(:warning), do: "yellow"
  def color(:critical), do: "red"

  @doc """
  Returns true if severity a is higher than severity b.
  """
  @spec higher_than?(t(), t()) :: boolean()
  def higher_than?(a, b) do
    priority(a) > priority(b)
  end

  defp priority(:info), do: 1
  defp priority(:warning), do: 2
  defp priority(:critical), do: 3
end
