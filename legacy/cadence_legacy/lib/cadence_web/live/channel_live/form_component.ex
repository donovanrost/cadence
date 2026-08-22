defmodule CadenceWeb.ChannelLive.FormComponent do
  @moduledoc """
  Form component for creating/editing channels.
  """
  use CadenceWeb, :live_component

  alias Cadence.Links
  alias Cadence.Links.Channel

  @impl true
  def render(assigns) do
    ~H"""
    <div>
      <.header>
        {@title}
        <:subtitle>Configure virtual channel for SCID {@link.scid}.</:subtitle>
      </.header>

      <.simple_form
        for={@form}
        id="channel-form"
        phx-target={@myself}
        phx-change="validate"
        phx-submit="save"
      >
        <div class="grid grid-cols-2 gap-4">
          <.input
            field={@form[:vcid]}
            type="number"
            label="VCID (0-63)"
            placeholder="0"
            min="0"
            max="63"
            disabled={@action == :edit}
          />
          <.input
            field={@form[:map_id]}
            type="number"
            label="MAP ID (optional)"
            placeholder="0"
            min="0"
            max="63"
          />
        </div>

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

        <.input field={@form[:enabled]} type="checkbox" label="Enabled" />

        <:actions>
          <.button phx-disable-with="Saving...">Save Channel</.button>
        </:actions>
      </.simple_form>
    </div>
    """
  end

  @impl true
  def update(%{channel: channel} = assigns, socket) do
    changeset = Links.change_channel(channel)

    {:ok,
     socket
     |> assign(assigns)
     |> assign_form(changeset)}
  end

  @impl true
  def handle_event("validate", %{"channel" => channel_params}, socket) do
    changeset =
      socket.assigns.channel
      |> Links.change_channel(channel_params)
      |> Map.put(:action, :validate)

    {:noreply, assign_form(socket, changeset)}
  end

  def handle_event("save", %{"channel" => channel_params}, socket) do
    save_channel(socket, socket.assigns.action, channel_params)
  end

  defp save_channel(socket, :edit, channel_params) do
    scope = socket.assigns.current_scope
    mission = socket.assigns.mission
    org_id = scope.current_organization.id

    case Bodyguard.permit(Cadence.Missions.Policy, :manage_targets, scope, mission) do
      :ok ->
        case Links.update_channel(org_id, mission.id, socket.assigns.channel, channel_params) do
          {:ok, channel} ->
            notify_parent({:saved, channel})

            {:noreply,
             socket
             |> put_flash(:info, "Channel updated successfully")
             |> push_patch(to: socket.assigns.patch)}

          {:error, %Ecto.Changeset{} = changeset} ->
            {:noreply, assign_form(socket, changeset)}

          {:error, :unauthorized} ->
            {:noreply,
             socket
             |> put_flash(:error, "You don't have permission to update this channel")
             |> push_patch(to: socket.assigns.patch)}
        end

      {:error, _} ->
        {:noreply,
         socket
         |> put_flash(:error, "You don't have permission to update channels")
         |> push_patch(to: socket.assigns.patch)}
    end
  end

  defp save_channel(socket, :new, channel_params) do
    scope = socket.assigns.current_scope
    mission = socket.assigns.mission
    org_id = scope.current_organization.id
    link = socket.assigns.link

    case Bodyguard.permit(Cadence.Missions.Policy, :manage_targets, scope, mission) do
      :ok ->
        # Add link_id and scid from the link
        params =
          channel_params
          |> Map.put("link_id", link.id)
          |> Map.put("scid", link.scid)

        case Links.create_channel(org_id, mission.id, params) do
          {:ok, channel} ->
            notify_parent({:saved, channel})

            {:noreply,
             socket
             |> put_flash(:info, "Channel created successfully")
             |> push_patch(to: socket.assigns.patch)}

          {:error, %Ecto.Changeset{} = changeset} ->
            {:noreply, assign_form(socket, changeset)}
        end

      {:error, _} ->
        {:noreply,
         socket
         |> put_flash(:error, "You don't have permission to create channels")
         |> push_patch(to: socket.assigns.patch)}
    end
  end

  defp assign_form(socket, %Ecto.Changeset{} = changeset) do
    assign(socket, :form, to_form(changeset, as: :channel))
  end

  defp assign_form(socket, %Channel{} = channel) do
    changeset = Channel.update_changeset(channel, %{})
    assign(socket, :form, to_form(changeset, as: :channel))
  end

  defp notify_parent(msg), do: send(self(), {__MODULE__, msg})
end
