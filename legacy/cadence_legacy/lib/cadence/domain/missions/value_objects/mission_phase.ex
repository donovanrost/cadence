defmodule Cadence.Domain.Missions.ValueObjects.MissionPhase do
  @moduledoc """
  Value object representing mission lifecycle phase.

  ## Phase Values

  - `:planning` - Mission is being configured and designed
  - `:testing` - Mission is in test/integration phase
  - `:operational` - Mission is fully operational
  - `:decommissioned` - Mission has been retired (terminal state)

  ## State Machine

  ```
  ┌──────────┐    test     ┌─────────┐    go-live   ┌─────────────┐
  │ PLANNING │ ──────────► │ TESTING │ ───────────► │ OPERATIONAL │
  └──────────┘             └─────────┘              └─────────────┘
       │                        │                         │
       │                        │ revert                  │
       │                        ▼                         │
       │                   ┌──────────┐                   │
       │                   │ PLANNING │                   │
       │                   └──────────┘                   │
       │                                                  │
       │ decommission                      decommission   │
       ▼                                                  ▼
  ┌────────────────┐                          ┌────────────────┐
  │ DECOMMISSIONED │ ◄────────────────────────│ DECOMMISSIONED │
  └────────────────┘        decommission      └────────────────┘
  ```
  """

  @type t :: :planning | :testing | :operational | :decommissioned

  @values [:planning, :testing, :operational, :decommissioned]

  @valid_transitions %{
    planning: [:testing, :decommissioned],
    testing: [:operational, :planning, :decommissioned],
    operational: [:decommissioned],
    decommissioned: []
  }

  @doc """
  Returns all valid phase values.
  """
  @spec values() :: [t()]
  def values, do: @values

  @doc """
  Returns the initial phase for a new mission.
  """
  @spec initial() :: t()
  def initial, do: :planning

  @doc """
  Returns true if the given value is a valid phase.
  """
  @spec valid?(term()) :: boolean()
  def valid?(value) when value in @values, do: true
  def valid?(_), do: false

  @doc """
  Validates a phase value.
  """
  @spec validate(term()) :: :ok | {:error, :invalid_phase}
  def validate(value) when value in @values, do: :ok
  def validate(_), do: {:error, :invalid_phase}

  @doc """
  Parses a string or atom into a phase.
  """
  @spec parse(String.t() | atom()) :: {:ok, t()} | {:error, :invalid_phase}
  def parse(value) when is_atom(value) and value in @values, do: {:ok, value}

  def parse(value) when is_binary(value) do
    case String.downcase(value) do
      "planning" -> {:ok, :planning}
      "testing" -> {:ok, :testing}
      "operational" -> {:ok, :operational}
      "decommissioned" -> {:ok, :decommissioned}
      _ -> {:error, :invalid_phase}
    end
  end

  def parse(_), do: {:error, :invalid_phase}

  @doc """
  Returns true if the mission is in a terminal phase.
  """
  @spec terminal?(t()) :: boolean()
  def terminal?(:decommissioned), do: true
  def terminal?(_), do: false

  @doc """
  Returns true if the mission is in a pre-operational phase.
  """
  @spec pre_operational?(t()) :: boolean()
  def pre_operational?(:planning), do: true
  def pre_operational?(:testing), do: true
  def pre_operational?(_), do: false

  @doc """
  Returns true if the mission is operational.
  """
  @spec operational?(t()) :: boolean()
  def operational?(:operational), do: true
  def operational?(_), do: false

  @doc """
  Returns the list of valid next phases.
  """
  @spec valid_next_phases(t()) :: [t()]
  def valid_next_phases(phase) when is_map_key(@valid_transitions, phase) do
    Map.fetch!(@valid_transitions, phase)
  end

  def valid_next_phases(_), do: []

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
  @spec validate_transition(t(), t()) :: :ok | {:error, {:invalid_phase_transition, t(), t()}}
  def validate_transition(from, to) do
    if can_transition?(from, to) do
      :ok
    else
      {:error, {:invalid_phase_transition, from, to}}
    end
  end

  @doc """
  Returns the display name for a phase.
  """
  @spec display_name(t()) :: String.t()
  def display_name(:planning), do: "Planning"
  def display_name(:testing), do: "Testing"
  def display_name(:operational), do: "Operational"
  def display_name(:decommissioned), do: "Decommissioned"

  @doc """
  Returns a color for the phase (for UI).
  """
  @spec color(t()) :: String.t()
  def color(:planning), do: "blue"
  def color(:testing), do: "yellow"
  def color(:operational), do: "green"
  def color(:decommissioned), do: "gray"
end
