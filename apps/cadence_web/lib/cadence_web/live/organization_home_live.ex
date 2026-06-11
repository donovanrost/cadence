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
     |> assign(summary)}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="space-y-6">
      <.page_header title={@organization.display_name} subtitle={@organization.slug} />

      <div id="organization-stats" class="grid gap-4 md:grid-cols-3">
        <.stat_card id="organization-stat-missions" label="Missions" value={@mission_count} />
        <.stat_card id="organization-stat-spacecraft" label="Spacecraft" value={@spacecraft_count} />
        <.stat_card id="organization-stat-members" label="Members" value={@member_count} />
      </div>

      <.recent_missions_card recent_missions={@recent_missions} />
    </div>
    """
  end

  attr :id, :string, required: true
  attr :label, :string, required: true
  attr :value, :integer, required: true

  defp stat_card(assigns) do
    ~H"""
    <.card id={@id} hover_glow>
      <p class="hud-label">{@label}</p>
      <p class="mt-2 font-mono text-3xl font-bold">{@value}</p>
    </.card>
    """
  end

  attr :recent_missions, :list, required: true

  defp recent_missions_card(assigns) do
    ~H"""
    <.card id="organization-recent-missions">
      <div class="flex items-start justify-between gap-4">
        <div>
          <p class="hud-label mb-2">Recent Missions</p>
          <h2 class="text-lg font-semibold">Jump into a mission</h2>
        </div>
        <.button variant={:ghost} navigate={~p"/missions"}>
          All missions
        </.button>
      </div>

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
        <ul class="mt-5 divide-y divide-base-300">
          <li :for={summary <- @recent_missions} class="py-3">
            <.link
              navigate={~p"/missions/#{summary.mission.mission_id}"}
              class="flex items-center justify-between gap-4 hover:text-primary"
            >
              <div>
                <p class="font-medium">{summary.mission.display_name}</p>
                <p class="font-mono text-xs text-base-content/60">{summary.mission.slug}</p>
              </div>
              <.status_badge status={summary.status} label={summary.status_label} />
            </.link>
          </li>
        </ul>
      <% end %>
    </.card>
    """
  end

  defp load_summary(organization_id) do
    missions = Cadence.list_missions(organization_id)
    members = Cadence.list_organization_members(organization_id)

    mission_summaries =
      Enum.map(missions, fn mission ->
        spacecraft = Cadence.list_spacecraft(organization_id, mission.mission_id)
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
end
