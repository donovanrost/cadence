defmodule Cadence.Domain.Interfaces.ValueObjects.DataDirection do
  @moduledoc """
  Value object representing target-interface routing direction.

  Used to describe how data flows between targets and interfaces:

  - READ handles incoming telemetry (interface to application)
  - WRITE handles outgoing commands (application to interface)

  ## Direction Values

  - `:read` - Incoming data only
  - `:write` - Outgoing data only
  - `:read_write` - Bidirectional
  """

  @type t :: :read | :write | :read_write

  @values [:read, :write, :read_write]

  @doc """
  Returns all valid direction values.
  """
  @spec values() :: [t()]
  def values, do: @values

  @doc """
  Returns the default direction.
  """
  @spec default() :: t()
  def default, do: :read_write

  @doc """
  Returns true if the given value is a valid direction.
  """
  @spec valid?(term()) :: boolean()
  def valid?(value) when value in @values, do: true
  def valid?(_), do: false

  @doc """
  Validates a direction value.
  """
  @spec validate(term()) :: :ok | {:error, :invalid_data_direction}
  def validate(value) when value in @values, do: :ok
  def validate(_), do: {:error, :invalid_data_direction}

  @doc """
  Parses a string or atom into a direction.
  """
  @spec parse(String.t() | atom()) :: {:ok, t()} | {:error, :invalid_data_direction}
  def parse(value) when is_atom(value) and value in @values, do: {:ok, value}

  def parse(value) when is_binary(value) do
    case String.downcase(value) do
      "read" -> {:ok, :read}
      "write" -> {:ok, :write}
      "read_write" -> {:ok, :read_write}
      _ -> {:error, :invalid_data_direction}
    end
  end

  def parse(_), do: {:error, :invalid_data_direction}

  @doc """
  Returns true if this direction handles reading (incoming data).
  """
  @spec handles_read?(t()) :: boolean()
  def handles_read?(:read), do: true
  def handles_read?(:read_write), do: true
  def handles_read?(:write), do: false

  @doc """
  Returns true if this direction handles writing (outgoing data).
  """
  @spec handles_write?(t()) :: boolean()
  def handles_write?(:write), do: true
  def handles_write?(:read_write), do: true
  def handles_write?(:read), do: false

  @doc """
  Returns true if this direction handles both read and write.
  """
  @spec bidirectional?(t()) :: boolean()
  def bidirectional?(:read_write), do: true
  def bidirectional?(_), do: false

  @doc """
  Returns the display name for a direction.
  """
  @spec display_name(t()) :: String.t()
  def display_name(:read), do: "Read Only"
  def display_name(:write), do: "Write Only"
  def display_name(:read_write), do: "Read/Write"

  @doc """
  Returns an icon name for the direction (for UI).
  """
  @spec icon(t()) :: String.t()
  def icon(:read), do: "arrow-down"
  def icon(:write), do: "arrow-up"
  def icon(:read_write), do: "arrows-up-down"
end
