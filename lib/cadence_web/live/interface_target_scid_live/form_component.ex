defmodule CadenceWeb.InterfaceTargetScidLive.FormComponent do
  use CadenceWeb, :live_component

  alias Cadence.Interfaces
  alias Cadence.Interfaces.TargetInterface

  @impl true
  def render(assigns) do
    ~H"""
    <div>
      <.header>
        {@title}
        <:subtitle>Assign a spacecraft ID for this target on the interface.</:subtitle>
      </.header>

      <.simple_form
        for={@form}
        id="interface-target-scid-form"
        phx-target={@myself}
        phx-change="validate"
        phx-submit="save"
      >
        <.input field={@form[:scid]} type="number" label="SCID" placeholder="0" />
        <p class="mt-2 text-sm text-base-content/60">
          Leave blank to clear the SCID mapping. Valid range: 0-1023.
        </p>

        <:actions>
          <.button phx-disable-with="Saving...">Save SCID</.button>
        </:actions>
      </.simple_form>
    </div>
    """
  end

  @impl true
  def update(%{target_interface: target_interface} = assigns, socket) do
    changeset = TargetInterface.changeset(target_interface, %{})

    {:ok,
     socket
     |> assign(assigns)
     |> assign_form(changeset)}
  end

  @impl true
  def handle_event("validate", %{"target_interface" => params}, socket) do
    changeset =
      socket.assigns.target_interface
      |> TargetInterface.changeset(params)
      |> Map.put(:action, :validate)

    {:noreply, assign_form(socket, changeset)}
  end

  def handle_event("save", %{"target_interface" => params}, socket) do
    scid = normalize_scid(params)

    case Interfaces.update_target_interface_scid(socket.assigns.target_interface, scid) do
      {:ok, mapping} ->
        notify_parent({:saved, mapping})

        {:noreply,
         socket
         |> put_flash(:info, "SCID mapping updated")
         |> push_patch(to: socket.assigns.patch)}

      {:error, %Ecto.Changeset{} = changeset} ->
        {:noreply, assign_form(socket, changeset)}
    end
  end

  defp normalize_scid(%{"scid" => ""}), do: nil
  defp normalize_scid(%{"scid" => value}), do: value
  defp normalize_scid(_params), do: nil

  defp assign_form(socket, %Ecto.Changeset{} = changeset) do
    assign(socket, :form, to_form(changeset))
  end

  defp notify_parent(msg), do: send(self(), {__MODULE__, msg})
end
