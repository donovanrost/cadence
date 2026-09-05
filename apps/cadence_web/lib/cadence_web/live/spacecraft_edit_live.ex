defmodule CadenceWeb.SpacecraftEditLive do
  @moduledoc false
  use CadenceWeb, :live_view

  alias Cadence.Spacecraft
  alias Phoenix.LiveView.JS

  @impl true
  def mount(_params, _session, socket) do
    spacecraft = socket.assigns.current_spacecraft
    organization_id = socket.assigns.current_scope.organization_id
    mission_id = socket.assigns.current_mission.mission_id

    available_types =
      Cadence.SpacecraftTypeStore.list_spacecraft_types(organization_id, mission_id)

    {:ok,
     socket
     |> assign(:page_title, "#{spacecraft.display_name} Identity")
     |> assign(:nav_item, :spacecraft)
     |> assign(
       :spacecraft_page,
       spacecraft_page_dto(socket.assigns.current_mission, spacecraft)
     )
     |> assign(
       :spacecraft_form,
       spacecraft_form_dto(spacecraft_values(spacecraft), mission_id, spacecraft.spacecraft_id)
     )
     |> assign(:profile_options, profile_options_dto(available_types))}
  end

  @impl true
  def handle_event("validate", %{"spacecraft" => params}, socket) do
    mission_id = socket.assigns.current_mission.mission_id
    spacecraft_id = socket.assigns.current_spacecraft.spacecraft_id

    {:noreply,
     assign(
       socket,
       :spacecraft_form,
       spacecraft_form_dto(params, mission_id, spacecraft_id)
     )}
  end

  @impl true
  def handle_event("save", %{"spacecraft" => params}, socket) do
    current_spacecraft = socket.assigns.current_spacecraft
    mission = socket.assigns.current_mission
    organization_id = socket.assigns.current_scope.organization_id
    display_name = normalize(params["display_name"])

    socket =
      assign(
        socket,
        :spacecraft_form,
        spacecraft_form_dto(params, mission.mission_id, current_spacecraft.spacecraft_id)
      )

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

      case Cadence.SpacecraftStore.update_spacecraft(organization_id, spacecraft) do
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
    <Layouts.app flash={@flash} current_scope={@current_scope}>
      <.vue
        id="spacecraft-edit-component"
        v-component="FederatedFullPageSurface"
        page={@spacecraft_page}
        form={@spacecraft_form}
        profile_options={@profile_options}
        v-on:validate={JS.push("validate")}
        v-on:save={JS.push("save")}
        v-ssr={false}
      />
    </Layouts.app>
    """
  end

  defp spacecraft_page_dto(mission, spacecraft) do
    %{
      id: "spacecraft-edit-page",
      heading: "Spacecraft Identity",
      subtitle:
        "SCID identifies this spacecraft. The optional profile pins its byte-interpretation contract.",
      breadcrumbs: [
        %{
          id: "spacecraft-edit-mission-link",
          label: mission.display_name,
          href: ~p"/missions/#{mission.mission_id}"
        },
        %{
          id: "spacecraft-edit-list-link",
          label: "Spacecraft",
          href: ~p"/missions/#{mission.mission_id}/spacecraft"
        },
        %{
          id: "spacecraft-edit-show-link",
          label: spacecraft.display_name,
          href: ~p"/missions/#{mission.mission_id}/spacecraft/#{spacecraft.spacecraft_id}"
        },
        %{id: "spacecraft-edit-current-breadcrumb", label: "Identity", href: nil}
      ]
    }
  end

  defp spacecraft_form_dto(params, mission_id, spacecraft_id) do
    %{
      id: "spacecraft-edit-form",
      sections: %{
        identity: %{id: "spacecraft-edit-identity-section", number: "01", title: "Identity"},
        profile: %{id: "spacecraft-edit-profile-section", number: "02", title: "Profile"}
      },
      fields: %{
        display_name: %{
          id: "spacecraft_display_name",
          name: "spacecraft[display_name]",
          type: "text",
          label: "Display Name",
          required: true,
          value: string_param(params, "display_name")
        },
        scid: %{
          id: "spacecraft_scid",
          name: "spacecraft[scid]",
          type: "text",
          label: "SCID",
          required: false,
          value: string_param(params, "scid")
        },
        spacecraft_type_id: %{
          id: "spacecraft_spacecraft_type_id",
          name: "spacecraft[spacecraft_type_id]",
          type: "select",
          label: "Spacecraft Profile",
          required: false,
          value: string_param(params, "spacecraft_type_id")
        }
      },
      actions: %{
        submit: %{id: "save-spacecraft-identity-button", label: "Save Identity"},
        cancel: %{
          id: "cancel-spacecraft-identity-link",
          label: "Cancel",
          href: ~p"/missions/#{mission_id}/spacecraft/#{spacecraft_id}"
        }
      }
    }
  end

  defp profile_options_dto(available_types) do
    %{
      options: [
        %{label: "None", value: ""}
        | Enum.map(available_types, fn type ->
            %{label: "#{type.display_name} (v#{type.version})", value: type.spacecraft_type_id}
          end)
      ]
    }
  end

  defp spacecraft_values(spacecraft) do
    %{
      "display_name" => spacecraft.display_name,
      "scid" => format_scid_value(spacecraft.scid),
      "spacecraft_type_id" => spacecraft.spacecraft_type_id || ""
    }
  end

  defp string_param(params, key) when is_map(params) do
    case Map.get(params, key) do
      value when is_binary(value) -> value
      _other -> ""
    end
  end

  defp string_param(_params, _key), do: ""

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
    case Cadence.SourceEndpoints.ensure_managed_source_endpoint(organization_id, spacecraft) do
      {:ok, _endpoint} -> :ok
      {:error, reason} -> {:error, reason}
    end
  end

  defp maybe_sync_managed_source_endpoint(organization_id, %Spacecraft{} = spacecraft) do
    source_endpoint_id = "spacecraft_runtime:" <> spacecraft.spacecraft_id

    case Cadence.SourceEndpoints.fetch_source_endpoint(
           organization_id,
           spacecraft.mission_id,
           source_endpoint_id
         ) do
      {:ok, _endpoint} ->
        case Cadence.SourceEndpoints.ensure_managed_source_endpoint(organization_id, spacecraft) do
          {:ok, _endpoint} -> :ok
          {:error, reason} -> {:error, reason}
        end

      {:error, :source_endpoint_not_found} ->
        :ok
    end
  end

  defp resolve_type_binding(_socket, value) when value in [nil, ""],
    do: {:ok, %{spacecraft_type_id: nil, spacecraft_type_version: nil}}

  defp resolve_type_binding(socket, spacecraft_type_id) when is_binary(spacecraft_type_id) do
    %{current_scope: scope, current_mission: mission} = socket.assigns

    case Cadence.SpacecraftTypeStore.fetch_spacecraft_type(
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
