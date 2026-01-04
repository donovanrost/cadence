defmodule Cadence.Domain.Commanding.Entities.QueuedCommand do
  @moduledoc """
  Pure domain entity representing a command queued for execution.

  This entity manages the lifecycle of queued commands, including
  priority, scheduling, retry logic, and state transitions.

  ## Lifecycle

  Commands flow through these states:
  - `:pending` - Waiting in queue
  - `:executing` - Being sent to spacecraft
  - `:completed` - Successfully executed
  - `:failed` - Execution failed (may retry)
  - `:cancelled` - Manually cancelled
  - `:expired` - Passed expiration time

  ## Priority

  Commands are processed by priority (0 = highest, 5 = lowest).
  Within the same priority, commands are processed by sequence number.

  ## Scheduling

  Commands can be scheduled for future execution via `scheduled_at`.
  They can also have an expiration time via `expires_at`.

  ## Usage

      # Create a new queued command
      {:ok, cmd} = QueuedCommand.new(%{
        organization_id: "org-uuid",
        mission_id: "mission-uuid",
        target_id: "target-uuid",
        user_id: "user-uuid",
        command_name: "POWER_ON",
        parameters: %{"subsystem" => "camera"},
        priority: 3
      })

      # Claim for execution
      {:ok, executing} = QueuedCommand.claim(cmd)

      # Mark as completed
      {:ok, completed} = QueuedCommand.complete(executing, "log-id-123")

      # Or mark as failed
      {:ok, failed} = QueuedCommand.fail(executing, "Connection timeout")

      # Retry a failed command
      {:ok, pending} = QueuedCommand.retry(failed)
  """

  alias Cadence.Domain.Commanding.ValueObjects.{Priority, QueueStatus}

  @type t :: %__MODULE__{
          id: String.t() | nil,
          organization_id: String.t(),
          mission_id: String.t(),
          target_id: String.t(),
          user_id: String.t() | nil,
          command_name: String.t(),
          parameters: map(),
          status: QueueStatus.t(),
          priority: Priority.t(),
          sequence_number: integer() | nil,
          scheduled_at: DateTime.t() | nil,
          expires_at: DateTime.t() | nil,
          attempts: non_neg_integer(),
          max_attempts: pos_integer(),
          last_attempt_at: DateTime.t() | nil,
          last_error: String.t() | nil,
          command_aggregate_id: String.t() | nil,
          dispatch_opts: map(),
          metadata: map(),
          created_at: DateTime.t() | nil
        }

  @enforce_keys [:organization_id, :mission_id, :target_id, :command_name]

  defstruct [
    :id,
    :organization_id,
    :mission_id,
    :target_id,
    :user_id,
    :command_name,
    :status,
    :priority,
    :sequence_number,
    :scheduled_at,
    :expires_at,
    :attempts,
    :max_attempts,
    :last_attempt_at,
    :last_error,
    :command_aggregate_id,
    :created_at,
    parameters: %{},
    dispatch_opts: %{},
    metadata: %{}
  ]

  # ===========================================================================
  # Construction
  # ===========================================================================

  @doc """
  Creates a new queued command.

  ## Required Attributes

  - `:organization_id` - Organization ID
  - `:mission_id` - Mission ID
  - `:target_id` - Target spacecraft ID
  - `:command_name` - Name of the command to execute

  ## Optional Attributes

  - `:id` - UUID (generated if not provided)
  - `:user_id` - User who queued the command
  - `:parameters` - Command parameters (default: %{})
  - `:priority` - Priority level 0-5 (default: 3)
  - `:scheduled_at` - Earliest execution time
  - `:expires_at` - Expiration time (command won't execute after)
  - `:max_attempts` - Max retry attempts (default: 3)
  - `:dispatch_opts` - Options for dispatch (hazard confirmation, etc.)
  - `:metadata` - Additional contextual data
  """
  @spec new(map()) :: {:ok, t()} | {:error, term()}
  def new(attrs) when is_map(attrs) do
    with :ok <- validate_required(attrs),
         :ok <- validate_priority(attrs),
         :ok <- validate_schedule(attrs) do
      cmd = %__MODULE__{
        id: Map.get(attrs, :id),
        organization_id: Map.fetch!(attrs, :organization_id),
        mission_id: Map.fetch!(attrs, :mission_id),
        target_id: Map.fetch!(attrs, :target_id),
        user_id: Map.get(attrs, :user_id),
        command_name: Map.fetch!(attrs, :command_name),
        parameters: Map.get(attrs, :parameters, %{}),
        status: QueueStatus.initial(),
        priority: Map.get(attrs, :priority, Priority.default()),
        sequence_number: Map.get(attrs, :sequence_number),
        scheduled_at: Map.get(attrs, :scheduled_at),
        expires_at: Map.get(attrs, :expires_at),
        attempts: 0,
        max_attempts: Map.get(attrs, :max_attempts, 3),
        dispatch_opts: Map.get(attrs, :dispatch_opts, %{}),
        metadata: Map.get(attrs, :metadata, %{}),
        created_at: DateTime.utc_now()
      }

      {:ok, cmd}
    end
  end

  # ===========================================================================
  # State Transitions
  # ===========================================================================

  @doc """
  Claims the command for execution.

  Transitions from `:pending` to `:executing` and increments attempt count.
  """
  @spec claim(t()) :: {:ok, t()} | {:error, term()}
  def claim(%__MODULE__{status: status} = cmd) do
    with :ok <- QueueStatus.validate_transition(status, :executing),
         :ok <- validate_ready(cmd) do
      {:ok,
       %{
         cmd
         | status: :executing,
           attempts: cmd.attempts + 1,
           last_attempt_at: DateTime.utc_now()
       }}
    end
  end

  @doc """
  Marks the command as successfully completed.

  Records the command aggregate ID for reference.
  """
  @spec complete(t(), String.t() | nil) :: {:ok, t()} | {:error, term()}
  def complete(%__MODULE__{status: status} = cmd, command_aggregate_id \\ nil) do
    with :ok <- QueueStatus.validate_transition(status, :completed) do
      {:ok,
       %{
         cmd
         | status: :completed,
           command_aggregate_id: command_aggregate_id,
           last_error: nil
       }}
    end
  end

  @doc """
  Marks the command as failed.

  Records the error message. The command may be retried if attempts < max_attempts.
  """
  @spec fail(t(), String.t()) :: {:ok, t()} | {:error, term()}
  def fail(%__MODULE__{status: status} = cmd, error_message) do
    with :ok <- QueueStatus.validate_transition(status, :failed) do
      {:ok,
       %{
         cmd
         | status: :failed,
           last_error: error_message
       }}
    end
  end

  @doc """
  Retries a failed command by returning it to pending status.

  Only works if the command is retriable (failed and under max attempts).
  """
  @spec retry(t()) :: {:ok, t()} | {:error, term()}
  def retry(%__MODULE__{status: :failed} = cmd) do
    if retriable?(cmd) do
      {:ok, %{cmd | status: :pending}}
    else
      {:error, :max_attempts_exceeded}
    end
  end

  def retry(%__MODULE__{status: status}) do
    {:error, {:not_retriable, status}}
  end

  @doc """
  Cancels a pending or failed command.
  """
  @spec cancel(t()) :: {:ok, t()} | {:error, term()}
  def cancel(%__MODULE__{status: status} = cmd) do
    with :ok <- QueueStatus.validate_transition(status, :cancelled) do
      {:ok, %{cmd | status: :cancelled}}
    end
  end

  @doc """
  Marks the command as expired.

  Called when a pending command passes its expiration time.
  """
  @spec expire(t()) :: {:ok, t()} | {:error, term()}
  def expire(%__MODULE__{status: status} = cmd) do
    with :ok <- QueueStatus.validate_transition(status, :expired) do
      {:ok, %{cmd | status: :expired}}
    end
  end

  # ===========================================================================
  # Priority Management
  # ===========================================================================

  @doc """
  Updates the priority of a pending command.
  """
  @spec set_priority(t(), Priority.t()) :: {:ok, t()} | {:error, term()}
  def set_priority(%__MODULE__{status: :pending} = cmd, priority) do
    with :ok <- Priority.validate(priority) do
      {:ok, %{cmd | priority: priority}}
    end
  end

  def set_priority(%__MODULE__{status: status}, _priority) do
    {:error, {:cannot_change_priority, status}}
  end

  @doc """
  Updates the sequence number (position in queue).
  """
  @spec set_sequence(t(), integer()) :: {:ok, t()}
  def set_sequence(%__MODULE__{} = cmd, sequence_number) when is_integer(sequence_number) do
    {:ok, %{cmd | sequence_number: sequence_number}}
  end

  # ===========================================================================
  # Queries
  # ===========================================================================

  @doc """
  Returns true if the command is ready for execution.

  A command is ready if:
  - Status is :pending
  - scheduled_at is nil or in the past
  - Not expired
  """
  @spec ready?(t()) :: boolean()
  def ready?(%__MODULE__{status: :pending} = cmd) do
    not expired?(cmd) and schedule_due?(cmd)
  end

  def ready?(_), do: false

  @doc """
  Returns true if the command has expired.
  """
  @spec expired?(t()) :: boolean()
  def expired?(%__MODULE__{expires_at: nil}), do: false

  def expired?(%__MODULE__{expires_at: expires_at}) do
    DateTime.compare(DateTime.utc_now(), expires_at) == :gt
  end

  @doc """
  Returns true if the scheduled time has passed (or no schedule set).
  """
  @spec schedule_due?(t()) :: boolean()
  def schedule_due?(%__MODULE__{scheduled_at: nil}), do: true

  def schedule_due?(%__MODULE__{scheduled_at: scheduled_at}) do
    DateTime.compare(DateTime.utc_now(), scheduled_at) != :lt
  end

  @doc """
  Returns true if the command can be retried.
  """
  @spec retriable?(t()) :: boolean()
  def retriable?(%__MODULE__{status: :failed, attempts: attempts, max_attempts: max}) do
    attempts < max
  end

  def retriable?(_), do: false

  @doc """
  Returns true if the command is in a terminal state.
  """
  @spec terminal?(t()) :: boolean()
  def terminal?(%__MODULE__{status: status}) do
    QueueStatus.terminal?(status)
  end

  @doc """
  Returns true if the command is an emergency priority.
  """
  @spec emergency?(t()) :: boolean()
  def emergency?(%__MODULE__{priority: priority}) do
    Priority.emergency?(priority)
  end

  @doc """
  Returns the remaining attempts before max is reached.
  """
  @spec remaining_attempts(t()) :: non_neg_integer()
  def remaining_attempts(%__MODULE__{attempts: attempts, max_attempts: max}) do
    max(0, max - attempts)
  end

  @doc """
  Returns seconds until scheduled execution, or nil if not scheduled.
  """
  @spec seconds_until_scheduled(t()) :: integer() | nil
  def seconds_until_scheduled(%__MODULE__{scheduled_at: nil}), do: nil

  def seconds_until_scheduled(%__MODULE__{scheduled_at: scheduled_at}) do
    DateTime.diff(scheduled_at, DateTime.utc_now(), :second)
  end

  @doc """
  Returns seconds until expiration, or nil if no expiration set.
  """
  @spec seconds_until_expiration(t()) :: integer() | nil
  def seconds_until_expiration(%__MODULE__{expires_at: nil}), do: nil

  def seconds_until_expiration(%__MODULE__{expires_at: expires_at}) do
    DateTime.diff(expires_at, DateTime.utc_now(), :second)
  end

  # ===========================================================================
  # Comparison
  # ===========================================================================

  @doc """
  Compares two commands for queue ordering.

  Orders by:
  1. Priority (lower number = higher priority)
  2. Sequence number (lower = earlier in queue)
  3. Created at (earlier = first)

  Returns `:lt`, `:eq`, or `:gt`.
  """
  @spec compare(t(), t()) :: :lt | :eq | :gt
  def compare(%__MODULE__{} = a, %__MODULE__{} = b) do
    # Priority.compare returns :gt when first is "higher priority" (more urgent)
    # For queue ordering, higher priority should come first (before, :lt)
    case Priority.compare(a.priority, b.priority) do
      :eq -> compare_sequence(a, b)
      # Higher priority comes first in queue
      :gt -> :lt
      # Lower priority comes later in queue
      :lt -> :gt
    end
  end

  defp compare_sequence(%{sequence_number: a_seq}, %{sequence_number: b_seq})
       when not is_nil(a_seq) and not is_nil(b_seq) do
    cond do
      a_seq < b_seq -> :lt
      a_seq > b_seq -> :gt
      true -> :eq
    end
  end

  defp compare_sequence(%{created_at: a_time}, %{created_at: b_time})
       when not is_nil(a_time) and not is_nil(b_time) do
    DateTime.compare(a_time, b_time)
  end

  defp compare_sequence(_, _), do: :eq

  # ===========================================================================
  # Private Helpers
  # ===========================================================================

  @required_fields [:organization_id, :mission_id, :target_id, :command_name]

  defp validate_required(attrs) do
    missing =
      @required_fields
      |> Enum.filter(fn field -> is_nil(Map.get(attrs, field)) end)

    if Enum.empty?(missing) do
      :ok
    else
      {:error, {:missing_required, missing}}
    end
  end

  defp validate_priority(%{priority: priority}) when not is_nil(priority) do
    Priority.validate(priority)
  end

  defp validate_priority(_), do: :ok

  defp validate_schedule(%{scheduled_at: scheduled_at, expires_at: expires_at})
       when not is_nil(scheduled_at) and not is_nil(expires_at) do
    if DateTime.compare(expires_at, scheduled_at) == :gt do
      :ok
    else
      {:error, :expires_before_scheduled}
    end
  end

  defp validate_schedule(_), do: :ok

  defp validate_ready(%__MODULE__{} = cmd) do
    cond do
      expired?(cmd) -> {:error, :expired}
      not schedule_due?(cmd) -> {:error, :not_scheduled_yet}
      true -> :ok
    end
  end
end
