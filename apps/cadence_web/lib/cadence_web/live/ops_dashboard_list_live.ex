defmodule CadenceWeb.OpsDashboardListLive do
  @moduledoc """
  Ops console landing: pick a dashboard or create the first one. The nav
  rail is the primary switcher; this page is where you land before choosing.
  Rename/archive live on the dashboard itself.
  """
  use CadenceWeb, :live_view

  @impl true
  def mount(_params, _session, socket) do
    %{current_scope: scope, current_mission: mission} = socket.assigns

    {:ok,
     socket
     |> assign(:page_title, "Ops Dashboards")
     |> assign(
       :archived_dashboards,
       Cadence.Dashboards.list_archived_dashboard_summaries(
         scope.organization_id,
         mission.mission_id
       )
     )}
  end

  @impl true
  def handle_event("restore_dashboard", params, socket) do
    dashboard_id = params["dashboard-id"]
    %{current_scope: scope, current_mission: mission} = socket.assigns

    with {:ok, summary} <- validate_restore_available(socket, dashboard_id),
         {:ok, expected_version} <- restore_expected_version(params, summary),
         :ok <-
           Cadence.Dashboards.restore_document(
             scope.organization_id,
             mission.mission_id,
             dashboard_id,
             expected_version: expected_version,
             actor_id: current_user_id(scope)
           ) do
      {:noreply,
       socket
       |> assign_dashboard_lists()
       |> put_flash(:info, "Dashboard restored.")}
    else
      {:error, :dashboard_restore_not_available} ->
        {:noreply,
         socket
         |> assign_dashboard_lists()
         |> put_flash(:info, "Dashboard is already active.")}

      {:error, :dashboard_not_found} ->
        {:noreply,
         socket
         |> assign_dashboard_lists()
         |> put_flash(:error, "Dashboard not found.")}

      {:error, {:dashboard_version_conflict, current_version}} ->
        {:noreply,
         socket
         |> assign_dashboard_lists()
         |> put_flash(
           :error,
           "Dashboard changed in another session. Reloaded version #{current_version}; review and try again."
         )}

      {:error, reason} ->
        {:noreply, put_flash(socket, :error, "Failed to restore dashboard: #{inspect(reason)}")}
    end
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div id="ops-dashboards-page" class="flex-1 overflow-y-auto">
      <div class="mx-auto max-w-3xl px-6 pt-16">
        <h1 class="hud-label">Dashboards</h1>
        <p class="mt-1 text-sm text-base-content/70">
          Mission-shared telemetry screens. Widgets bind to dictionary points, so limit colors
          and staleness always match the alarm system.
        </p>

        <%= if @ops_dashboards == [] do %>
          <div class="mt-8">
            <.empty_state
              title="No dashboards"
              description="Create a dashboard to watch live telemetry across the constellation."
              action_label="Create the first dashboard"
              action_navigate={~p"/missions/#{@current_mission.mission_id}/ops/dashboards/new"}
            />
          </div>
        <% else %>
          <div class="mt-6 grid grid-cols-1 gap-4 sm:grid-cols-2">
            <.link
              :for={dashboard <- @ops_dashboards}
              id={"active-dashboard-#{dashboard.dashboard_id}"}
              navigate={
                ~p"/missions/#{@current_mission.mission_id}/ops/dashboards/#{dashboard.dashboard_id}"
              }
              data-dashboard-publication-state={dashboard_publication_state(dashboard)}
              data-dashboard-archive-available={
                dashboard_action_available_text(dashboard, :archive)
              }
              data-dashboard-restore-available={
                dashboard_action_available_text(dashboard, :restore)
              }
            >
              <.card hover_glow>
                <h2 class="text-sm font-semibold text-primary">{dashboard.name}</h2>
                <p :if={dashboard.description} class="mt-1 text-sm text-base-content/70 truncate">
                  {dashboard.description}
                </p>
                <p class="mt-2 font-mono text-xs text-base-content/60">
                  {dashboard.widget_count} widgets
                </p>
              </.card>
            </.link>
            <.link navigate={~p"/missions/#{@current_mission.mission_id}/ops/dashboards/new"}>
              <.card class="border-dashed">
                <p class="flex items-center gap-2 text-sm text-base-content/70">
                  <.icon name="hero-plus" class="h-4 w-4" /> New Dashboard
                </p>
              </.card>
            </.link>
          </div>
        <% end %>
        <div :if={@archived_dashboards != []} class="mt-8 border-t border-base-300/60 pt-5">
          <div class="flex items-center justify-between gap-3">
            <div>
              <h2 class="hud-label">Archived</h2>
              <p class="mt-1 text-sm text-base-content/60">
                Hidden from the ops rail until restored.
              </p>
            </div>
          </div>
          <div id="archived-dashboards" class="mt-3 divide-y divide-base-300/60 border border-base-300/60">
            <div
              :for={dashboard <- @archived_dashboards}
              id={"archived-dashboard-#{dashboard.dashboard_id}"}
              data-dashboard-publication-state={dashboard_publication_state(dashboard)}
              data-dashboard-archive-available={
                dashboard_action_available_text(dashboard, :archive)
              }
              data-dashboard-restore-available={
                dashboard_action_available_text(dashboard, :restore)
              }
              class="flex items-center gap-3 px-3 py-2"
            >
              <div class="min-w-0 flex-1">
                <p class="text-sm font-semibold truncate">{dashboard.name}</p>
                <p class="font-mono text-xs text-base-content/50">
                  {dashboard.widget_count} widgets · archived
                </p>
              </div>
              <.button
                id={"restore-dashboard-#{dashboard.dashboard_id}"}
                variant={:ghost}
                size={:xs}
                phx-click="restore_dashboard"
                phx-value-dashboard-id={dashboard.dashboard_id}
                phx-value-expected-version={dashboard.latest_version}
                disabled={not dashboard_action_available?(dashboard, :restore)}
                data-dashboard-lifecycle-action="restore"
                data-dashboard-action-available={
                  dashboard_action_available_text(dashboard, :restore)
                }
              >
                <.icon name="hero-arrow-uturn-left" class="h-3.5 w-3.5" /> Restore
              </.button>
            </div>
          </div>
        </div>
      </div>
    </div>
    """
  end

  defp assign_dashboard_lists(socket) do
    %{current_scope: scope, current_mission: mission} = socket.assigns

    socket
    |> assign(
      :ops_dashboards,
      Cadence.Dashboards.list_dashboard_summaries(scope.organization_id, mission.mission_id)
    )
    |> assign(
      :archived_dashboards,
      Cadence.Dashboards.list_archived_dashboard_summaries(
        scope.organization_id,
        mission.mission_id
      )
    )
  end

  defp validate_restore_available(socket, dashboard_id) when is_binary(dashboard_id) do
    case dashboard_summary(socket, dashboard_id) do
      nil ->
        {:error, :dashboard_not_found}

      summary ->
        if dashboard_action_available?(summary, :restore),
          do: {:ok, summary},
          else: {:error, :dashboard_restore_not_available}
    end
  end

  defp dashboard_summary(socket, dashboard_id) do
    socket.assigns.ops_dashboards
    |> Kernel.++(socket.assigns.archived_dashboards)
    |> Enum.find(&(&1.dashboard_id == dashboard_id))
  end

  defp restore_expected_version(%{"expected-version" => version}, _summary)
       when is_binary(version) do
    case Integer.parse(version) do
      {version, ""} when version > 0 -> {:ok, version}
      _invalid -> {:error, :invalid_dashboard_version}
    end
  end

  defp restore_expected_version(_params, summary), do: {:ok, summary.latest_version}

  defp dashboard_publication_state(summary) do
    summary
    |> dashboard_lifecycle_status()
    |> Map.fetch!(:publication_state)
    |> Atom.to_string()
  end

  defp dashboard_action_available?(summary, :archive) do
    summary
    |> dashboard_lifecycle_status()
    |> Map.fetch!(:archive_available?)
  end

  defp dashboard_action_available?(summary, :restore) do
    summary
    |> dashboard_lifecycle_status()
    |> Map.fetch!(:restore_available?)
  end

  defp dashboard_action_available_text(summary, action) do
    if dashboard_action_available?(summary, action), do: "true", else: "false"
  end

  defp dashboard_lifecycle_status(summary) do
    Cadence.Dashboards.dashboard_lifecycle_status(summary)
  end

  defp current_user_id(%{user: %{user_id: user_id}}) when is_binary(user_id), do: user_id
  defp current_user_id(_scope), do: nil
end
