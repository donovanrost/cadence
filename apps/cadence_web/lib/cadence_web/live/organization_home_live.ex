defmodule CadenceWeb.OrganizationHomeLive do
  @moduledoc false
  use CadenceWeb, :live_view

  @recent_mission_limit 3

  @impl true
  def mount(_params, _session, socket) do
    org = socket.assigns.current_scope.organization
    summary = load_summary(org.organization_id)

    {:ok,
     socket
     |> assign(:page_title, org.display_name)
     |> assign(:nav_item, :organization_home)
     |> assign(:organization, org)
     |> assign(summary)
     |> assign(:recent_mission_rows, Enum.map(summary.recent_missions, &recent_mission_row/1))}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="space-y-6">
      <.page_header title={@organization.display_name} subtitle={@organization.slug} />

      <.vue
        id="organization-stats-component"
        v-component="OrganizationStats"
        mission_count={@mission_count}
        spacecraft_count={@spacecraft_count}
        member_count={@member_count}
        v-ssr={false}
      />

      <.recent_missions_card
        recent_missions={@recent_missions}
        recent_mission_rows={@recent_mission_rows}
      />
    </div>
    """
  end

  attr(:recent_missions, :list, required: true)
  attr(:recent_mission_rows, :list, required: true)

  defp recent_missions_card(assigns) do
    ~H"""
    <.card id="organization-recent-missions">
      <.section_header eyebrow="Recent Missions" title="Jump into a mission">
        <:actions>
          <.button variant={:ghost} navigate={~p"/missions"}>All missions</.button>
        </:actions>
      </.section_header>

      <%= if @recent_missions == [] do %>
        <div class="mt-6">
          <.empty_state
            icon="hero-rocket-launch"
            title="No missions yet"
            description="Create your first mission to get started."
            action_label="New Mission"
            action_navigate={~p"/missions/new"}
          />
        </div>
      <% else %>
        <.vue
          id="organization-recent-missions-component"
          v-component="RecentMissions"
          rows={@recent_mission_rows}
          v-ssr={false}
        />
      <% end %>
    </.card>
    """
  end

  defp load_summary(organization_id) do
    missions = Cadence.Missions.list_missions(organization_id)
    members = Cadence.Accounts.list_organization_members(organization_id)

    mission_summaries =
      Enum.map(missions, fn mission ->
        spacecraft = Cadence.SpacecraftStore.list_spacecraft(organization_id, mission.mission_id)
        Map.put(mission_status(spacecraft), :mission, mission)
      end)

    %{
      mission_count: length(missions),
      member_count: length(members),
      spacecraft_count: Enum.sum(Enum.map(mission_summaries, & &1.spacecraft_count)),
      recent_missions: Enum.take(mission_summaries, @recent_mission_limit)
    }
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

  defp recent_mission_row(row) do
    %{
      id: "organization-recent-mission-#{row.mission.mission_id}",
      display_name: row.mission.display_name,
      slug: row.mission.slug,
      status: Atom.to_string(row.status),
      status_label: row.status_label,
      href: ~p"/missions/#{row.mission.mission_id}"
    }
  end
end
