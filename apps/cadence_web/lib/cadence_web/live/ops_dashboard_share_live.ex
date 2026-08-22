defmodule CadenceWeb.OpsDashboardShareLive do
  @moduledoc false
  use CadenceWeb, :live_view

  alias Cadence.Dashboards.Management

  @impl true
  def mount(%{"share_id" => share_id}, _session, socket) do
    %{current_scope: scope, current_mission: mission} = socket.assigns

    case Management.fetch_active_share(scope.organization_id, mission.mission_id, share_id) do
      {:ok, share} ->
        {:ok,
         socket
         |> assign(:page_title, "Shared Dashboard")
         |> assign(:ops_nav_item, :dashboards)
         |> assign(:active_dashboard_id, share.dashboard_id)
         |> assign(:dashboard_share, share)
         |> assign(:dashboard_path, dashboard_path(mission.mission_id, share))}

      {:error, reason} ->
        {:ok,
         socket
         |> put_flash(:error, "Dashboard share is unavailable: #{inspect(reason)}")
         |> push_navigate(to: ~p"/missions/#{mission.mission_id}/ops/dashboards")}
    end
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_scope}>
      <section id="dashboard-share-page" class="h-full overflow-y-auto bg-base-100 p-6">
        <div class="mx-auto max-w-3xl border border-primary/30 bg-base-200/30 p-6">
          <p class="hud-label">Authenticated mission share</p>
          <h1 class="mt-2 text-2xl font-semibold">Dashboard context is ready</h1>
          <p class="mt-3 text-sm text-base-content/65">
            This link is restricted to members of {@current_mission.display_name}. It declares
            <span id="dashboard-share-visibility" class="font-mono">{@dashboard_share.data_visibility}</span>
            and opens the dashboard with the captured operational selectors.
          </p>
          <dl id="dashboard-share-context" class="mt-5 grid gap-2 text-xs sm:grid-cols-2">
            <div :for={{key, value} <- Enum.sort(@dashboard_share.runtime_context)} class="border border-base-300 bg-base-100 p-2">
              <dt class="font-mono uppercase text-base-content/45">{key}</dt>
              <dd class="mt-1 break-all">{value}</dd>
            </div>
          </dl>
          <.link id="dashboard-share-open-dashboard" navigate={@dashboard_path} class="btn btn-primary mt-6">
            Open live dashboard
          </.link>
        </div>
      </section>
    </Layouts.app>
    """
  end

  defp dashboard_path(mission_id, share) do
    base = "/missions/#{mission_id}/ops/dashboards/#{share.dashboard_id}"
    query = URI.encode_query(share.runtime_context)
    if query == "", do: base, else: base <> "?" <> query
  end
end
