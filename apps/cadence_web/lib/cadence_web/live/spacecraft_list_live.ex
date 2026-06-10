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
      <.page_header
        title="Spacecraft"
        subtitle="Manage mission spacecraft identities and reusable spacecraft profiles."
        back_label={@current_mission.display_name}
        back_navigate={~p"/missions/#{@current_mission.mission_id}"}
      />

      <div id="spacecraft-setup-summary" class="grid gap-3 md:grid-cols-4">
        <.stat_tile label="Vehicles" value={@spacecraft_count} />
        <.stat_tile label="Profiles" value={@profile_count} />
        <.stat_tile label="Missing profile" value={@missing_profile_count} />
        <.stat_tile label="Profile drift" value={@profile_drift_count} />
      </div>

      <.card
        id="spacecraft-vehicles-card"
        heading="Vehicles"
        subtitle={"#{@spacecraft_count} total · #{@missing_profile_count} missing profile"}
        padding={if @spacecraft_empty?, do: :default, else: :none}
      >
        <:actions>
          <.button
            navigate={~p"/missions/#{@current_mission.mission_id}/spacecraft/new"}
            class="gap-1"
          >
            <.icon name="hero-plus" class="h-4 w-4" /> New spacecraft
          </.button>
        </:actions>

        <%= if @spacecraft_empty? do %>
          <.empty_state
            title="No spacecraft yet"
            description="Register the first spacecraft for this mission."
            action_label="Register the first spacecraft"
            action_navigate={~p"/missions/#{@current_mission.mission_id}/spacecraft/new"}
          />
        <% else %>
          <.table
            id="spacecraft-vehicles-table"
            body_id="spacecraft-vehicles"
            rows={@streams.spacecraft}
          >
            <:col :let={spacecraft} label="Name" class="font-medium">
              {spacecraft.display_name}
            </:col>
            <:col :let={spacecraft} label="SCID" mono>
              <span class={
                if(spacecraft.scid, do: "text-primary/80", else: "text-base-content/40 italic")
              }>
                {spacecraft.scid || "Not set"}
              </span>
            </:col>
            <:col :let={spacecraft} label="Profile" class="text-sm text-base-content/70">
              {profile_label(spacecraft, @profiles_by_id)}
            </:col>
            <:col :let={spacecraft} label="Applications" class="text-sm text-base-content/70">
              {spacecraft_applications_label(spacecraft, @profiles_by_id)}
            </:col>
            <:col :let={spacecraft} label="Setup">
              <.status_badge
                status={setup_status(spacecraft, @profiles_by_id)}
                label={setup_status_label(spacecraft, @profiles_by_id)}
              />
            </:col>
            <:col :let={spacecraft} label="Actions" align={:right}>
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
            </:col>
          </.table>
        <% end %>
      </.card>

      <.card
        id="spacecraft-profiles-card"
        heading="Profiles"
        subtitle={"#{@profile_count} total · #{@profile_drift_count} drift warning"}
        padding={if @profiles_empty?, do: :default, else: :none}
      >
        <:actions>
          <.button
            navigate={~p"/missions/#{@current_mission.mission_id}/spacecraft/profiles/new"}
            class="gap-1"
          >
            <.icon name="hero-plus" class="h-4 w-4" /> New profile
          </.button>
        </:actions>

        <%= if @profiles_empty? do %>
          <.empty_state
            title="No profiles yet"
            description="Create a profile to reuse frame and packet interpretation settings across spacecraft."
            action_label="Create the first profile"
            action_navigate={~p"/missions/#{@current_mission.mission_id}/spacecraft/profiles/new"}
          />
        <% else %>
          <.table
            id="spacecraft-profiles-preview-table"
            body_id="spacecraft-profile-previews"
            rows={@streams.spacecraft_profiles}
          >
            <:col :let={profile} label="Name" class="font-medium">
              {profile.display_name}
            </:col>
            <:col :let={profile} label="Version" mono class="text-base-content/70">
              v{profile.version}
            </:col>
            <:col :let={profile} label="Protocols" mono class="uppercase text-primary/80">
              {profile.downlink_protocol} / {profile.uplink_protocol}
            </:col>
            <:col :let={profile} label="Packet" mono class="text-base-content/70">
              {human_atom(profile.packet_protocol)}
            </:col>
            <:col :let={profile} label="Applications" class="text-sm text-base-content/70">
              {applications_summary(profile.applications)}
            </:col>
            <:col :let={profile} label="Used by" mono class="text-base-content/70">
              {profile_usage_count(profile, @profile_usage_counts)}
            </:col>
            <:col :let={profile} label="State">
              <.status_badge status={profile_status(profile)} label={profile_status_label(profile)} />
            </:col>
            <:col :let={profile} label="Actions" align={:right}>
              <.action_menu>
                <:action>
                  <.link navigate={
                    ~p"/missions/#{@current_mission.mission_id}/spacecraft/profiles/#{profile.spacecraft_type_id}"
                  }>
                    View
                  </.link>
                </:action>
              </.action_menu>
            </:col>
          </.table>

          <div :if={@profiles_truncated?} class="border-t border-base-300 px-4 py-3 text-right">
            <.button
              variant={:ghost}
              navigate={~p"/missions/#{@current_mission.mission_id}/spacecraft/profiles"}
            >
              View all profiles
            </.button>
          </div>
        <% end %>
      </.card>
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
