defmodule Cadence.Domain.Commanding.ValueObjects.QueueStatus do
  @moduledoc """
  Value object representing command queue entry status.

  ## Status Values

  - `:pending` - Waiting in queue for execution
  - `:executing` - Currently being sent to spacecraft
  - `:completed` - Successfully executed
  - `:failed` - Execution failed (may be retried)
  - `:cancelled` - Manually cancelled by user
  - `:expired` - Passed expiration time without execution

  ## State Machine

  ```
  ┌─────────┐     claim      ┌───────────┐     success    ┌───────────┐
  │ PENDING │ ─────────────► │ EXECUTING │ ─────────────► │ COMPLETED │
  └─────────┘                └───────────┘                └───────────┘
       │                          │
       │ cancel                   │ failure
       ▼                          ▼
  ┌───────────┐              ┌────────┐     retry     ┌─────────┐
  │ CANCELLED │              │ FAILED │ ─────────────► │ PENDING │
  └───────────┘              └────────┘                └─────────┘
       │
       │ expire
       ▼
  ┌─────────┐
  │ EXPIRED │
  └─────────┘
  ```
  """

  @type t :: :pending | :executing | :completed | :failed | :cancelled | :expired

  @values [:pending, :executing, :completed, :failed, :cancelled, :expired]

  # Terminal states
  @terminal_states [:completed, :cancelled, :expired]

  # States that can be retried
  @retriable_states [:failed]

  # Valid transitions
  @valid_transitions %{
    pending: [:executing, :cancelled, :expired],
    executing: [:completed, :failed],
    # retry goes back to pending
    failed: [:pending, :cancelled],
    completed: [],
    cancelled: [],
    expired: []
  }

  @doc """
  Returns all valid status values.
  """
  @spec values() :: [t()]
  def values, do: @values

  @doc """
  Returns the initial status for a new queue entry.
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
      "executing" -> {:ok, :executing}
      "completed" -> {:ok, :completed}
      "failed" -> {:ok, :failed}
      "cancelled" -> {:ok, :cancelled}
      "expired" -> {:ok, :expired}
      _ -> {:error, :invalid_status}
    end
  end

  def parse(_), do: {:error, :invalid_status}

  @doc """
  Returns true if the status is terminal (no further transitions).
  """
  @spec terminal?(t()) :: boolean()
  def terminal?(status) when status in @terminal_states, do: true
  def terminal?(_), do: false

  @doc """
  Returns true if the entry can be retried.
  """
  @spec retriable?(t()) :: boolean()
  def retriable?(status) when status in @retriable_states, do: true
  def retriable?(_), do: false

  @doc """
  Returns true if the entry is waiting to be processed.
  """
  @spec pending?(t()) :: boolean()
  def pending?(:pending), do: true
  def pending?(_), do: false

  @doc """
  Returns true if the entry is currently executing.
  """
  @spec executing?(t()) :: boolean()
  def executing?(:executing), do: true
  def executing?(_), do: false

  @doc """
  Returns true if the entry completed successfully.
  """
  @spec successful?(t()) :: boolean()
  def successful?(:completed), do: true
  def successful?(_), do: false

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
  def display_name(:executing), do: "Executing"
  def display_name(:completed), do: "Completed"
  def display_name(:failed), do: "Failed"
  def display_name(:cancelled), do: "Cancelled"
  def display_name(:expired), do: "Expired"

  @doc """
  Returns a color for the status (for UI).
  """
  @spec color(t()) :: String.t()
  def color(:pending), do: "blue"
  def color(:executing), do: "yellow"
  def color(:completed), do: "green"
  def color(:failed), do: "red"
  def color(:cancelled), do: "gray"
  def color(:expired), do: "gray"
end
