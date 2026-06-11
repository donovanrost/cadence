defmodule CadenceWeb.SpacecraftNewLive do
  @moduledoc false

  # Authz note: Any active organization member can create a spacecraft. This
  # gate should tighten once platform-wide authorization is defined (likely to
  # the :organization_admin role, possibly a finer capability).
  use CadenceWeb, :live_view

  alias Cadence.Spacecraft

  @impl true
  def mount(_params, _session, socket) do
    organization_id = socket.assigns.current_scope.organization_id
    mission_id = socket.assigns.current_mission.mission_id
    available_types = Cadence.list_spacecraft_types(organization_id, mission_id)

    {:ok,
     socket
     |> assign(:page_title, "New Spacecraft")
     |> assign(:nav_item, :spacecraft)
     |> assign(:available_types, available_types)
     |> assign(:form, empty_form())}
  end

  @impl true
  def handle_event("validate", %{"spacecraft" => params}, socket) do
    {:noreply, assign(socket, :form, form_from_params(params))}
  end

  @impl true
  def handle_event("save", %{"spacecraft" => params}, socket) do
    mission = socket.assigns.current_mission
    organization_id = socket.assigns.current_scope.organization_id
    display_name = normalize(params["display_name"])

    with true <- not is_nil(display_name),
         {:ok, scid} <- parse_optional_scid(params["scid"]),
         {:ok, type_binding} <- resolve_type_binding(socket, params["spacecraft_type_id"]) do
      spacecraft =
        Spacecraft.new(
          Map.merge(
            %{
              mission_id: mission.mission_id,
              display_name: display_name,
              scid: scid
            },
            type_binding
          )
        )

      case Cadence.persist_spacecraft(organization_id, spacecraft) do
        {:ok, persisted} ->
          _ = maybe_ensure_source_endpoint(organization_id, persisted)

          {:noreply,
           push_navigate(socket,
             to: ~p"/missions/#{mission.mission_id}/spacecraft/#{persisted.spacecraft_id}"
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
    else
      false ->
        {:noreply, put_flash(socket, :error, "Display name is required.")}

      {:error, message} ->
        {:noreply, put_flash(socket, :error, message)}
    end
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div id="spacecraft-new-page" class="space-y-6 max-w-xl">
      <.page_header
        title="New Spacecraft"
        subtitle="Register a spacecraft for this mission. Optionally select a profile to pin its byte-interpretation contract."
        back_label="Spacecraft"
        back_navigate={~p"/missions/#{@current_mission.mission_id}/spacecraft"}
      />

      <.form
        for={@form}
        id="spacecraft-form"
        phx-change="validate"
        phx-submit="save"
        class="space-y-8"
      >
        <section class="space-y-4">
          <.section_heading number="01" title="Identity" />
          <.input field={@form[:display_name]} type="text" label="Display Name" required />
          <.input field={@form[:scid]} type="text" label="SCID" />
        </section>

        <section class="space-y-4">
          <.section_heading number="02" title="Profile" />
          <.input
            field={@form[:spacecraft_type_id]}
            type="select"
            label="Spacecraft Profile"
            options={type_options(@available_types)}
          />
          <p :if={@available_types == []} class="text-xs text-base-content/70">
            No spacecraft profiles defined yet.
            <.link
              navigate={~p"/missions/#{@current_mission.mission_id}/spacecraft/profiles/new"}
              class="text-primary hover:underline"
            >
              Create one
            </.link>
            to give this spacecraft a reusable interpretation profile.
          </p>
        </section>

        <div class="flex items-center gap-3 border-t border-base-300/60 pt-5">
          <.button type="submit" size={:md}>
            Create Spacecraft
          </.button>
          <.button
            variant={:ghost}
            size={:md}
            navigate={~p"/missions/#{@current_mission.mission_id}/spacecraft"}
          >
            Cancel
          </.button>
        </div>
      </.form>
    </div>
    """
  end

  attr :number, :string, required: true
  attr :title, :string, required: true

  defp section_heading(assigns) do
    ~H"""
    <div class="flex items-center gap-3">
      <span class="hud-label text-primary/70">{@number}</span>
      <h2 class="hud-label">{@title}</h2>
      <div class="flex-1 h-px bg-base-300/60"></div>
    </div>
    """
  end

  defp empty_form do
    to_form(
      %{"display_name" => "", "scid" => "", "spacecraft_type_id" => ""},
      as: :spacecraft
    )
  end

  defp form_from_params(params) do
    to_form(
      %{
        "display_name" => Map.get(params, "display_name", ""),
        "scid" => Map.get(params, "scid", ""),
        "spacecraft_type_id" => Map.get(params, "spacecraft_type_id", "")
      },
      as: :spacecraft
    )
  end

  defp type_options(available_types) do
    [
      {"None", ""}
      | Enum.map(available_types, &{"#{&1.display_name} (v#{&1.version})", &1.spacecraft_type_id})
    ]
  end

  defp resolve_type_binding(_socket, value) when value in [nil, ""], do: {:ok, %{}}

  defp resolve_type_binding(socket, spacecraft_type_id) when is_binary(spacecraft_type_id) do
    %{current_scope: scope, current_mission: mission} = socket.assigns

    case Cadence.fetch_spacecraft_type(
           scope.organization_id,
           mission.mission_id,
           spacecraft_type_id
         ) do
      {:ok, type} ->
        {:ok,
         %{spacecraft_type_id: type.spacecraft_type_id, spacecraft_type_version: type.version}}

      {:error, _reason} ->
        {:error, "Selected spacecraft profile is not available."}
    end
  end

  defp normalize(value) when is_binary(value) do
    case String.trim(value) do
      "" -> nil
      trimmed -> trimmed
    end
  end

  defp normalize(_other), do: nil

  defp parse_optional_scid(value) when is_binary(value) do
    case normalize(value) do
      nil ->
        {:ok, nil}

      value ->
        case Integer.parse(value) do
          {scid, ""} when scid >= 0 and scid <= 1023 -> {:ok, scid}
          _other -> {:error, "SCID must be an integer from 0 to 1023."}
        end
    end
  end

  defp parse_optional_scid(_value), do: {:ok, nil}

  defp maybe_ensure_source_endpoint(_organization_id, %{scid: nil}), do: :ok

  defp maybe_ensure_source_endpoint(organization_id, spacecraft) do
    Cadence.ensure_managed_spacecraft_source_endpoint(organization_id, spacecraft)
  end

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
