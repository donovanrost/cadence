defmodule CadenceWeb.InterfaceVcidLive.FormComponent do
  use CadenceWeb, :live_component

  alias Cadence.Interfaces
  alias Cadence.Interfaces.InterfaceVcid

  @impl true
  def render(assigns) do
    ~H"""
    <div>
      <.header>
        {@title}
        <:subtitle>Assign VCID routing metadata for this interface.</:subtitle>
      </.header>

      <.simple_form
        for={@form}
        id="interface-vcid-form"
        phx-target={@myself}
        phx-change="validate"
        phx-submit="save"
      >
        <.input
          field={@form[:target_id]}
          type="select"
          label="Target (optional)"
          prompt="Default (no target)"
          options={@target_options}
        />

        <.input
          field={@form[:vcid]}
          type="number"
          label="VCID"
          placeholder="0"
        />

        <div class="grid grid-cols-2 gap-4">
          <.input
            field={@form[:lane]}
            type="text"
            label="Lane Override"
            placeholder="payload"
          />
          <.input
            field={@form[:qos]}
            type="text"
            label="QoS Tag"
            placeholder="realtime"
          />
        </div>

        <.input
          field={@form[:notes]}
          type="text"
          label="Notes"
          placeholder="Housekeeping channel"
        />

        <:actions>
          <.button phx-disable-with="Saving...">Save VCID Mapping</.button>
        </:actions>
      </.simple_form>
    </div>
    """
  end

  @impl true
  def update(%{vcid: vcid, targets: targets} = assigns, socket) do
    changeset = InterfaceVcid.changeset(vcid, %{})

    target_options =
      Enum.map(targets, fn target ->
        label =
          if target.name do
            "#{target.identifier} - #{target.name}"
          else
            target.identifier
          end

        {label, target.id}
      end)

    {:ok,
     socket
     |> assign(assigns)
     |> assign(:target_options, target_options)
     |> assign_form(changeset)}
  end

  @impl true
  def handle_event("validate", %{"interface_vcid" => params}, socket) do
    changeset =
      socket.assigns.vcid
      |> InterfaceVcid.changeset(params)
      |> Map.put(:action, :validate)

    {:noreply, assign_form(socket, changeset)}
  end

  def handle_event("save", %{"interface_vcid" => params}, socket) do
    save_vcid(socket, socket.assigns.action, params)
  end

  defp save_vcid(socket, :new, params) do
    case Interfaces.create_interface_vcid(socket.assigns.interface, params) do
      {:ok, vcid} ->
        notify_parent({:saved, vcid})

        {:noreply,
         socket
         |> put_flash(:info, "VCID mapping created")
         |> push_patch(to: socket.assigns.patch)}

      {:error, %Ecto.Changeset{} = changeset} ->
        {:noreply, assign_form(socket, changeset)}
    end
  end

  defp save_vcid(socket, :edit, params) do
    case Interfaces.update_interface_vcid(socket.assigns.vcid, params) do
      {:ok, vcid} ->
        notify_parent({:saved, vcid})

        {:noreply,
         socket
         |> put_flash(:info, "VCID mapping updated")
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
