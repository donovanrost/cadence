defmodule Cadence.Control.MissionRuntime do
  @moduledoc false

  use Supervisor

  def start_link(mission_id) when is_binary(mission_id) do
    Supervisor.start_link(__MODULE__, mission_id, name: runtime_name(mission_id))
  end

  @impl true
  def init(mission_id) do
    children =
      [
        {Cadence.Control.MissionRuntimeReconciler, mission_id: mission_id},
        contact_scheduler_child(mission_id)
      ]
      |> Enum.reject(&is_nil/1)

    Supervisor.init(children, strategy: :one_for_one)
  end

  @spec runtime_name(binary()) :: {:via, Registry, {module(), term()}}
  def runtime_name(mission_id) do
    {:via, Registry, {Cadence.Control.Registry, {:mission_control_runtime, mission_id}}}
  end

  @spec contact_scheduler_name(binary()) :: {:via, Registry, {module(), term()}}
  def contact_scheduler_name(mission_id) do
    {:via, Registry, {Cadence.Control.Registry, {:contact_scheduler, mission_id}}}
  end

  @spec reconciler_name(binary()) :: {:via, Registry, {module(), term()}}
  def reconciler_name(mission_id) do
    {:via, Registry, {Cadence.Control.Registry, {:mission_runtime_reconciler, mission_id}}}
  end

  defp contact_scheduler_child(mission_id) do
    contact_scheduler_config = Application.get_env(:cadence, :contact_scheduler, [])

    if Keyword.get(contact_scheduler_config, :enabled, true) do
      {Cadence.Contacts.Scheduler,
       contact_scheduler_config
       |> Keyword.put(:mission_id, mission_id)
       |> Keyword.put(:name, contact_scheduler_name(mission_id))}
    end
  end
end
