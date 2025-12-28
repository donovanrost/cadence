defmodule CadenceWeb.ProcedureLive.FormComponent do
  @moduledoc """
  Form component for creating and editing procedures.
  """
  use CadenceWeb, :live_component

  alias Cadence.Procedures
  alias Cadence.Procedures.Procedure

  @impl true
  def render(assigns) do
    ~H"""
    <div>
      <.header>
        {@title}
        <:subtitle>
          Create a procedure with sections, steps, and blocks.
        </:subtitle>
      </.header>

      <.simple_form
        for={@form}
        id="procedure-form"
        phx-target={@myself}
        phx-change="validate"
        phx-submit="save"
      >
        <.input field={@form[:name]} type="text" label="Name" required />

        <.input field={@form[:description]} type="textarea" label="Description" rows={3} />

        <div class="form-control">
          <label class="label">
            <span class="label-text">Tags</span>
          </label>
          <input
            type="text"
            name="tags_input"
            value={@tags_input}
            class="input input-bordered w-full"
            placeholder="Enter tags separated by commas (e.g., safety, recovery, phase-1)"
            phx-target={@myself}
            phx-debounce="blur"
          />
          <label class="label">
            <span class="label-text-alt text-base-content/50">
              Tags must contain only lowercase letters, numbers, and hyphens
            </span>
          </label>
          <div :if={length(@parsed_tags) > 0} class="flex flex-wrap gap-1 mt-1">
            <span :for={tag <- @parsed_tags} class="badge badge-primary badge-sm">{tag}</span>
          </div>
        </div>

        <:actions>
          <.button phx-disable-with="Creating..." class="btn-primary">Create Procedure</.button>
        </:actions>
      </.simple_form>
    </div>
    """
  end

  @impl true
  def update(%{procedure: procedure} = assigns, socket) do
    # Extract tags for editing
    tags = procedure.tags || []
    tags_input = Enum.join(tags, ", ")

    changeset = Procedure.changeset(procedure, %{})

    {:ok,
     socket
     |> assign(assigns)
     |> assign(:tags_input, tags_input)
     |> assign(:parsed_tags, tags)
     |> assign_form(changeset)}
  end

  @impl true
  def handle_event("validate", %{"procedure" => procedure_params} = params, socket) do
    # Parse tags from input
    tags_input = params["tags_input"] || socket.assigns.tags_input
    parsed_tags = parse_tags(tags_input)

    changeset =
      socket.assigns.procedure
      |> Procedure.changeset(procedure_params)
      |> Map.put(:action, :validate)

    {:noreply,
     socket
     |> assign(:tags_input, tags_input)
     |> assign(:parsed_tags, parsed_tags)
     |> assign_form(changeset)}
  end

  def handle_event("save", %{"procedure" => procedure_params} = params, socket) do
    # Parse tags from input
    tags_input = params["tags_input"] || socket.assigns.tags_input
    parsed_tags = parse_tags(tags_input)

    # Add tags to procedure params
    procedure_params = Map.put(procedure_params, "tags", parsed_tags)

    save_procedure(socket, socket.assigns.action, procedure_params)
  end

  defp save_procedure(socket, :edit, procedure_params) do
    case Procedures.update_procedure(socket.assigns.procedure, procedure_params) do
      {:ok, procedure} ->
        notify_parent({:saved, procedure})

        {:noreply,
         socket
         |> put_flash(:info, "Procedure updated successfully")
         |> push_patch(to: socket.assigns.patch)}

      {:error, %Ecto.Changeset{} = changeset} ->
        {:noreply, assign_form(socket, changeset)}
    end
  end

  defp save_procedure(socket, :new, procedure_params) do
    attrs = %{
      name: procedure_params["name"],
      description: procedure_params["description"],
      tags: procedure_params["tags"],
      organization_id: socket.assigns.mission.organization_id,
      mission_id: socket.assigns.mission.id
    }

    case Procedures.create_procedure_v2(attrs, user_id: socket.assigns.current_user.id) do
      {:ok, {procedure, version}} ->
        notify_parent({:saved, procedure, version})

        {:noreply,
         socket
         |> put_flash(:info, "Procedure created")}

      {:error, reason} ->
        {:noreply, put_flash(socket, :error, "Failed to create procedure: #{inspect(reason)}")}
    end
  end

  defp assign_form(socket, %Ecto.Changeset{} = changeset) do
    assign(socket, :form, to_form(changeset))
  end

  defp notify_parent(msg), do: send(self(), {__MODULE__, msg})

  defp parse_tags(input) when is_binary(input) do
    input
    |> String.split(",")
    |> Enum.map(&String.trim/1)
    |> Enum.map(&String.downcase/1)
    |> Enum.reject(&(&1 == ""))
    |> Enum.uniq()
  end

  defp parse_tags(_), do: []
end
