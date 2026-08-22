defmodule CadenceWeb.MissionLive.GroundStationProfiles do
  @moduledoc """
  LiveView for managing ground station profiles within a mission.
  """

  use CadenceWeb, :live_view

  alias Cadence.GroundStations
  alias Cadence.GroundStations.GroundStationProfile
  alias Cadence.Targets
  alias Cadence.Transports

  @impl true
  def mount(_params, _session, socket) do
    {:ok, socket}
  end

  @impl true
  def handle_params(params, _uri, socket) do
    mission = socket.assigns.mission

    case Bodyguard.permit(Cadence.Missions.Policy, :view, socket.assigns.current_scope, mission) do
      :ok ->
        {:noreply, apply_action(socket, socket.assigns.live_action, params)}

      {:error, _} ->
        {:noreply,
         socket
         |> put_flash(:error, "You don't have permission to view this mission")
         |> push_navigate(to: ~p"/missions")}
    end
  end

  defp apply_action(socket, :index, _params) do
    mission = socket.assigns.mission
    org_id = socket.assigns.current_scope.current_organization.id

    profiles = GroundStations.list_profiles(org_id, mission_id: mission.id)
    ground_stations = ground_station_targets(mission.id)
    transports = Transports.list_interfaces(org_id, mission.id)

    socket
    |> assign(:page_title, "Ground Station Profiles")
    |> assign(:profiles, profiles)
    |> assign(:profile, nil)
    |> assign(:ground_stations, ground_stations)
    |> assign(:transport_options, transport_options(transports))
    |> assign(:antennas, [])
    |> assign(:form, nil)
  end

  defp apply_action(socket, :new, _params) do
    mission = socket.assigns.mission
    org_id = socket.assigns.current_scope.current_organization.id

    profiles = GroundStations.list_profiles(org_id, mission_id: mission.id)
    ground_stations = ground_station_targets(mission.id)
    transports = Transports.list_interfaces(org_id, mission.id)

    profile = %GroundStationProfile{enabled: true}
    form = profile |> GroundStationProfile.changeset(%{}) |> to_form()

    socket
    |> assign(:page_title, "New Ground Station Profile")
    |> assign(:profiles, profiles)
    |> assign(:profile, profile)
    |> assign(:ground_stations, ground_stations)
    |> assign(:transport_options, transport_options(transports))
    |> assign(:antennas, [default_antenna()])
    |> assign(:form, form)
  end

  defp apply_action(socket, :edit, %{"profile_id" => profile_id}) do
    mission = socket.assigns.mission
    org_id = socket.assigns.current_scope.current_organization.id

    profiles = GroundStations.list_profiles(org_id, mission_id: mission.id)
    ground_stations = ground_station_targets(mission.id)
    transports = Transports.list_interfaces(org_id, mission.id)

    case GroundStations.get_profile(profile_id, org_id, mission.id) do
      {:ok, profile} ->
        form = profile |> GroundStationProfile.changeset(%{}) |> to_form()
        antennas = profile_antennas(profile)

        socket
        |> assign(:page_title, "Edit Ground Station Profile")
        |> assign(:profiles, profiles)
        |> assign(:profile, profile)
        |> assign(:ground_stations, ground_stations)
        |> assign(:transport_options, transport_options(transports))
        |> assign(:antennas, antennas)
        |> assign(:form, form)

      {:error, :not_found} ->
        socket
        |> put_flash(:error, "Ground station profile not found")
        |> push_patch(to: ~p"/missions/#{mission}/ground-station-profiles")
    end
  end

  @impl true
  def handle_event("add_antenna", _params, socket) do
    {:noreply, update(socket, :antennas, fn antennas -> antennas ++ [default_antenna()] end)}
  end

  @impl true
  def handle_event("remove_antenna", %{"index" => index}, socket) do
    antennas = List.delete_at(socket.assigns.antennas, parse_index(index))
    antennas = if antennas == [], do: [default_antenna()], else: antennas
    {:noreply, assign(socket, :antennas, antennas)}
  end

  @impl true
  def handle_event("save", %{"ground_station_profile" => profile_params}, socket) do
    mission = socket.assigns.mission
    org_id = socket.assigns.current_scope.current_organization.id

    antennas = parse_antennas(profile_params)

    profile_params =
      profile_params
      |> Map.put("resources", %{"antennas" => antennas})

    case socket.assigns.live_action do
      :new ->
        create_profile(socket, org_id, mission.id, profile_params)

      :edit ->
        update_profile(socket, org_id, mission.id, profile_params)
    end
  end

  @impl true
  def handle_event("delete", %{"id" => profile_id}, socket) do
    mission = socket.assigns.mission
    org_id = socket.assigns.current_scope.current_organization.id

    with :ok <- authorize_manage(socket),
         {:ok, profile} <- GroundStations.get_profile(profile_id, org_id, mission.id),
         {:ok, _} <- GroundStations.delete_profile(org_id, mission.id, profile) do
      profiles = GroundStations.list_profiles(org_id, mission_id: mission.id)

      {:noreply,
       socket
       |> put_flash(:info, "Profile deleted successfully")
       |> assign(:profiles, profiles)}
    else
      {:error, :not_found} ->
        {:noreply, put_flash(socket, :error, "Profile not found")}

      {:error, :unauthorized} ->
        {:noreply, put_flash(socket, :error, "You don't have permission to delete profiles")}

      {:error, _reason} ->
        {:noreply, put_flash(socket, :error, "Failed to delete profile")}
    end
  end

  defp create_profile(socket, org_id, mission_id, params) do
    case GroundStations.create_profile(org_id, mission_id, params) do
      {:ok, _profile} ->
        profiles = GroundStations.list_profiles(org_id, mission_id: mission_id)

        {:noreply,
         socket
         |> put_flash(:info, "Profile created successfully")
         |> assign(:profiles, profiles)
         |> push_patch(to: ~p"/missions/#{mission_id}/ground-station-profiles")}

      {:error, changeset} ->
        {:noreply, assign(socket, :form, to_form(changeset))}
    end
  end

  defp update_profile(socket, org_id, mission_id, params) do
    profile = socket.assigns.profile

    case GroundStations.update_profile(org_id, mission_id, profile, params) do
      {:ok, _profile} ->
        profiles = GroundStations.list_profiles(org_id, mission_id: mission_id)

        {:noreply,
         socket
         |> put_flash(:info, "Profile updated successfully")
         |> assign(:profiles, profiles)
         |> push_patch(to: ~p"/missions/#{mission_id}/ground-station-profiles")}

      {:error, :unauthorized} ->
        {:noreply, put_flash(socket, :error, "You don't have permission to update profiles")}

      {:error, changeset} ->
        {:noreply, assign(socket, :form, to_form(changeset))}
    end
  end

  defp authorize_manage(socket) do
    mission = socket.assigns.mission
    scope = socket.assigns.current_scope

    case Bodyguard.permit(Cadence.Missions.Policy, :manage_targets, scope, mission) do
      :ok -> :ok
      {:error, _} -> {:error, :unauthorized}
    end
  end

  defp ground_station_targets(mission_id) do
    Targets.list_targets_with_preloads(mission_id)
    |> Enum.filter(fn target -> target.type == "ground_station" end)
  end

  defp transport_options(transports) do
    Enum.map(transports, fn transport -> {transport.name, transport.id} end)
  end

  defp profile_antennas(profile) do
    resources = profile.resources || %{}
    antennas = Map.get(resources, "antennas") || Map.get(resources, :antennas) || []
    if antennas == [], do: [default_antenna()], else: antennas
  end

  defp parse_antennas(profile_params) do
    profile_params
    |> Map.get("antennas", %{})
    |> Enum.sort_by(fn {index, _} -> parse_index(index) end)
    |> Enum.map(fn {_index, antenna} -> normalize_antenna(antenna) end)
    |> Enum.reject(&empty_antenna?/1)
  end

  defp normalize_antenna(antenna) do
    %{
      "id" => presence(antenna["id"]),
      "name" => presence(antenna["name"]),
      "activation" => %{
        "uplink_transport_id" => presence(antenna["uplink_transport_id"]),
        "downlink_transport_id" => presence(antenna["downlink_transport_id"])
      }
    }
  end

  defp empty_antenna?(antenna) do
    antenna["id"] in [nil, ""] and antenna["name"] in [nil, ""]
  end

  defp presence(""), do: nil
  defp presence(value), do: value

  defp parse_index(nil), do: 0

  defp parse_index(value) do
    case Integer.parse(to_string(value)) do
      {int, _} -> int
      :error -> 0
    end
  end

  defp default_antenna do
    %{
      "id" => "",
      "name" => "",
      "uplink_transport_id" => "",
      "downlink_transport_id" => ""
    }
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_scope} variant={:bare}>
      <div class="px-4 py-4">
        <.header>
          Ground Station Profiles
          <:subtitle>Map antennas to transports for contact activation</:subtitle>
          <:actions>
            <.link patch={~p"/missions/#{@mission}/ground-station-profiles/new"}>
              <.button>New Profile</.button>
            </.link>
          </:actions>
        </.header>

        <.table id="ground-station-profiles" rows={@profiles}>
          <:col :let={profile} label="Name">{profile.name}</:col>
          <:col :let={profile} label="Ground Station">
            {ground_station_name(@ground_stations, profile.ground_station_target_id)}
          </:col>
          <:col :let={profile} label="Antennas">
            {antenna_count(profile.resources)}
          </:col>
          <:col :let={profile} label="Enabled">
            <.enabled_indicator enabled={profile.enabled} />
          </:col>
          <:action :let={profile}>
            <.link patch={~p"/missions/#{@mission}/ground-station-profiles/#{profile}/edit"}>
              Edit
            </.link>
            <.link
              phx-click={JS.push("delete", value: %{id: profile.id})}
              data-confirm="Are you sure you want to delete this profile?"
            >
              Delete
            </.link>
          </:action>
        </.table>

        <%= if @profiles == [] do %>
          <div class="text-center py-12">
            <.icon name="hero-signal" class="mx-auto h-12 w-12 text-gray-400" />
            <h3 class="mt-2 text-sm font-semibold text-gray-900">No profiles</h3>
            <p class="mt-1 text-sm text-gray-500">
              Create a ground station profile to map antennas to transports.
            </p>
            <div class="mt-6">
              <.link patch={~p"/missions/#{@mission}/ground-station-profiles/new"}>
                <.button>
                  <.icon name="hero-plus" class="-ml-0.5 mr-1.5 h-5 w-5" /> New Profile
                </.button>
              </.link>
            </div>
          </div>
        <% end %>
      </div>

      <.modal
        :if={@live_action in [:new, :edit]}
        id="ground-station-profile-modal"
        show
        on_cancel={JS.patch(~p"/missions/#{@mission}/ground-station-profiles")}
      >
        <div class="p-6">
          <h3 class="text-lg font-semibold text-gray-900">{@page_title}</h3>

          <.form
            for={@form}
            id="ground-station-profile-form"
            phx-submit="save"
            class="mt-6 space-y-4"
          >
            <.input
              field={@form[:ground_station_target_id]}
              type="select"
              label="Ground Station"
              options={ground_station_options(@ground_stations)}
              prompt="Select ground station"
              required
            />

            <.input
              field={@form[:name]}
              type="text"
              label="Profile Name"
              placeholder="Primary Station"
              required
            />

            <.input
              field={@form[:enabled]}
              type="checkbox"
              label="Enabled"
            />

            <div class="border rounded-lg p-4 bg-gray-50">
              <div class="flex items-center justify-between">
                <h4 class="text-sm font-semibold text-gray-900">Antennas</h4>
                <.button type="button" phx-click="add_antenna" class="btn-sm">
                  <.icon name="hero-plus" class="h-4 w-4" /> Add Antenna
                </.button>
              </div>

              <div class="mt-4 space-y-4">
                <%= for {antenna, index} <- Enum.with_index(@antennas) do %>
                  <div class="border rounded-lg p-4 bg-white">
                    <div class="flex items-center justify-between">
                      <h5 class="text-sm font-medium text-gray-900">Antenna {index + 1}</h5>
                      <.button
                        type="button"
                        phx-click="remove_antenna"
                        phx-value-index={index}
                        class="btn-ghost btn-xs"
                      >
                        Remove
                      </.button>
                    </div>

                    <div class="grid grid-cols-1 gap-4 md:grid-cols-2 mt-3">
                      <.input
                        name={"ground_station_profile[antennas][#{index}][id]"}
                        id={"ground_station_profile_antennas_#{index}_id"}
                        type="text"
                        label="Antenna ID"
                        value={antenna["id"]}
                        required
                      />

                      <.input
                        name={"ground_station_profile[antennas][#{index}][name]"}
                        id={"ground_station_profile_antennas_#{index}_name"}
                        type="text"
                        label="Antenna Name"
                        value={antenna["name"]}
                      />
                    </div>

                    <div class="grid grid-cols-1 gap-4 md:grid-cols-2 mt-2">
                      <.input
                        name={"ground_station_profile[antennas][#{index}][uplink_transport_id]"}
                        id={"ground_station_profile_antennas_#{index}_uplink"}
                        type="select"
                        label="Uplink Transport"
                        options={@transport_options}
                        prompt="Select transport"
                        value={antenna["uplink_transport_id"]}
                      />

                      <.input
                        name={"ground_station_profile[antennas][#{index}][downlink_transport_id]"}
                        id={"ground_station_profile_antennas_#{index}_downlink"}
                        type="select"
                        label="Downlink Transport"
                        options={@transport_options}
                        prompt="Select transport"
                        value={antenna["downlink_transport_id"]}
                      />
                    </div>
                  </div>
                <% end %>
              </div>
            </div>

            <div class="flex items-center justify-end gap-3">
              <.button type="submit" class="btn-primary" phx-disable-with="Saving...">
                Save Profile
              </.button>
            </div>
          </.form>
        </div>
      </.modal>
    </Layouts.app>
    """
  end

  defp ground_station_options(targets) do
    Enum.map(targets, fn target -> {target.name, target.id} end)
  end

  defp ground_station_name(targets, target_id) do
    case Enum.find(targets, fn target -> target.id == target_id end) do
      nil -> "Unknown"
      target -> target.name
    end
  end

  defp antenna_count(resources) when is_map(resources) do
    antennas = Map.get(resources, "antennas") || Map.get(resources, :antennas) || []
    length(antennas)
  end

  defp antenna_count(_), do: 0
end
