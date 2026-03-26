defmodule CadenceWeb.MissionLive.ContactActions do
  @moduledoc """
  LiveView for managing contact command actions.
  """

  use CadenceWeb, :live_view

  alias Cadence.Contacts
  alias Cadence.Contacts.ContactCommandAction

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

  defp apply_action(socket, :index, %{"contact_id" => contact_id}) do
    case fetch_contact(socket, contact_id) do
      {:ok, contact} ->
        actions = list_actions(socket, contact.id)

        socket
        |> assign(:page_title, "Contact Actions")
        |> assign(:contact, contact)
        |> assign(:actions, actions)
        |> assign(:action, nil)
        |> assign(:form, nil)

      {:error, :not_found} ->
        socket
        |> put_flash(:error, "Contact not found")
        |> push_patch(to: ~p"/missions/#{socket.assigns.mission}/contacts")
    end
  end

  defp apply_action(socket, :new, %{"contact_id" => contact_id}) do
    case fetch_contact(socket, contact_id) do
      {:ok, contact} ->
        action = %ContactCommandAction{
          contact_id: contact.id,
          state: :planned,
          gate: :uplink_ready,
          order: 0,
          command_ref: %{}
        }

        socket
        |> assign(:page_title, "New Contact Action")
        |> assign(:contact, contact)
        |> assign(:actions, list_actions(socket, contact.id))
        |> assign(:action, action)
        |> assign(:form, build_form(action))

      {:error, :not_found} ->
        socket
        |> put_flash(:error, "Contact not found")
        |> push_patch(to: ~p"/missions/#{socket.assigns.mission}/contacts")
    end
  end

  defp apply_action(socket, :edit, %{"contact_id" => contact_id, "action_id" => action_id}) do
    with {:ok, contact} <- fetch_contact(socket, contact_id),
         {:ok, action} <-
           Contacts.get_contact_command_action(
             action_id,
             socket.assigns.current_scope.current_organization.id,
             socket.assigns.mission.id
           ) do
      socket
      |> assign(:page_title, "Edit Contact Action")
      |> assign(:contact, contact)
      |> assign(:actions, list_actions(socket, contact.id))
      |> assign(:action, action)
      |> assign(:form, build_form(action))
    else
      {:error, :not_found} ->
        socket
        |> put_flash(:error, "Action not found")
        |> push_patch(to: ~p"/missions/#{socket.assigns.mission}/contacts/#{contact_id}/actions")
    end
  end

  @impl true
  def handle_event("validate", %{"action" => action_params}, socket) do
    action = socket.assigns.action || %ContactCommandAction{}
    {_params, changeset} = build_changeset(action, action_params, socket.assigns.contact.id)

    form = to_form(changeset)

    {:noreply, socket |> assign(:form, form)}
  end

  @impl true
  def handle_event("save", %{"action" => action_params}, socket) do
    mission = socket.assigns.mission
    org_id = socket.assigns.current_scope.current_organization.id
    contact_id = socket.assigns.contact.id

    {params, changeset} = build_changeset(socket.assigns.action, action_params, contact_id)

    if changeset.valid? do
      case socket.assigns.live_action do
        :new ->
          create_action(socket, org_id, mission.id, params)

        :edit ->
          update_action(socket, org_id, mission.id, socket.assigns.action, params)
      end
    else
      {:noreply, assign(socket, :form, to_form(changeset))}
    end
  end

  @impl true
  def handle_event("delete", %{"id" => action_id}, socket) do
    mission = socket.assigns.mission
    org_id = socket.assigns.current_scope.current_organization.id

    with {:ok, action} <- Contacts.get_contact_command_action(action_id, org_id, mission.id),
         {:ok, _} <- Contacts.delete_contact_command_action(org_id, mission.id, action) do
      actions = list_actions(socket, action.contact_id)

      {:noreply,
       socket
       |> put_flash(:info, "Action deleted successfully")
       |> assign(:actions, actions)}
    else
      {:error, :not_found} ->
        {:noreply, put_flash(socket, :error, "Action not found")}

      {:error, :unauthorized} ->
        {:noreply, put_flash(socket, :error, "You don't have permission to delete actions")}

      {:error, _reason} ->
        {:noreply, put_flash(socket, :error, "Failed to delete action")}
    end
  end

  defp create_action(socket, org_id, mission_id, params) do
    case Contacts.create_contact_command_action(org_id, mission_id, params) do
      {:ok, _action} ->
        actions = list_actions(socket, socket.assigns.contact.id)

        {:noreply,
         socket
         |> put_flash(:info, "Action created successfully")
         |> assign(:actions, actions)
         |> push_patch(
           to: ~p"/missions/#{mission_id}/contacts/#{socket.assigns.contact.id}/actions"
         )}

      {:error, changeset} ->
        {:noreply, assign(socket, :form, to_form(changeset))}
    end
  end

  defp update_action(socket, org_id, mission_id, action, params) do
    case Contacts.update_contact_command_action(org_id, mission_id, action, params) do
      {:ok, _action} ->
        actions = list_actions(socket, socket.assigns.contact.id)

        {:noreply,
         socket
         |> put_flash(:info, "Action updated successfully")
         |> assign(:actions, actions)
         |> push_patch(
           to: ~p"/missions/#{mission_id}/contacts/#{socket.assigns.contact.id}/actions"
         )}

      {:error, :unauthorized} ->
        {:noreply, put_flash(socket, :error, "You don't have permission to update actions")}

      {:error, changeset} ->
        {:noreply, assign(socket, :form, to_form(changeset))}
    end
  end

  defp list_actions(socket, contact_id) do
    org_id = socket.assigns.current_scope.current_organization.id

    Contacts.list_contact_command_actions(org_id,
      mission_id: socket.assigns.mission.id,
      contact_id: contact_id
    )
  end

  defp fetch_contact(socket, contact_id) do
    mission = socket.assigns.mission
    org_id = socket.assigns.current_scope.current_organization.id
    Contacts.get_contact(contact_id, org_id, mission.id)
  end

  defp build_form(%ContactCommandAction{} = action) do
    command_ref = action.command_ref || %{}

    action = %ContactCommandAction{
      action
      | command_name: fetch_value(command_ref, :command_name),
        parameters_json: encode_params(fetch_value(command_ref, :parameters))
    }

    action
    |> ContactCommandAction.changeset(%{})
    |> to_form()
  end

  defp build_changeset(action, params, contact_id) do
    command_name = Map.get(params, "command_name")
    parameters_json = Map.get(params, "parameters_json", "")

    {parameters, params_errors} = parse_parameters(parameters_json)

    params =
      params
      |> Map.put("contact_id", contact_id)
      |> Map.put("command_ref", %{
        "command_name" => command_name,
        "parameters" => parameters || %{}
      })

    changeset = ContactCommandAction.changeset(action || %ContactCommandAction{}, params)

    changeset =
      if params_errors do
        Ecto.Changeset.add_error(changeset, :parameters_json, params_errors)
      else
        changeset
      end

    {params, changeset}
  end

  defp parse_parameters(""), do: {%{}, nil}

  defp parse_parameters(json) do
    case Jason.decode(json) do
      {:ok, value} when is_map(value) -> {value, nil}
      {:ok, _} -> {%{}, "must be a JSON object"}
      {:error, _} -> {%{}, "invalid JSON"}
    end
  end

  defp encode_params(nil), do: ""

  defp encode_params(params) when is_map(params) do
    case Jason.encode(params) do
      {:ok, json} -> json
      {:error, _} -> ""
    end
  end

  defp fetch_value(map, key) when is_map(map) do
    case Map.fetch(map, key) do
      {:ok, value} -> value
      :error -> Map.get(map, Atom.to_string(key))
    end
  end

  defp gate_options do
    [
      {"Uplink ready", :uplink_ready},
      {"Active", :active}
    ]
  end

  defp state_options do
    [
      {"Planned", :planned},
      {"Cancelled", :cancelled}
    ]
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_scope}>
      <div class="p-6 space-y-6">
        <.header>
          Contact Actions
          <:subtitle>
            {@mission.name} · Contact {@contact.id}
          </:subtitle>
        </.header>

        <div class="text-sm text-base-content/60">
          Actions will run when the selected gate becomes satisfied (default: uplink_ready).
        </div>

        <div class="grid grid-cols-1 lg:grid-cols-3 gap-6">
          <div class="lg:col-span-2">
            <div class="flex items-center justify-between mb-4">
              <h2 class="text-sm font-semibold uppercase tracking-wide text-base-content/70">
                Actions
              </h2>

              <.link
                navigate={~p"/missions/#{@mission.id}/contacts/#{@contact.id}/actions/new"}
                class="btn btn-sm btn-primary"
                id="new-contact-action"
              >
                <.icon name="hero-plus" class="size-4" /> New Action
              </.link>
            </div>

            <div class="overflow-x-auto rounded-lg border border-base-200">
              <table class="table" id="contact-actions-table">
                <thead>
                  <tr>
                    <th>Order</th>
                    <th>Gate</th>
                    <th>Command</th>
                    <th>State</th>
                    <th></th>
                  </tr>
                </thead>
                <tbody>
                  <%= for action <- @actions do %>
                    <tr id={"contact-action-#{action.id}"}>
                      <td>{action.order}</td>
                      <td>{action.gate}</td>
                      <td>{fetch_value(action.command_ref || %{}, :command_name) || "(unset)"}</td>
                      <td>{action.state}</td>
                      <td class="text-right">
                        <div class="flex items-center justify-end gap-2">
                          <.link
                            navigate={
                              ~p"/missions/#{@mission.id}/contacts/#{@contact.id}/actions/#{action.id}/edit"
                            }
                            class="btn btn-ghost btn-xs"
                          >
                            Edit
                          </.link>
                          <.button
                            type="button"
                            class="btn btn-ghost btn-xs text-error"
                            phx-click="delete"
                            phx-value-id={action.id}
                          >
                            Delete
                          </.button>
                        </div>
                      </td>
                    </tr>
                  <% end %>
                </tbody>
              </table>
            </div>
          </div>

          <div class="lg:col-span-1">
            <%= if @form do %>
              <div class="card bg-base-200">
                <div class="card-body">
                  <h2 class="card-title text-sm uppercase tracking-wide text-base-content/70">
                    {@page_title}
                  </h2>

                  <.form
                    for={@form}
                    id="contact-action-form"
                    phx-change="validate"
                    phx-submit="save"
                  >
                    <.input field={@form[:gate]} type="select" label="Gate" options={gate_options()} />
                    <.input field={@form[:order]} type="number" label="Order" />
                    <.input
                      field={@form[:state]}
                      type="select"
                      label="State"
                      options={state_options()}
                    />
                    <.input field={@form[:command_name]} type="text" label="Command Name" />

                    <.input
                      field={@form[:parameters_json]}
                      type="textarea"
                      label="Parameters (JSON)"
                      placeholder="e.g. param: 1"
                    />

                    <div class="text-xs text-base-content/60">
                      Will run when: {@form[:gate].value || :uplink_ready}
                    </div>

                    <div class="mt-4 flex gap-2">
                      <.button type="submit" class="btn btn-primary" id="save-contact-action">
                        Save Action
                      </.button>
                      <.link
                        navigate={~p"/missions/#{@mission.id}/contacts/#{@contact.id}/actions"}
                        class="btn btn-ghost"
                      >
                        Cancel
                      </.link>
                    </div>
                  </.form>
                </div>
              </div>
            <% end %>
          </div>
        </div>
      </div>
    </Layouts.app>
    """
  end
end
