defmodule Cadence.Control.Missions do
  @moduledoc "Public Control-plane lifecycle boundary for mission control owners."

  alias Cadence.Contacts.Scheduler
  alias Cadence.Control.MissionRuntime
  alias Cadence.Control.MissionRuntimeReconciler
  alias Cadence.Control.ProcessNamespace

  @spec ensure_started(binary()) :: {:ok, pid()} | {:error, term()}
  def ensure_started(mission_id) when is_binary(mission_id),
    do: ensure_started(ProcessNamespace.default(), mission_id)

  @spec ensure_started(ProcessNamespace.t(), binary()) :: {:ok, pid()} | {:error, term()}
  def ensure_started(%ProcessNamespace{} = process_namespace, mission_id)
      when is_binary(mission_id) do
    child_spec =
      Supervisor.child_spec({MissionRuntime, mission_id},
        id: {:mission_control_runtime, mission_id}
      )

    case DynamicSupervisor.start_child(process_namespace.mission_supervisor, child_spec) do
      {:ok, pid} -> {:ok, pid}
      {:error, {:already_started, pid}} -> {:ok, pid}
      {:error, {:already_present, _child_spec}} -> lookup(process_namespace, mission_id)
      {:error, reason} -> {:error, reason}
    end
  end

  @spec stop(binary()) :: :ok | {:error, term()}
  def stop(mission_id) when is_binary(mission_id),
    do: stop(ProcessNamespace.default(), mission_id)

  @spec stop(ProcessNamespace.t(), binary()) :: :ok | {:error, term()}
  def stop(%ProcessNamespace{} = process_namespace, mission_id) when is_binary(mission_id) do
    case lookup(process_namespace, mission_id) do
      {:ok, pid} ->
        with {:ok, _settlement} <- await_settled(process_namespace, mission_id) do
          DynamicSupervisor.terminate_child(process_namespace.mission_supervisor, pid)
        end

      {:error, :mission_control_not_running} ->
        :ok
    end
  end

  @doc """
  Waits for every mission-control child to finish work already in progress.

  Future safety and contact wakeup timers may remain scheduled. Callers can use
  this boundary before reconfiguration or shutdown without knowing the child
  process topology.
  """
  @spec await_settled(binary()) :: {:ok, map()} | {:error, term()}
  def await_settled(mission_id) when is_binary(mission_id),
    do: await_settled(ProcessNamespace.default(), mission_id)

  @spec await_settled(ProcessNamespace.t(), binary()) :: {:ok, map()} | {:error, term()}
  def await_settled(%ProcessNamespace{} = process_namespace, mission_id)
      when is_binary(mission_id) do
    with {:ok, _mission_control_runtime} <- lookup(process_namespace, mission_id),
         {:ok, reconciler} <-
           MissionRuntimeReconciler.await_settled(process_namespace, mission_id),
         {:ok, contact_scheduler} <- await_contact_scheduler(process_namespace, mission_id) do
      {:ok,
       %{
         status: :settled,
         mission_id: mission_id,
         reconciler: reconciler,
         contact_scheduler: contact_scheduler
       }}
    end
  end

  @spec running_mission_ids() :: [binary()]
  def running_mission_ids, do: running_mission_ids(ProcessNamespace.default())

  @spec running_mission_ids(ProcessNamespace.t()) :: [binary()]
  def running_mission_ids(%ProcessNamespace{} = process_namespace) do
    case Process.whereis(process_namespace.registry) do
      nil ->
        []

      _registry ->
        process_namespace.registry
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

  defp lookup(process_namespace, mission_id) do
    case Registry.lookup(process_namespace.registry, {:mission_control_runtime, mission_id}) do
      [{pid, _value}] -> {:ok, pid}
      [] -> {:error, :mission_control_not_running}
    end
  end

  defp await_contact_scheduler(process_namespace, mission_id) do
    server = MissionRuntime.contact_scheduler_name(process_namespace, mission_id)

    case GenServer.whereis(server) do
      pid when is_pid(pid) -> Scheduler.await_settled(server)
      nil -> {:ok, :disabled}
    end
  end
end
