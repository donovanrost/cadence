defmodule Cadence.Observability.Metrics.MissionRuntimeMetrics do
  @moduledoc """
  The mission runtime's admission gauges (director 11-17, after the calibration incident; U91),
  recorded by `MissionHealthSampler` per active mission on its fixed interval from
  `Cadence.Control.MissionRuntimeGauges`. Exported as `cadence_mission_runtime_*` with the label
  `cadence_mission_id`; devops alerts on desired - applied != 0 for 2 min and on a missing
  applied series.
  """

  alias Cadence.Observability.Metrics.Definition

  @attributes ["cadence.mission.id"]

  @gauges [
    {"cadence.mission_runtime.desired_generation", "{generation}",
     "The generation the mission's active activation asks its runtime to run."},
    {"cadence.mission_runtime.applied_generation", "{generation}",
     "The generation the mission's runtime has applied; 0 when none is applied on this node or " <>
       "its reconciler isn't running."},
    {"cadence.mission_runtime.admitted", "{state}",
     "1 when the mission's runtime runs its desired generation, else 0."}
  ]

  @doc "The metric names (the catalog allows `cadence.mission.id` on them)."
  @spec names() :: [binary()]
  def names, do: Enum.map(@gauges, &elem(&1, 0))

  @spec definitions() :: [Definition.t()]
  def definitions do
    for {name, unit, description} <- @gauges do
      %Definition{
        name: name,
        type: :gauge,
        unit: unit,
        description: description,
        attributes: @attributes
      }
    end
  end
end
