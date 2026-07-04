defmodule CadenceWeb.CommsGroundStationShowLive do
  @moduledoc false
  use CadenceWeb, :live_view

  @impl true
  def mount(%{"ground_station_id" => ground_station_id}, _session, socket) do
    %{current_scope: scope, current_mission: mission} = socket.assigns

    case Cadence.fetch_ground_station(
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
         |> assign(:archive_confirm, "Archive #{ground_station.display_name}?")}

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

    case Cadence.archive_ground_station(
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
    <div id="comms-ground-station-show-page" class="space-y-6">
      <.page_header
        title={@ground_station.display_name}
        subtitle={@ground_station.ground_station_id}
        breadcrumbs={[
          {@current_mission.display_name, ~p"/missions/#{@current_mission.mission_id}"},
          {"Comms", ~p"/missions/#{@current_mission.mission_id}/comms"},
          {"Ground Stations", ~p"/missions/#{@current_mission.mission_id}/comms/ground-stations"},
          {@ground_station.display_name, nil}
        ]}
      >
        <:title_suffix>{@ground_station.lifecycle_state |> Atom.to_string() |> String.upcase()}</:title_suffix>
        <:actions>
          <.button
            id="edit-ground-station-link"
            size={:sm}
            navigate={
              ~p"/missions/#{@current_mission.mission_id}/comms/ground-stations/#{@ground_station.ground_station_id}/edit"
            }
          >
            Edit
          </.button>
          <.button
            id="archive-ground-station-button"
            type="button"
            size={:sm}
            variant={:ghost}
            phx-click="archive"
            data-confirm={@archive_confirm}
          >
            Archive
          </.button>
        </:actions>
      </.page_header>

      <div class="grid gap-4 xl:grid-cols-[1fr_22rem]">
        <.card title="Ground Station">
          <p class="text-sm text-base-content/70">
            Stable setup identity for an antenna or ground-station site. Runtime contact and RF state are observed separately.
          </p>

          <div class="mt-6 space-y-1">
            <.detail_row label="Provider" value={@ground_station.provider || "Unspecified"} />
            <.detail_row label="Region" value={@ground_station.region || "Unspecified"} />
            <.detail_row label="Station ID" value={@ground_station.ground_station_id} />
          </div>
        </.card>

        <.card title="Metadata">
          <pre class="overflow-x-auto font-mono text-xs text-base-content/70">{Jason.encode!(@ground_station.metadata, pretty: true)}</pre>
        </.card>
      </div>
    </div>
    """
  end
end
