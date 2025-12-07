defmodule Cadence.MissionDatabase.CommandVerifier do
  @moduledoc """
  Verifies command execution by checking telemetry conditions.

  Command verifiers monitor telemetry to confirm that a command has
  progressed through various stages of execution.

  ## Verification Stages (XTCE)

  1. **transferred_to_range**: Confirmed sent to communication system
  2. **sent_from_range**: Confirmed transmitted to spacecraft
  3. **received**: Spacecraft acknowledged receipt
  4. **accepted**: Spacecraft accepted command for execution
  5. **queued**: Command queued for later execution
  6. **executing**: Command is being executed (can track progress %)
  7. **complete**: Command execution finished successfully
  8. **failed**: Command execution failed

  ## Example: Simple Counter Verification

      %CommandVerifier{
        name: "ACCEPT_CHECK",
        stage: :accepted,
        telemetry_item_ref: "HEALTH.CMD_ACCEPT_COUNT",
        comparison: :changed,
        timeout_ms: 5000
      }

  ## Example: Match Criteria Verification

      %CommandVerifier{
        name: "MODE_CHANGE",
        stage: :complete,
        match_criteria: %MatchCriteria{
          parameter_ref: "SYSTEM.MODE",
          comparison: :equal,
          value: "SAFE"
        },
        timeout_ms: 30000
      }
  """

  use Ecto.Schema
  import Ecto.Changeset

  alias Cadence.MissionDatabase.MatchCriteria

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  @verification_stages [
    :transferred_to_range,
    :sent_from_range,
    :received,
    :accepted,
    :queued,
    :executing,
    :complete,
    :failed
  ]

  @comparisons [:equal, :not_equal, :greater, :less, :greater_equal, :less_equal, :changed]

  schema "mdb_command_verifiers" do
    belongs_to :meta_command, Cadence.MissionDatabase.MetaCommand

    field :name, :string
    field :description, :string

    field :stage, Ecto.Enum, values: @verification_stages

    # Full match criteria (for complex conditions)
    embeds_one :match_criteria, MatchCriteria, on_replace: :update

    # Simple telemetry check (alternative to match_criteria)
    field :telemetry_item_ref, :string
    field :expected_value, :string
    field :comparison, Ecto.Enum, values: @comparisons

    # Timeout
    field :timeout_ms, :integer

    # For :executing stage
    field :progress_parameter_ref, :string

    # Actions
    field :on_success_action, :string
    field :on_failure_action, :string
    field :on_timeout_action, :string

    timestamps(type: :utc_datetime)
  end

  @doc """
  Creates a changeset for a CommandVerifier.
  """
  def changeset(verifier, attrs) do
    verifier
    |> cast(attrs, [
      :meta_command_id,
      :name,
      :description,
      :stage,
      :telemetry_item_ref,
      :expected_value,
      :comparison,
      :timeout_ms,
      :progress_parameter_ref,
      :on_success_action,
      :on_failure_action,
      :on_timeout_action
    ])
    |> cast_embed(:match_criteria)
    |> validate_required([:meta_command_id, :stage])
    |> validate_inclusion(:stage, @verification_stages)
    |> validate_number(:timeout_ms, greater_than: 0)
    |> validate_verification_method()
  end

  defp validate_verification_method(changeset) do
    match_criteria = get_field(changeset, :match_criteria)
    telemetry_ref = get_field(changeset, :telemetry_item_ref)

    has_criteria = not is_nil(match_criteria)
    has_simple = not is_nil(telemetry_ref) and telemetry_ref != ""

    cond do
      not has_criteria and not has_simple ->
        add_error(
          changeset,
          :match_criteria,
          "must specify either match_criteria or telemetry_item_ref"
        )

      has_simple and is_nil(get_field(changeset, :comparison)) ->
        add_error(changeset, :comparison, "required when using telemetry_item_ref")

      true ->
        changeset
    end
  end

  @doc """
  Returns true if this verifier uses a simple telemetry check.
  """
  def simple_check?(%__MODULE__{telemetry_item_ref: ref}) when not is_nil(ref) and ref != "",
    do: true

  def simple_check?(_), do: false

  @doc """
  Returns the list of valid verification stages.
  """
  def valid_stages, do: @verification_stages

  @doc """
  Returns the list of valid comparisons.
  """
  def valid_comparisons, do: @comparisons
end
