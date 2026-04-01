defmodule Cadence.Domain.Commanding.ValueObjects.Priority do
  @moduledoc """
  Value object representing command queue priority levels.

  Commands in the queue are processed in priority order, with lower
  numbers indicating higher priority.

  ## Priority Levels

  - `0` - Emergency: Immediate execution, bypasses normal queue
  - `1` - Critical: Highest normal priority
  - `2` - High: Important but not critical
  - `3` - Normal: Default priority for most commands
  - `4` - Low: Can wait for higher priority commands
  - `5` - Background: Lowest priority, batch operations

  ## Usage

      iex> Priority.valid?(3)
      true

      iex> Priority.compare(1, 3)
      :gt  # Priority 1 is higher (more urgent) than 3

      iex> Priority.display_name(0)
      "Emergency"
  """

  @type t :: 0..5

  @values [0, 1, 2, 3, 4, 5]

  @names %{
    0 => "Emergency",
    1 => "Critical",
    2 => "High",
    3 => "Normal",
    4 => "Low",
    5 => "Background"
  }

  @doc """
  Returns all valid priority levels.
  """
  @spec values() :: [t()]
  def values, do: @values

  @doc """
  Returns the default priority level.
  """
  @spec default() :: t()
  def default, do: 3

  @doc """
  Returns true if the given value is a valid priority.
  """
  @spec valid?(term()) :: boolean()
  def valid?(value) when value in @values, do: true
  def valid?(_), do: false

  @doc """
  Validates a priority value.

  Returns `:ok` if valid, `{:error, :invalid_priority}` otherwise.
  """
  @spec validate(term()) :: :ok | {:error, :invalid_priority}
  def validate(value) when value in @values, do: :ok
  def validate(_), do: {:error, :invalid_priority}

  @doc """
  Parses a string or integer into a priority.
  """
  @spec parse(String.t() | integer()) :: {:ok, t()} | {:error, :invalid_priority}
  def parse(value) when is_integer(value) and value in @values, do: {:ok, value}

  def parse(value) when is_binary(value) do
    case Integer.parse(value) do
      {int, ""} when int in @values -> {:ok, int}
      _ -> parse_name(value)
    end
  end

  def parse(_), do: {:error, :invalid_priority}

  defp parse_name(value) do
    case String.downcase(value) do
      "emergency" -> {:ok, 0}
      "critical" -> {:ok, 1}
      "high" -> {:ok, 2}
      "normal" -> {:ok, 3}
      "low" -> {:ok, 4}
      "background" -> {:ok, 5}
      _ -> {:error, :invalid_priority}
    end
  end

  @doc """
  Compares two priority levels.

  Returns `:gt` if the first priority is higher (more urgent),
  `:lt` if lower, `:eq` if equal.

  Note: Lower numbers = higher priority.
  """
  @spec compare(t(), t()) :: :lt | :eq | :gt
  def compare(a, b) when a in @values and b in @values do
    cond do
      # Lower number = higher priority
      a < b -> :gt
      a > b -> :lt
      true -> :eq
    end
  end

  @doc """
  Returns true if the first priority is higher (more urgent) than the second.
  """
  @spec higher?(t(), t()) :: boolean()
  def higher?(a, b), do: compare(a, b) == :gt

  @doc """
  Returns true if the priority is emergency level.
  """
  @spec emergency?(t()) :: boolean()
  def emergency?(0), do: true
  def emergency?(_), do: false

  @doc """
  Returns the display name for a priority level.
  """
  @spec display_name(t()) :: String.t()
  def display_name(priority) when is_map_key(@names, priority) do
    Map.fetch!(@names, priority)
  end

  @doc """
  Returns a color associated with the priority (for UI).
  """
  @spec color(t()) :: String.t()
  def color(0), do: "red"
  def color(1), do: "orange"
  def color(2), do: "yellow"
  def color(3), do: "blue"
  def color(4), do: "gray"
  def color(5), do: "gray"
end
