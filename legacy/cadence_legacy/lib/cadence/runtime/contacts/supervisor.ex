defmodule Cadence.Runtime.Contacts.Supervisor do
  @moduledoc """
  DynamicSupervisor for per-contact runtime workers in a mission.
  """

  use DynamicSupervisor

  alias Cadence.Runtime.Contacts.ContactRuntime

  @registry Cadence.MissionRegistry

  def start_link(opts) do
    mission_id = Keyword.fetch!(opts, :mission_id)
    DynamicSupervisor.start_link(__MODULE__, mission_id, name: via_tuple(mission_id))
  end

  @impl true
  def init(_mission_id) do
    DynamicSupervisor.init(strategy: :one_for_one)
  end

  @spec start_contact(String.t(), keyword()) :: DynamicSupervisor.on_start_child()
  def start_contact(mission_id, opts) do
    case whereis(mission_id) do
      nil -> {:error, :not_running}
      pid -> DynamicSupervisor.start_child(pid, {ContactRuntime, opts})
    end
  end

  @spec stop_contact(String.t(), String.t()) :: :ok | {:error, :not_found}
  def stop_contact(mission_id, contact_id) do
    case {whereis(mission_id), ContactRuntime.whereis(mission_id, contact_id)} do
      {nil, _} -> {:error, :not_found}
      {_, nil} -> :ok
      {sup_pid, child_pid} -> DynamicSupervisor.terminate_child(sup_pid, child_pid)
    end
  end

  defp whereis(mission_id) do
    case Registry.lookup(@registry, {:contact_supervisor, mission_id}) do
      [{pid, _}] -> pid
      [] -> nil
    end
  end

  defp via_tuple(mission_id) do
    {:via, Registry, {@registry, {:contact_supervisor, mission_id}}}
  end
end
