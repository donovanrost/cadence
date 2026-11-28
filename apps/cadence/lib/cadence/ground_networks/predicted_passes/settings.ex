defmodule Cadence.GroundNetworks.PredictedPasses.Settings do
  @moduledoc """
  Pass prediction settings (#891), scoped section `cadence.pass_prediction`:

  - `horizon_days` (default 7, at most 14): how far ahead passes are predicted.

  Set for the organization and overridable per mission, like `cadence.pass_review`
  (`Cadence.Platform.ScopedSettings`). A stored value outside 1–14 is clamped to it.
  """

  alias Cadence.Platform.ScopedSettings

  @section "cadence.pass_prediction"
  @default %{"value" => %{"horizon_days" => 7}, "allow_override" => true}
  @max_horizon_days 14

  def section_id, do: @section
  def default, do: @default

  @doc "The longest horizon a mission may set, in days."
  @spec max_horizon_days() :: pos_integer()
  def max_horizon_days, do: @max_horizon_days

  @doc "The mission's horizon in days."
  @spec horizon_days(binary(), binary()) :: pos_integer()
  def horizon_days(organization_id, mission_id) do
    value =
      Map.merge(
        @default["value"],
        ScopedSettings.load(organization_id, mission_id, @section, @default).effective || %{}
      )

    case value["horizon_days"] do
      days when is_integer(days) -> days |> max(1) |> min(@max_horizon_days)
      _other -> @default["value"]["horizon_days"]
    end
  end
end
