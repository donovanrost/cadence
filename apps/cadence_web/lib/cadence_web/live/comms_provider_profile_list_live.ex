defmodule CadenceWeb.CommsProviderProfileListLive do
  @moduledoc false
  use CadenceWeb, :live_view

  import CadenceWeb.CommsComponents

  @impl true
  def mount(_params, _session, socket) do
    %{current_scope: scope, current_mission: mission} = socket.assigns

    provider_profiles = Cadence.list_provider_profiles(scope.organization_id, mission.mission_id)
    path_templates = Cadence.list_path_templates(scope.organization_id, mission.mission_id)

    {:ok,
     socket
     |> assign(:page_title, "Comms Providers")
     |> assign(:nav_item, :comms_providers)
     |> assign(:provider_profiles, provider_profiles)
     |> assign(:path_templates, path_templates)}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div id="comms-provider-profiles-page" class="space-y-6">
      <section class="card bg-base-200">
        <div class="card-body p-6">
          <div class="flex items-start justify-between gap-4">
            <div>
              <p class="hud-label mb-2">External I/O Adapters</p>
              <h2 class="text-lg font-semibold">Providers</h2>
              <p class="mt-1 text-sm text-base-content/60">
                Providers describe how Cadence connects to, receives from, or drives an
                external stream. They are reusable and versioned before being attached to links.
              </p>
            </div>
            <.status_badge
              status={if @provider_profiles == [], do: :attention, else: :ready}
              label={if @provider_profiles == [], do: "Not Started", else: "Configured"}
            />
          </div>
          <div class="mt-4">
            <.link
              id="new-provider-profile-link"
              navigate={~p"/missions/#{@current_mission.mission_id}/comms/providers/new"}
              class="btn btn-primary btn-sm"
            >
              New Provider
            </.link>
          </div>

          <%= if @provider_profiles == [] do %>
            <div class="mt-6">
              <.empty_state
                icon="hero-signal"
                title="No providers"
                description="Create providers before assembling mission links for GSaaS, sockets, or simulator streams."
                action_label="New Provider"
                action_navigate={~p"/missions/#{@current_mission.mission_id}/comms/providers/new"}
              />
            </div>
          <% else %>
            <div class="mt-6 overflow-x-auto">
              <table id="provider-profiles-table" class="table">
                <thead>
                  <tr>
                    <th class="hud-label">Name</th>
                    <th class="hud-label">Adapter</th>
                    <th class="hud-label">Provider ID</th>
                    <th class="hud-label">Version</th>
                    <th class="hud-label text-right">Linked Templates</th>
                  </tr>
                </thead>
                <tbody>
                  <tr :for={profile <- @provider_profiles}>
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
                    <td><.status_badge status={:info} label={human_atom(profile.adapter_key)} /></td>
                    <td class="font-mono text-xs text-base-content/70">
                      {profile.provider_profile_id}
                    </td>
                    <td class="font-mono text-sm">v{profile.version}</td>
                    <td class="text-right font-mono text-sm">
                      {linked_path_count(profile.provider_profile_id, @path_templates)}
                    </td>
                  </tr>
                </tbody>
              </table>
            </div>
          <% end %>
        </div>
      </section>
    </div>
    """
  end

  defp linked_path_count(provider_profile_id, path_templates) do
    Enum.count(path_templates, &(provider_profile_id in &1.provider_profile_ids))
  end
end
