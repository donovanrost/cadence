defmodule Cadence.Commands.QueueEntry do
  @moduledoc """
  Schema for queued commands awaiting execution.

  Commands are queued and processed in order, with support for:
  - Priority levels (higher priority commands execute first)
  - Scheduled execution (execute at or after a specific time)
  - Retry logic (automatic retry on transient failures)
  - Pause/resume (queue can be paused during anomalies)

  ## Lifecycle

  ```
  :pending → :executing → :completed
                       → :failed
                       → :cancelled
  ```

  ## Priority Levels

  - 0: Emergency (immediate, bypasses queue)
  - 1: Critical
  - 2: High
  - 3: Normal (default)
  - 4: Low
  - 5: Background
  """

  use Ecto.Schema
  import Ecto.Changeset

  alias Cadence.Accounts.User
  alias Cadence.Missions.Mission
  alias Cadence.Organizations.Organization
  alias Cadence.Targets.Target

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  # Order matches PostgreSQL enum for correct ORDER BY behavior
  @status_values [:executing, :pending, :failed, :completed, :cancelled, :expired]
  @priority_levels [0, 1, 2, 3, 4, 5]

  schema "command_queue_entries" do
    belongs_to :organization, Organization
    belongs_to :mission, Mission
    belongs_to :target, Target
    belongs_to :user, User

    # Command details
    field :command_name, :string
    field :parameters, :map, default: %{}

    # Queue management
    field :status, Ecto.Enum, values: @status_values, default: :pending
    field :priority, :integer, default: 3
    field :sequence_number, :integer

    # Scheduling
    field :scheduled_at, :utc_datetime_usec
    field :expires_at, :utc_datetime_usec

    # Execution tracking
    field :attempts, :integer, default: 0
    field :max_attempts, :integer, default: 3
    field :last_attempt_at, :utc_datetime_usec
    field :last_error, :string

    # Result linking
    field :command_aggregate_id, :binary_id, source: :command_log_id

    # Options passed to dispatch
    field :dispatch_opts, :map, default: %{}

    # Metadata
    field :metadata, :map, default: %{}

    timestamps(type: :utc_datetime_usec)
  end

  @doc """
  Changeset for creating a new queue entry.
  """
  def changeset(entry, attrs) do
    entry
    |> cast(attrs, [
      :organization_id,
      :mission_id,
      :target_id,
      :user_id,
      :command_name,
      :parameters,
      :status,
      :priority,
      :sequence_number,
      :scheduled_at,
      :expires_at,
      :max_attempts,
      :dispatch_opts,
      :metadata,
      :command_aggregate_id
    ])
    |> validate_required([:organization_id, :mission_id, :target_id, :command_name])
    |> validate_inclusion(:priority, @priority_levels)
    |> validate_number(:max_attempts, greater_than: 0, less_than_or_equal_to: 10)
    |> validate_expiry()
    |> foreign_key_constraint(:organization_id)
    |> foreign_key_constraint(:mission_id)
    |> foreign_key_constraint(:target_id)
  end

  @doc """
  Changeset for updating queue entry status during execution.
  """
  def execution_changeset(entry, attrs) do
    entry
    |> cast(attrs, [
      :status,
      :attempts,
      :last_attempt_at,
      :last_error,
      :command_aggregate_id
    ])
    |> validate_required([:status])
  end

  @doc """
  Changeset for cancelling a queue entry.
  """
  def cancel_changeset(entry, attrs \\ %{}) do
    entry
    |> cast(attrs, [:metadata])
    |> put_change(:status, :cancelled)
  end

  # Validate that expires_at is after scheduled_at (if both provided)
  defp validate_expiry(changeset) do
    scheduled_at = get_field(changeset, :scheduled_at)
    expires_at = get_field(changeset, :expires_at)

    if scheduled_at && expires_at && DateTime.compare(expires_at, scheduled_at) != :gt do
      add_error(changeset, :expires_at, "must be after scheduled_at")
    else
      changeset
    end
  end

  @doc """
  Returns true if the entry is ready to execute.
  """
  def ready?(%__MODULE__{status: :pending, scheduled_at: nil}), do: true

  def ready?(%__MODULE__{status: :pending, scheduled_at: scheduled_at}) do
    DateTime.compare(DateTime.utc_now(), scheduled_at) != :lt
  end

  def ready?(_), do: false

  @doc """
  Returns true if the entry has expired.
  """
  def expired?(%__MODULE__{expires_at: nil}), do: false

  def expired?(%__MODULE__{expires_at: expires_at}) do
    DateTime.compare(DateTime.utc_now(), expires_at) == :gt
  end

  @doc """
  Returns true if the entry can be retried.
  """
  def retriable?(%__MODULE__{status: :failed, attempts: attempts, max_attempts: max}) do
    attempts < max
  end

  def retriable?(_), do: false

  @doc """
  Returns the list of valid status values.
  """
  def status_values, do: @status_values

  @doc """
  Returns the list of valid priority levels.
  """
  def priority_levels, do: @priority_levels
end
