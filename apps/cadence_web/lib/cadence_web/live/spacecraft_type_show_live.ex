defmodule CadenceWeb.SpacecraftTypeShowLive do
  @moduledoc false
  use CadenceWeb, :live_view

  @impl true
  def mount(%{"profile_id" => profile_id}, _session, socket) do
    mission = socket.assigns.current_mission
    organization_id = socket.assigns.current_scope.organization_id

    case Cadence.SpacecraftTypeStore.fetch_spacecraft_type(
           organization_id,
           mission.mission_id,
           profile_id
         ) do
      {:ok, profile} ->
        versions =
          Cadence.SpacecraftTypeStore.list_spacecraft_type_versions(
            organization_id,
            mission.mission_id,
            profile.spacecraft_type_id
          )

        {:ok,
         socket
         |> assign(:page_title, profile.display_name)
         |> assign(:nav_item, :spacecraft)
         |> assign(:profile_details, profile_details_dto(profile))
         |> assign(:navigation, navigation_dto(mission, profile))
         |> assign(:labels, labels_dto())
         |> assign(:version_rows, Enum.map(versions, &version_row_dto/1))}

      {:error, :spacecraft_type_not_found} ->
        {:ok,
         socket
         |> put_flash(:error, "Spacecraft profile not found.")
         |> push_navigate(to: ~p"/missions/#{mission.mission_id}/spacecraft/profiles")}
    end
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_scope}>
      <div id="spacecraft-profile-show-page">
        <.vue
          id="spacecraft-profile-show-component"
          v-component="SpacecraftTypeShow"
          profile={@profile_details}
          navigation={@navigation}
          labels={@labels}
          versions={@version_rows}
          v-ssr={false}
        />
      </div>
    </Layouts.app>
    """
  end

  defp profile_details_dto(profile) do
    %{
      id: "spacecraft-profile-#{profile.spacecraft_type_id}",
      profile_id: profile.spacecraft_type_id,
      display_name: profile.display_name,
      version: "v#{profile.version}",
      lifecycle: to_string(profile.lifecycle_state),
      downlink_protocol: protocol_label(profile.downlink_protocol),
      uplink_protocol: protocol_label(profile.uplink_protocol),
      packet_protocol: to_string(profile.packet_protocol),
      frame_parameters:
        profile.frame_parameters
        |> Enum.sort()
        |> Enum.map(&frame_parameter_dto/1),
      applications:
        profile.applications
        |> Enum.sort()
        |> Enum.map(&application_dto/1)
    }
  end

  defp navigation_dto(mission, profile) do
    %{
      mission: %{
        label: mission.display_name,
        href: ~p"/missions/#{mission.mission_id}"
      },
      spacecraft: %{
        label: "Spacecraft",
        href: ~p"/missions/#{mission.mission_id}/spacecraft"
      },
      profiles: %{
        label: "Spacecraft Profiles",
        href: ~p"/missions/#{mission.mission_id}/spacecraft/profiles"
      },
      current: %{label: profile.display_name}
    }
  end

  defp labels_dto do
    %{
      byte_interpretation: "Byte Interpretation",
      applications: "Applications",
      version_history: "Version History",
      frame_parameters: "Frame Parameters",
      no_applications: "No applications enabled.",
      downlink_protocol: "Downlink Protocol",
      uplink_protocol: "Uplink Protocol",
      packet_protocol: "Packet Protocol",
      lifecycle: "Lifecycle",
      version: "Version",
      downlink: "Downlink",
      uplink: "Uplink"
    }
  end

  defp frame_parameter_dto({key, value}) do
    %{
      id: "spacecraft-profile-frame-parameter-#{key}",
      label: humanize(key),
      value: format_value(value)
    }
  end

  defp application_dto({key, _config}) do
    %{
      id: "spacecraft-profile-application-#{key}",
      label: humanize(key)
    }
  end

  defp version_row_dto(version) do
    %{
      id: "spacecraft-profile-version-#{version.spacecraft_type_id}-#{version.version}",
      version: "v#{version.version}",
      lifecycle: to_string(version.lifecycle_state),
      downlink_protocol: protocol_label(version.downlink_protocol),
      uplink_protocol: protocol_label(version.uplink_protocol)
    }
  end

  defp protocol_label(protocol) do
    protocol
    |> to_string()
    |> String.upcase()
  end

  defp humanize(key) when is_atom(key), do: humanize(Atom.to_string(key))

  defp humanize(key) when is_binary(key) do
    key
    |> String.split("_")
    |> Enum.map_join(" ", &String.capitalize/1)
  end

  defp format_value(value) when is_binary(value), do: value
  defp format_value(value) when is_integer(value), do: Integer.to_string(value)
  defp format_value(true), do: "yes"
  defp format_value(false), do: "no"
  defp format_value(value), do: inspect(value)
end
