defmodule CadenceWeb.MissionLive.FormComponent do
  use CadenceWeb, :live_component

  alias Cadence.{Missions, Organizations}

  @impl true
  def render(assigns) do
    ~H"""
    <div>
      <.header>
        <%= @title %>
        <:subtitle>Use this form to manage mission records in your database.</:subtitle>
      </.header>

      <.simple_form
        for={@form}
        id="mission-form"
        phx-target={@myself}
        phx-change="validate"
        phx-submit="save"
      >
        <.input
          field={@form[:organization_id]}
          type="select"
          label="Organization"
          prompt="Choose an organization"
          options={@organizations}
        />
        <.input field={@form[:name]} type="text" label="Name" />
        <.input field={@form[:slug]} type="text" label="Slug" />
        <.input field={@form[:description]} type="textarea" label="Description" />
        <.input
          field={@form[:status]}
          type="select"
          label="Status"
          options={[{"Inactive", "inactive"}, {"Active", "active"}, {"Suspended", "suspended"}]}
        />
        <.input
          field={@form[:phase]}
          type="select"
          label="Phase"
          options={[
            {"Planning", "planning"},
            {"Testing", "testing"},
            {"Operational", "operational"},
            {"Decommissioned", "decommissioned"}
          ]}
        />
        <:actions>
          <.button phx-disable-with="Saving...">Save Mission</.button>
        </:actions>
      </.simple_form>
    </div>
    """
  end

  @impl true
  def update(%{mission: mission} = assigns, socket) do
    changeset = Missions.change_mission(mission)

    organizations =
      Organizations.list_organizations()
      |> Enum.map(&{&1.name, &1.id})

    {:ok,
     socket
     |> assign(assigns)
     |> assign(:organizations, organizations)
     |> assign_form(changeset)}
  end

  @impl true
  def handle_event("validate", %{"mission" => mission_params}, socket) do
    changeset =
      socket.assigns.mission
      |> Missions.change_mission(mission_params)
      |> Map.put(:action, :validate)

    {:noreply, assign_form(socket, changeset)}
  end

  def handle_event("save", %{"mission" => mission_params}, socket) do
    save_mission(socket, socket.assigns.action, mission_params)
  end

  defp save_mission(socket, :edit, mission_params) do
    scope = socket.assigns.current_scope

    case Missions.update_mission_authorized(socket.assigns.mission, mission_params, scope) do
      {:ok, mission} ->
        notify_parent({:saved, mission})

        {:noreply,
         socket
         |> put_flash(:info, "Mission updated successfully")
         |> push_patch(to: socket.assigns.patch)}

      {:error, :unauthorized} ->
        {:noreply,
         socket
         |> put_flash(:error, "You don't have permission to update this mission")
         |> push_patch(to: socket.assigns.patch)}

      {:error, %Ecto.Changeset{} = changeset} ->
        {:noreply, assign_form(socket, changeset)}
    end
  end

  defp save_mission(socket, :new, mission_params) do
    # Add creator_user_id so mission_membership is auto-created
    params_with_creator = Map.put(mission_params, "creator_user_id", socket.assigns.current_user.id)

    case Missions.create_mission(params_with_creator) do
      {:ok, mission} ->
        notify_parent({:saved, mission})

        {:noreply,
         socket
         |> put_flash(:info, "Mission created successfully")
         |> push_patch(to: socket.assigns.patch)}

      {:error, %Ecto.Changeset{} = changeset} ->
        {:noreply, assign_form(socket, changeset)}
    end
  end

  defp assign_form(socket, %Ecto.Changeset{} = changeset) do
    assign(socket, :form, to_form(changeset))
  end

  defp notify_parent(msg), do: send(self(), {__MODULE__, msg})
end
