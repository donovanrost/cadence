defmodule CadenceWeb.OpsDashboardShareLive do
  @moduledoc false
  use CadenceWeb, :live_view

  alias Cadence.Dashboards.Management

  @impl true
  def mount(%{"share_id" => share_id}, _session, socket) do
    %{current_scope: scope, current_mission: mission} = socket.assigns

    case Management.fetch_active_share(scope.organization_id, mission.mission_id, share_id) do
      {:ok, share} ->
        dashboard_path = dashboard_path(mission.mission_id, share)

        {:ok,
         socket
         |> assign(:page_title, "Shared Dashboard")
         |> assign(:ops_nav_item, :dashboards)
         |> assign(:active_dashboard_id, share.dashboard_id)
         |> assign(:dashboard_share, share)
         |> assign(:dashboard_path, dashboard_path)
         |> assign(:dashboard_share_props, dashboard_share_dto(mission, share, dashboard_path))}

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
      <.vue
        id="ops-dashboard-share-component"
        v-component="FederatedFullPageSurface"
        share={@dashboard_share_props}
        v-ssr={false}
        class="h-full"
      />
    </Layouts.app>
    """
  end

  defp dashboard_share_dto(mission, share, dashboard_path) do
    %{
      id: "dashboard-share-page",
      eyebrow: "Authenticated mission share",
      title: "Dashboard context is ready",
      restriction: %{
        prefix: "This link is restricted to members of #{mission.display_name}. It declares",
        visibility_id: "dashboard-share-visibility",
        visibility: share.data_visibility,
        suffix: "and opens the dashboard with the captured operational selectors."
      },
      context: %{
        id: "dashboard-share-context",
        entries:
          share.runtime_context
          |> Enum.sort()
          |> Enum.map(fn {key, value} -> %{key: to_string(key), value: to_string(value)} end)
      },
      action: %{
        id: "dashboard-share-open-dashboard",
        label: "Open live dashboard",
        href: dashboard_path
      }
    }
  end

  defp dashboard_path(mission_id, share) do
    base = "/missions/#{mission_id}/ops/dashboards/#{share.dashboard_id}"
    query = share.runtime_context |> Enum.sort() |> URI.encode_query()
    if query == "", do: base, else: base <> "?" <> query
  end
end
