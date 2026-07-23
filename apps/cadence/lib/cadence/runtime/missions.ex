defmodule Cadence.Runtime.Missions do
  @moduledoc """
  Public data-plane command and observation boundary for mission generations.
  """

  alias Cadence.Runtime
  alias Cadence.Runtime.GenerationApplied
  alias Cadence.Runtime.MissionCoordinator
  alias Cadence.Runtime.MissionRuntimeSpec

  @spec apply(MissionRuntimeSpec.t()) :: {:ok, GenerationApplied.t()} | {:error, term()}
  def apply(%MissionRuntimeSpec{} = spec) do
    if Process.whereis(Cadence.Runtime.MissionSupervisor) do
      with {:ok, _mission_runtime} <- Runtime.ensure_mission_started(spec.mission_id) do
        MissionCoordinator.apply_spec(spec)
      end
    else
      {:error, :data_plane_not_running}
    end
  end

  @spec applied_spec(binary()) :: {:ok, MissionRuntimeSpec.t()} | {:error, term()}
  def applied_spec(mission_id) when is_binary(mission_id) do
    if mission_id in Runtime.running_mission_ids() do
      MissionCoordinator.active_spec(mission_id)
    else
      {:error, :mission_runtime_not_running}
    end
  end
end
