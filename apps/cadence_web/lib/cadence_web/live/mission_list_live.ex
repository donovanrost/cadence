defmodule CadenceWeb.MissionListLive do
  @moduledoc false
  use CadenceWeb, :live_view

  @impl true
  def mount(_params, _session, socket) do
    organization_id = socket.assigns.current_scope.organization_id
    mission_rows = load_mission_rows(organization_id)

    {:ok,
     socket
     |> assign(:page_title, "Missions")
     |> assign(:nav_item, :missions)
     |> assign(:mission_rows, mission_rows)}
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
        <.empty_state
          icon="hero-rocket-launch"
          title="No missions yet"
          description="Create your first mission to get started."
          action_label="New Mission"
          action_navigate={~p"/missions/new"}
        />
      <% else %>
        <.card padding={:none}>
          <.table
            id="mission-list-table"
            rows={@mission_rows}
            row_id={fn row -> "mission-row-#{row.mission.mission_id}" end}
          >
            <:col :let={row} label="Mission" class="font-medium">
              <.link navigate={~p"/missions/#{row.mission.mission_id}"} class="text-primary hover:underline">
                {row.mission.display_name}
              </.link>
            </:col>
            <:col :let={row} label="Slug" mono class="text-primary/80">
              {row.mission.slug}
            </:col>
            <:col :let={row} label="Spacecraft" align={:right} mono>
              {row.spacecraft_count}
            </:col>
            <:col :let={row} label="Status">
              <.status_badge status={row.status} label={row.status_label} />
            </:col>
          </.table>
        </.card>
      <% end %>
    </div>
    """
  end

  defp load_mission_rows(organization_id) do
    organization_id
    |> Cadence.list_missions()
    |> Enum.map(fn mission ->
      spacecraft = Cadence.list_spacecraft(organization_id, mission.mission_id)
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
end
