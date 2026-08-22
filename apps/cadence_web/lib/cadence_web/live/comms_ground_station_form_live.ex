defmodule CadenceWeb.CommsGroundStationFormLive do
  @moduledoc false
  use CadenceWeb, :live_view

  alias Cadence.Comms.GroundStationStore

  alias Cadence.Comms.GroundStation
  alias CadenceWeb.CommsComponents

  @impl true
  def mount(params, _session, socket) do
    %{current_scope: scope, current_mission: mission} = socket.assigns

    case socket.assigns.live_action do
      :new ->
        {:ok,
         socket
         |> assign(:page_title, "New Ground Station")
         |> assign(:nav_item, :comms_ground_stations)
         |> assign(:mode, :new)
         |> assign(:ground_station, nil)
         |> assign(:return_to, ~p"/missions/#{mission.mission_id}/comms/ground-stations")
         |> assign(:form, to_form(empty_form_params(), as: :ground_station))}

      :edit ->
        ground_station_id = params["ground_station_id"]

        case GroundStationStore.fetch_ground_station(
               scope.organization_id,
               mission.mission_id,
               ground_station_id
             ) do
          {:ok, ground_station} ->
            {:ok,
             socket
             |> assign(:page_title, "Edit #{ground_station.display_name}")
             |> assign(:nav_item, :comms_ground_stations)
             |> assign(:mode, :edit)
             |> assign(:ground_station, ground_station)
             |> assign(
               :return_to,
               ~p"/missions/#{mission.mission_id}/comms/ground-stations/#{ground_station.ground_station_id}"
             )
             |> assign(:form, to_form(form_params(ground_station), as: :ground_station))}

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
    {:noreply, assign(socket, :form, to_form(params, as: :ground_station))}
  end

  @impl true
  def handle_event("save", %{"ground_station" => params}, %{assigns: %{mode: :new}} = socket) do
    %{current_scope: scope, current_mission: mission} = socket.assigns

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
    <div id="comms-ground-station-form-page" class="space-y-6 max-w-2xl">
      <.page_header
        title={form_title(@mode)}
        subtitle="Define a stable mission setup identity for an antenna, site, or provider station."
        breadcrumbs={[
          {@current_mission.display_name, ~p"/missions/#{@current_mission.mission_id}"},
          {"Comms", ~p"/missions/#{@current_mission.mission_id}/comms"},
          {"Ground Stations", @return_to},
          {form_title(@mode), nil}
        ]}
      />

      <.form
        for={@form}
        id="ground-station-form"
        phx-change="validate"
        phx-submit="save"
        class="space-y-8"
      >
        <.form_section number="01" title="Identity">
          <.input
            field={@form[:ground_station_id]}
            type="text"
            label="Station ID"
            required={@mode == :new}
            disabled={@mode == :edit}
            placeholder="dss-14"
          />
          <.input field={@form[:display_name]} type="text" label="Display Name" required />
        </.form_section>

        <.form_section number="02" title="Network Context">
          <.input field={@form[:provider]} type="text" label="Provider" placeholder="DSN" />
          <.input field={@form[:region]} type="text" label="Region" placeholder="goldstone" />
        </.form_section>

        <.form_section number="03" title="Metadata">
          <.input
            field={@form[:metadata_json]}
            type="textarea"
            label="Metadata JSON"
            class="min-h-40 font-mono text-xs"
            placeholder={~s({"antenna_diameter_m":70})}
          />
        </.form_section>

        <.form_actions submit={submit_label(@mode)} cancel_navigate={@return_to} />
      </.form>
    </div>
    """
  end

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

  defp format_error(%Ecto.Changeset{} = changeset), do: CommsComponents.format_error(changeset)
  defp format_error(reason), do: "Failed to save ground station: #{inspect(reason)}"
end
