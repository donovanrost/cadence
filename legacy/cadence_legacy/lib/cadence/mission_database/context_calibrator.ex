defmodule Cadence.MissionDatabase.ContextCalibrator do
  @moduledoc """
  A calibrator that applies when a specific condition is met.

  Context calibrators allow different calibration algorithms to be used
  based on the current state of other telemetry parameters.

  ## Example

  Different calibration for battery charging vs discharging:

      %ContextCalibrator{
        data_type_id: battery_temp_type.id,
        algorithm_id: charging_cal.id,
        match_criteria: %MatchCriteria{
          parameter_ref: "POWER.CHARGE_MODE",
          comparison: :equal,
          value: "CHARGING"
        },
        priority: 0
      }

  ## Priority

  Context calibrators are evaluated in priority order (lower = higher priority).
  The first matching context calibrator is used. If none match, the DataType's
  `default_calibrator` is used.
  """

  use Ecto.Schema
  import Ecto.Changeset

  alias Cadence.MissionDatabase.{Algorithm, DataType, MatchCriteria}

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  schema "mdb_context_calibrators" do
    belongs_to :data_type, DataType
    belongs_to :algorithm, Algorithm

    embeds_one :match_criteria, MatchCriteria, on_replace: :update

    field :priority, :integer, default: 0

    timestamps(type: :utc_datetime)
  end

  @doc """
  Creates a changeset for a ContextCalibrator.
  """
  def changeset(context_calibrator, attrs) do
    context_calibrator
    |> cast(attrs, [:data_type_id, :algorithm_id, :priority])
    |> cast_embed(:match_criteria, required: true)
    |> validate_required([:data_type_id, :algorithm_id])
  end
end
