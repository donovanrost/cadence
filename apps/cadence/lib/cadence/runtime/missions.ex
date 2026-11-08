defmodule Cadence.Runtime.Missions do
  @moduledoc """
  Public data-plane command and observation boundary for mission generations.
  """

  import Kernel, except: [apply: 2]

  alias Cadence.Platform.Drain
  alias Cadence.Runtime
  alias Cadence.Runtime.GenerationApplied
  alias Cadence.Runtime.MissionCoordinator
  alias Cadence.Runtime.MissionRuntime
  alias Cadence.Runtime.MissionRuntimeSpec
  alias Cadence.Runtime.ProcessNamespace

  @spec apply(MissionRuntimeSpec.t()) :: {:ok, GenerationApplied.t()} | {:error, term()}
  def apply(%MissionRuntimeSpec{} = spec) do
    apply(ProcessNamespace.default(), spec)
  end

  @spec apply(ProcessNamespace.t(), MissionRuntimeSpec.t()) ::
          {:ok, GenerationApplied.t()} | {:error, term()}
  def apply(%ProcessNamespace{} = process_namespace, %MissionRuntimeSpec{} = spec) do
    cond do
      Drain.draining?() ->
        {:error, :cadence_draining}

      Process.whereis(process_namespace.mission_supervisor) ->
        with {:ok, _mission_runtime} <-
               Runtime.ensure_mission_started(process_namespace, spec.mission_id) do
          MissionCoordinator.apply_spec(process_namespace, spec)
        end

      true ->
        {:error, :data_plane_not_running}
    end
  end

  @doc "Observes the last fully applied generation; use rollout_status/2 for current convergence."
  def applied_summary(mission_id) when is_binary(mission_id),
    do: applied_summary(ProcessNamespace.default(), mission_id)

  def applied_summary(%ProcessNamespace{} = process_namespace, mission_id) do
    if mission_id in Runtime.running_mission_ids(process_namespace) do
      GenServer.call(
        MissionRuntime.coordinator_name(process_namespace, mission_id),
        :applied_summary
      )
    else
      {:error, :mission_runtime_not_running}
    end
  end

  @doc "Reports desired generation and partition convergence without implying atomic cutover."
  def rollout_status(mission_id), do: rollout_status(ProcessNamespace.default(), mission_id)

  def rollout_status(%ProcessNamespace{} = namespace, mission_id) do
    GenServer.call(MissionRuntime.coordinator_name(namespace, mission_id), :rollout_status)
  end

  @doc "Confirms exact application, waiting for matching work and detecting runtime loss."
  def confirm_applied(%ProcessNamespace{} = process_namespace, mission_id, identity) do
    if Process.whereis(process_namespace.registry) do
      GenServer.call(
        MissionRuntime.coordinator_name(process_namespace, mission_id),
        {:applied_identity, identity},
        :infinity
      )
    else
      :apply_required
    end
  catch
    :exit, {reason, _details} when reason in [:noproc, :normal, :shutdown] -> :apply_required
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
