defmodule CadenceWeb.LinkLive.FormComponent do
  @moduledoc """
  Form component for creating/editing links.
  """
  use CadenceWeb, :live_component

  alias Cadence.Links
  alias Cadence.Links.Link

  @impl true
  def render(assigns) do
    ~H"""
    <div>
      <.header>
        {@title}
        <:subtitle>Configure spacecraft link identified by SCID.</:subtitle>
      </.header>

      <div class="mb-4 rounded-sm border border-warning/50 bg-warning/10 px-4 py-3 text-sm text-warning">
        <span class="font-semibold">Note:</span>
        SCID is owned by the spacecraft target. Prefer creating or updating SCID on the target;
        links are derived from that value.
      </div>

      <.simple_form
        for={@form}
        id="link-form"
        phx-target={@myself}
        phx-change="validate"
        phx-submit="save"
      >
        <.input
          field={@form[:scid]}
          type="number"
          label="SCID (Spacecraft ID)"
          placeholder="42"
          disabled={@action == :edit}
        />

        <.input
          field={@form[:name]}
          type="text"
          label="Name (optional)"
          placeholder="SAT-001"
        />

        <:actions>
          <.button phx-disable-with="Saving...">Save Link</.button>
        </:actions>
      </.simple_form>
    </div>
    """
  end

  @impl true
  def update(%{link: link} = assigns, socket) do
    changeset = Links.change_link(link)

    {:ok,
     socket
     |> assign(assigns)
     |> assign_form(changeset)}
  end

  @impl true
  def handle_event("validate", %{"link" => link_params}, socket) do
    changeset =
      socket.assigns.link
      |> Links.change_link(link_params)
      |> Map.put(:action, :validate)

    {:noreply, assign_form(socket, changeset)}
  end

  def handle_event("save", %{"link" => link_params}, socket) do
    save_link(socket, socket.assigns.action, link_params)
  end

  defp save_link(socket, :edit, link_params) do
    scope = socket.assigns.current_scope
    mission = socket.assigns.mission
    org_id = scope.current_organization.id

    case Bodyguard.permit(Cadence.Missions.Policy, :manage_targets, scope, mission) do
      :ok ->
        case Links.update_link(org_id, mission.id, socket.assigns.link, link_params) do
          {:ok, link} ->
            notify_parent({:saved, link})

            {:noreply,
             socket
             |> put_flash(:info, "Link updated successfully")
             |> push_patch(to: socket.assigns.patch)}

          {:error, %Ecto.Changeset{} = changeset} ->
            {:noreply, assign_form(socket, changeset)}

          {:error, :unauthorized} ->
            {:noreply,
             socket
             |> put_flash(:error, "You don't have permission to update this link")
             |> push_patch(to: socket.assigns.patch)}
        end

      {:error, _} ->
        {:noreply,
         socket
         |> put_flash(:error, "You don't have permission to update links")
         |> push_patch(to: socket.assigns.patch)}
    end
  end

  defp save_link(socket, :new, link_params) do
    scope = socket.assigns.current_scope
    mission = socket.assigns.mission
    org_id = scope.current_organization.id

    case Bodyguard.permit(Cadence.Missions.Policy, :manage_targets, scope, mission) do
      :ok ->
        case Links.create_link(org_id, mission.id, link_params) do
          {:ok, link} ->
            notify_parent({:saved, link})

            {:noreply,
             socket
             |> put_flash(:info, "Link created successfully")
             |> push_patch(to: socket.assigns.patch)}

          {:error, %Ecto.Changeset{} = changeset} ->
            {:noreply, assign_form(socket, changeset)}
        end

      {:error, _} ->
        {:noreply,
         socket
         |> put_flash(:error, "You don't have permission to create links")
         |> push_patch(to: socket.assigns.patch)}
    end
  end

  defp assign_form(socket, %Ecto.Changeset{} = changeset) do
    assign(socket, :form, to_form(changeset, as: :link))
  end

  defp assign_form(socket, %Link{} = link) do
    changeset = Link.update_changeset(link, %{})
    assign(socket, :form, to_form(changeset, as: :link))
  end

  defp notify_parent(msg), do: send(self(), {__MODULE__, msg})
end
