defmodule CadenceWeb.CommsProviderProfileListLive do
  @moduledoc false
  use CadenceWeb, :live_view

  import CadenceWeb.CommsComponents

  @impl true
  def mount(_params, _session, socket) do
    %{current_scope: scope, current_mission: mission} = socket.assigns

    provider_profiles = Cadence.list_provider_profiles(scope.organization_id, mission.mission_id)

    {:ok,
     socket
     |> assign(:page_title, "Comms Providers")
     |> assign(:nav_item, :comms_providers)
     |> assign(:provider_profiles, provider_profiles)}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div id="comms-provider-profiles-page" class="space-y-6">
      <.page_header
        title="Providers"
        subtitle="Transport adapters Cadence uses to send and receive bytes — sockets, GSaaS providers, simulator streams."
        breadcrumbs={[
          {@current_mission.display_name, ~p"/missions/#{@current_mission.mission_id}"},
          {"Comms", ~p"/missions/#{@current_mission.mission_id}/comms"},
          {"Providers", nil}
        ]}
      >
        <:title_suffix>{length(@provider_profiles)} configured</:title_suffix>
        <:actions>
          <.button
            id="new-provider-profile-link"
            navigate={~p"/missions/#{@current_mission.mission_id}/comms/providers/new"}
            class="gap-1"
          >
            <span class="hero-plus h-4 w-4"></span> New Provider
          </.button>
        </:actions>
      </.page_header>

      <%= if @provider_profiles == [] do %>
        <.empty_state
          title="No providers"
          description="Create a provider to move bytes between Cadence and a ground network."
          action_label="Create the first provider"
          action_navigate={~p"/missions/#{@current_mission.mission_id}/comms/providers/new"}
        />
      <% else %>
        <.provider_profiles_table
          provider_profiles={@provider_profiles}
          current_mission={@current_mission}
        />
      <% end %>
    </div>
    """
  end

  attr :provider_profiles, :list, required: true
  attr :current_mission, :map, required: true

  defp provider_profiles_table(assigns) do
    ~H"""
    <.card padding={:none}>
      <.table id="provider-profiles-table" rows={@provider_profiles}>
        <:col :let={profile} label="Name" class="font-medium">
          <.link
            navigate={
              ~p"/missions/#{@current_mission.mission_id}/comms/providers/#{profile.provider_profile_id}"
            }
            class="text-primary hover:underline"
          >
            {display_name(profile, :provider_profile_id)}
          </.link>
        </:col>
        <:col :let={profile} label="Adapter" mono class="uppercase text-primary/80">
          {human_atom(profile.adapter_key)}
        </:col>
        <:col :let={profile} label="Version" mono class="text-base-content/70">
          v{profile.version}
        </:col>
        <:col :let={profile} label="Provider ID" class="font-mono text-xs text-base-content/60">
          {profile.provider_profile_id}
        </:col>
      </.table>
    </.card>
    """
  end
end
