defmodule Cadence.RuntimeTestSupport do
  @moduledoc false

  alias Cadence.Contacts.ContactSettler
  alias Cadence.Control.Missions, as: ControlMissions
  alias Cadence.Telemetry.CurrentValueStore
  alias Cadence.Telemetry.CurrentValueStore.ETS

  def prepare_default_runtime do
    Cadence.DataCase.ensure_cadence_started!()
    stop_default_runtime_instances()
  end

  def cleanup_default_runtime do
    stop_default_runtime_instances()
    stop_default_contact_settlers()

    if Cadence.DataCase.telemetry_current_value_store_module() == ETS do
      CurrentValueStore.reset()
    end

    :ok
  end

  defp stop_default_runtime_instances do
    ControlMissions.running_mission_ids()
    |> Enum.each(&ControlMissions.stop/1)

    Cadence.Runtime.stop_all_missions()
  end

  defp stop_default_contact_settlers do
    case GenServer.whereis(ContactSettler.supervisor_name()) do
      nil ->
        :ok

      supervisor ->
        supervisor
        |> DynamicSupervisor.which_children()
        |> Enum.each(&terminate_settler_child(supervisor, &1))
    end
  end

  defp terminate_settler_child(supervisor, {_, child, _, _}) when is_pid(child) do
    # A settler may finish between the snapshot and termination.
    case DynamicSupervisor.terminate_child(supervisor, child) do
      :ok -> :ok
      {:error, :not_found} -> :ok
    end
  end

  defp terminate_settler_child(_supervisor, _not_running), do: :ok
end
