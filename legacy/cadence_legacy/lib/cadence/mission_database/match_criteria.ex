defmodule Cadence.MissionDatabase.MatchCriteria do
  @moduledoc """
  A condition that can be evaluated against current telemetry state.

  Used for:
  - Container identification (RestrictionCriteria)
  - Transmission constraints
  - Context calibrators/alarms
  - Command verifiers
  - Conditional container entries

  ## Simple Comparison Example

      %MatchCriteria{
        parameter_ref: "HEALTH.MODE",
        comparison: :equal,
        value: "NOMINAL"
      }

  ## Compound Condition Example

      %MatchCriteria{
        operator: :and,
        conditions: [
          %MatchCriteria{parameter_ref: "HEALTH.MODE", comparison: :equal, value: "NOMINAL"},
          %MatchCriteria{parameter_ref: "POWER.VOLTAGE", comparison: :greater, value: "24.0"}
        ]
      }

  ## Boolean Expression Example

      %MatchCriteria{
        boolean_expression: "HEALTH.MODE == 'NOMINAL' AND POWER.VOLTAGE > 24.0"
      }
  """

  use Ecto.Schema
  import Ecto.Changeset

  @primary_key false
  embedded_schema do
    # Simple comparison
    field :parameter_ref, :string

    field :comparison, Ecto.Enum,
      values: [
        :equal,
        :not_equal,
        :greater,
        :less,
        :greater_equal,
        :less_equal,
        :in_range,
        :not_in_range
      ]

    field :value, :string
    field :use_calibrated, :boolean, default: true

    # For range comparisons
    field :range_min, :float
    field :range_max, :float

    # Boolean expression (alternative to simple comparison)
    field :boolean_expression, :string

    # Compound conditions
    field :operator, Ecto.Enum, values: [:and, :or]
    embeds_many :conditions, __MODULE__, on_replace: :delete

    # Algorithm-based condition
    field :algorithm_ref, :string
  end

  @doc """
  Changeset for creating or updating match criteria.
  """
  def changeset(match_criteria, attrs) do
    match_criteria
    |> cast(attrs, [
      :parameter_ref,
      :comparison,
      :value,
      :use_calibrated,
      :range_min,
      :range_max,
      :boolean_expression,
      :operator,
      :algorithm_ref
    ])
    |> cast_embed(:conditions)
    |> validate_match_criteria_type()
  end

  # Ensure at least one type of condition is specified
  defp validate_match_criteria_type(changeset) do
    has_simple = get_field(changeset, :parameter_ref) != nil
    has_expression = get_field(changeset, :boolean_expression) != nil
    has_compound = get_field(changeset, :operator) != nil
    has_algorithm = get_field(changeset, :algorithm_ref) != nil

    if has_simple or has_expression or has_compound or has_algorithm do
      changeset
    else
      add_error(
        changeset,
        :base,
        "must specify parameter_ref, boolean_expression, operator with conditions, or algorithm_ref"
      )
    end
  end
end
