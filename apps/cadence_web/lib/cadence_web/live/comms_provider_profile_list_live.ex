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
      <div class="flex items-end justify-between gap-4 border-b border-primary/20 pb-4">
        <div>
          <.link
            navigate={~p"/missions/#{@current_mission.mission_id}/comms"}
            class="hud-label text-base-content/50 hover:text-primary"
          >
            &larr; Comms
          </.link>
          <h1 class="mt-2 text-2xl font-bold text-base-content tracking-tight">
            Providers
            <span class="ml-3 font-mono text-base text-base-content/40">
              {length(@provider_profiles)} configured
            </span>
          </h1>
          <p class="mt-1 max-w-2xl text-sm text-base-content/60">
            Transport adapters Cadence uses to send and receive bytes &mdash; sockets, GSaaS providers, simulator streams.
          </p>
        </div>
        <.link
          id="new-provider-profile-link"
          navigate={~p"/missions/#{@current_mission.mission_id}/comms/providers/new"}
          class="btn btn-primary btn-sm gap-1 hover-glow-cyan transition-glow"
        >
          <span class="hero-plus h-4 w-4"></span> New Provider
        </.link>
      </div>

      <%= if @provider_profiles == [] do %>
        <div class="card bg-base-200 hud-corners border border-base-300">
          <div class="card-body p-8 text-center">
            <p class="hud-label mb-3 text-base-content/60">No providers</p>
            <p class="text-sm text-base-content/60 max-w-md mx-auto">
              Create a provider to move bytes between Cadence and a ground network.
            </p>
            <div class="mt-5">
              <.link
                navigate={~p"/missions/#{@current_mission.mission_id}/comms/providers/new"}
                class="btn btn-primary btn-sm hover-glow-cyan transition-glow"
              >
                Create the first provider
              </.link>
            </div>
          </div>
        </div>
      <% else %>
        <div class="card bg-base-200 hud-corners border border-base-300">
          <table id="provider-profiles-table" class="table">
            <thead>
              <tr>
                <th class="hud-label">Name</th>
                <th class="hud-label">Adapter</th>
                <th class="hud-label">Version</th>
                <th class="hud-label">Provider ID</th>
              </tr>
            </thead>
            <tbody>
              <tr
                :for={profile <- @provider_profiles}
                class="border-l-2 border-l-transparent hover:border-l-primary/60 transition-colors"
              >
                <td class="font-medium">
                  <.link
                    navigate={
                      ~p"/missions/#{@current_mission.mission_id}/comms/providers/#{profile.provider_profile_id}"
                    }
                    class="text-primary hover:underline"
                  >
                    {display_name(profile, :provider_profile_id)}
                  </.link>
                </td>
                <td class="font-mono text-sm uppercase text-primary/80">
                  {human_atom(profile.adapter_key)}
                </td>
                <td class="font-mono text-sm text-base-content/70">v{profile.version}</td>
                <td class="font-mono text-xs text-base-content/50">
                  {profile.provider_profile_id}
                </td>
              </tr>
            </tbody>
          </table>
        </div>
      <% end %>
    </div>
    """
  end
end
