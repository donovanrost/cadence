defmodule CadenceWeb.CommsGroundStationShowLive do
  alias Cadence.Comms.GroundStationStore
  alias Phoenix.LiveView.JS

  @moduledoc false
  use CadenceWeb, :live_view

  @impl true
  def mount(%{"ground_station_id" => ground_station_id}, _session, socket) do
    %{current_scope: scope, current_mission: mission} = socket.assigns

    case GroundStationStore.fetch_ground_station(
           scope.organization_id,
           mission.mission_id,
           ground_station_id
         ) do
      {:ok, ground_station} ->
        {:ok,
         socket
         |> assign(:page_title, ground_station.display_name)
         |> assign(:nav_item, :comms_ground_stations)
         |> assign(:ground_station, ground_station)
         |> assign(:navigation, navigation_dto(mission, ground_station))
         |> assign(:ground_station_details, ground_station_dto(ground_station))
         |> assign(:actions, actions_dto(mission, ground_station))}

      {:error, _reason} ->
        {:ok,
         socket
         |> put_flash(:error, "Ground station not found.")
         |> push_navigate(to: ~p"/missions/#{mission.mission_id}/comms/ground-stations")}
    end
  end

  @impl true
  def handle_event("archive", _params, socket) do
    %{current_scope: scope, current_mission: mission, ground_station: ground_station} =
      socket.assigns

    case GroundStationStore.archive_ground_station(
           scope.organization_id,
           mission.mission_id,
           ground_station.ground_station_id,
           %{"archived_by" => "mission_comms_ui"}
         ) do
      {:ok, _archived} ->
        {:noreply,
         socket
         |> put_flash(:info, "Ground station archived.")
         |> push_navigate(to: ~p"/missions/#{mission.mission_id}/comms/ground-stations")}

      {:error, reason} ->
        {:noreply,
         put_flash(socket, :error, "Failed to archive ground station: #{inspect(reason)}")}
    end
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_scope}>
      <div id="comms-ground-station-show-page">
        <.vue
          id="comms-ground-station-show-component"
          v-component="FederatedFullPageSurface"
          navigation={@navigation}
          ground_station={@ground_station_details}
          actions={@actions}
          v-on:archive={JS.push("archive")}
          v-ssr={false}
        />
      </div>
    </Layouts.app>
    """
  end

  defp navigation_dto(mission, ground_station) do
    %{
      breadcrumbs: [
        %{label: mission.display_name, href: ~p"/missions/#{mission.mission_id}"},
        %{label: "Comms", href: ~p"/missions/#{mission.mission_id}/comms"},
        %{
          label: "Ground Stations",
          href: ~p"/missions/#{mission.mission_id}/comms/ground-stations"
        },
        %{label: ground_station.display_name, href: nil}
      ]
    }
  end

  defp ground_station_dto(ground_station) do
    %{
      display_name: ground_station.display_name,
      ground_station_id: ground_station.ground_station_id,
      lifecycle_state: ground_station.lifecycle_state |> Atom.to_string() |> String.upcase(),
      details_title: "Ground Station",
      description:
        "Stable setup identity for an antenna or ground-station site. Runtime contact and RF state are observed separately.",
      details: [
        %{label: "Provider", value: ground_station.provider || "Unspecified"},
        %{label: "Region", value: ground_station.region || "Unspecified"},
        %{label: "Station ID", value: ground_station.ground_station_id}
      ],
      metadata_title: "Metadata",
      metadata_json: Jason.encode!(ground_station.metadata, pretty: true)
    }
  end

  defp actions_dto(mission, ground_station) do
    %{
      edit: %{
        id: "edit-ground-station-link",
        label: "Edit",
        href:
          ~p"/missions/#{mission.mission_id}/comms/ground-stations/#{ground_station.ground_station_id}/edit"
      },
      archive: %{
        id: "archive-ground-station-button",
        label: "Archive",
        confirm: "Archive #{ground_station.display_name}?"
      }
    }
  end
end
