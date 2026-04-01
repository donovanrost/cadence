defmodule Cadence.Domain.Alerting.ValueObjects.AlarmStatus do
  @moduledoc """
  Value object representing alarm status with state machine transitions.

  ## Status Values

  - `:active` - Alarm condition is present and not acknowledged
  - `:acknowledged` - User has acknowledged but condition persists
  - `:shelved` - Temporarily silenced until a specified time
  - `:cleared` - Condition has resolved (terminal state)

  ## State Machine

  ```
  ┌─────────┐    violation    ┌─────────┐    user action    ┌──────────────┐
  │ (none)  │ ──────────────► │ ACTIVE  │ ─────────────────► │ ACKNOWLEDGED │
  └─────────┘                 └─────────┘                    └──────────────┘
                                   │                               │
                                   │ recovery                      │ recovery
                                   ▼                               ▼
                              ┌─────────┐                    ┌──────────┐
                              │ CLEARED │◄───────────────────│ CLEARED  │
                              └─────────┘                    └──────────┘

                                   │
                              user action
                                   ▼
                              ┌─────────┐
                              │ SHELVED │ (temporarily silenced)
                              └─────────┘
  ```

  ## Usage

      iex> AlarmStatus.can_transition?(:active, :acknowledged)
      true

      iex> AlarmStatus.can_transition?(:cleared, :active)
      false

      iex> AlarmStatus.active?(:shelved)
      true
  """

  @type t :: :active | :acknowledged | :shelved | :cleared

  @values [:active, :acknowledged, :shelved, :cleared]

  # Terminal states (no transitions out)
  @terminal_states [:cleared]

  # States considered "active" (alarm condition still present)
  @active_states [:active, :acknowledged, :shelved]

  # Valid state transitions
  @valid_transitions %{
    active: [:acknowledged, :shelved, :cleared],
    acknowledged: [:shelved, :cleared],
    shelved: [:active, :acknowledged, :cleared],
    cleared: []
  }

  @doc """
  Returns all valid status values.
  """
  @spec values() :: [t()]
  def values, do: @values

  @doc """
  Returns true if the given value is a valid status.
  """
  @spec valid?(term()) :: boolean()
  def valid?(value) when value in @values, do: true
  def valid?(_), do: false

  @doc """
  Validates a status value.

  Returns `:ok` if valid, `{:error, :invalid_status}` otherwise.
  """
  @spec validate(term()) :: :ok | {:error, :invalid_status}
  def validate(value) when value in @values, do: :ok
  def validate(_), do: {:error, :invalid_status}

  @doc """
  Parses a string or atom into a status.

  Returns `{:ok, status}` or `{:error, :invalid_status}`.
  """
  @spec parse(String.t() | atom()) :: {:ok, t()} | {:error, :invalid_status}
  def parse(value) when is_atom(value) and value in @values, do: {:ok, value}

  def parse(value) when is_binary(value) do
    case String.downcase(value) do
      "active" -> {:ok, :active}
      "acknowledged" -> {:ok, :acknowledged}
      "shelved" -> {:ok, :shelved}
      "cleared" -> {:ok, :cleared}
      _ -> {:error, :invalid_status}
    end
  end

  def parse(_), do: {:error, :invalid_status}

  @doc """
  Returns true if the status is a terminal state (no further transitions).
  """
  @spec terminal?(t()) :: boolean()
  def terminal?(status) when status in @terminal_states, do: true
  def terminal?(_), do: false

  @doc """
  Returns true if the alarm is in an active (non-terminal) state.

  Active states are those where the alarm condition is still present
  and the alarm should be visible in active alarm lists.
  """
  @spec active?(t()) :: boolean()
  def active?(status) when status in @active_states, do: true
  def active?(_), do: false

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

  Returns `:ok` or `{:error, {:invalid_transition, from, to}}`.
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
  def display_name(:active), do: "Active"
  def display_name(:acknowledged), do: "Acknowledged"
  def display_name(:shelved), do: "Shelved"
  def display_name(:cleared), do: "Cleared"

  @doc """
  Returns a color associated with the status (for UI).
  """
  @spec color(t()) :: String.t()
  def color(:active), do: "red"
  def color(:acknowledged), do: "yellow"
  def color(:shelved), do: "gray"
  def color(:cleared), do: "green"

  @doc """
  Returns the initial status for a new alarm.
  """
  @spec initial() :: t()
  def initial, do: :active
end
