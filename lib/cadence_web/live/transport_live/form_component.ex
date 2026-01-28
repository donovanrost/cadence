defmodule CadenceWeb.TransportLive.FormComponent do
  @moduledoc """
  Form component for creating/editing transport interfaces.
  """
  use CadenceWeb, :live_component

  alias Cadence.Transports

  @impl true
  def render(assigns) do
    ~H"""
    <div>
      <.header>
        {@title}
        <:subtitle>Configure transport interface settings.</:subtitle>
      </.header>

      <.simple_form
        for={@form}
        id="transport-form"
        phx-target={@myself}
        phx-change="validate"
        phx-submit="save"
      >
        <.input field={@form[:name]} type="text" label="Name" placeholder="Primary Ground Station" />

        <.input
          field={@form[:type]}
          type="select"
          label="Transport Type"
          prompt="Choose transport type"
          options={[
            {"TCP", "tcp"},
            {"UDP", "udp"},
            {"Serial", "serial"},
            {"File", "file"},
            {"S3", "s3"},
            {"Replay", "replay"}
          ]}
        />

        <%!-- Type-specific endpoint fields --%>
        <%= if @transport_type in ["tcp", "udp"] do %>
          <div class="grid grid-cols-2 gap-4">
            <.input
              field={@form[:endpoint_host]}
              type="text"
              label="Host"
              placeholder="192.168.1.100"
            />
            <.input field={@form[:endpoint_port]} type="number" label="Port" placeholder="8080" />
          </div>
          <.input
            field={@form[:endpoint_mode]}
            type="select"
            label="Mode"
            options={[
              {"Client (connect to)", "client"},
              {"Server (accept from)", "server"}
            ]}
          />
        <% end %>

        <%= if @transport_type == "serial" do %>
          <.input
            field={@form[:endpoint_device]}
            type="text"
            label="Device Path"
            placeholder="/dev/ttyUSB0"
          />
          <div class="grid grid-cols-2 gap-4">
            <.input
              field={@form[:endpoint_baud_rate]}
              type="select"
              label="Baud Rate"
              options={[
                {"9600", "9600"},
                {"19200", "19200"},
                {"38400", "38400"},
                {"57600", "57600"},
                {"115200", "115200"},
                {"230400", "230400"},
                {"460800", "460800"},
                {"921600", "921600"}
              ]}
            />
            <.input
              field={@form[:endpoint_data_bits]}
              type="select"
              label="Data Bits"
              options={[{"7", "7"}, {"8", "8"}]}
            />
          </div>
        <% end %>

        <%= if @transport_type == "file" do %>
          <.input
            field={@form[:endpoint_path]}
            type="text"
            label="File Path"
            placeholder="/path/to/data.bin"
          />
        <% end %>

        <%= if @transport_type == "s3" do %>
          <.input
            field={@form[:endpoint_bucket]}
            type="text"
            label="S3 Bucket"
            placeholder="my-telemetry-bucket"
          />
          <.input
            field={@form[:endpoint_prefix]}
            type="text"
            label="Key Prefix"
            placeholder="mission-data/"
          />
        <% end %>

        <hr class="my-6 border-base-300" />

        <div>
          <label class="block text-sm font-semibold leading-6 text-base-content mb-2">
            Allowed Directions
          </label>
          <div class="flex gap-4">
            <label class="flex items-center gap-2 cursor-pointer">
              <input
                type="checkbox"
                name="interface[allowed_directions][]"
                value="uplink"
                checked={:uplink in (@allowed_directions || [])}
                class="checkbox checkbox-sm"
              />
              <span class="text-sm">Uplink</span>
            </label>
            <label class="flex items-center gap-2 cursor-pointer">
              <input
                type="checkbox"
                name="interface[allowed_directions][]"
                value="downlink"
                checked={:downlink in (@allowed_directions || [])}
                class="checkbox checkbox-sm"
              />
              <span class="text-sm">Downlink</span>
            </label>
            <label class="flex items-center gap-2 cursor-pointer">
              <input
                type="checkbox"
                name="interface[allowed_directions][]"
                value="both"
                checked={:both in (@allowed_directions || [])}
                class="checkbox checkbox-sm"
              />
              <span class="text-sm">Both</span>
            </label>
          </div>
        </div>

        <.input
          field={@form[:tags]}
          type="text"
          label="Tags (comma-separated)"
          placeholder="ground-station, primary"
        />

        <.input field={@form[:enabled]} type="checkbox" label="Enabled" />

        <:actions>
          <.button phx-disable-with="Saving...">Save Transport</.button>
        </:actions>
      </.simple_form>
    </div>
    """
  end

  @impl true
  def update(%{interface: interface} = assigns, socket) do
    # Build initial form data
    form_data = build_form_data(interface)
    changeset = build_changeset(interface, form_data)

    transport_type = form_data["type"] || interface.type
    allowed_directions = interface.allowed_directions || [:both]

    {:ok,
     socket
     |> assign(assigns)
     |> assign(:transport_type, to_string(transport_type || ""))
     |> assign(:allowed_directions, allowed_directions)
     |> assign_form(changeset)}
  end

  defp build_form_data(%{id: nil}), do: %{}

  defp build_form_data(interface) do
    endpoint = interface.endpoint || %{}

    %{
      "name" => interface.name,
      "type" => interface.type,
      "enabled" => interface.enabled,
      "tags" => Enum.join(interface.tags || [], ", "),
      "endpoint_host" => endpoint_value(endpoint, :host),
      "endpoint_port" => endpoint_value(endpoint, :port),
      "endpoint_mode" => endpoint_value(endpoint, :mode),
      "endpoint_device" => endpoint_value(endpoint, :device),
      "endpoint_baud_rate" => endpoint_value(endpoint, :baud_rate),
      "endpoint_data_bits" => endpoint_value(endpoint, :data_bits),
      "endpoint_path" => endpoint_value(endpoint, :path),
      "endpoint_bucket" => endpoint_value(endpoint, :bucket),
      "endpoint_prefix" => endpoint_value(endpoint, :prefix)
    }
  end

  defp endpoint_value(endpoint, key) do
    Map.get(endpoint, key) || Map.get(endpoint, Atom.to_string(key))
  end

  defp build_changeset(interface, attrs) do
    # For form validation, we use a simple changeset
    types = %{
      name: :string,
      type: :string,
      enabled: :boolean,
      tags: :string,
      endpoint_host: :string,
      endpoint_port: :integer,
      endpoint_mode: :string,
      endpoint_device: :string,
      endpoint_baud_rate: :string,
      endpoint_data_bits: :string,
      endpoint_path: :string,
      endpoint_bucket: :string,
      endpoint_prefix: :string
    }

    {interface, types}
    |> Ecto.Changeset.cast(attrs, Map.keys(types))
  end

  @impl true
  def handle_event("validate", %{"interface" => interface_params}, socket) do
    transport_type = Map.get(interface_params, "type", "")

    # Parse allowed directions from checkboxes
    allowed_directions =
      interface_params
      |> Map.get("allowed_directions", [])
      |> Enum.map(&String.to_existing_atom/1)

    changeset = build_changeset(socket.assigns.interface, interface_params)

    {:noreply,
     socket
     |> assign(:transport_type, transport_type)
     |> assign(:allowed_directions, allowed_directions)
     |> assign_form(Map.put(changeset, :action, :validate))}
  end

  def handle_event("save", %{"interface" => interface_params}, socket) do
    save_interface(socket, socket.assigns.action, interface_params)
  end

  defp save_interface(socket, :edit, interface_params) do
    scope = socket.assigns.current_scope
    mission = socket.assigns.mission
    org_id = scope.current_organization.id

    case Bodyguard.permit(Cadence.Missions.Policy, :manage_targets, scope, mission) do
      :ok ->
        attrs = build_interface_attrs(interface_params)

        case Transports.update_interface(org_id, mission.id, socket.assigns.interface, attrs) do
          {:ok, interface} ->
            notify_parent({:saved, interface})

            {:noreply,
             socket
             |> put_flash(:info, "Transport updated successfully")
             |> push_patch(to: socket.assigns.patch)}

          {:error, %Ecto.Changeset{} = changeset} ->
            {:noreply, assign_form(socket, changeset)}

          {:error, :unauthorized} ->
            {:noreply,
             socket
             |> put_flash(:error, "You don't have permission to update this transport")
             |> push_patch(to: socket.assigns.patch)}
        end

      {:error, _} ->
        {:noreply,
         socket
         |> put_flash(:error, "You don't have permission to update transports")
         |> push_patch(to: socket.assigns.patch)}
    end
  end

  defp save_interface(socket, :new, interface_params) do
    scope = socket.assigns.current_scope
    mission = socket.assigns.mission
    org_id = scope.current_organization.id

    case Bodyguard.permit(Cadence.Missions.Policy, :manage_targets, scope, mission) do
      :ok ->
        attrs = build_interface_attrs(interface_params)

        case Transports.create_interface(org_id, mission.id, attrs) do
          {:ok, interface} ->
            notify_parent({:saved, interface})

            {:noreply,
             socket
             |> put_flash(:info, "Transport created successfully")
             |> push_patch(to: socket.assigns.patch)}

          {:error, %Ecto.Changeset{} = changeset} ->
            {:noreply, assign_form(socket, changeset)}
        end

      {:error, _} ->
        {:noreply,
         socket
         |> put_flash(:error, "You don't have permission to create transports")
         |> push_patch(to: socket.assigns.patch)}
    end
  end

  defp build_interface_attrs(params) do
    transport_type = Map.get(params, "type")

    # Build endpoint map based on type
    endpoint = build_endpoint(transport_type, params)

    # Parse tags
    tags =
      params
      |> Map.get("tags", "")
      |> String.split(",")
      |> Enum.map(&String.trim/1)
      |> Enum.reject(&(&1 == ""))

    # Parse allowed directions
    allowed_directions =
      params
      |> Map.get("allowed_directions", ["both"])
      |> Enum.map(&String.to_existing_atom/1)

    %{
      name: Map.get(params, "name"),
      type: transport_type,
      endpoint: endpoint,
      tags: tags,
      allowed_directions: allowed_directions,
      enabled: Map.get(params, "enabled") == "true"
    }
  end

  defp build_endpoint("tcp", params), do: build_network_endpoint(params)
  defp build_endpoint("udp", params), do: build_network_endpoint(params)

  defp build_endpoint("serial", params) do
    %{
      device: Map.get(params, "endpoint_device"),
      baud_rate: Map.get(params, "endpoint_baud_rate"),
      data_bits: Map.get(params, "endpoint_data_bits")
    }
  end

  defp build_endpoint("file", params) do
    %{path: Map.get(params, "endpoint_path")}
  end

  defp build_endpoint("s3", params) do
    %{
      bucket: Map.get(params, "endpoint_bucket"),
      prefix: Map.get(params, "endpoint_prefix")
    }
  end

  defp build_endpoint(_, _), do: %{}

  defp build_network_endpoint(params) do
    port = Map.get(params, "endpoint_port")

    %{
      host: Map.get(params, "endpoint_host"),
      port: if(port && port != "", do: String.to_integer(port), else: nil),
      mode: Map.get(params, "endpoint_mode")
    }
  end

  defp assign_form(socket, %Ecto.Changeset{} = changeset) do
    assign(socket, :form, to_form(changeset))
  end

  defp assign_form(socket, {_data, _types} = changeset) do
    assign(socket, :form, to_form(changeset, as: :interface))
  end

  defp notify_parent(msg), do: send(self(), {__MODULE__, msg})
end
