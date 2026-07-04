defmodule CadenceWeb.OpsDashboardShowLive.MountFlow do
  @moduledoc false

  import Phoenix.LiveView, only: [put_flash: 3, push_navigate: 2]

  alias CadenceWeb.OpsDashboardShowLive.DocumentLifecycle
  alias CadenceWeb.OpsDashboardShowLive.MountState
  alias CadenceWeb.OpsDashboardShowLive.RuntimeShell

  def mount_dashboard(socket, dashboard_id, connected?, opts \\ []) do
    %{current_scope: scope, current_mission: mission} = socket.assigns

    case fetch_operator_document_fn(opts).(scope, mission, dashboard_id) do
      {:ok, document, document_mode} ->
        socket =
          assign_loaded_dashboard_fn(opts).(socket, scope, mission, document, document_mode)

        {:ok,
         activate_runtime_fn(opts).(
           socket,
           scope,
           mission,
           document,
           connected?,
           runtime_shell_opts(opts)
         )}

      {:error, reason} ->
        {:ok, handle_load_error(socket, reason, opts)}
    end
  end

  defp handle_load_error(socket, :dashboard_not_found, opts) do
    socket
    |> put_flash(:error, "Dashboard not found.")
    |> push_navigate(to: dashboard_list_path(opts, socket))
  end

  defp handle_load_error(socket, :dashboard_archived, opts) do
    socket
    |> put_flash(:error, "Dashboard is archived.")
    |> push_navigate(to: dashboard_list_path(opts, socket))
  end

  defp handle_load_error(socket, reason, opts) do
    socket
    |> put_flash(:error, "Failed to load dashboard: #{inspect(reason)}")
    |> push_navigate(to: dashboard_list_path(opts, socket))
  end

  defp fetch_operator_document_fn(opts) do
    Keyword.get(opts, :fetch_operator_document, &DocumentLifecycle.fetch_operator_document/3)
  end

  defp assign_loaded_dashboard_fn(opts) do
    Keyword.get(opts, :assign_loaded_dashboard, &MountState.assign_loaded_dashboard/5)
  end

  defp activate_runtime_fn(opts) do
    Keyword.get(opts, :activate_runtime, &RuntimeShell.activate/6)
  end

  defp runtime_shell_opts(opts), do: Keyword.get(opts, :runtime_shell_opts, [])

  defp dashboard_list_path(opts, socket) do
    opts
    |> Keyword.fetch!(:dashboard_list_path)
    |> then(& &1.(socket))
  end
end
