defmodule CadenceWeb.SpacecraftNewLive do
  @moduledoc false

  # TODO(authz): Any active organization member can create a spacecraft. This
  # gate should tighten once platform-wide authorization is defined (likely to
  # the :organization_admin role, possibly a finer capability).
  use CadenceWeb, :live_view

  alias Cadence.Spacecraft

  @impl true
  def mount(_params, _session, socket) do
    {:ok,
     socket
     |> assign(:page_title, "New Spacecraft")
     |> assign(:nav_item, :spacecraft)
     |> assign(:form, empty_form())}
  end

  @impl true
  def handle_event("validate", %{"spacecraft" => params}, socket) do
    display_name = Map.get(params, "display_name", "")
    form = to_form(%{"display_name" => display_name}, as: :spacecraft)
    {:noreply, assign(socket, :form, form)}
  end

  @impl true
  def handle_event("save", %{"spacecraft" => params}, socket) do
    mission = socket.assigns.current_mission
    organization_id = socket.assigns.current_scope.organization_id
    display_name = normalize(params["display_name"])

    if is_nil(display_name) do
      {:noreply, put_flash(socket, :error, "Display name is required.")}
    else
      spacecraft =
        Spacecraft.new(%{
          mission_id: mission.mission_id,
          display_name: display_name
        })

      case Cadence.persist_spacecraft(organization_id, spacecraft) do
        {:ok, persisted} ->
          {:noreply,
           push_navigate(socket,
             to: "/missions/#{mission.mission_id}/spacecraft/#{persisted.spacecraft_id}"
           )}

        {:error, :mission_not_found} ->
          {:noreply,
           socket
           |> put_flash(:error, "Mission not found.")
           |> push_navigate(to: ~p"/missions")}

        {:error, {:organization_mission_mismatch, _, _, _}} ->
          {:noreply, put_flash(socket, :error, "Could not create spacecraft.")}

        {:error, %Ecto.Changeset{} = changeset} ->
          {:noreply, put_flash(socket, :error, format_errors(changeset))}

        {:error, reason} ->
          {:noreply, put_flash(socket, :error, "Failed to create spacecraft: #{inspect(reason)}")}
      end
    end
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="space-y-6 max-w-xl">
      <div>
        <.link
          navigate={~p"/missions/#{@current_mission.mission_id}/spacecraft"}
          class="text-sm text-primary hover:underline"
        >
          &larr; Spacecraft
        </.link>
        <h1 class="text-2xl font-bold text-base-content mt-1">New Spacecraft</h1>
      </div>

      <.form
        for={@form}
        id="spacecraft-form"
        phx-change="validate"
        phx-submit="save"
        class="space-y-4"
      >
        <.input field={@form[:display_name]} type="text" label="Display Name" required />
        <div class="flex items-center gap-3">
          <button type="submit" class="btn btn-primary">Create Spacecraft</button>
          <.link
            navigate={~p"/missions/#{@current_mission.mission_id}/spacecraft"}
            class="btn btn-ghost"
          >
            Cancel
          </.link>
        </div>
      </.form>
    </div>
    """
  end

  defp empty_form, do: to_form(%{"display_name" => ""}, as: :spacecraft)

  defp normalize(value) when is_binary(value) do
    case String.trim(value) do
      "" -> nil
      trimmed -> trimmed
    end
  end

  defp normalize(_other), do: nil

  defp format_errors(%Ecto.Changeset{} = changeset) do
    Ecto.Changeset.traverse_errors(changeset, fn {msg, opts} ->
      Enum.reduce(opts, msg, fn {key, value}, acc ->
        String.replace(acc, "%{#{key}}", to_string(value))
      end)
    end)
    |> Enum.map_join(", ", fn {field, messages} ->
      "#{Phoenix.Naming.humanize(field)} #{Enum.join(messages, ", ")}"
    end)
  end
end
