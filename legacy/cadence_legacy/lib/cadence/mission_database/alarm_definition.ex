defmodule Cadence.MissionDatabase.AlarmDefinition do
  @moduledoc """
  Alarm/limit definition for a parameter.

  Supports both XTCE alarm levels (watch, warning, distress, critical, severe)
  and OpenC3-style limits (which map to these levels).

  ## XTCE Model

  Defines ranges where values are considered nominal. Values outside these
  ranges trigger alarms of increasing severity:

  - **watch**: First level, informational
  - **warning**: Attention needed
  - **distress**: Problem occurring
  - **critical**: Serious problem
  - **severe**: Most serious

  ## OpenC3 Mapping

  OpenC3's `red_low`, `yellow_low`, `yellow_high`, `red_high` map to:
  - `yellow_*` -> warning_range
  - `red_*` -> critical_range

  ## Example

      %AlarmDefinition{
        warning_range: %AlarmRange{min_inclusive: 10.0, max_inclusive: 90.0},
        critical_range: %AlarmRange{min_inclusive: 0.0, max_inclusive: 100.0},
        min_violations: 3
      }
  """

  use Ecto.Schema
  import Ecto.Changeset

  alias Cadence.MissionDatabase.AlarmRange

  @primary_key false
  embedded_schema do
    # Static range alarms (XTCE model)
    # Values INSIDE the range are nominal; outside triggers alarm
    embeds_one :watch_range, AlarmRange, on_replace: :update
    embeds_one :warning_range, AlarmRange, on_replace: :update
    embeds_one :distress_range, AlarmRange, on_replace: :update
    embeds_one :critical_range, AlarmRange, on_replace: :update
    embeds_one :severe_range, AlarmRange, on_replace: :update

    # Change alarms (rate of change)
    field :change_per_second_warning, :float
    field :change_per_second_critical, :float

    # Delta alarms (change since last sample)
    field :delta_warning, :float
    field :delta_critical, :float

    # Persistence (samples out-of-limits before alarm)
    field :min_violations, :integer, default: 1

    # Actions on alarm
    field :alarm_actions, {:array, :string}, default: []
  end

  @doc """
  Changeset for creating or updating an alarm definition.
  """
  def changeset(alarm_definition, attrs) do
    alarm_definition
    |> cast(attrs, [
      :change_per_second_warning,
      :change_per_second_critical,
      :delta_warning,
      :delta_critical,
      :min_violations,
      :alarm_actions
    ])
    |> cast_embed(:watch_range)
    |> cast_embed(:warning_range)
    |> cast_embed(:distress_range)
    |> cast_embed(:critical_range)
    |> cast_embed(:severe_range)
    |> validate_number(:min_violations, greater_than: 0)
  end

  @doc """
  Creates an AlarmDefinition from OpenC3-style limits.

  ## Example

      AlarmDefinition.from_openc3_limits(%{
        red_low: -50.0,
        yellow_low: -10.0,
        yellow_high: 85.0,
        red_high: 100.0
      })
  """
  def from_openc3_limits(limits) do
    %__MODULE__{
      warning_range: build_range(limits[:yellow_low], limits[:yellow_high]),
      critical_range: build_range(limits[:red_low], limits[:red_high])
    }
  end

  defp build_range(nil, nil), do: nil

  defp build_range(low, high) do
    %AlarmRange{
      min_inclusive: low,
      max_inclusive: high
    }
  end
end
