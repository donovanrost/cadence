defmodule Cadence.MissionDatabase.CommandInterlock do
  @moduledoc """
  Interlock requiring a previous command to reach a verification stage
  before this command can be sent.

  Interlocks ensure sequential command execution where one command
  must complete (or reach a certain stage) before another can begin.

  ## Example

      %CommandInterlock{
        previous_command_ref: "ARM_THRUSTER",
        verification_stage: :accepted,
        suspendable: false
      }

  This would prevent the current command from being sent until
  ARM_THRUSTER has been accepted by the spacecraft.

  ## Stages

  - **transferred_to_range**: Confirmed sent to communication system
  - **sent_from_range**: Confirmed transmitted to spacecraft
  - **received**: Spacecraft acknowledged receipt
  - **accepted**: Spacecraft accepted command for execution
  - **queued**: Command queued for later execution
  - **executing**: Command is being executed
  - **complete**: Command execution finished
  """

  use Ecto.Schema
  import Ecto.Changeset

  @primary_key false

  @verification_stages [
    :transferred_to_range,
    :sent_from_range,
    :received,
    :accepted,
    :queued,
    :executing,
    :complete
  ]

  embedded_schema do
    field :previous_command_ref, :string
    field :verification_stage, Ecto.Enum, values: @verification_stages
    field :verification_progress_percent, :integer  # For :executing stage
    field :suspendable, :boolean, default: false
  end

  @doc """
  Changeset for creating or updating a command interlock.
  """
  def changeset(interlock, attrs) do
    interlock
    |> cast(attrs, [:previous_command_ref, :verification_stage, :verification_progress_percent, :suspendable])
    |> validate_required([:previous_command_ref, :verification_stage])
    |> validate_inclusion(:verification_stage, @verification_stages)
    |> validate_progress_percent()
  end

  defp validate_progress_percent(changeset) do
    stage = get_field(changeset, :verification_stage)
    progress = get_field(changeset, :verification_progress_percent)

    cond do
      stage == :executing and not is_nil(progress) and (progress < 0 or progress > 100) ->
        add_error(changeset, :verification_progress_percent, "must be between 0 and 100")

      stage != :executing and not is_nil(progress) ->
        add_error(changeset, :verification_progress_percent, "only valid for :executing stage")

      true ->
        changeset
    end
  end

  @doc """
  Returns the list of valid verification stages.
  """
  def valid_verification_stages, do: @verification_stages
end
