defmodule CadenceWeb.BindingLive.FormComponent do
  @moduledoc """
  Form component for creating/editing channel-transport bindings.
  """
  use CadenceWeb, :live_component

  alias Cadence.Links
  alias Cadence.Links.Binding

  @impl true
  def render(assigns) do
    ~H"""
    <div>
      <.header>
        {@title}
        <:subtitle>
          Bind channel SCID {@channel.scid}/VCID {@channel.vcid} to a transport interface.
        </:subtitle>
      </.header>

      <.simple_form
        for={@form}
        id="binding-form"
        phx-target={@myself}
        phx-change="validate"
        phx-submit="save"
      >
        <.input
          field={@form[:interface_id]}
          type="select"
          label="Transport Interface"
          prompt="Select interface"
          options={interface_options(@interfaces)}
          disabled={@action == :edit}
        />

        <.input
          field={@form[:direction]}
          type="select"
          label="Direction"
          options={[
            {"Downlink (receive)", "downlink"},
            {"Uplink (send)", "uplink"},
            {"Both", "both"}
          ]}
        />

        <.input
          field={@form[:role]}
          type="select"
          label="Role"
          options={[
            {"Primary - Main data path", "primary"},
            {"Backup - Failover path", "backup"},
            {"Replay - Historical data", "replay"},
            {"Any - No specific role", "any"}
          ]}
        />

        <.input
          field={@form[:priority]}
          type="number"
          label="Priority"
          placeholder="100"
          min="0"
          max="999"
        />
        <p class="text-xs text-base-content/50 -mt-4">
          Lower values = higher priority. Used when selecting among multiple active bindings.
        </p>

        <.input
          field={@form[:desired_state]}
          type="select"
          label="Desired State"
          options={[
            {"Inactive - Binding paused", "inactive"},
            {"Active - Binding live", "active"},
            {"Draining - Finishing pending data", "draining"}
          ]}
        />

        <:actions>
          <.button phx-disable-with="Saving...">Save Binding</.button>
        </:actions>
      </.simple_form>
    </div>
    """
  end

  defp interface_options(interfaces) do
    Enum.map(interfaces, fn interface ->
      label = "#{interface.name} (#{interface.type})"
      {label, interface.id}
    end)
  end

  @impl true
  def update(%{binding: binding} = assigns, socket) do
    changeset = Links.change_binding(binding)

    {:ok,
     socket
     |> assign(assigns)
     |> assign_form(changeset)}
  end

  @impl true
  def handle_event("validate", %{"binding" => binding_params}, socket) do
    changeset =
      socket.assigns.binding
      |> Links.change_binding(binding_params)
      |> Map.put(:action, :validate)

    {:noreply, assign_form(socket, changeset)}
  end

  def handle_event("save", %{"binding" => binding_params}, socket) do
    save_binding(socket, socket.assigns.action, binding_params)
  end

  defp save_binding(socket, :edit, binding_params) do
    scope = socket.assigns.current_scope
    mission = socket.assigns.mission
    org_id = scope.current_organization.id

    case Bodyguard.permit(Cadence.Missions.Policy, :manage_targets, scope, mission) do
      :ok ->
        case Links.update_binding(org_id, mission.id, socket.assigns.binding, binding_params) do
          {:ok, binding} ->
            notify_parent({:saved, binding})

            {:noreply,
             socket
             |> put_flash(:info, "Binding updated successfully")
             |> push_patch(to: socket.assigns.patch)}

          {:error, %Ecto.Changeset{} = changeset} ->
            {:noreply, assign_form(socket, changeset)}

          {:error, :unauthorized} ->
            {:noreply,
             socket
             |> put_flash(:error, "You don't have permission to update this binding")
             |> push_patch(to: socket.assigns.patch)}
        end

      {:error, _} ->
        {:noreply,
         socket
         |> put_flash(:error, "You don't have permission to update bindings")
         |> push_patch(to: socket.assigns.patch)}
    end
  end

  defp save_binding(socket, :new, binding_params) do
    scope = socket.assigns.current_scope
    mission = socket.assigns.mission
    org_id = scope.current_organization.id
    channel = socket.assigns.channel

    case Bodyguard.permit(Cadence.Missions.Policy, :manage_targets, scope, mission) do
      :ok ->
        # Add channel_id from the channel
        params = Map.put(binding_params, "channel_id", channel.id)

        case Links.create_binding(org_id, mission.id, params) do
          {:ok, binding} ->
            notify_parent({:saved, binding})

            {:noreply,
             socket
             |> put_flash(:info, "Binding created successfully")
             |> push_patch(to: socket.assigns.patch)}

          {:error, %Ecto.Changeset{} = changeset} ->
            {:noreply, assign_form(socket, changeset)}
        end

      {:error, _} ->
        {:noreply,
         socket
         |> put_flash(:error, "You don't have permission to create bindings")
         |> push_patch(to: socket.assigns.patch)}
    end
  end

  defp assign_form(socket, %Ecto.Changeset{} = changeset) do
    assign(socket, :form, to_form(changeset, as: :binding))
  end

  defp assign_form(socket, %Binding{} = binding) do
    changeset = Binding.update_changeset(binding, %{})
    assign(socket, :form, to_form(changeset, as: :binding))
  end

  defp notify_parent(msg), do: send(self(), {__MODULE__, msg})
end
