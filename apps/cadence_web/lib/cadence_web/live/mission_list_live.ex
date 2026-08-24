defmodule CadenceWeb.MissionListLive do
  @moduledoc false
  use CadenceWeb, :live_view

  @impl true
  def mount(_params, _session, socket) do
    organization_id = socket.assigns.current_scope.organization_id
    mission_rows = load_mission_rows(organization_id)
    mission_table_rows = Enum.map(mission_rows, &mission_table_row/1)

    {:ok,
     socket
     |> assign(:page_title, "Missions")
     |> assign(:nav_item, :missions)
     |> assign(:mission_rows, mission_rows)
     |> assign(:mission_table_rows, mission_table_rows)}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="space-y-6">
      <.page_header title="Missions" eyebrow="Organization">
        <:title_suffix>{length(@mission_rows)} configured</:title_suffix>
        <:actions>
          <.button navigate={~p"/missions/new"} class="gap-1">
            <span class="hero-plus h-4 w-4"></span> New Mission
          </.button>
        </:actions>
      </.page_header>

      <%= if @mission_rows == [] do %>
        <div id="mission-list-empty-state">
          <.empty_state
            icon="hero-rocket-launch"
            title="No missions yet"
            description="Create your first mission to get started."
            action_label="New Mission"
            action_navigate={~p"/missions/new"}
          />
        </div>
      <% else %>
        <.card padding={:none}>
          <.vue
            id="mission-list-table-component"
            v-component="MissionTable"
            rows={@mission_table_rows}
            v-ssr={false}
          />
        </.card>
      <% end %>
    </div>
    """
  end

  defp load_mission_rows(organization_id) do
    organization_id
    |> Cadence.Missions.list_missions()
    |> Enum.map(fn mission ->
      spacecraft = Cadence.SpacecraftStore.list_spacecraft(organization_id, mission.mission_id)
      Map.put(mission_status(spacecraft), :mission, mission)
    end)
  end

  defp mission_status(spacecraft) do
    cond do
      spacecraft == [] ->
        %{spacecraft_count: 0, status: :info, status_label: "No spacecraft"}

      Enum.all?(spacecraft, & &1.scid) ->
        %{spacecraft_count: length(spacecraft), status: :ready, status_label: "Ready"}

      true ->
        %{spacecraft_count: length(spacecraft), status: :attention, status_label: "Needs setup"}
    end
  end

  defp mission_table_row(row) do
    %{
      id: "mission-row-#{row.mission.mission_id}",
      display_name: row.mission.display_name,
      slug: row.mission.slug,
      spacecraft_count: row.spacecraft_count,
      status: Atom.to_string(row.status),
      status_label: row.status_label,
      href: ~p"/missions/#{row.mission.mission_id}"
    }
  end
end
