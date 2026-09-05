defmodule CadenceWeb.CommsGroundStationFormLive do
  @moduledoc false
  use CadenceWeb, :live_view

  alias Cadence.Comms.GroundStationStore

  alias Cadence.Comms.GroundStation
  alias CadenceWeb.CommsComponents
  alias Phoenix.LiveView.JS

  @impl true
  def mount(params, _session, socket) do
    %{current_scope: scope, current_mission: mission} = socket.assigns

    case socket.assigns.live_action do
      :new ->
        return_to = ~p"/missions/#{mission.mission_id}/comms/ground-stations"

        {:ok,
         socket
         |> assign(:page_title, "New Ground Station")
         |> assign(:nav_item, :comms_ground_stations)
         |> assign(:mode, :new)
         |> assign(:ground_station, nil)
         |> assign(:return_to, return_to)
         |> assign(:page, page_dto(mission, :new, return_to))
         |> assign_form(empty_form_params())}

      :edit ->
        ground_station_id = params["ground_station_id"]

        case GroundStationStore.fetch_ground_station(
               scope.organization_id,
               mission.mission_id,
               ground_station_id
             ) do
          {:ok, ground_station} ->
            return_to =
              ~p"/missions/#{mission.mission_id}/comms/ground-stations/#{ground_station.ground_station_id}"

            {:ok,
             socket
             |> assign(:page_title, "Edit #{ground_station.display_name}")
             |> assign(:nav_item, :comms_ground_stations)
             |> assign(:mode, :edit)
             |> assign(:ground_station, ground_station)
             |> assign(:return_to, return_to)
             |> assign(:page, page_dto(mission, :edit, return_to))
             |> assign_form(form_params(ground_station))}

          {:error, _reason} ->
            {:ok,
             socket
             |> put_flash(:error, "Ground station not found.")
             |> push_navigate(to: ~p"/missions/#{mission.mission_id}/comms/ground-stations")}
        end
    end
  end

  @impl true
  def handle_event("validate", %{"ground_station" => params}, socket) do
    {:noreply, assign_form(socket, params)}
  end

  @impl true
  def handle_event("save", %{"ground_station" => params}, %{assigns: %{mode: :new}} = socket) do
    %{current_scope: scope, current_mission: mission} = socket.assigns
    socket = assign_form(socket, params)

    case form_attrs(params, require_id?: true) do
      {:ok, attrs} ->
        ground_station =
          GroundStation.new(
            Map.merge(attrs, %{
              mission_id: mission.mission_id,
              ground_station_id: attrs.ground_station_id
            })
          )

        case GroundStationStore.persist_ground_station(
               scope.organization_id,
               ground_station
             ) do
          {:ok, persisted} ->
            {:noreply,
             push_navigate(socket,
               to:
                 ~p"/missions/#{mission.mission_id}/comms/ground-stations/#{persisted.ground_station_id}"
             )}

          {:error, reason} ->
            {:noreply, put_flash(socket, :error, format_error(reason))}
        end

      {:error, message} ->
        {:noreply, put_flash(socket, :error, message)}
    end
  end

  @impl true
  def handle_event("save", %{"ground_station" => params}, %{assigns: %{mode: :edit}} = socket) do
    %{current_scope: scope, current_mission: mission, ground_station: ground_station} =
      socket.assigns

    socket = assign_form(socket, params)

    case form_attrs(params, require_id?: false) do
      {:ok, attrs} ->
        case GroundStationStore.update_ground_station(
               scope.organization_id,
               mission.mission_id,
               ground_station.ground_station_id,
               attrs
             ) do
          {:ok, persisted} ->
            {:noreply,
             push_navigate(socket,
               to:
                 ~p"/missions/#{mission.mission_id}/comms/ground-stations/#{persisted.ground_station_id}"
             )}

          {:error, reason} ->
            {:noreply, put_flash(socket, :error, format_error(reason))}
        end

      {:error, message} ->
        {:noreply, put_flash(socket, :error, message)}
    end
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_scope}>
      <.vue
        id="comms-ground-station-form-component"
        v-component="FederatedFullPageSurface"
        page={@page}
        mode={Atom.to_string(@mode)}
        form={@form_props}
        v-on:validate={JS.push("validate")}
        v-on:save={JS.push("save")}
        v-ssr={false}
      />
    </Layouts.app>
    """
  end

  defp page_dto(mission, mode, return_to) do
    %{
      id: "comms-ground-station-form-page",
      heading: form_title(mode),
      subtitle:
        "Define a stable mission setup identity for an antenna, site, or provider station.",
      breadcrumbs: [
        %{label: mission.display_name, href: ~p"/missions/#{mission.mission_id}"},
        %{label: "Comms", href: ~p"/missions/#{mission.mission_id}/comms"},
        %{label: "Ground Stations", href: return_to},
        %{label: form_title(mode), href: nil}
      ]
    }
  end

  defp assign_form(socket, params) do
    form = to_form(params, as: :ground_station)

    socket
    |> assign(:form, form)
    |> assign(:form_props, form_dto(form.params, socket.assigns.mode, socket.assigns.return_to))
  end

  defp form_dto(params, mode, return_to) do
    %{
      id: "ground-station-form",
      sections: %{
        identity: %{id: "ground-station-identity-section", number: "01", title: "Identity"},
        network: %{
          id: "ground-station-network-section",
          number: "02",
          title: "Network Context"
        },
        metadata: %{id: "ground-station-metadata-section", number: "03", title: "Metadata"}
      },
      fields: %{
        ground_station_id: %{
          id: "ground_station_ground_station_id",
          name: "ground_station[ground_station_id]",
          type: "text",
          label: "Station ID",
          required: mode == :new,
          disabled: mode == :edit,
          placeholder: "dss-14",
          value: string_param(params, "ground_station_id")
        },
        display_name: %{
          id: "ground_station_display_name",
          name: "ground_station[display_name]",
          type: "text",
          label: "Display Name",
          required: true,
          disabled: false,
          placeholder: nil,
          value: string_param(params, "display_name")
        },
        provider: %{
          id: "ground_station_provider",
          name: "ground_station[provider]",
          type: "text",
          label: "Provider",
          required: false,
          disabled: false,
          placeholder: "DSN",
          value: string_param(params, "provider")
        },
        region: %{
          id: "ground_station_region",
          name: "ground_station[region]",
          type: "text",
          label: "Region",
          required: false,
          disabled: false,
          placeholder: "goldstone",
          value: string_param(params, "region")
        },
        metadata_json: %{
          id: "ground_station_metadata_json",
          name: "ground_station[metadata_json]",
          type: "textarea",
          label: "Metadata JSON",
          required: false,
          disabled: false,
          placeholder: ~s({"antenna_diameter_m":70}),
          value: string_param(params, "metadata_json")
        }
      },
      actions: %{
        submit: %{id: submit_id(mode), label: submit_label(mode)},
        cancel: %{id: "cancel-ground-station-link", label: "Cancel", href: return_to}
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

  defp empty_form_params do
    %{
      "ground_station_id" => "",
      "display_name" => "",
      "provider" => "",
      "region" => "",
      "metadata_json" => "{}"
    }
  end

  defp form_params(%GroundStation{} = ground_station) do
    %{
      "ground_station_id" => ground_station.ground_station_id,
      "display_name" => ground_station.display_name,
      "provider" => ground_station.provider || "",
      "region" => ground_station.region || "",
      "metadata_json" => Jason.encode!(ground_station.metadata, pretty: true)
    }
  end

  defp form_attrs(params, opts) do
    with {:ok, display_name} <- required_text(params["display_name"], "Display name is required."),
         {:ok, ground_station_id} <- ground_station_id(params, opts),
         {:ok, metadata} <- parse_metadata(params["metadata_json"]) do
      {:ok,
       %{
         ground_station_id: ground_station_id,
         display_name: display_name,
         provider: optional_text(params["provider"]),
         region: optional_text(params["region"]),
         metadata: metadata
       }}
    end
  end

  defp ground_station_id(params, require_id?: true) do
    with {:ok, ground_station_id} <-
           required_text(params["ground_station_id"], "Station ID is required.") do
      validate_ground_station_id(ground_station_id)
    end
  end

  defp ground_station_id(_params, require_id?: false), do: {:ok, nil}

  defp validate_ground_station_id(value) do
    if Regex.match?(~r/^[A-Za-z0-9][A-Za-z0-9_.:-]*$/, value) do
      {:ok, value}
    else
      {:error, "Station ID may contain letters, numbers, dots, underscores, colons, and dashes."}
    end
  end

  defp parse_metadata(value) do
    case CommsComponents.parse_config_json(value) do
      {:ok, metadata} -> {:ok, metadata}
      {:error, _message} -> {:error, "Metadata JSON must be an object."}
    end
  end

  defp required_text(value, message) do
    case CommsComponents.normalize_text(value) do
      nil -> {:error, message}
      text -> {:ok, text}
    end
  end

  defp optional_text(value), do: CommsComponents.normalize_text(value)

  defp form_title(:new), do: "New Ground Station"
  defp form_title(:edit), do: "Edit Ground Station"

  defp submit_label(:new), do: "Create Ground Station"
  defp submit_label(:edit), do: "Save Ground Station"

  defp submit_id(:new), do: "create-ground-station-button"
  defp submit_id(:edit), do: "save-ground-station-button"

  defp format_error(%Ecto.Changeset{} = changeset), do: CommsComponents.format_error(changeset)
  defp format_error(reason), do: "Failed to save ground station: #{inspect(reason)}"
end
