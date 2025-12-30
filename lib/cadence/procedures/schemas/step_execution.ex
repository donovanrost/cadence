defmodule Cadence.Procedures.StepExecution do
  @moduledoc """
  Tracks the execution state of a single step within a procedure run.

  Each step in a procedure version gets a corresponding StepExecution record
  when the procedure execution reaches it. The step execution tracks:

  - Current status (pending, active, completed, etc.)
  - Timing (started_at, completed_at)
  - Result (pass, fail, skip)
  - Error information if failed
  - Skip reason if skipped

  ## Status Lifecycle

  Steps progress through these statuses:

  - `:pending` - Step not yet reached
  - `:active` - Currently being worked on by operator
  - `:awaiting_signoff` - Work complete, waiting for signoff
  - `:completed` - Step finished successfully
  - `:skipped` - Step was skipped (condition or manual)
  - `:failed` - Step failed with error
  - `:blocked` - Waiting for dependencies to complete

  ## Relationships

  - Belongs to a `ProcedureExecution` (the overall run)
  - Belongs to a `ProcedureStep` (the definition)
  - Has many `BlockExecution` records (one per block)
  - Has many `StepSignoff` records (operator signoffs)
  - Has many `ExecutionComment` records (comments on this step)
  """

  use Ecto.Schema
  import Ecto.Changeset

  alias Cadence.Accounts.User

  alias Cadence.Procedures.{
    BlockExecution,
    ExecutionComment,
    ProcedureExecution,
    ProcedureStep,
    StepSignoff
  }

  @type t :: %__MODULE__{}

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  @statuses [:pending, :active, :awaiting_signoff, :completed, :skipped, :failed, :blocked]
  @results [:pass, :fail, :skip]

  schema "step_executions" do
    field :status, Ecto.Enum, values: @statuses, default: :pending

    # Timing
    field :started_at, :utc_datetime
    field :completed_at, :utc_datetime

    # Result
    field :result, Ecto.Enum, values: @results
    field :error_message, :string

    # Skip tracking
    field :skipped_reason, :string

    belongs_to :procedure_execution, ProcedureExecution
    belongs_to :step, ProcedureStep
    belongs_to :skipped_by, User

    has_many :block_executions, BlockExecution
    has_many :signoffs, StepSignoff
    has_many :comments, ExecutionComment

    timestamps(type: :utc_datetime)
  end

  @required_fields [:procedure_execution_id, :step_id]
  @optional_fields [
    :status,
    :started_at,
    :completed_at,
    :result,
    :error_message,
    :skipped_reason,
    :skipped_by_id
  ]

  @doc """
  Creates a changeset for a step execution.
  """
  def changeset(step_execution, attrs) do
    step_execution
    |> cast(attrs, @required_fields ++ @optional_fields)
    |> validate_required(@required_fields)
    |> validate_length(:error_message, max: 10_000)
    |> validate_length(:skipped_reason, max: 1000)
    |> validate_status_transition()
    |> foreign_key_constraint(:procedure_execution_id)
    |> foreign_key_constraint(:step_id)
    |> foreign_key_constraint(:skipped_by_id)
    |> unique_constraint([:procedure_execution_id, :step_id],
      name: :step_executions_execution_step_index
    )
  end

  @doc """
  Changeset for activating a step.
  """
  def activate_changeset(step_execution) do
    now = DateTime.utc_now() |> DateTime.truncate(:second)

    step_execution
    |> change()
    |> put_change(:status, :active)
    |> put_change(:started_at, now)
    |> validate_status_transition()
  end

  @doc """
  Changeset for marking step as awaiting signoff.
  """
  def awaiting_signoff_changeset(step_execution) do
    step_execution
    |> change()
    |> put_change(:status, :awaiting_signoff)
    |> validate_status_transition()
  end

  @doc """
  Changeset for completing a step.
  """
  def complete_changeset(step_execution, result \\ :pass) do
    now = DateTime.utc_now() |> DateTime.truncate(:second)

    step_execution
    |> change()
    |> put_change(:status, :completed)
    |> put_change(:completed_at, now)
    |> put_change(:result, result)
    |> validate_status_transition()
  end

  @doc """
  Changeset for skipping a step.
  """
  def skip_changeset(step_execution, attrs) do
    now = DateTime.utc_now() |> DateTime.truncate(:second)

    step_execution
    |> cast(attrs, [:skipped_reason, :skipped_by_id])
    |> put_change(:status, :skipped)
    |> put_change(:completed_at, now)
    |> put_change(:result, :skip)
    |> validate_required([:skipped_reason])
    |> validate_status_transition()
  end

  @doc """
  Changeset for failing a step.
  """
  def fail_changeset(step_execution, error_message) do
    now = DateTime.utc_now() |> DateTime.truncate(:second)

    step_execution
    |> change()
    |> put_change(:status, :failed)
    |> put_change(:completed_at, now)
    |> put_change(:result, :fail)
    |> put_change(:error_message, error_message)
    |> validate_status_transition()
  end

  @doc """
  Changeset for blocking a step (waiting on dependencies).
  """
  def block_changeset(step_execution) do
    step_execution
    |> change()
    |> put_change(:status, :blocked)
    |> validate_status_transition()
  end

  # Validates that status transitions are valid
  defp validate_status_transition(changeset) do
    old_status = changeset.data.status
    new_status = get_change(changeset, :status)

    cond do
      is_nil(new_status) ->
        changeset

      valid_transition?(old_status, new_status) ->
        changeset

      true ->
        add_error(changeset, :status, "cannot transition from #{old_status} to #{new_status}")
    end
  end

  @doc """
  Returns whether a status transition is valid.
  """
  def valid_transition?(from, to)

  # From pending
  def valid_transition?(:pending, :active), do: true
  def valid_transition?(:pending, :blocked), do: true
  def valid_transition?(:pending, :skipped), do: true

  # From blocked
  def valid_transition?(:blocked, :active), do: true
  def valid_transition?(:blocked, :skipped), do: true

  # From active
  def valid_transition?(:active, :awaiting_signoff), do: true
  def valid_transition?(:active, :completed), do: true
  def valid_transition?(:active, :failed), do: true
  def valid_transition?(:active, :skipped), do: true

  # From awaiting_signoff
  def valid_transition?(:awaiting_signoff, :completed), do: true
  def valid_transition?(:awaiting_signoff, :failed), do: true
  def valid_transition?(:awaiting_signoff, :skipped), do: true

  # No other transitions allowed
  def valid_transition?(_, _), do: false

  @doc """
  Returns true if step is in a terminal state.
  """
  def terminal?(%__MODULE__{status: status}), do: status in [:completed, :skipped, :failed]

  @doc """
  Returns true if step is active and can accept input.
  """
  def active?(%__MODULE__{status: :active}), do: true
  def active?(%__MODULE__{status: :awaiting_signoff}), do: true
  def active?(%__MODULE__{}), do: false

  @doc """
  Returns duration in seconds if step is complete.
  """
  def duration_seconds(%__MODULE__{started_at: nil}), do: nil
  def duration_seconds(%__MODULE__{completed_at: nil}), do: nil

  def duration_seconds(%__MODULE__{started_at: started, completed_at: completed}) do
    DateTime.diff(completed, started, :second)
  end

  def statuses, do: @statuses
  def results, do: @results
end
