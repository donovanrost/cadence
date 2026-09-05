defmodule CadenceWeb.SpacecraftNewLive do
  @moduledoc false

  # Authz note: Any active organization member can create a spacecraft. This
  # gate should tighten once platform-wide authorization is defined (likely to
  # the :organization_admin role, possibly a finer capability).
  use CadenceWeb, :live_view

  alias Cadence.Spacecraft
  alias Phoenix.LiveView.JS

  @impl true
  def mount(_params, _session, socket) do
    organization_id = socket.assigns.current_scope.organization_id
    mission_id = socket.assigns.current_mission.mission_id

    available_types =
      Cadence.SpacecraftTypeStore.list_spacecraft_types(organization_id, mission_id)

    {:ok,
     socket
     |> assign(:page_title, "New Spacecraft")
     |> assign(:nav_item, :spacecraft)
     |> assign(:available_types, available_types)
     |> assign(:spacecraft_page, spacecraft_page_dto(socket.assigns.current_mission))
     |> assign(:spacecraft_form, spacecraft_form_dto(%{}, mission_id))
     |> assign(
       :profile_options,
       profile_options_dto(available_types, mission_id)
     )}
  end

  @impl true
  def handle_event("validate", %{"spacecraft" => params}, socket) do
    mission_id = socket.assigns.current_mission.mission_id
    {:noreply, assign(socket, :spacecraft_form, spacecraft_form_dto(params, mission_id))}
  end

  @impl true
  def handle_event("save", %{"spacecraft" => params}, socket) do
    mission = socket.assigns.current_mission
    organization_id = socket.assigns.current_scope.organization_id
    display_name = normalize(params["display_name"])
    socket = assign(socket, :spacecraft_form, spacecraft_form_dto(params, mission.mission_id))

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

      case Cadence.SpacecraftStore.persist_spacecraft(organization_id, spacecraft) do
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
    <Layouts.app flash={@flash} current_scope={@current_scope}>
      <.vue
        id="spacecraft-new-component"
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

  defp spacecraft_page_dto(mission) do
    %{
      id: "spacecraft-new-page",
      heading: "New Spacecraft",
      subtitle:
        "Register a spacecraft for this mission. Optionally select a profile to pin its byte-interpretation contract.",
      breadcrumbs: [
        %{label: mission.display_name, href: ~p"/missions/#{mission.mission_id}"},
        %{label: "Spacecraft", href: ~p"/missions/#{mission.mission_id}/spacecraft"},
        %{label: "New Spacecraft", href: nil}
      ]
    }
  end

  defp spacecraft_form_dto(params, mission_id) do
    %{
      id: "spacecraft-form",
      sections: %{
        identity: %{id: "spacecraft-identity-section", number: "01", title: "Identity"},
        profile: %{id: "spacecraft-profile-section", number: "02", title: "Profile"}
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
        submit: %{id: "create-spacecraft-button", label: "Create Spacecraft"},
        cancel: %{
          id: "cancel-spacecraft-link",
          label: "Cancel",
          href: ~p"/missions/#{mission_id}/spacecraft"
        }
      }
    }
  end

  defp profile_options_dto(available_types, mission_id) do
    %{
      options: [
        %{label: "None", value: ""}
        | Enum.map(available_types, fn type ->
            %{label: "#{type.display_name} (v#{type.version})", value: type.spacecraft_type_id}
          end)
      ],
      empty: available_types == [],
      empty_state: %{
        message: "No spacecraft profiles defined yet.",
        action: %{
          id: "create-spacecraft-profile-link",
          label: "Create one",
          href: ~p"/missions/#{mission_id}/spacecraft/profiles/new"
        },
        suffix: "to give this spacecraft a reusable interpretation profile."
      }
    }
  end

  defp string_param(params, key) when is_map(params) do
    case Map.get(params, key) do
      value when is_binary(value) -> value
      _other -> ""
    end
  end

  defp string_param(_params, _key), do: ""

  defp resolve_type_binding(_socket, value) when value in [nil, ""], do: {:ok, %{}}

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
    Cadence.SourceEndpoints.ensure_managed_source_endpoint(organization_id, spacecraft)
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
