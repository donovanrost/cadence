defmodule CadenceWeb.MissionLive.Contacts do
  @moduledoc """
  LiveView for managing planned contacts within a mission.
  """

  use CadenceWeb, :live_view

  alias Cadence.Application.Contacts.ContactValidator
  alias Cadence.Contacts
  alias Cadence.Contacts.Contact
  alias Cadence.GroundStations
  alias Cadence.Targets

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

    contacts = Contacts.list_contacts(org_id, mission_id: mission.id)
    targets = Targets.list_targets_with_preloads(mission.id)
    profiles = GroundStations.list_enabled_profiles(mission.id)

    {spacecraft_targets, ground_station_targets} = split_targets(targets)
    profiles_by_station = build_profiles_by_station(profiles)

    socket
    |> assign(:page_title, "Contacts")
    |> assign(:contacts, contacts)
    |> assign(:contact, nil)
    |> assign(:spacecraft_targets, spacecraft_targets)
    |> assign(:ground_station_targets, ground_station_targets)
    |> assign(:profiles_by_station, profiles_by_station)
    |> assign(:available_antennas, [])
    |> assign(:form, nil)
    |> assign_validation(org_id, mission.id, contacts)
  end

  defp apply_action(socket, :new, _params) do
    mission = socket.assigns.mission
    org_id = socket.assigns.current_scope.current_organization.id

    contacts = Contacts.list_contacts(org_id, mission_id: mission.id)
    targets = Targets.list_targets_with_preloads(mission.id)
    profiles = GroundStations.list_enabled_profiles(mission.id)

    {spacecraft_targets, ground_station_targets} = split_targets(targets)
    profiles_by_station = build_profiles_by_station(profiles)

    contact = %Contact{state: :planned}
    form = contact |> Contact.changeset(%{}) |> to_form()

    socket
    |> assign(:page_title, "New Contact")
    |> assign(:contacts, contacts)
    |> assign(:contact, contact)
    |> assign(:spacecraft_targets, spacecraft_targets)
    |> assign(:ground_station_targets, ground_station_targets)
    |> assign(:profiles_by_station, profiles_by_station)
    |> assign(:available_antennas, [])
    |> assign(:form, form)
    |> assign_validation(org_id, mission.id, contacts)
  end

  defp apply_action(socket, :edit, %{"contact_id" => contact_id}) do
    mission = socket.assigns.mission
    org_id = socket.assigns.current_scope.current_organization.id

    contacts = Contacts.list_contacts(org_id, mission_id: mission.id)
    targets = Targets.list_targets_with_preloads(mission.id)
    profiles = GroundStations.list_enabled_profiles(mission.id)

    {spacecraft_targets, ground_station_targets} = split_targets(targets)
    profiles_by_station = build_profiles_by_station(profiles)

    case Contacts.get_contact(contact_id, org_id, mission.id) do
      {:ok, contact} ->
        form = contact |> Contact.changeset(%{}) |> to_form()

        available_antennas =
          antennas_for_station(contact.ground_station_target_id, profiles_by_station)

        socket
        |> assign(:page_title, "Edit Contact")
        |> assign(:contacts, contacts)
        |> assign(:contact, contact)
        |> assign(:spacecraft_targets, spacecraft_targets)
        |> assign(:ground_station_targets, ground_station_targets)
        |> assign(:profiles_by_station, profiles_by_station)
        |> assign(:available_antennas, available_antennas)
        |> assign(:form, form)
        |> assign_validation(org_id, mission.id, contacts)

      {:error, :not_found} ->
        socket
        |> put_flash(:error, "Contact not found")
        |> push_patch(to: ~p"/missions/#{mission}/contacts")
    end
  end

  @impl true
  def handle_event("save", %{"contact" => contact_params}, socket) do
    mission = socket.assigns.mission
    org_id = socket.assigns.current_scope.current_organization.id

    contact_params =
      contact_params
      |> Map.put("start_time", parse_datetime_local(contact_params["start_time"]))
      |> Map.put("end_time", parse_datetime_local(contact_params["end_time"]))

    case socket.assigns.live_action do
      :new ->
        create_contact(socket, org_id, mission.id, contact_params)

      :edit ->
        update_contact(socket, org_id, mission.id, contact_params)
    end
  end

  @impl true
  def handle_event("validate", %{"contact" => contact_params}, socket) do
    contact = socket.assigns.contact || %Contact{state: :planned}
    changeset = Contact.changeset(contact, contact_params)
    form = to_form(changeset)

    ground_station_id = Map.get(contact_params, "ground_station_target_id")

    available_antennas =
      antennas_for_station(ground_station_id, socket.assigns.profiles_by_station)

    {:noreply,
     socket
     |> assign(:form, form)
     |> assign(:available_antennas, available_antennas)}
  end

  @impl true
  def handle_event("delete", %{"id" => contact_id}, socket) do
    mission = socket.assigns.mission
    org_id = socket.assigns.current_scope.current_organization.id

    with :ok <- authorize_manage(socket),
         {:ok, contact} <- Contacts.get_contact(contact_id, org_id, mission.id),
         {:ok, _} <- Contacts.delete_contact(org_id, mission.id, contact) do
      contacts = Contacts.list_contacts(org_id, mission_id: mission.id)

      {:noreply,
       socket
       |> put_flash(:info, "Contact deleted successfully")
       |> assign(:contacts, contacts)}
    else
      {:error, :not_found} ->
        {:noreply, put_flash(socket, :error, "Contact not found")}

      {:error, :unauthorized} ->
        {:noreply, put_flash(socket, :error, "You don't have permission to delete contacts")}

      {:error, _reason} ->
        {:noreply, put_flash(socket, :error, "Failed to delete contact")}
    end
  end

  defp create_contact(socket, org_id, mission_id, params) do
    case Contacts.create_contact(org_id, mission_id, params) do
      {:ok, _contact} ->
        contacts = Contacts.list_contacts(org_id, mission_id: mission_id)

        {:noreply,
         socket
         |> put_flash(:info, "Contact created successfully")
         |> assign(:contacts, contacts)
         |> push_patch(to: ~p"/missions/#{mission_id}/contacts")}

      {:error, changeset} ->
        {:noreply, assign(socket, :form, to_form(changeset))}
    end
  end

  defp update_contact(socket, org_id, mission_id, params) do
    contact = socket.assigns.contact

    case Contacts.update_contact(org_id, mission_id, contact, params) do
      {:ok, _contact} ->
        contacts = Contacts.list_contacts(org_id, mission_id: mission_id)

        {:noreply,
         socket
         |> put_flash(:info, "Contact updated successfully")
         |> assign(:contacts, contacts)
         |> push_patch(to: ~p"/missions/#{mission_id}/contacts")}

      {:error, :unauthorized} ->
        {:noreply, put_flash(socket, :error, "You don't have permission to update contacts")}

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

  defp split_targets(targets) do
    Enum.split_with(targets, fn target -> target.type != "ground_station" end)
  end

  defp parse_datetime_local(nil), do: nil
  defp parse_datetime_local(""), do: nil

  defp parse_datetime_local(value) when is_binary(value) do
    trimmed = String.trim(value)

    if trimmed == "" do
      nil
    else
      parse_datetime_string(trimmed)
    end
  end

  defp parse_datetime_string(value) do
    normalized = normalize_datetime_string(value)

    case DateTime.from_iso8601(normalized) do
      {:ok, dt, _} -> dt
      _ -> parse_naive_datetime(value)
    end
  end

  defp normalize_datetime_string(value) do
    cond do
      String.contains?(value, "Z") or String.contains?(value, "+") ->
        value

      String.match?(value, ~r/\d{2}:\d{2}:\d{2}$/) ->
        value <> "Z"

      true ->
        value <> ":00Z"
    end
  end

  defp parse_naive_datetime(value) do
    case NaiveDateTime.from_iso8601(value) do
      {:ok, naive} ->
        case DateTime.from_naive(naive, "Etc/UTC") do
          {:ok, dt} -> dt
          {:error, _} -> nil
        end

      {:error, _} ->
        nil
    end
  end

  defp datetime_local_value(nil), do: nil
  defp datetime_local_value(%DateTime{} = dt), do: Calendar.strftime(dt, "%Y-%m-%dT%H:%M")

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_scope} variant={:bare}>
      <div class="px-4 py-4">
        <.header>
          Contacts
          <:subtitle>Plan communication windows for scheduled transport activation</:subtitle>
          <:actions>
            <.link patch={~p"/missions/#{@mission}/contacts/new"}>
              <.button>New Contact</.button>
            </.link>
          </:actions>
        </.header>

        <.table id="contacts" rows={@contacts}>
          <:col :let={contact} label="Window">
            <div class="font-medium">
              {Calendar.strftime(contact.start_time, "%Y-%m-%d %H:%M")} – {Calendar.strftime(
                contact.end_time,
                "%Y-%m-%d %H:%M"
              )} UTC
            </div>
          </:col>
          <:col :let={contact} label="Spacecraft">
            {target_name(@spacecraft_targets, contact.spacecraft_target_id)}
          </:col>
          <:col :let={contact} label="Ground Station">
            {target_name(@ground_station_targets, contact.ground_station_target_id)}
          </:col>
          <:col :let={contact} label="Antenna">{contact.antenna_id}</:col>
          <:col :let={contact} label="Priority">
            <span class="font-mono">{contact.priority}</span>
          </:col>
          <:col :let={contact} label="Direction">
            <span class="badge badge-outline">{format_direction(contact.direction)}</span>
          </:col>
          <:col :let={contact} label="Conflicts">
            <% conflict_count = length(Map.get(@contact_conflicts, contact.id, [])) %>
            <%= if conflict_count > 0 do %>
              <.badge variant="warning" class="badge-sm">{conflict_count}</.badge>
            <% else %>
              <span class="text-xs text-gray-500">None</span>
            <% end %>
          </:col>
          <:col :let={contact} label="State">
            <.enabled_indicator enabled={contact.state == :planned} />
          </:col>
          <:action :let={contact}>
            <.link patch={~p"/missions/#{@mission}/contacts/#{contact}/edit"}>Edit</.link>
            <.link navigate={~p"/missions/#{@mission}/contacts/#{contact}/actions"}>Actions</.link>
            <.link
              phx-click={JS.push("delete", value: %{id: contact.id})}
              data-confirm="Are you sure you want to delete this contact?"
            >
              Delete
            </.link>
          </:action>
        </.table>

        <%= if @contacts == [] do %>
          <div class="text-center py-12">
            <.icon name="hero-calendar-days" class="mx-auto h-12 w-12 text-gray-400" />
            <h3 class="mt-2 text-sm font-semibold text-gray-900">No contacts</h3>
            <p class="mt-1 text-sm text-gray-500">
              Get started by creating a planned contact window.
            </p>
            <div class="mt-6">
              <.link patch={~p"/missions/#{@mission}/contacts/new"}>
                <.button>
                  <.icon name="hero-plus" class="-ml-0.5 mr-1.5 h-5 w-5" /> New Contact
                </.button>
              </.link>
            </div>
          </div>
        <% end %>
      </div>

      <.modal
        :if={@live_action in [:new, :edit]}
        id="contact-modal"
        show
        on_cancel={JS.patch(~p"/missions/#{@mission}/contacts")}
      >
        <div class="p-6">
          <h3 class="text-lg font-semibold text-gray-900">{@page_title}</h3>

          <.form
            for={@form}
            id="contact-form"
            phx-change="validate"
            phx-submit="save"
            class="mt-6 space-y-4"
          >
            <.input
              field={@form[:spacecraft_target_id]}
              type="select"
              label="Spacecraft Target"
              options={target_options(@spacecraft_targets)}
              prompt="Select spacecraft"
              required
            />

            <.input
              field={@form[:ground_station_target_id]}
              type="select"
              label="Ground Station Target"
              options={target_options(@ground_station_targets)}
              prompt="Select ground station"
              required
            />

            <%= if @available_antennas != [] do %>
              <.input
                field={@form[:antenna_id]}
                type="select"
                label="Antenna"
                options={@available_antennas}
                prompt="Select antenna"
                required
              />
            <% else %>
              <.input
                field={@form[:antenna_id]}
                type="text"
                label="Antenna ID"
                placeholder="ant-1"
                required
              />
              <p class="text-xs text-gray-500">
                No enabled ground station profile found for this station. Enter an antenna ID.
              </p>
            <% end %>

            <div class="grid grid-cols-1 gap-4 md:grid-cols-2">
              <.input
                field={@form[:start_time]}
                type="datetime-local"
                label="Start Time (UTC)"
                value={datetime_local_value(@contact && @contact.start_time)}
                required
              />

              <.input
                field={@form[:end_time]}
                type="datetime-local"
                label="End Time (UTC)"
                value={datetime_local_value(@contact && @contact.end_time)}
                required
              />
            </div>

            <div class="grid grid-cols-1 gap-4 md:grid-cols-2">
              <.input
                field={@form[:direction]}
                type="select"
                label="Direction"
                options={[
                  {"Uplink", :uplink},
                  {"Downlink", :downlink},
                  {"Bidirectional", :bidirectional}
                ]}
                required
              />

              <.input
                field={@form[:state]}
                type="select"
                label="State"
                options={[{"Planned", :planned}, {"Cancelled", :cancelled}]}
                required
              />
            </div>

            <.input
              field={@form[:priority]}
              type="number"
              label="Priority"
              min="0"
              step="1"
            />
            <p class="text-xs text-gray-500">
              Higher values take priority when contacts overlap. Running contacts are not preempted.
            </p>

            <%= if @contact do %>
              <% hard_errors = Map.get(@contact_hard_errors, @contact.id, []) %>
              <%= if hard_errors != [] do %>
                <div class="rounded-md border border-red-200 bg-red-50 p-3 text-sm text-red-800">
                  <p class="font-semibold">Hard validation issues</p>
                  <ul class="mt-2 space-y-1">
                    <%= for issue <- hard_errors do %>
                      <li>{issue.message}</li>
                    <% end %>
                  </ul>
                </div>
              <% end %>

              <% conflicts = Map.get(@contact_conflicts, @contact.id, []) %>
              <%= if conflicts != [] do %>
                <div class="rounded-md border border-amber-200 bg-amber-50 p-3 text-sm text-amber-900">
                  <p class="font-semibold">Scheduling conflicts</p>
                  <ul class="mt-2 space-y-1">
                    <%= for conflict <- conflicts do %>
                      <li>
                        {conflict_label(conflict, @ground_station_targets)}
                      </li>
                    <% end %>
                  </ul>
                </div>
              <% end %>
            <% end %>

            <div class="flex items-center justify-end gap-3">
              <.button type="submit" class="btn-primary" phx-disable-with="Saving...">
                Save Contact
              </.button>
            </div>
          </.form>
        </div>
      </.modal>
    </Layouts.app>
    """
  end

  defp target_options(targets) do
    Enum.map(targets, fn target -> {target.name, target.id} end)
  end

  defp target_name(targets, target_id) do
    case Enum.find(targets, fn target -> target.id == target_id end) do
      nil -> "Unknown"
      target -> target.name
    end
  end

  defp format_direction(direction) when is_atom(direction), do: Atom.to_string(direction)
  defp format_direction(direction), do: to_string(direction)

  defp assign_validation(socket, organization_id, mission_id, contacts) do
    validation = ContactValidator.validate(organization_id, mission_id, contacts)

    socket
    |> assign(:contact_conflicts, Map.get(validation, :conflicts, %{}))
    |> assign(:contact_hard_errors, Map.get(validation, :hard_errors, %{}))
  end

  defp build_profiles_by_station(profiles) do
    profiles
    |> Enum.group_by(&Map.get(&1, :ground_station_target_id))
    |> Map.new(fn {ground_station_id, grouped} ->
      {to_string(ground_station_id), select_profile(grouped)}
    end)
  end

  defp select_profile([]), do: nil

  defp select_profile(profiles) do
    profiles
    |> Enum.sort_by(
      fn profile ->
        {Map.get(profile, :inserted_at) || ~U[0001-01-01 00:00:00Z],
         Map.get(profile, :name) || ""}
      end,
      fn {left_dt, left_name}, {right_dt, right_name} ->
        case DateTime.compare(left_dt, right_dt) do
          :gt -> true
          :lt -> false
          :eq -> left_name <= right_name
        end
      end
    )
    |> List.first()
  end

  defp antennas_for_station(nil, _profiles_by_station), do: []
  defp antennas_for_station("", _profiles_by_station), do: []

  defp antennas_for_station(ground_station_id, profiles_by_station) do
    ground_station_id
    |> get_profile(profiles_by_station)
    |> antenna_options()
  end

  defp get_profile(ground_station_id, profiles_by_station) do
    Map.get(profiles_by_station, to_string(ground_station_id))
  end

  defp antenna_options(nil), do: []

  defp antenna_options(profile) do
    resources = profile.resources || %{}
    antennas = Map.get(resources, "antennas") || Map.get(resources, :antennas) || []

    antennas
    |> Enum.map(&antenna_option/1)
    |> Enum.reject(&invalid_antenna_option?/1)
  end

  defp antenna_option(antenna) do
    id = get_key(antenna, "id")
    name = get_key(antenna, "name")
    label = if name in [nil, ""], do: to_string(id), else: "#{name} (#{id})"
    {label, to_string(id)}
  end

  defp invalid_antenna_option?({_label, id}), do: id in [nil, ""]

  defp get_key(map, key) when is_map(map) do
    cond do
      Map.has_key?(map, key) ->
        Map.get(map, key)

      atom_key_for(key) && Map.has_key?(map, atom_key_for(key)) ->
        Map.get(map, atom_key_for(key))

      true ->
        nil
    end
  end

  defp atom_key_for("id"), do: :id
  defp atom_key_for("name"), do: :name
  defp atom_key_for(_), do: nil

  defp conflict_label(conflict, ground_station_targets) do
    case conflict.type do
      :antenna_conflict ->
        ground_station =
          target_name(ground_station_targets, conflict.resource.ground_station_target_id)

        "Overlaps contact #{conflict.with} on #{ground_station} antenna #{conflict.resource.antenna_id}"

      :spacecraft_conflict ->
        "Overlaps contact #{conflict.with} on spacecraft"

      _ ->
        "Overlaps contact #{conflict.with}"
    end
  end
end
