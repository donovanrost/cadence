defmodule Cadence.MissionDatabase.TransmissionConstraint do
  @moduledoc """
  Precondition that must be satisfied before command transmission.

  Transmission constraints check that the spacecraft is in the correct
  state before allowing a command to be sent. They evaluate conditions
  against the current telemetry state.

  ## Example

      %TransmissionConstraint{
        name: "BATTERY_CHECK",
        description: "Battery must be above 20% before power-intensive operations",
        match_criteria: %MatchCriteria{
          parameter_ref: "POWER.BATTERY_PERCENT",
          comparison: :greater,
          value: "20"
        },
        timeout_ms: 5000,
        on_failure: :block
      }

  ## Evaluation Order

  Constraints are evaluated in priority order (lower = higher priority).
  All constraints must pass for the command to be transmitted.

  ## Suspendable Constraints

  Some constraints can be marked as `suspendable`, allowing operators
  to override them in special circumstances with appropriate authorization.
  """

  use Ecto.Schema
  import Ecto.Changeset

  alias Cadence.MissionDatabase.MatchCriteria

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  @failure_actions [:block, :warn]

  schema "mdb_transmission_constraints" do
    belongs_to :meta_command, Cadence.MissionDatabase.MetaCommand

    field :name, :string
    field :description, :string

    # Condition that must be true
    embeds_one :match_criteria, MatchCriteria, on_replace: :update

    # Timeout for condition to become true
    field :timeout_ms, :integer

    # Can this constraint be suspended by operator?
    field :suspendable, :boolean, default: false

    # What happens if constraint fails
    field :on_failure, Ecto.Enum, values: @failure_actions, default: :block

    # Order of evaluation
    field :priority, :integer, default: 0

    timestamps(type: :utc_datetime)
  end

  @doc """
  Creates a changeset for a TransmissionConstraint.
  """
  def changeset(constraint, attrs) do
    constraint
    |> cast(attrs, [
      :meta_command_id,
      :name,
      :description,
      :timeout_ms,
      :suspendable,
      :on_failure,
      :priority
    ])
    |> cast_embed(:match_criteria, required: true)
    |> validate_required([:meta_command_id])
    |> validate_inclusion(:on_failure, @failure_actions)
    |> validate_number(:timeout_ms, greater_than: 0)
    |> validate_number(:priority, greater_than_or_equal_to: 0)
  end

  @doc """
  Returns true if this constraint blocks transmission on failure.
  """
  def blocking?(%__MODULE__{on_failure: :block}), do: true
  def blocking?(_), do: false

  @doc """
  Returns true if this constraint can be suspended by operator.
  """
  def suspendable?(%__MODULE__{suspendable: true}), do: true
  def suspendable?(_), do: false

  @doc """
  Returns the list of valid failure actions.
  """
  def valid_failure_actions, do: @failure_actions
end
