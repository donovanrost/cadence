defmodule CadenceWeb.DatabaseLive.DatabaseFormComponent do
  @moduledoc """
  Form component for creating and editing Database entries.

  A Database is a named container for versioned DefinitionSets within a mission.
  """
  use CadenceWeb, :live_component

  alias Cadence.MissionDatabase
  alias Cadence.MissionDatabase.Database

  @impl true
  def render(assigns) do
    ~H"""
    <div>
      <.header>
        <%= @title %>
        <:subtitle>
          <%= if @action == :new do %>
            Create a new database to hold versioned command and telemetry definitions.
          <% else %>
            Update the database settings.
          <% end %>
        </:subtitle>
      </.header>

      <.simple_form
        for={@form}
        id="database-form"
        phx-target={@myself}
        phx-change="validate"
        phx-submit="save"
      >
        <.input field={@form[:name]} type="text" label="Name" placeholder="e.g., York Transport" />
        <.input
          field={@form[:slug]}
          type="text"
          label="Slug"
          placeholder="e.g., york-transport"
          phx-debounce="300"
        />
        <p class="text-sm text-zinc-500 -mt-4">
          URL-safe identifier. Auto-generated from name if left blank.
        </p>
        <.input
          field={@form[:description]}
          type="textarea"
          label="Description"
          placeholder="Optional description of this database"
        />

        <:actions>
          <.button phx-disable-with="Saving...">Save Database</.button>
        </:actions>
      </.simple_form>
    </div>
    """
  end

  @impl true
  def update(%{database: database} = assigns, socket) do
    changeset = Database.changeset(database, %{})

    {:ok,
     socket
     |> assign(assigns)
     |> assign_form(changeset)}
  end

  @impl true
  def handle_event("validate", %{"database" => database_params}, socket) do
    # Auto-generate slug from name if slug is empty
    database_params =
      if database_params["slug"] in [nil, ""] and database_params["name"] not in [nil, ""] do
        Map.put(database_params, "slug", Database.slugify(database_params["name"]))
      else
        database_params
      end

    changeset =
      socket.assigns.database
      |> Database.changeset(database_params)
      |> Map.put(:action, :validate)

    {:noreply, assign_form(socket, changeset)}
  end

  def handle_event("save", %{"database" => database_params}, socket) do
    save_database(socket, socket.assigns.action, database_params)
  end

  defp save_database(socket, :edit, database_params) do
    case MissionDatabase.update_database(socket.assigns.database, database_params) do
      {:ok, database} ->
        notify_parent({:saved, database})

        {:noreply,
         socket
         |> put_flash(:info, "Database updated successfully")
         |> push_patch(to: socket.assigns.patch)}

      {:error, %Ecto.Changeset{} = changeset} ->
        {:noreply, assign_form(socket, changeset)}
    end
  end

  defp save_database(socket, :new, database_params) do
    database_params = Map.put(database_params, "mission_id", socket.assigns.mission.id)

    case MissionDatabase.create_database(database_params) do
      {:ok, database} ->
        notify_parent({:saved, database})

        {:noreply,
         socket
         |> put_flash(:info, "Database created successfully")
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
