defmodule CadenceWeb.CommsGroundStationListLive do
  @moduledoc false
  use CadenceWeb, :live_view

  alias CadenceWeb.ListParams

  @page_size 50
  @sortable ~w(display_name)

  @impl true
  def mount(_params, _session, socket) do
    %{current_scope: scope, current_mission: mission} = socket.assigns
    ground_stations = Cadence.list_ground_stations(scope.organization_id, mission.mission_id)

    {:ok,
     socket
     |> assign(:page_title, "Ground Stations")
     |> assign(:nav_item, :comms_ground_stations)
     |> assign(:ground_stations, ground_stations)
     |> assign(:ground_station_count, length(ground_stations))
     |> assign(:ground_stations_empty?, ground_stations == [])}
  end

  @impl true
  def handle_params(params, _uri, socket) do
    list = ListParams.parse(params, sortable: @sortable, default_sort: "display_name")
    {visible, total} = filter_ground_stations(socket.assigns.ground_stations, list)

    {:noreply,
     socket
     |> assign(:list, list)
     |> assign(:filtered_count, total)
     |> stream(:ground_stations, visible,
       reset: true,
       dom_id: &"ground-station-#{&1.ground_station_id}"
     )}
  end

  @impl true
  def handle_event("search", %{"q" => q}, socket) do
    {:noreply, patch_list(socket, %{socket.assigns.list | q: q, page: 1})}
  end

  @impl true
  def handle_event("sort", %{"sort" => key}, socket) when key in @sortable do
    {:noreply, patch_list(socket, ListParams.toggle_sort(socket.assigns.list, key))}
  end

  @impl true
  def handle_event("paginate", %{"page" => page}, socket) do
    list = %{socket.assigns.list | page: ListParams.parse(%{"page" => page}, sortable: []).page}
    {:noreply, patch_list(socket, list)}
  end

  defp patch_list(socket, list) do
    mission_id = socket.assigns.current_mission.mission_id
    query = ListParams.to_query(list)
    push_patch(socket, to: ~p"/missions/#{mission_id}/comms/ground-stations?#{query}")
  end

  defp filter_ground_stations(ground_stations, %ListParams{} = list) do
    matching =
      ground_stations
      |> Enum.filter(&matches_query?(&1, list.q))
      |> Enum.sort_by(&String.downcase(&1.display_name), list.dir)

    last_page = max(ceil(length(matching) / @page_size), 1)
    page = min(list.page, last_page)
    visible = Enum.slice(matching, (page - 1) * @page_size, @page_size)
    {visible, length(matching)}
  end

  defp matches_query?(_ground_station, nil), do: true

  defp matches_query?(ground_station, q) do
    downcased = String.downcase(q)

    Enum.any?(
      [
        ground_station.display_name,
        ground_station.ground_station_id,
        ground_station.provider,
        ground_station.region
      ],
      &(is_binary(&1) and String.contains?(String.downcase(&1), downcased))
    )
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div id="comms-ground-stations-page" class="space-y-6">
      <.page_header
        title="Ground Stations"
        subtitle="Mission-owned antenna and site identities used by dashboard scope, source diagnostics, and comms setup."
        breadcrumbs={[
          {@current_mission.display_name, ~p"/missions/#{@current_mission.mission_id}"},
          {"Comms", ~p"/missions/#{@current_mission.mission_id}/comms"},
          {"Ground Stations", nil}
        ]}
      >
        <:title_suffix>{@ground_station_count} configured</:title_suffix>
        <:actions>
          <.button
            id="new-ground-station-link"
            size={:sm}
            navigate={~p"/missions/#{@current_mission.mission_id}/comms/ground-stations/new"}
          >
            New Ground Station
          </.button>
        </:actions>
      </.page_header>

      <%= if @ground_stations_empty? do %>
        <.empty_state
          title="No ground stations"
          description="Create a setup record before linking telemetry diagnostics to a stable station identity."
          action_label="New Ground Station"
          action_navigate={~p"/missions/#{@current_mission.mission_id}/comms/ground-stations/new"}
        />
      <% else %>
        <.card padding={:none}>
          <.toolbar
            id="ground-stations-toolbar"
            search={@list.q}
            placeholder="Search ground stations"
          />
          <.table
            id="ground-stations-table"
            body_id="ground-stations"
            rows={@streams.ground_stations}
            sort_by={@list.sort}
            sort_dir={@list.dir}
          >
            <:col :let={ground_station} label="Name" sort="display_name" class="font-medium">
              <.link
                navigate={
                  ~p"/missions/#{@current_mission.mission_id}/comms/ground-stations/#{ground_station.ground_station_id}"
                }
                class="text-primary hover:underline"
              >
                {ground_station.display_name}
              </.link>
            </:col>
            <:col :let={ground_station} label="Provider" mono class="uppercase text-primary/80">
              {ground_station.provider || "UNSPECIFIED"}
            </:col>
            <:col :let={ground_station} label="Region" mono class="text-base-content/70">
              {ground_station.region || "none"}
            </:col>
            <:col :let={ground_station} label="Station ID" mono class="text-base-content/70">
              {ground_station.ground_station_id}
            </:col>
          </.table>
          <p :if={@filtered_count == 0} class="py-6 text-center text-sm text-base-content/70">
            No ground stations match the current search.
          </p>
          <.pagination
            id="ground-stations-pagination"
            page={@list.page}
            page_size={50}
            total_count={@filtered_count}
          />
        </.card>
      <% end %>
    </div>
    """
  end
end
