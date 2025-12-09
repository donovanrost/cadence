defmodule Cadence.Procedures.ProcedureExecution do
  @moduledoc """
  A record of a procedure execution.

  Tracks the lifecycle of a procedure run from start to completion,
  including checkpoints for pause/resume functionality.

  ## State Machine

  Executions follow a strict state machine. Invalid transitions are rejected.

  ```
                      ┌──────────────┐
                      │   pending    │
                      └──────┬───────┘
                             │ start
                             ▼
      ┌──────────────────────────────────────┐
      │              running                  │
      └───┬────────┬────────┬────────┬───────┘
          │        │        │        │
          │pause   │complete│fail    │cancel
          ▼        │        │        │
      ┌───────┐    │        │        │
      │pausing│────┼────────┼────────┤ (can also fail/cancel from pausing)
      └───┬───┘    │        │        │
          │        │        │        │
          │done    │        │        │
          ▼        ▼        ▼        ▼
      ┌──────┐ ┌─────────┐ ┌──────┐ ┌─────────┐
      │paused│ │completed│ │failed│ │cancelled│
      └──┬───┘ └─────────┘ └──────┘ └─────────┘
         │         (terminal states)
         │resume
         ▼
      (back to running)
  ```

  ### Valid Transitions

  | From     | To                                        |
  |----------|-------------------------------------------|
  | pending  | running, cancelled                        |
  | running  | pausing, completed, failed, cancelled     |
  | pausing  | paused, running*, failed, cancelled       |
  | paused   | running, cancelled                        |
  | completed| (none - terminal)                         |
  | failed   | (none - terminal)                         |
  | cancelled| (none - terminal)                         |

  *pausing -> running: allowed for "cancel pause" before it takes effect

  ### Required Fields by Transition

  - `-> running`: requires `started_at` to be set
  - `-> completed`: requires `completed_at` to be set
  - `-> failed`: should have `error_message` set (warning if missing)

  ## Statuses

  - `pending` - Created but not yet started
  - `running` - Currently executing
  - `pausing` - Pause requested, waiting for current step to complete
  - `paused` - Paused by operator, can be resumed
  - `completed` - Finished successfully
  - `failed` - Encountered an error
  - `cancelled` - Cancelled by operator

  ## Checkpoints

  The `current_step_index` and `checkpoint_state` fields enable pause/resume:

  - `current_step_index` - The step that was last completed (0-indexed)
  - `checkpoint_state` - Serialized Luerl VM state for resume

  ## Triggers

  Executions can be triggered by:

  - `manual` - User initiated via UI
  - `schedule` - Oban cron job
  - `event` - Automation rule fired
  """

  use Ecto.Schema
  import Ecto.Changeset

  alias Cadence.Procedures.{Procedure, ProcedureVersion}

  @type t :: %__MODULE__{}

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  @statuses [:pending, :running, :pausing, :paused, :completed, :failed, :cancelled]
  @triggers [:manual, :schedule, :event]

  schema "procedure_executions" do
    field :status, Ecto.Enum, values: @statuses, default: :pending
    field :parameters, :map, default: %{}

    field :started_at, :utc_datetime
    field :completed_at, :utc_datetime

    field :current_step_index, :integer, default: 0
    field :checkpoint_state, :binary

    field :error_message, :string
    field :error_step_index, :integer

    field :triggered_by, Ecto.Enum, values: @triggers, default: :manual
    field :trigger_event_id, :binary_id
    field :trigger_context, :map

    # DAG execution tracking (for non-linear procedures)
    field :completed_steps, {:array, :string}, default: []
    field :skipped_steps, {:array, :string}, default: []
    field :failed_steps, {:array, :string}, default: []
    field :blocked_steps, {:array, :string}, default: []
    field :step_results, :map, default: %{}

    belongs_to :procedure, Procedure
    belongs_to :procedure_version, ProcedureVersion
    belongs_to :organization, Cadence.Organizations.Organization
    belongs_to :mission, Cadence.Missions.Mission
    belongs_to :target, Cadence.Targets.Target
    belongs_to :triggered_by_user, Cadence.Accounts.User

    timestamps(type: :utc_datetime)
  end

  @required_fields [:procedure_id, :procedure_version_id, :organization_id, :mission_id]
  @optional_fields [
    :target_id,
    :parameters,
    :status,
    :started_at,
    :completed_at,
    :current_step_index,
    :checkpoint_state,
    :error_message,
    :error_step_index,
    :triggered_by,
    :triggered_by_user_id,
    :trigger_event_id,
    :trigger_context,
    :completed_steps,
    :skipped_steps,
    :failed_steps,
    :blocked_steps,
    :step_results
  ]

  def changeset(execution, attrs) do
    execution
    |> cast(attrs, @required_fields ++ @optional_fields)
    |> validate_required(@required_fields)
    |> validate_length(:error_message, max: 10_000)
    |> foreign_key_constraint(:procedure_id)
    |> foreign_key_constraint(:procedure_version_id)
    |> foreign_key_constraint(:organization_id)
    |> foreign_key_constraint(:mission_id)
    |> foreign_key_constraint(:target_id)
    |> foreign_key_constraint(:triggered_by_user_id)
  end

  def status_changeset(execution, attrs) do
    execution
    |> cast(attrs, [
      :status,
      :started_at,
      :completed_at,
      :current_step_index,
      :checkpoint_state,
      :error_message,
      :error_step_index,
      # DAG execution fields
      :completed_steps,
      :skipped_steps,
      :failed_steps,
      :blocked_steps,
      :step_results
    ])
    |> validate_status_transition()
    |> validate_transition_requirements()
  end

  defp validate_status_transition(changeset) do
    old_status = changeset.data.status
    new_status = get_change(changeset, :status)

    if new_status && !valid_transition?(old_status, new_status) do
      add_error(changeset, :status, "invalid transition from #{old_status} to #{new_status}")
    else
      changeset
    end
  end

  # State machine transition rules
  # See module doc for visual diagram
  defp valid_transition?(from, to) do
    valid_transitions = %{
      # pending can start running or be cancelled before starting
      pending: [:running, :cancelled],
      # running can pause, complete, fail, or be cancelled
      # Note: direct running -> paused removed; must go through pausing
      running: [:pausing, :completed, :failed, :cancelled],
      # pausing transitions to paused when step completes, or can be
      # cancelled/fail, or return to running if pause is cancelled
      pausing: [:paused, :running, :failed, :cancelled],
      # paused can resume (-> running) or be cancelled
      paused: [:running, :cancelled],
      # Terminal states - no transitions allowed
      completed: [],
      failed: [],
      cancelled: []
    }

    to in Map.get(valid_transitions, from, [])
  end

  # Validate that required fields are set for certain transitions
  defp validate_transition_requirements(changeset) do
    new_status = get_change(changeset, :status)

    case new_status do
      :running ->
        # started_at should be set when transitioning to running
        # (either from pending or from paused on resume)
        old_status = changeset.data.status

        if old_status == :pending do
          # First time running - must have started_at
          if is_nil(get_field(changeset, :started_at)) and
               is_nil(get_change(changeset, :started_at)) do
            add_error(changeset, :started_at, "must be set when starting execution")
          else
            changeset
          end
        else
          # Resume - started_at already set
          changeset
        end

      :completed ->
        # completed_at is required for completion
        validate_required(changeset, [:completed_at])

      :failed ->
        # error_message is strongly recommended for failures
        # We add it as a warning via Logger rather than blocking the transition
        # since some crash scenarios might not have a message ready
        if is_nil(get_change(changeset, :error_message)) and
             is_nil(get_field(changeset, :error_message)) do
          require Logger
          Logger.warning("Execution transitioning to failed without error_message")
        end

        changeset

      _ ->
        changeset
    end
  end

  def statuses, do: @statuses
  def triggers, do: @triggers
end
