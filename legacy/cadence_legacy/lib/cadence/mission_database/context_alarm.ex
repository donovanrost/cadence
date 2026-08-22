defmodule Cadence.MissionDatabase.ContextAlarm do
  @moduledoc """
  Context-dependent alarm that overrides the default alarm based on conditions.

  Context alarms allow different alarm thresholds to be applied based on
  the current state of the spacecraft or mission phase.

  ## Example

  Different temperature limits during eclipse:

      %ContextAlarm{
        data_type_id: temp_type.id,
        match_criteria: %MatchCriteria{
          parameter_ref: "NAV.IN_ECLIPSE",
          comparison: :equal,
          value: "true"
        },
        alarm_definition: %AlarmDefinition{
          warning_range: %AlarmRange{min_inclusive: -30.0, max_inclusive: 60.0},
          critical_range: %AlarmRange{min_inclusive: -50.0, max_inclusive: 80.0}
        },
        priority: 0
      }

  ## Priority

  Context alarms are evaluated in priority order (lower = higher priority).
  The first matching context alarm is used. If none match, the DataType's
  `default_alarm` is used.
  """

  use Ecto.Schema
  import Ecto.Changeset

  alias Cadence.MissionDatabase.{AlarmDefinition, DataType, MatchCriteria}

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  schema "mdb_context_alarms" do
    belongs_to :data_type, DataType

    embeds_one :match_criteria, MatchCriteria, on_replace: :update
    embeds_one :alarm_definition, AlarmDefinition, on_replace: :update

    field :priority, :integer, default: 0

    timestamps(type: :utc_datetime)
  end

  @doc """
  Creates a changeset for a ContextAlarm.
  """
  def changeset(context_alarm, attrs) do
    context_alarm
    |> cast(attrs, [:data_type_id, :priority])
    |> cast_embed(:match_criteria, required: true)
    |> cast_embed(:alarm_definition, required: true)
    |> validate_required([:data_type_id])
  end
end
