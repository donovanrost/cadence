defmodule CadenceWeb.SpacecraftListLive do
  @moduledoc false
  use CadenceWeb, :live_view

  @profile_preview_limit 5

  @impl true
  def mount(_params, _session, socket) do
    mission = socket.assigns.current_mission
    organization_id = socket.assigns.current_scope.organization_id
    spacecraft = Cadence.list_spacecraft(organization_id, mission.mission_id)
    profiles = Cadence.list_spacecraft_types(organization_id, mission.mission_id)
    profiles_by_id = Map.new(profiles, &{&1.spacecraft_type_id, &1})
    profile_usage_counts = profile_usage_counts(profiles, spacecraft)
    profile_preview = Enum.take(profiles, @profile_preview_limit)

    {:ok,
     socket
     |> assign(:page_title, "Spacecraft")
     |> assign(:nav_item, :spacecraft)
     |> assign(:profiles_by_id, profiles_by_id)
     |> assign(:profile_usage_counts, profile_usage_counts)
     |> assign(:spacecraft_count, length(spacecraft))
     |> assign(:profile_count, length(profiles))
     |> assign(:missing_profile_count, Enum.count(spacecraft, &is_nil(&1.spacecraft_type_id)))
     |> assign(:profile_drift_count, Enum.count(spacecraft, &profile_drift?(&1, profiles_by_id)))
     |> assign(:spacecraft_empty?, spacecraft == [])
     |> assign(:profiles_empty?, profiles == [])
     |> assign(:profiles_truncated?, length(profiles) > @profile_preview_limit)
     |> stream(:spacecraft, spacecraft, dom_id: &"spacecraft-#{&1.spacecraft_id}")
     |> stream(:spacecraft_profiles, profile_preview,
       dom_id: &"spacecraft-profile-preview-#{&1.spacecraft_type_id}"
     )}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div id="spacecraft-management-page" class="space-y-6">
      <div class="border-b border-primary/20 pb-4">
        <div>
          <.link
            navigate={~p"/missions/#{@current_mission.mission_id}"}
            class="hud-label text-base-content/50 hover:text-primary"
          >
            &larr; {@current_mission.display_name}
          </.link>
          <h1 class="mt-2 text-2xl font-bold text-base-content tracking-tight">
            Spacecraft
          </h1>
          <p class="mt-1 max-w-3xl text-sm text-base-content/60">
            Manage mission spacecraft identities and reusable spacecraft profiles.
          </p>
        </div>
      </div>

      <div id="spacecraft-setup-summary" class="grid gap-3 md:grid-cols-4">
        <.summary_tile label="Vehicles" value={@spacecraft_count} />
        <.summary_tile label="Profiles" value={@profile_count} />
        <.summary_tile label="Missing profile" value={@missing_profile_count} />
        <.summary_tile label="Profile drift" value={@profile_drift_count} />
      </div>

      <section id="spacecraft-vehicles-card" class="card bg-base-200 hud-corners border border-base-300">
        <div class="card-body p-0">
          <div class="flex items-start justify-between gap-4 border-b border-base-300 px-4 py-3">
            <div>
              <h2 class="text-base font-semibold text-base-content">Vehicles</h2>
              <p class="mt-1 text-xs text-base-content/60">
                {@spacecraft_count} total · {@missing_profile_count} missing profile
              </p>
            </div>
            <.link
              navigate={~p"/missions/#{@current_mission.mission_id}/spacecraft/new"}
              class="btn btn-primary btn-sm gap-1 hover-glow-cyan transition-glow"
            >
              <.icon name="hero-plus" class="h-4 w-4" /> New spacecraft
            </.link>
          </div>

          <%= if @spacecraft_empty? do %>
            <div class="p-8 text-center">
              <p class="hud-label mb-3 text-base-content/60">No spacecraft yet</p>
              <p class="mx-auto max-w-md text-sm text-base-content/60">
                Register the first spacecraft for this mission.
              </p>
              <div class="mt-5">
                <.link
                  navigate={~p"/missions/#{@current_mission.mission_id}/spacecraft/new"}
                  class="btn btn-primary btn-sm hover-glow-cyan transition-glow"
                >
                  Register the first spacecraft
                </.link>
              </div>
            </div>
          <% else %>
            <table id="spacecraft-vehicles-table" class="table">
              <thead>
                <tr>
                  <th class="hud-label">Name</th>
                  <th class="hud-label">SCID</th>
                  <th class="hud-label">Profile</th>
                  <th class="hud-label">Applications</th>
                  <th class="hud-label">Setup</th>
                  <th class="hud-label text-right">Actions</th>
                </tr>
              </thead>
              <tbody id="spacecraft-vehicles" phx-update="stream">
                <tr
                  :for={{id, spacecraft} <- @streams.spacecraft}
                  id={id}
                  class="border-l-2 border-l-transparent hover:border-l-primary/60 transition-colors"
                >
                  <td class="font-medium">{spacecraft.display_name}</td>
                  <td class={[
                    "font-mono text-sm",
                    if(spacecraft.scid, do: "text-primary/80", else: "text-base-content/40 italic")
                  ]}>
                    {spacecraft.scid || "Not set"}
                  </td>
                  <td class="text-sm text-base-content/70">
                    {profile_label(spacecraft, @profiles_by_id)}
                  </td>
                  <td class="text-sm text-base-content/70">
                    {spacecraft_applications_label(spacecraft, @profiles_by_id)}
                  </td>
                  <td>
                    <.status_badge
                      status={setup_status(spacecraft, @profiles_by_id)}
                      label={setup_status_label(spacecraft, @profiles_by_id)}
                    />
                  </td>
                  <td class="text-right">
                    <.action_menu>
                      <:action>
                        <.link navigate={
                          ~p"/missions/#{@current_mission.mission_id}/spacecraft/#{spacecraft.spacecraft_id}"
                        }>
                          View
                        </.link>
                      </:action>
                      <:action>
                        <.link navigate={
                          ~p"/missions/#{@current_mission.mission_id}/spacecraft/#{spacecraft.spacecraft_id}/identity"
                        }>
                          Identity
                        </.link>
                      </:action>
                    </.action_menu>
                  </td>
                </tr>
              </tbody>
            </table>
          <% end %>
        </div>
      </section>

      <section id="spacecraft-profiles-card" class="card bg-base-200 hud-corners border border-base-300">
        <div class="card-body p-0">
          <div class="flex items-start justify-between gap-4 border-b border-base-300 px-4 py-3">
            <div>
              <h2 class="text-base font-semibold text-base-content">Profiles</h2>
              <p class="mt-1 text-xs text-base-content/60">
                {@profile_count} total · {@profile_drift_count} drift warning
              </p>
            </div>
            <.link
              navigate={~p"/missions/#{@current_mission.mission_id}/spacecraft/profiles/new"}
              class="btn btn-primary btn-sm gap-1 hover-glow-cyan transition-glow"
            >
              <.icon name="hero-plus" class="h-4 w-4" /> New profile
            </.link>
          </div>

          <%= if @profiles_empty? do %>
            <div class="p-8 text-center">
              <p class="hud-label mb-3 text-base-content/60">No profiles yet</p>
              <p class="mx-auto max-w-md text-sm text-base-content/60">
                Create a profile to reuse frame and packet interpretation settings across spacecraft.
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
          <% else %>
            <table id="spacecraft-profiles-preview-table" class="table">
              <thead>
                <tr>
                  <th class="hud-label">Name</th>
                  <th class="hud-label">Version</th>
                  <th class="hud-label">Protocols</th>
                  <th class="hud-label">Packet</th>
                  <th class="hud-label">Applications</th>
                  <th class="hud-label">Used by</th>
                  <th class="hud-label">State</th>
                  <th class="hud-label text-right">Actions</th>
                </tr>
              </thead>
              <tbody id="spacecraft-profile-previews" phx-update="stream">
                <tr
                  :for={{id, profile} <- @streams.spacecraft_profiles}
                  id={id}
                  class="border-l-2 border-l-transparent hover:border-l-primary/60 transition-colors"
                >
                  <td class="font-medium">{profile.display_name}</td>
                  <td class="font-mono text-sm text-base-content/70">v{profile.version}</td>
                  <td class="font-mono text-sm uppercase text-primary/80">
                    {profile.downlink_protocol} / {profile.uplink_protocol}
                  </td>
                  <td class="font-mono text-sm text-base-content/70">
                    {human_atom(profile.packet_protocol)}
                  </td>
                  <td class="text-sm text-base-content/70">
                    {applications_summary(profile.applications)}
                  </td>
                  <td class="font-mono text-sm text-base-content/70">
                    {profile_usage_count(profile, @profile_usage_counts)}
                  </td>
                  <td>
                    <.status_badge status={profile_status(profile)} label={profile_status_label(profile)} />
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

            <div
              :if={@profiles_truncated?}
              class="border-t border-base-300 px-4 py-3 text-right"
            >
              <.link
                navigate={~p"/missions/#{@current_mission.mission_id}/spacecraft/profiles"}
                class="btn btn-ghost btn-sm"
              >
                View all profiles
              </.link>
            </div>
          <% end %>
        </div>
      </section>
    </div>
    """
  end

  attr :label, :string, required: true
  attr :value, :integer, required: true

  defp summary_tile(assigns) do
    ~H"""
    <div class="border border-base-300 bg-base-200 px-3 py-2 hud-corners">
      <p class="hud-label text-base-content/50">{@label}</p>
      <p class="mt-1 font-mono text-xl text-base-content">{@value}</p>
    </div>
    """
  end

  defp profile_label(%{spacecraft_type_id: nil}, _profiles_by_id), do: "Not selected"

  defp profile_label(spacecraft, profiles_by_id) do
    case Map.get(profiles_by_id, spacecraft.spacecraft_type_id) do
      nil ->
        "Missing profile"

      profile ->
        "#{profile.display_name} v#{spacecraft.spacecraft_type_version || profile.version}"
    end
  end

  defp spacecraft_applications_label(%{spacecraft_type_id: nil}, _profiles_by_id),
    do: "No profile"

  defp spacecraft_applications_label(spacecraft, profiles_by_id) do
    case Map.get(profiles_by_id, spacecraft.spacecraft_type_id) do
      nil -> "Unavailable"
      profile -> applications_summary(profile.applications)
    end
  end

  defp setup_status(%{scid: nil}, _profiles_by_id), do: :attention
  defp setup_status(%{spacecraft_type_id: nil}, _profiles_by_id), do: :attention

  defp setup_status(spacecraft, profiles_by_id) do
    if profile_drift?(spacecraft, profiles_by_id), do: :attention, else: :ready
  end

  defp setup_status_label(%{scid: nil}, _profiles_by_id), do: "Needs SCID"
  defp setup_status_label(%{spacecraft_type_id: nil}, _profiles_by_id), do: "Needs profile"

  defp setup_status_label(spacecraft, profiles_by_id) do
    if profile_drift?(spacecraft, profiles_by_id), do: "Profile drift", else: "Setup complete"
  end

  defp profile_drift?(%{spacecraft_type_id: nil}, _profiles_by_id), do: false

  defp profile_drift?(spacecraft, profiles_by_id) do
    case Map.get(profiles_by_id, spacecraft.spacecraft_type_id) do
      nil ->
        false

      profile ->
        spacecraft.spacecraft_type_version && spacecraft.spacecraft_type_version < profile.version
    end
  end

  defp profile_usage_counts(profiles, spacecraft) do
    Map.new(profiles, fn profile ->
      count =
        Enum.count(spacecraft, fn vehicle ->
          vehicle.spacecraft_type_id == profile.spacecraft_type_id
        end)

      {profile.spacecraft_type_id, count}
    end)
  end

  defp profile_usage_count(profile, profile_usage_counts) do
    profile_usage_counts
    |> Map.get(profile.spacecraft_type_id, 0)
    |> Integer.to_string()
  end

  defp profile_status(%{lifecycle_state: :active}), do: :ready
  defp profile_status(_profile), do: :attention

  defp profile_status_label(%{lifecycle_state: :active}), do: "Active"
  defp profile_status_label(_profile), do: "Archived"

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

  defp human_atom(value) when is_atom(value) do
    value
    |> Atom.to_string()
    |> String.replace("_", " ")
    |> String.capitalize()
  end

  defp human_atom(value), do: to_string(value)
end
