defmodule Cadence.Domain.Interfaces.ValueObjects.InterfaceStatus do
  @moduledoc """
  Value object representing interface connection status.

  **IMPORTANT**: Interface status is runtime-only state. It is not persisted
  to the database during normal operation. Status is managed by GenServer
  processes and broadcast via PubSub for UI updates.

  This value object exists for type safety and validation, not persistence.

  ## Status Values

  - `:disconnected` - Not connected, idle
  - `:connecting` - Connection attempt in progress
  - `:connected` - Successfully connected
  - `:error` - Connection failed or error occurred

  ## State Machine

  ```
  ┌──────────────┐
  │ DISCONNECTED │◄──────────────────────────────────┐
  └──────────────┘                                   │
        │                                            │
        │ connect()                          disconnect/timeout
        ▼                                            │
  ┌──────────────┐                                   │
  │  CONNECTING  │───────────────────────────────────┤
  └──────────────┘                                   │
        │                                            │
        │ success                             failure│
        ▼                                            ▼
  ┌──────────────┐    error/disconnect         ┌─────────┐
  │  CONNECTED   │────────────────────────────►│  ERROR  │
  └──────────────┘                             └─────────┘
                                                     │
                                             retry/reconnect
                                                     │
                                                     ▼
                                               (CONNECTING)
  ```
  """

  @type t :: :disconnected | :connecting | :connected | :error

  @values [:disconnected, :connecting, :connected, :error]

  @valid_transitions %{
    disconnected: [:connecting],
    connecting: [:connected, :error, :disconnected],
    connected: [:disconnected, :error],
    error: [:connecting, :disconnected]
  }

  @doc """
  Returns all valid status values.
  """
  @spec values() :: [t()]
  def values, do: @values

  @doc """
  Returns the initial status for a new interface.
  """
  @spec initial() :: t()
  def initial, do: :disconnected

  @doc """
  Returns true if the given value is a valid status.
  """
  @spec valid?(term()) :: boolean()
  def valid?(value) when value in @values, do: true
  def valid?(_), do: false

  @doc """
  Validates a status value.
  """
  @spec validate(term()) :: :ok | {:error, :invalid_status}
  def validate(value) when value in @values, do: :ok
  def validate(_), do: {:error, :invalid_status}

  @doc """
  Parses a string or atom into a status.
  """
  @spec parse(String.t() | atom()) :: {:ok, t()} | {:error, :invalid_status}
  def parse(value) when is_atom(value) and value in @values, do: {:ok, value}

  def parse(value) when is_binary(value) do
    case String.downcase(value) do
      "disconnected" -> {:ok, :disconnected}
      "connecting" -> {:ok, :connecting}
      "connected" -> {:ok, :connected}
      "error" -> {:ok, :error}
      _ -> {:error, :invalid_status}
    end
  end

  def parse(_), do: {:error, :invalid_status}

  @doc """
  Returns true if the interface is connected.
  """
  @spec connected?(t()) :: boolean()
  def connected?(:connected), do: true
  def connected?(_), do: false

  @doc """
  Returns true if a connection attempt is in progress.
  """
  @spec connecting?(t()) :: boolean()
  def connecting?(:connecting), do: true
  def connecting?(_), do: false

  @doc """
  Returns true if the interface is in an error state.
  """
  @spec error?(t()) :: boolean()
  def error?(:error), do: true
  def error?(_), do: false

  @doc """
  Returns true if the interface is idle (disconnected, not connecting).
  """
  @spec idle?(t()) :: boolean()
  def idle?(:disconnected), do: true
  def idle?(_), do: false

  @doc """
  Returns the list of valid next states from the given status.
  """
  @spec valid_next_states(t()) :: [t()]
  def valid_next_states(status) when is_map_key(@valid_transitions, status) do
    Map.fetch!(@valid_transitions, status)
  end

  def valid_next_states(_), do: []

  @doc """
  Returns true if a transition from one status to another is valid.
  """
  @spec can_transition?(t(), t()) :: boolean()
  def can_transition?(from, to) when from in @values and to in @values do
    to in Map.get(@valid_transitions, from, [])
  end

  def can_transition?(_, _), do: false

  @doc """
  Validates a transition and returns detailed error if invalid.
  """
  @spec validate_transition(t(), t()) :: :ok | {:error, {:invalid_transition, t(), t()}}
  def validate_transition(from, to) do
    if can_transition?(from, to) do
      :ok
    else
      {:error, {:invalid_transition, from, to}}
    end
  end

  @doc """
  Returns the display name for a status.
  """
  @spec display_name(t()) :: String.t()
  def display_name(:disconnected), do: "Disconnected"
  def display_name(:connecting), do: "Connecting"
  def display_name(:connected), do: "Connected"
  def display_name(:error), do: "Error"

  @doc """
  Returns a color associated with the status (for UI).
  """
  @spec color(t()) :: String.t()
  def color(:disconnected), do: "gray"
  def color(:connecting), do: "yellow"
  def color(:connected), do: "green"
  def color(:error), do: "red"

  @doc """
  Returns an icon name for the status (for UI).
  """
  @spec icon(t()) :: String.t()
  def icon(:disconnected), do: "minus-circle"
  def icon(:connecting), do: "loader"
  def icon(:connected), do: "check-circle"
  def icon(:error), do: "x-circle"
end
