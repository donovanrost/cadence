defmodule CadenceWeb.SpacecraftTypeListLive do
  @moduledoc false
  use CadenceWeb, :live_view

  @impl true
  def mount(_params, _session, socket) do
    mission = socket.assigns.current_mission
    organization_id = socket.assigns.current_scope.organization_id

    profiles =
      Cadence.SpacecraftTypeStore.list_spacecraft_types(organization_id, mission.mission_id)

    spacecraft_profile_rows =
      Enum.map(profiles, &spacecraft_profile_row_dto(&1, mission.mission_id))

    {:ok,
     socket
     |> assign(:page_title, "Spacecraft Profiles")
     |> assign(:nav_item, :spacecraft)
     |> assign(:spacecraft_profile_count, length(profiles))
     |> assign(:spacecraft_profiles_empty?, profiles == [])
     |> assign(:spacecraft_profile_rows, spacecraft_profile_rows)}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div id="spacecraft-profiles-page" class="space-y-6">
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
            id="new-spacecraft-profile-link"
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
          <.vue
            id="spacecraft-profiles-list-component"
            v-component="SpacecraftTypeList"
            rows={@spacecraft_profile_rows}
            v-ssr={false}
          />
        </.card>
      <% end %>
    </div>
    """
  end

  defp spacecraft_profile_row_dto(profile, mission_id) do
    %{
      id: "spacecraft-profile-#{profile.spacecraft_type_id}",
      display_name: profile.display_name,
      version: "v#{profile.version}",
      downlink_protocol: protocol_label(profile.downlink_protocol),
      uplink_protocol: protocol_label(profile.uplink_protocol),
      applications: applications_summary(profile.applications),
      href: ~p"/missions/#{mission_id}/spacecraft/profiles/#{profile.spacecraft_type_id}"
    }
  end

  defp protocol_label(protocol) when is_atom(protocol) do
    protocol
    |> Atom.to_string()
    |> String.upcase()
  end

  defp protocol_label(protocol) when is_binary(protocol), do: String.upcase(protocol)

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
