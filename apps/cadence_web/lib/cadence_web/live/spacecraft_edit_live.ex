defmodule CadenceWeb.SpacecraftEditLive do
  @moduledoc false
  use CadenceWeb, :live_view

  alias Cadence.Spacecraft

  @impl true
  def mount(_params, _session, socket) do
    spacecraft = socket.assigns.current_spacecraft
    organization_id = socket.assigns.current_scope.organization_id
    mission_id = socket.assigns.current_mission.mission_id
    available_types = Cadence.list_spacecraft_types(organization_id, mission_id)

    {:ok,
     socket
     |> assign(:page_title, "#{spacecraft.display_name} Identity")
     |> assign(:nav_item, :spacecraft)
     |> assign(:available_types, available_types)
     |> assign(:form, form_from_spacecraft(spacecraft))}
  end

  @impl true
  def handle_event("validate", %{"spacecraft" => params}, socket) do
    {:noreply, assign(socket, :form, form_from_params(params))}
  end

  @impl true
  def handle_event("save", %{"spacecraft" => params}, socket) do
    current_spacecraft = socket.assigns.current_spacecraft
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
              spacecraft_id: current_spacecraft.spacecraft_id,
              organization_id: current_spacecraft.organization_id,
              mission_id: mission.mission_id,
              display_name: display_name,
              scid: scid,
              metadata: current_spacecraft.metadata
            },
            type_binding
          )
        )

      case Cadence.update_spacecraft(organization_id, spacecraft) do
        {:ok, updated_spacecraft} ->
          {:noreply, after_spacecraft_update(socket, organization_id, updated_spacecraft)}

        {:error, :spacecraft_not_found} ->
          {:noreply,
           socket
           |> put_flash(:error, "Spacecraft not found.")
           |> push_navigate(to: ~p"/missions/#{mission.mission_id}/spacecraft")}

        {:error, {:organization_mission_mismatch, _, _, _}} ->
          {:noreply, put_flash(socket, :error, "Could not update spacecraft.")}

        {:error, %Ecto.Changeset{} = changeset} ->
          {:noreply, put_flash(socket, :error, format_errors(changeset))}

        {:error, reason} ->
          {:noreply, put_flash(socket, :error, "Failed to update spacecraft: #{inspect(reason)}")}
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
    <div class="space-y-6 max-w-xl">
      <.page_header
        title="Spacecraft Identity"
        subtitle="SCID identifies this spacecraft. The optional profile pins its byte-interpretation contract."
        breadcrumbs={[
          {@current_mission.display_name, ~p"/missions/#{@current_mission.mission_id}"},
          {"Spacecraft", ~p"/missions/#{@current_mission.mission_id}/spacecraft"},
          {@current_spacecraft.display_name,
           ~p"/missions/#{@current_mission.mission_id}/spacecraft/#{@current_spacecraft.spacecraft_id}"},
          {"Identity", nil}
        ]}
      />

      <.form
        for={@form}
        id="spacecraft-edit-form"
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
        </section>

        <div class="flex items-center gap-3 border-t border-base-300/60 pt-5">
          <.button type="submit" size={:md}>
            Save Identity
          </.button>
          <.button
            variant={:ghost}
            size={:md}
            navigate={
              ~p"/missions/#{@current_mission.mission_id}/spacecraft/#{@current_spacecraft.spacecraft_id}"
            }
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

  defp after_spacecraft_update(socket, organization_id, spacecraft) do
    case maybe_sync_managed_source_endpoint(organization_id, spacecraft) do
      :ok ->
        socket
        |> put_flash(:info, "Spacecraft updated.")
        |> push_navigate(
          to: ~p"/missions/#{spacecraft.mission_id}/spacecraft/#{spacecraft.spacecraft_id}"
        )

      {:error, reason} ->
        socket
        |> put_flash(
          :error,
          "Spacecraft updated, but Cadence could not sync the telemetry identity: #{inspect(reason)}"
        )
        |> push_navigate(
          to: ~p"/missions/#{spacecraft.mission_id}/spacecraft/#{spacecraft.spacecraft_id}"
        )
    end
  end

  defp maybe_sync_managed_source_endpoint(organization_id, %Spacecraft{scid: scid} = spacecraft)
       when is_integer(scid) do
    case Cadence.ensure_managed_spacecraft_source_endpoint(organization_id, spacecraft) do
      {:ok, _endpoint} -> :ok
      {:error, reason} -> {:error, reason}
    end
  end

  defp maybe_sync_managed_source_endpoint(organization_id, %Spacecraft{} = spacecraft) do
    source_endpoint_id = "spacecraft_runtime:" <> spacecraft.spacecraft_id

    case Cadence.fetch_source_endpoint(
           organization_id,
           spacecraft.mission_id,
           source_endpoint_id
         ) do
      {:ok, _endpoint} ->
        case Cadence.ensure_managed_spacecraft_source_endpoint(organization_id, spacecraft) do
          {:ok, _endpoint} -> :ok
          {:error, reason} -> {:error, reason}
        end

      {:error, :source_endpoint_not_found} ->
        :ok

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp type_options(available_types) do
    [
      {"None", ""}
      | Enum.map(available_types, &{"#{&1.display_name} (v#{&1.version})", &1.spacecraft_type_id})
    ]
  end

  defp resolve_type_binding(_socket, value) when value in [nil, ""],
    do: {:ok, %{spacecraft_type_id: nil, spacecraft_type_version: nil}}

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

  defp form_from_spacecraft(spacecraft) do
    to_form(
      %{
        "display_name" => spacecraft.display_name,
        "scid" => format_scid_value(spacecraft.scid),
        "spacecraft_type_id" => spacecraft.spacecraft_type_id || ""
      },
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

  defp format_scid_value(nil), do: ""
  defp format_scid_value(scid), do: Integer.to_string(scid)

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
