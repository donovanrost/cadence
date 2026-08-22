defmodule CadenceWeb.ApplicationInventoryLifecycle do
  @moduledoc """
  Shared LiveView event handling for host-owned application lifecycle actions.

  Inventory hosts decide whether an installation is eligible at their scope;
  this module resolves the packaged definition and delegates the durable
  lifecycle transition to the application-installation boundary.
  """

  alias Cadence.Applications.ApplicationInstallations
  alias Cadence.ExtensionCatalog
  alias Phoenix.LiveView
  alias Phoenix.LiveView.Socket

  @type install_decision :: :allowed | {:denied, binary()}
  @type refresh :: (Socket.t() -> Socket.t())

  @spec install(Socket.t(), binary(), install_decision(), refresh()) ::
          {:noreply, Socket.t()}
  def install(%Socket{} = socket, application_key, :allowed, refresh)
      when is_binary(application_key) and is_function(refresh, 1) do
    host_context = socket.assigns.application_host_context

    with {:ok, definition} <- ExtensionCatalog.fetch_available_application(application_key),
         true <- host_context.placement in definition.installable_scopes,
         {:ok, _installation} <-
           ApplicationInstallations.install(
             socket.assigns.current_scope,
             host_context,
             definition.application_key,
             application_version: definition.version
           ) do
      {:noreply,
       socket
       |> LiveView.put_flash(:info, "Application is available in the host workspace.")
       |> refresh.()}
    else
      false ->
        {:noreply,
         LiveView.put_flash(socket, :error, "Application is not available at this scope.")}

      {:error, reason} ->
        {:noreply,
         LiveView.put_flash(
           socket,
           :error,
           "Could not install application: #{inspect(reason)}"
         )}
    end
  end

  def install(%Socket{} = socket, _application_key, {:denied, message}, _refresh)
      when is_binary(message) do
    {:noreply, LiveView.put_flash(socket, :error, message)}
  end

  @spec disable(Socket.t(), binary(), refresh()) :: {:noreply, Socket.t()}
  def disable(%Socket{} = socket, application_key, refresh)
      when is_binary(application_key) and is_function(refresh, 1) do
    case ApplicationInstallations.disable(
           socket.assigns.current_scope,
           socket.assigns.application_host_context,
           application_key
         ) do
      {:ok, _installation} ->
        {:noreply,
         socket
         |> LiveView.put_flash(
           :info,
           "Application workspace disabled. Active runtime state is unchanged."
         )
         |> refresh.()}

      {:error, reason} ->
        {:noreply,
         LiveView.put_flash(
           socket,
           :error,
           "Could not disable application: #{inspect(reason)}"
         )}
    end
  end

  @spec uninstall(Socket.t(), binary(), refresh()) :: {:noreply, Socket.t()}
  def uninstall(%Socket{} = socket, application_key, refresh)
      when is_binary(application_key) and is_function(refresh, 1) do
    case ApplicationInstallations.uninstall(
           socket.assigns.current_scope,
           socket.assigns.application_host_context,
           application_key
         ) do
      {:ok, _installation} ->
        {:noreply,
         socket
         |> LiveView.put_flash(
           :info,
           "Application uninstalled. Its configuration and runtime state were preserved."
         )
         |> refresh.()}

      {:error, reason} ->
        {:noreply,
         LiveView.put_flash(
           socket,
           :error,
           "Could not uninstall application: #{inspect(reason)}"
         )}
    end
  end
end
