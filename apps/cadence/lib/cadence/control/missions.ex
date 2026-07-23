defmodule Cadence.Control.Missions do
  @moduledoc "Public Control-plane lifecycle boundary for mission control owners."

  alias Cadence.Control.MissionRuntime

  @spec ensure_started(binary()) :: {:ok, pid()} | {:error, term()}
  def ensure_started(mission_id) when is_binary(mission_id) do
    child_spec =
      Supervisor.child_spec({MissionRuntime, mission_id},
        id: {:mission_control_runtime, mission_id}
      )

    case DynamicSupervisor.start_child(Cadence.Control.MissionSupervisor, child_spec) do
      {:ok, pid} -> {:ok, pid}
      {:error, {:already_started, pid}} -> {:ok, pid}
      {:error, {:already_present, _child_spec}} -> lookup(mission_id)
      {:error, reason} -> {:error, reason}
    end
  end

  @spec stop(binary()) :: :ok | {:error, term()}
  def stop(mission_id) when is_binary(mission_id) do
    case lookup(mission_id) do
      {:ok, pid} -> DynamicSupervisor.terminate_child(Cadence.Control.MissionSupervisor, pid)
      {:error, :mission_control_not_running} -> :ok
    end
  end

  @spec running_mission_ids() :: [binary()]
  def running_mission_ids do
    case Process.whereis(Cadence.Control.Registry) do
      nil ->
        []

      _registry ->
        Cadence.Control.Registry
        |> Registry.select([
          {{{:mission_control_runtime, :"$1"}, :"$2", :_}, [], [{{:"$1", :"$2"}}]}
        ])
        |> Enum.filter(fn {_mission_id, pid} -> Process.alive?(pid) end)
        |> Enum.map(fn {mission_id, _pid} -> mission_id end)
        |> Enum.sort()
    end
  rescue
    ArgumentError -> []
  catch
    :exit, _reason -> []
  end

  defp lookup(mission_id) do
    case Registry.lookup(Cadence.Control.Registry, {:mission_control_runtime, mission_id}) do
      [{pid, _value}] -> {:ok, pid}
      [] -> {:error, :mission_control_not_running}
    end
  end
end
