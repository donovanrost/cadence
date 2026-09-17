defmodule CadenceWeb.ApplicationManagement do
  @moduledoc "Host-owned optional application management, independent of federated releases."

  import Phoenix.Component, only: [assign: 3]
  alias Cadence.Applications.HostContext
  alias Cadence.Reads.Applications.Installations
  alias CadenceWeb.{ApplicationInventory, ApplicationInventoryLifecycle}

  def load(socket) do
    host = context(socket.assigns)
    socket = assign(socket, :application_host_context, host)

    case Installations.load(socket.assigns.current_scope, host) do
      {:ok, %{"presentation" => presentation}} ->
        socket |> assign(:presentation, presentation) |> assign(:management_error, nil)

      _error ->
        socket
        |> assign(:presentation, nil)
        |> assign(:management_error, "Application management could not be loaded.")
    end
  end

  def snapshot(%{application_host_context: %HostContext{placement: placement}} = assigns) do
    %{
      version: 1,
      scope: to_string(placement),
      status: if(assigns[:presentation], do: "ready", else: "unavailable"),
      data: assigns[:presentation]
    }
  end

  def snapshot(_assigns), do: nil

  def handle_event(event, %{"key" => key}, socket)
      when event in ["install", "disable", "uninstall"] and is_binary(key) do
    case event do
      "install" ->
        ApplicationInventoryLifecycle.install(socket, key, install_decision(socket, key), &load/1)

      "disable" ->
        ApplicationInventoryLifecycle.disable(socket, key, &load/1)

      "uninstall" ->
        ApplicationInventoryLifecycle.uninstall(socket, key, &load/1)
    end
  end

  def handle_event(_event, _params, socket), do: {:noreply, socket}

  defp install_decision(%{assigns: %{current_spacecraft: spacecraft} = assigns}, key)
       when not is_nil(spacecraft) do
    with {:ok, items} <- ApplicationInventory.spacecraft(assigns.current_scope, spacecraft),
         true <- Enum.any?(items, &(&1.application_key == key and &1.installable?)) do
      :allowed
    else
      _denied ->
        {:denied, "This application is not available for this spacecraft."}
    end
  end

  defp install_decision(_socket, _key), do: :allowed

  defp context(%{current_mission: mission, current_spacecraft: spacecraft})
       when not is_nil(spacecraft) do
    HostContext.spacecraft(mission.mission_id, spacecraft.spacecraft_id)
  end

  defp context(%{current_mission: mission}) do
    HostContext.mission(mission.mission_id)
  end
end
