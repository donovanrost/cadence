defmodule Cadence.Domain.Procedures.ValueObjects.ExecutionStatus do
  @moduledoc """
  Value object representing procedure execution status.

  ## Status Values

  - `:pending` - Execution created, waiting to start
  - `:running` - Actively executing steps
  - `:paused` - Temporarily halted, can be resumed
  - `:completed` - All steps finished successfully
  - `:failed` - Execution stopped due to error
  - `:cancelled` - Manually cancelled by user

  ## State Machine

  ```
  ┌─────────┐    start    ┌─────────┐    finish     ┌───────────┐
  │ PENDING │ ──────────► │ RUNNING │ ────────────► │ COMPLETED │
  └─────────┘             └─────────┘               └───────────┘
       │                       │
       │ cancel                │ pause / fail / cancel
       ▼                       ▼
  ┌───────────┐           ┌────────┐    resume    ┌─────────┐
  │ CANCELLED │           │ PAUSED │ ───────────► │ RUNNING │
  └───────────┘           └────────┘              └─────────┘
                               │
                               │ cancel
                               ▼
                          ┌───────────┐
                          │ CANCELLED │
                          └───────────┘
  ```
  """

  @type t :: :pending | :running | :paused | :completed | :failed | :cancelled

  @values [:pending, :running, :paused, :completed, :failed, :cancelled]

  # Active states (execution in progress)
  @active_states [:pending, :running, :paused]

  # Terminal states
  @terminal_states [:completed, :failed, :cancelled]

  # Valid transitions
  @valid_transitions %{
    pending: [:running, :cancelled],
    running: [:paused, :completed, :failed, :cancelled],
    paused: [:running, :cancelled],
    completed: [],
    failed: [],
    cancelled: []
  }

  @doc """
  Returns all valid status values.
  """
  @spec values() :: [t()]
  def values, do: @values

  @doc """
  Returns the initial status for a new execution.
  """
  @spec initial() :: t()
  def initial, do: :pending

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
      "pending" -> {:ok, :pending}
      "running" -> {:ok, :running}
      "paused" -> {:ok, :paused}
      "completed" -> {:ok, :completed}
      "failed" -> {:ok, :failed}
      "cancelled" -> {:ok, :cancelled}
      _ -> {:error, :invalid_status}
    end
  end

  def parse(_), do: {:error, :invalid_status}

  @doc """
  Returns true if the execution is active (in progress).
  """
  @spec active?(t()) :: boolean()
  def active?(status) when status in @active_states, do: true
  def active?(_), do: false

  @doc """
  Returns true if the execution is terminal (finished).
  """
  @spec terminal?(t()) :: boolean()
  def terminal?(status) when status in @terminal_states, do: true
  def terminal?(_), do: false

  @doc """
  Returns true if the execution completed successfully.
  """
  @spec successful?(t()) :: boolean()
  def successful?(:completed), do: true
  def successful?(_), do: false

  @doc """
  Returns true if the execution can be resumed.
  """
  @spec resumable?(t()) :: boolean()
  def resumable?(:paused), do: true
  def resumable?(_), do: false

  @doc """
  Returns true if the execution can be paused.
  """
  @spec pausable?(t()) :: boolean()
  def pausable?(:running), do: true
  def pausable?(_), do: false

  @doc """
  Returns true if the execution can be cancelled.
  """
  @spec cancellable?(t()) :: boolean()
  def cancellable?(status) when status in @active_states, do: true
  def cancellable?(_), do: false

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
  def display_name(:pending), do: "Pending"
  def display_name(:running), do: "Running"
  def display_name(:paused), do: "Paused"
  def display_name(:completed), do: "Completed"
  def display_name(:failed), do: "Failed"
  def display_name(:cancelled), do: "Cancelled"

  @doc """
  Returns a color for the status (for UI).
  """
  @spec color(t()) :: String.t()
  def color(:pending), do: "blue"
  def color(:running), do: "yellow"
  def color(:paused), do: "orange"
  def color(:completed), do: "green"
  def color(:failed), do: "red"
  def color(:cancelled), do: "gray"
end
