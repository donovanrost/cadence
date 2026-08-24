defmodule CadenceWeb.MissionNewLive do
  @moduledoc false

  # Authz note: Any active organization member can create a mission. This gate
  # should tighten once platform-wide authorization is defined (likely to the
  # :organization_admin role, possibly a finer capability).
  use CadenceWeb, :live_view

  alias Cadence.Missions.Mission
  alias Phoenix.LiveView.JS

  @impl true
  def mount(_params, _session, socket) do
    {:ok,
     socket
     |> assign(:page_title, "New Mission")
     |> assign(:nav_item, :missions)
     |> assign(:slug_auto, true)
     |> assign(:last_auto_slug, "")
     |> assign(:mission_page, mission_page_dto())
     |> assign(:mission_form, mission_form_dto("", ""))}
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

    {:noreply,
     socket
     |> assign(:mission_form, mission_form_dto(display_name, slug))
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

        case Cadence.Missions.persist_mission(mission) do
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
    <Layouts.app flash={@flash} current_scope={@current_scope}>
      <.vue
        id="mission-new-component"
        v-component="MissionNew"
        page={@mission_page}
        form={@mission_form}
        v-on:validate={JS.push("validate")}
        v-on:save={JS.push("save")}
        v-ssr={false}
        class="space-y-6 max-w-xl"
      />
    </Layouts.app>
    """
  end

  defp mission_page_dto do
    %{
      id: "mission-new-page",
      heading: "New Mission",
      breadcrumbs: [
        %{label: "Missions", href: ~p"/missions"},
        %{label: "New Mission", href: nil}
      ]
    }
  end

  defp mission_form_dto(display_name, slug) do
    %{
      id: "mission-form",
      fields: %{
        display_name: %{
          id: "mission_display_name",
          name: "mission[display_name]",
          type: "text",
          label: "Display Name",
          required: true,
          value: display_name
        },
        slug: %{
          id: "mission_slug",
          name: "mission[slug]",
          type: "text",
          label: "Slug",
          required: true,
          value: slug
        }
      },
      actions: %{
        submit: %{id: "create-mission-button", label: "Create Mission"},
        cancel: %{id: "cancel-mission-link", label: "Cancel", href: ~p"/missions"}
      }
    }
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
