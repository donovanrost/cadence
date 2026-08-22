defmodule Cadence.Domain.Missions.ValueObjects.MissionStatus do
  @moduledoc """
  Value object representing mission runtime status.

  ## Status Values

  - `:inactive` - Mission is not running (default initial state)
  - `:active` - Mission runtime is running and processing telemetry/commands
  - `:suspended` - Mission is temporarily paused

  ## State Machine

  ```
  ┌──────────┐    start     ┌────────┐
  │ INACTIVE │ ────────────►│ ACTIVE │
  └──────────┘              └────────┘
       ▲                        │ │
       │ stop                   │ │ suspend
       │                        │ ▼
       │                   ┌───────────┐
       └───────────────────│ SUSPENDED │
             stop          └───────────┘
                                │
                                │ resume
                                ▼
                           ┌────────┐
                           │ ACTIVE │
                           └────────┘
  ```
  """

  @type t :: :inactive | :active | :suspended

  @values [:inactive, :active, :suspended]

  @valid_transitions %{
    inactive: [:active],
    active: [:inactive, :suspended],
    suspended: [:active, :inactive]
  }

  @doc """
  Returns all valid status values.
  """
  @spec values() :: [t()]
  def values, do: @values

  @doc """
  Returns the initial status for a new mission.
  """
  @spec initial() :: t()
  def initial, do: :inactive

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
      "inactive" -> {:ok, :inactive}
      "active" -> {:ok, :active}
      "suspended" -> {:ok, :suspended}
      _ -> {:error, :invalid_status}
    end
  end

  def parse(_), do: {:error, :invalid_status}

  @doc """
  Returns true if the mission is running.
  """
  @spec running?(t()) :: boolean()
  def running?(:active), do: true
  def running?(_), do: false

  @doc """
  Returns true if the mission can be started.
  """
  @spec can_start?(t()) :: boolean()
  def can_start?(:inactive), do: true
  def can_start?(_), do: false

  @doc """
  Returns true if the mission can be stopped.
  """
  @spec can_stop?(t()) :: boolean()
  def can_stop?(:active), do: true
  def can_stop?(:suspended), do: true
  def can_stop?(_), do: false

  @doc """
  Returns true if the mission can be suspended.
  """
  @spec can_suspend?(t()) :: boolean()
  def can_suspend?(:active), do: true
  def can_suspend?(_), do: false

  @doc """
  Returns true if the mission can be resumed.
  """
  @spec can_resume?(t()) :: boolean()
  def can_resume?(:suspended), do: true
  def can_resume?(_), do: false

  @doc """
  Returns the list of valid next states.
  """
  @spec valid_next_states(t()) :: [t()]
  def valid_next_states(status) when is_map_key(@valid_transitions, status) do
    Map.fetch!(@valid_transitions, status)
  end

  def valid_next_states(_), do: []

  @doc """
  Returns true if a transition is valid.
  """
  @spec can_transition?(t(), t()) :: boolean()
  def can_transition?(from, to) when from in @values and to in @values do
    to in Map.get(@valid_transitions, from, [])
  end

  def can_transition?(_, _), do: false

  @doc """
  Validates a transition.
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
  def display_name(:inactive), do: "Inactive"
  def display_name(:active), do: "Active"
  def display_name(:suspended), do: "Suspended"

  @doc """
  Returns a color for the status (for UI).
  """
  @spec color(t()) :: String.t()
  def color(:inactive), do: "gray"
  def color(:active), do: "green"
  def color(:suspended), do: "yellow"
end
