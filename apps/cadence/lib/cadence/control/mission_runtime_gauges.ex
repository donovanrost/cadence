defmodule Cadence.Control.MissionRuntimeGauges do
  @moduledoc """
  Per ACTIVE mission (one with an activation, whether or not its runtime runs here): the desired
  generation (the active activation's), the applied one (`MissionRuntimeStatus`, 0 when nothing is
  applied on this node or the reconciler isn't running) and whether it's admitted (applied ==
  desired). The mission health sampler emits them on its fixed interval as
  `cadence.mission_runtime.*` gauges; devops alerts on desired - applied != 0 for 2 min and on a
  missing applied series (director 11-17, after the calibration incident; U91).
  """

  alias Cadence.Control.{Activations, MissionRuntimeStatus}

  @type gauge :: %{
          mission_id: binary(),
          desired: non_neg_integer(),
          applied: non_neg_integer(),
          admitted: 0 | 1
        }

  @spec read() :: [gauge()]
  def read do
    for %{mission_id: mission_id, generation: desired} <- Activations.list_active_bases(),
        is_binary(mission_id) and is_integer(desired) do
      applied = applied(MissionRuntimeStatus.status(mission_id))

      %{
        mission_id: mission_id,
        desired: desired,
        applied: applied,
        admitted: if(applied == desired, do: 1, else: 0)
      }
    end
  end

  defp applied(%{applied_generation: generation}) when is_integer(generation), do: generation
  defp applied(_none), do: 0
end
