defmodule Cadence.Runtime.Missions.MissionSupervisor do
  @moduledoc """
  Dynamic supervisor for managing individual mission supervision trees.

  Each mission gets its own isolated supervision tree containing:
  - Current Value Table (CVT) process
  - Interface supervisors (TCP/UDP/Serial)
  - Telemetry pipeline processors
  - Command queue manager
  - Limits monitor

  This ensures complete runtime isolation between missions - if one mission
  crashes, it doesn't affect others.

  ## Data Plane

  This module is part of the Data Plane - it manages runtime processes and
  does not make database calls. Configuration is received via domain entities
  or PubSub events.
  """

  use DynamicSupervisor

  require Logger

  # Accept both Ecto schema and domain entity for backwards compatibility
  alias Cadence.Missions.Mission
  alias Cadence.Domain.Missions.Entities.Mission, as: MissionEntity

  def start_link(init_arg) do
    DynamicSupervisor.start_link(__MODULE__, init_arg, name: __MODULE__)
  end

  @impl true
  def init(_init_arg) do
    DynamicSupervisor.init(strategy: :one_for_one)
  end

  @doc """
  Starts a mission's supervision tree.

  Accepts either an Ecto schema or a domain entity.
  Returns `{:ok, pid}` on success or `{:error, reason}` on failure.
  """
  def start_mission(%Mission{} = mission) do
    do_start_mission(mission.id, mission.name, mission)
  end

  def start_mission(%MissionEntity{} = entity) do
    # Convert domain entity to a map that MissionInstance can use
    do_start_mission(entity.id, entity.name, entity)
  end

  defp do_start_mission(mission_id, _mission_name, mission_data) do
    Logger.info("Starting mission supervision tree for mission_id=#{mission_id}")

    child_spec = {
      Cadence.Runtime.Missions.MissionInstance,
      mission: mission_data
    }

    case DynamicSupervisor.start_child(__MODULE__, child_spec) do
      {:ok, pid} = result ->
        Logger.info(
          "Mission supervision tree started successfully for mission_id=#{mission_id}, pid=#{inspect(pid)}"
        )

        result

      {:error, {:already_started, pid}} ->
        Logger.warning(
          "Mission supervision tree already running for mission_id=#{mission_id}, pid=#{inspect(pid)}"
        )

        {:ok, pid}

      {:error, reason} = error ->
        Logger.error(
          "Failed to start mission supervision tree for mission_id=#{mission_id}, reason=#{inspect(reason)}"
        )

        error
    end
  end

  @doc """
  Stops a mission's supervision tree.
  """
  def stop_mission(mission_id) when is_binary(mission_id) do
    Logger.info("Stopping mission supervision tree for mission_id=#{mission_id}")

    case Registry.lookup(Cadence.MissionRegistry, mission_id) do
      [{pid, _}] ->
        DynamicSupervisor.terminate_child(__MODULE__, pid)

      [] ->
        Logger.warning("No mission supervision tree found for mission_id=#{mission_id}")
        {:error, :not_found}
    end
  end

  @doc """
  Lists all running missions.
  """
  def list_running_missions do
    DynamicSupervisor.which_children(__MODULE__)
    |> Enum.map(fn {_id, pid, _type, _modules} -> pid end)
  end

  @doc """
  Gets the PID of a running mission by ID.
  """
  def get_mission_pid(mission_id) when is_binary(mission_id) do
    case Registry.lookup(Cadence.MissionRegistry, mission_id) do
      [{pid, _}] -> {:ok, pid}
      [] -> {:error, :not_found}
    end
  end
end

