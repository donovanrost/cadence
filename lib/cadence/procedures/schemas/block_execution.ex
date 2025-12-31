defmodule Cadence.Procedures.BlockExecution do
  @moduledoc """
  Tracks the execution state and captured data for a single block.

  Each block in a step gets a corresponding BlockExecution record during
  procedure execution. The record captures:

  - Status (pending, in_progress, completed, failed, skipped)
  - Captured values (for input blocks)
  - Validation results (for telemetry check blocks)
  - Command results (for command blocks)
  - Telemetry readings (for telemetry blocks)

  ## Value Storage

  The `value` field stores captured user input as a map. The structure
  depends on the block type:

  - `:text_input` -> `%{text: "user input"}`
  - `:number_input` -> `%{number: 25.3}`
  - `:checkbox_input` -> `%{checked: true}` or `%{selections: ["a", "b"]}`
  - `:select_input` -> `%{selected: "option_value"}`
  - `:timestamp_input` -> `%{timestamp: ~U[2025-12-26 15:00:00Z]}`
  - `:duration_input` -> `%{duration_seconds: 3600}`
  - `:signature_input` -> `%{signature_data: "base64...", signed_at: ...}`

  ## Telemetry Reading

  For telemetry blocks, `telemetry_reading` captures the value at evaluation:

      %{
        "value" => 25.4,
        "timestamp" => "2025-12-26T15:30:00Z",
        "quality" => "good",
        "source" => %{
          "source_type" => "cvt",
          "raw_path" => "SC-001.EPS.battery_voltage"
        }
      }

  ## Command Result

  For command blocks, `command_result` captures the dispatch outcome:

      %{
        "dispatched_at" => "2025-12-26T15:30:00Z",
        "command_id" => "uuid",
        "status" => "sent",
        "verification" => %{
          "status" => "satisfied",
          "verified_at" => "2025-12-26T15:30:05Z"
        }
      }
  """

  use Ecto.Schema
  import Ecto.Changeset

  alias Cadence.Accounts.User
  alias Cadence.Procedures.{ProcedureBlock, StepExecution}

  @type t :: %__MODULE__{}

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  @statuses [:pending, :in_progress, :completed, :failed, :skipped]
  @validation_message_max 255

  schema "block_executions" do
    field :status, Ecto.Enum, values: @statuses, default: :pending

    # For input blocks: captured value
    field :value, :map

    # For validation blocks: pass/fail
    field :passed, :boolean
    field :validation_message, :string

    # For command blocks: execution result
    field :command_result, :map

    # For telemetry blocks: captured reading
    field :telemetry_reading, :map

    # Timing
    field :started_at, :utc_datetime
    field :completed_at, :utc_datetime

    belongs_to :step_execution, StepExecution
    belongs_to :block, ProcedureBlock
    belongs_to :entered_by, User

    timestamps(type: :utc_datetime)
  end

  @required_fields [:step_execution_id, :block_id]
  @optional_fields [
    :status,
    :value,
    :passed,
    :validation_message,
    :command_result,
    :telemetry_reading,
    :started_at,
    :completed_at,
    :entered_by_id
  ]

  @doc """
  Creates a changeset for a block execution.
  """
  def changeset(block_execution, attrs) do
    block_execution
    |> cast(attrs, @required_fields ++ @optional_fields)
    |> validate_required(@required_fields)
    |> validate_length(:validation_message, max: @validation_message_max)
    |> foreign_key_constraint(:step_execution_id)
    |> foreign_key_constraint(:block_id)
    |> foreign_key_constraint(:entered_by_id)
    |> unique_constraint([:step_execution_id, :block_id],
      name: :block_executions_step_block_index
    )
  end

  @doc """
  Changeset for starting block execution.
  """
  def start_changeset(block_execution) do
    now = DateTime.utc_now() |> DateTime.truncate(:second)

    block_execution
    |> change()
    |> put_change(:status, :in_progress)
    |> put_change(:started_at, now)
  end

  @doc """
  Changeset for entering a value into an input block.
  """
  def enter_value_changeset(block_execution, value, user_id) do
    now = DateTime.utc_now() |> DateTime.truncate(:second)

    block_execution
    |> change()
    |> put_change(:status, :completed)
    |> put_change(:value, value)
    |> put_change(:entered_by_id, user_id)
    |> put_change(:completed_at, now)
  end

  @doc """
  Changeset for recording a telemetry reading.
  """
  def telemetry_reading_changeset(block_execution, reading, passed \\ nil) do
    now = DateTime.utc_now() |> DateTime.truncate(:second)

    block_execution
    |> change()
    |> put_change(:status, :completed)
    |> put_change(:telemetry_reading, reading)
    |> put_change(:passed, passed)
    |> put_change(:completed_at, now)
  end

  @doc """
  Changeset for recording a telemetry check result.
  """
  def telemetry_check_changeset(block_execution, reading, passed, validation_message \\ nil) do
    now = DateTime.utc_now() |> DateTime.truncate(:second)
    validation_message = truncate_message(validation_message)

    block_execution
    |> change()
    |> put_change(:status, :completed)
    |> put_change(:telemetry_reading, reading)
    |> put_change(:passed, passed)
    |> put_change(:validation_message, validation_message)
    |> put_change(:completed_at, now)
  end

  @doc """
  Changeset for recording a command result.
  """
  def command_result_changeset(block_execution, result) do
    now = DateTime.utc_now() |> DateTime.truncate(:second)

    block_execution
    |> change()
    |> put_change(:status, :completed)
    |> put_change(:command_result, result)
    |> put_change(:completed_at, now)
  end

  @doc """
  Changeset for marking block as failed.
  """
  def fail_changeset(block_execution, message) do
    now = DateTime.utc_now() |> DateTime.truncate(:second)
    message = truncate_message(message)

    block_execution
    |> change()
    |> put_change(:status, :failed)
    |> put_change(:validation_message, message)
    |> put_change(:completed_at, now)
  end

  @doc """
  Changeset for skipping a block.
  """
  def skip_changeset(block_execution) do
    now = DateTime.utc_now() |> DateTime.truncate(:second)

    block_execution
    |> change()
    |> put_change(:status, :skipped)
    |> put_change(:completed_at, now)
  end

  @doc """
  Returns true if block is complete.
  """
  def complete?(%__MODULE__{status: status}), do: status in [:completed, :skipped]

  @doc """
  Returns true if block passed validation.
  """
  def passed?(%__MODULE__{passed: true}), do: true
  def passed?(%__MODULE__{}), do: false

  @doc """
  Returns the captured value for display.
  """
  def display_value(%__MODULE__{value: nil}), do: nil

  def display_value(%__MODULE__{value: %{"text" => text}}), do: text
  def display_value(%__MODULE__{value: %{text: text}}), do: text

  def display_value(%__MODULE__{value: %{"number" => num}}), do: num
  def display_value(%__MODULE__{value: %{number: num}}), do: num

  def display_value(%__MODULE__{value: %{"selected" => sel}}), do: sel
  def display_value(%__MODULE__{value: %{selected: sel}}), do: sel

  def display_value(%__MODULE__{value: %{"checked" => checked}}), do: checked
  def display_value(%__MODULE__{value: %{checked: checked}}), do: checked

  def display_value(%__MODULE__{value: value}), do: inspect(value)

  def statuses, do: @statuses

  defp truncate_message(nil), do: nil

  defp truncate_message(message) when is_binary(message) do
    if String.length(message) > @validation_message_max do
      String.slice(message, 0, @validation_message_max - 3) <> "..."
    else
      message
    end
  end

  defp truncate_message(message), do: truncate_message(inspect(message))
end
