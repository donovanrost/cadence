defmodule CadenceWeb.OpsDashboardSnapshotLive do
  @moduledoc false
  use CadenceWeb, :live_view

  alias Cadence.Dashboards.{Document, Management}

  @impl true
  def mount(%{"snapshot_id" => snapshot_id}, _session, socket) do
    %{current_scope: scope, current_mission: mission} = socket.assigns

    case Management.fetch_snapshot(scope.organization_id, mission.mission_id, snapshot_id) do
      {:ok, snapshot} ->
        document = Document.from_map(snapshot.document)

        {:ok,
         socket
         |> assign(:page_title, "#{document.name} Snapshot")
         |> assign(:ops_nav_item, :dashboards)
         |> assign(:active_dashboard_id, snapshot.dashboard_id)
         |> assign(:dashboard_snapshot, snapshot)
         |> assign(:snapshot_document, document)}

      {:error, reason} ->
        {:ok,
         socket
         |> put_flash(:error, "Dashboard snapshot is unavailable: #{inspect(reason)}")
         |> push_navigate(to: ~p"/missions/#{mission.mission_id}/ops/dashboards")}
    end
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_scope}>
      <section id="dashboard-snapshot-page" class="h-full overflow-y-auto bg-base-100 p-6">
        <div class="mx-auto max-w-4xl space-y-5">
          <header class="border border-primary/30 bg-base-200/30 p-6">
            <p class="hud-label">Read-only snapshot</p>
            <h1 class="mt-2 text-2xl font-semibold">{@snapshot_document.name}</h1>
            <p id="dashboard-snapshot-policy" class="mt-2 text-sm text-base-content/60">
              Definition version {@dashboard_snapshot.dashboard_version} · {@dashboard_snapshot.data_semantics} · {@dashboard_snapshot.data_visibility}
            </p>
            <p class="mt-3 text-xs text-warning">
              The definition and selectors are immutable. Runtime values are only visible through
              the declared data policy and may still reflect current data when the time window was not frozen.
            </p>
          </header>
          <section id="dashboard-snapshot-definition" class="grid gap-3 sm:grid-cols-3">
            <div class="border border-base-300 p-4"><p class="hud-label">Widgets</p><p class="mt-2 text-xl font-semibold">{length(@snapshot_document.placements)}</p></div>
            <div class="border border-base-300 p-4"><p class="hud-label">Captured selectors</p><p class="mt-2 text-xl font-semibold">{map_size(@dashboard_snapshot.runtime_context)}</p></div>
            <div class="border border-base-300 p-4"><p class="hud-label">Schema</p><p class="mt-2 text-xl font-semibold">v{@snapshot_document.schema_version}</p></div>
          </section>
          <.link id="dashboard-snapshot-open-current" navigate={~p"/missions/#{@current_mission.mission_id}/ops/dashboards/#{@dashboard_snapshot.dashboard_id}"} class="btn btn-outline">
            Open current dashboard
          </.link>
        </div>
      </section>
    </Layouts.app>
    """
  end
end
