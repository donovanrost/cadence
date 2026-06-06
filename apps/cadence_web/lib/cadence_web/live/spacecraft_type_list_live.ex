defmodule CadenceWeb.SpacecraftTypeListLive do
  @moduledoc false
  use CadenceWeb, :live_view

  @impl true
  def mount(_params, _session, socket) do
    mission = socket.assigns.current_mission
    organization_id = socket.assigns.current_scope.organization_id
    profiles = Cadence.list_spacecraft_types(organization_id, mission.mission_id)

    {:ok,
     socket
     |> assign(:page_title, "Spacecraft Profiles")
     |> assign(:nav_item, :spacecraft)
     |> assign(:spacecraft_profile_count, length(profiles))
     |> assign(:spacecraft_profiles_empty?, profiles == [])
     |> stream(:spacecraft_profiles, profiles,
       dom_id: &"spacecraft-profile-#{&1.spacecraft_type_id}"
     )}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="space-y-6">
      <div class="flex items-end justify-between gap-4 border-b border-primary/20 pb-4">
        <div>
          <.link
            navigate={~p"/missions/#{@current_mission.mission_id}"}
            class="hud-label text-base-content/50 hover:text-primary"
          >
            &larr; {@current_mission.display_name}
          </.link>
          <h1 class="mt-2 text-2xl font-bold text-base-content tracking-tight">
            Spacecraft Profiles
            <span class="ml-3 font-mono text-base text-base-content/40">
              {@spacecraft_profile_count} defined
            </span>
          </h1>
          <p class="mt-1 max-w-2xl text-sm text-base-content/60">
            Reusable byte-interpretation contracts for spacecraft that share bus protocols, frame parameters, and platform applications.
          </p>
        </div>
        <.link
          navigate={~p"/missions/#{@current_mission.mission_id}/spacecraft/profiles/new"}
          class="btn btn-primary btn-sm gap-1 hover-glow-cyan transition-glow"
        >
          <.icon name="hero-plus" class="h-4 w-4" /> New Profile
        </.link>
      </div>

      <%= if @spacecraft_profiles_empty? do %>
        <div class="card bg-base-200 hud-corners border border-base-300">
          <div class="card-body p-8 text-center">
            <p class="hud-label mb-3 text-base-content/60">No profiles yet</p>
            <p class="text-sm text-base-content/60 max-w-md mx-auto">
              Define a profile to capture the protocol stack and applications shared by a set of spacecraft.
            </p>
            <div class="mt-5">
              <.link
                navigate={~p"/missions/#{@current_mission.mission_id}/spacecraft/profiles/new"}
                class="btn btn-primary btn-sm hover-glow-cyan transition-glow"
              >
                Create the first profile
              </.link>
            </div>
          </div>
        </div>
      <% else %>
        <div class="card bg-base-200 hud-corners border border-base-300">
          <table class="table">
            <thead>
              <tr>
                <th class="hud-label">Name</th>
                <th class="hud-label">Version</th>
                <th class="hud-label">Downlink</th>
                <th class="hud-label">Uplink</th>
                <th class="hud-label">Applications</th>
                <th class="hud-label text-right">Actions</th>
              </tr>
            </thead>
            <tbody id="spacecraft-profiles" phx-update="stream">
              <tr
                :for={{id, profile} <- @streams.spacecraft_profiles}
                id={id}
                class="border-l-2 border-l-transparent hover:border-l-primary/60 transition-colors"
              >
                <td class="font-medium">{profile.display_name}</td>
                <td class="font-mono text-sm text-base-content/70">v{profile.version}</td>
                <td class="font-mono text-sm uppercase text-primary/80">{profile.downlink_protocol}</td>
                <td class="font-mono text-sm uppercase text-primary/80">{profile.uplink_protocol}</td>
                <td class="text-sm text-base-content/70">
                  {applications_summary(profile.applications)}
                </td>
                <td class="text-right">
                  <.action_menu>
                    <:action>
                      <.link navigate={
                        ~p"/missions/#{@current_mission.mission_id}/spacecraft/profiles/#{profile.spacecraft_type_id}"
                      }>
                        View
                      </.link>
                    </:action>
                  </.action_menu>
                </td>
              </tr>
            </tbody>
          </table>
        </div>
      <% end %>
    </div>
    """
  end

  defp applications_summary(applications)
       when is_map(applications) and map_size(applications) > 0 do
    applications
    |> Map.keys()
    |> Enum.sort()
    |> Enum.map_join(", ", &humanize_application_key/1)
  end

  defp applications_summary(_), do: "None"

  defp humanize_application_key(key) when is_atom(key) do
    key
    |> Atom.to_string()
    |> String.split("_")
    |> Enum.map_join(" ", &String.capitalize/1)
  end

  defp humanize_application_key(key) when is_binary(key) do
    key
    |> String.split("_")
    |> Enum.map_join(" ", &String.capitalize/1)
  end
end
