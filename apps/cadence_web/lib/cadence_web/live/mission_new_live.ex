defmodule CadenceWeb.MissionNewLive do
  @moduledoc false

  # Authz note: Any active organization member can create a mission. This gate
  # should tighten once platform-wide authorization is defined (likely to the
  # :organization_admin role, possibly a finer capability).
  use CadenceWeb, :live_view

  alias Cadence.Missions.Mission

  @impl true
  def mount(_params, _session, socket) do
    {:ok,
     socket
     |> assign(:page_title, "New Mission")
     |> assign(:nav_item, :missions)
     |> assign(:slug_auto, true)
     |> assign(:last_auto_slug, "")
     |> assign(:form, empty_form())}
  end

  @impl true
  def handle_event("validate", %{"mission" => params}, socket) do
    display_name = Map.get(params, "display_name", "")
    slug_input = Map.get(params, "slug", "")

    slug_auto =
      socket.assigns.slug_auto and slug_input == socket.assigns.last_auto_slug

    {slug, last_auto_slug} =
      if slug_auto do
        derived = slugify(display_name)
        {derived, derived}
      else
        {slug_input, socket.assigns.last_auto_slug}
      end

    form = to_form(%{"display_name" => display_name, "slug" => slug}, as: :mission)

    {:noreply,
     socket
     |> assign(:form, form)
     |> assign(:slug_auto, slug_auto)
     |> assign(:last_auto_slug, last_auto_slug)}
  end

  @impl true
  def handle_event("save", %{"mission" => params}, socket) do
    display_name = normalize(params["display_name"])
    slug = normalize(params["slug"])

    cond do
      is_nil(display_name) ->
        {:noreply, put_flash(socket, :error, "Display name is required.")}

      is_nil(slug) ->
        {:noreply, put_flash(socket, :error, "Slug is required.")}

      true ->
        mission =
          Mission.new(%{
            organization_id: socket.assigns.current_scope.organization_id,
            slug: slug,
            display_name: display_name
          })

        case Cadence.persist_mission(mission) do
          {:ok, persisted} ->
            {:noreply, push_navigate(socket, to: ~p"/missions/#{persisted.mission_id}")}

          {:error, %Ecto.Changeset{} = changeset} ->
            {:noreply, put_flash(socket, :error, format_errors(changeset))}

          {:error, reason} ->
            {:noreply, put_flash(socket, :error, "Failed to create mission: #{inspect(reason)}")}
        end
    end
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="space-y-6 max-w-xl">
      <.page_header title="New Mission" back_label="Missions" back_navigate={~p"/missions"} />

      <.form for={@form} id="mission-form" phx-change="validate" phx-submit="save" class="space-y-6">
        <.input field={@form[:display_name]} type="text" label="Display Name" required />
        <.input field={@form[:slug]} type="text" label="Slug" required />
        <div class="flex items-center gap-3 border-t border-base-300/60 pt-5">
          <.button type="submit" size={:md}>
            Create Mission
          </.button>
          <.button variant={:ghost} size={:md} navigate={~p"/missions"}>Cancel</.button>
        </div>
      </.form>
    </div>
    """
  end

  defp empty_form do
    to_form(%{"display_name" => "", "slug" => ""}, as: :mission)
  end

  defp slugify(value) when is_binary(value) do
    value
    |> String.downcase()
    |> String.replace(~r/[^a-z0-9]+/, "-")
    |> String.trim("-")
  end

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
