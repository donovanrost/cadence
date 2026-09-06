defmodule CadenceWeb.ApplicationManagement do
  @moduledoc "Host-owned optional application management, independent of federated releases."

  import Phoenix.Component, only: [assign: 3]
  alias Cadence.Applications.{HostContext, Registry}
  alias Cadence.Reads.ApplicationSurfaces
  alias CadenceWeb.{ApplicationInventory, ApplicationInventoryLifecycle}

  def load(socket) do
    {host, key, surface_id} = context(socket.assigns)
    socket = assign(socket, :application_host_context, host)

    with {:ok, definition} <- Registry.fetch_available(key),
         {:ok, surface} <- Registry.fetch_surface(definition, host.placement, surface_id),
         {:ok, %{"data" => %{"presentation" => presentation}}} <-
           ApplicationSurfaces.load(
             socket.assigns.current_scope,
             host,
             key,
             definition.version,
             surface
           ) do
      socket |> assign(:presentation, presentation) |> assign(:management_error, nil)
    else
      _error ->
        socket
        |> assign(:presentation, nil)
        |> assign(:management_error, "Application management could not be loaded.")
    end
  end

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
        {:denied, "Declare this application in the spacecraft profile before installing it."}
    end
  end

  defp install_decision(_socket, _key), do: :allowed

  defp context(%{current_mission: mission, current_spacecraft: spacecraft})
       when not is_nil(spacecraft) do
    {HostContext.spacecraft(mission.mission_id, spacecraft.spacecraft_id), "spacecraft",
     "applications"}
  end

  defp context(%{current_mission: mission}) do
    {HostContext.mission(mission.mission_id), "mission_catalog", "mission_applications"}
  end
end
