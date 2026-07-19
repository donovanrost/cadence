defmodule CadenceWeb.SpacecraftTypeListLive do
  @moduledoc false
  use CadenceWeb, :live_view

  @impl true
  def mount(_params, _session, socket) do
    mission = socket.assigns.current_mission
    organization_id = socket.assigns.current_scope.organization_id

    profiles =
      Cadence.SpacecraftTypeStore.list_spacecraft_types(organization_id, mission.mission_id)

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
      <.page_header
        title="Spacecraft Profiles"
        subtitle="Reusable byte-interpretation contracts for spacecraft that share bus protocols, frame parameters, and platform applications."
        breadcrumbs={[
          {@current_mission.display_name, ~p"/missions/#{@current_mission.mission_id}"},
          {"Spacecraft", ~p"/missions/#{@current_mission.mission_id}/spacecraft"},
          {"Spacecraft Profiles", nil}
        ]}
      >
        <:title_suffix>{@spacecraft_profile_count} defined</:title_suffix>
        <:actions>
          <.button
            navigate={~p"/missions/#{@current_mission.mission_id}/spacecraft/profiles/new"}
            class="gap-1"
          >
            <.icon name="hero-plus" class="h-4 w-4" /> New Profile
          </.button>
        </:actions>
      </.page_header>

      <%= if @spacecraft_profiles_empty? do %>
        <.empty_state
          title="No profiles yet"
          description="Define a profile to capture the protocol stack and applications shared by a set of spacecraft."
          action_label="Create the first profile"
          action_navigate={~p"/missions/#{@current_mission.mission_id}/spacecraft/profiles/new"}
        />
      <% else %>
        <.card padding={:none}>
          <.table
            id="spacecraft-profiles-table"
            body_id="spacecraft-profiles"
            rows={@streams.spacecraft_profiles}
          >
            <:col :let={profile} label="Name" class="font-medium">
              <.link
                navigate={
                  ~p"/missions/#{@current_mission.mission_id}/spacecraft/profiles/#{profile.spacecraft_type_id}"
                }
                class="text-primary hover:underline"
              >
                {profile.display_name}
              </.link>
            </:col>
            <:col :let={profile} label="Version" mono class="text-base-content/70">
              v{profile.version}
            </:col>
            <:col :let={profile} label="Downlink" mono class="uppercase text-primary/80">
              {profile.downlink_protocol}
            </:col>
            <:col :let={profile} label="Uplink" mono class="uppercase text-primary/80">
              {profile.uplink_protocol}
            </:col>
            <:col :let={profile} label="Applications" class="text-sm text-base-content/70">
              {applications_summary(profile.applications)}
            </:col>
          </.table>
        </.card>
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
