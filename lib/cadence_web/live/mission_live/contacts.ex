defmodule CadenceWeb.MissionLive.Contacts do
  @moduledoc """
  LiveView for managing planned contacts within a mission.
  """

  use CadenceWeb, :live_view

  alias Cadence.Contacts
  alias Cadence.Contacts.Contact
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

    {spacecraft_targets, ground_station_targets} = split_targets(targets)

    socket
    |> assign(:page_title, "Contacts")
    |> assign(:contacts, contacts)
    |> assign(:contact, nil)
    |> assign(:spacecraft_targets, spacecraft_targets)
    |> assign(:ground_station_targets, ground_station_targets)
    |> assign(:form, nil)
  end

  defp apply_action(socket, :new, _params) do
    mission = socket.assigns.mission
    org_id = socket.assigns.current_scope.current_organization.id

    contacts = Contacts.list_contacts(org_id, mission_id: mission.id)
    targets = Targets.list_targets_with_preloads(mission.id)

    {spacecraft_targets, ground_station_targets} = split_targets(targets)

    contact = %Contact{state: :planned}
    form = contact |> Contact.changeset(%{}) |> to_form()

    socket
    |> assign(:page_title, "New Contact")
    |> assign(:contacts, contacts)
    |> assign(:contact, contact)
    |> assign(:spacecraft_targets, spacecraft_targets)
    |> assign(:ground_station_targets, ground_station_targets)
    |> assign(:form, form)
  end

  defp apply_action(socket, :edit, %{"contact_id" => contact_id}) do
    mission = socket.assigns.mission
    org_id = socket.assigns.current_scope.current_organization.id

    contacts = Contacts.list_contacts(org_id, mission_id: mission.id)
    targets = Targets.list_targets_with_preloads(mission.id)

    {spacecraft_targets, ground_station_targets} = split_targets(targets)

    case Contacts.get_contact(contact_id, org_id, mission.id) do
      {:ok, contact} ->
        form = contact |> Contact.changeset(%{}) |> to_form()

        socket
        |> assign(:page_title, "Edit Contact")
        |> assign(:contacts, contacts)
        |> assign(:contact, contact)
        |> assign(:spacecraft_targets, spacecraft_targets)
        |> assign(:ground_station_targets, ground_station_targets)
        |> assign(:form, form)

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
      normalized =
        cond do
          String.contains?(trimmed, "Z") or String.contains?(trimmed, "+") ->
            trimmed

          String.match?(trimmed, ~r/\d{2}:\d{2}:\d{2}$/) ->
            trimmed <> "Z"

          true ->
            trimmed <> ":00Z"
        end

      case DateTime.from_iso8601(normalized) do
        {:ok, dt, _} ->
          dt

        _ ->
          case NaiveDateTime.from_iso8601(trimmed) do
            {:ok, naive} ->
              case DateTime.from_naive(naive, "Etc/UTC") do
                {:ok, dt} -> dt
                {:error, _} -> nil
              end

            {:error, _} ->
              nil
          end
      end
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
          <:col :let={contact} label="Direction">
            <span class="badge badge-outline">{format_direction(contact.direction)}</span>
          </:col>
          <:col :let={contact} label="State">
            <.enabled_indicator enabled={contact.state == :planned} />
          </:col>
          <:action :let={contact}>
            <.link patch={~p"/missions/#{@mission}/contacts/#{contact}/edit"}>Edit</.link>
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

            <.input
              field={@form[:antenna_id]}
              type="text"
              label="Antenna ID"
              placeholder="ant-1"
              required
            />

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
end
