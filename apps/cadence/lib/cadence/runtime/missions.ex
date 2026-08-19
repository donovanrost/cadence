defmodule Cadence.Runtime.Missions do
  @moduledoc """
  Public data-plane command and observation boundary for mission generations.
  """

  import Kernel, except: [apply: 2]

  alias Cadence.Runtime
  alias Cadence.Runtime.GenerationApplied
  alias Cadence.Runtime.MissionCoordinator
  alias Cadence.Runtime.MissionRuntimeSpec
  alias Cadence.Runtime.ProcessNamespace

  @spec apply(MissionRuntimeSpec.t()) :: {:ok, GenerationApplied.t()} | {:error, term()}
  def apply(%MissionRuntimeSpec{} = spec) do
    apply(ProcessNamespace.default(), spec)
  end

  @spec apply(ProcessNamespace.t(), MissionRuntimeSpec.t()) ::
          {:ok, GenerationApplied.t()} | {:error, term()}
  def apply(%ProcessNamespace{} = process_namespace, %MissionRuntimeSpec{} = spec) do
    if Process.whereis(process_namespace.mission_supervisor) do
      with {:ok, _mission_runtime} <-
             Runtime.ensure_mission_started(process_namespace, spec.mission_id) do
        MissionCoordinator.apply_spec(process_namespace, spec)
      end
    else
      {:error, :data_plane_not_running}
    end
  end

  @spec applied_spec(binary()) :: {:ok, MissionRuntimeSpec.t()} | {:error, term()}
  def applied_spec(mission_id) when is_binary(mission_id) do
    applied_spec(ProcessNamespace.default(), mission_id)
  end

  @spec applied_spec(ProcessNamespace.t(), binary()) ::
          {:ok, MissionRuntimeSpec.t()} | {:error, term()}
  def applied_spec(%ProcessNamespace{} = process_namespace, mission_id)
      when is_binary(mission_id) do
    if mission_id in Runtime.running_mission_ids(process_namespace) do
      MissionCoordinator.active_spec(process_namespace, mission_id)
    else
      {:error, :mission_runtime_not_running}
    end
  end
end
