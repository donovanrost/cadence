defmodule CadenceWeb.ProtocolLive.FormComponent do
  use CadenceWeb, :live_component

  alias Cadence.Interfaces

  @impl true
  def render(assigns) do
    ~H"""
    <div>
      <.header>
        <%= @title %>
        <:subtitle>Configure protocol type and packet framing settings.</:subtitle>
      </.header>

      <.simple_form
        for={@form}
        id="protocol-form"
        phx-target={@myself}
        phx-change="validate"
        phx-submit="save"
      >
        <.input
          field={@form[:protocol_type]}
          type="select"
          label="Protocol Type"
          prompt="Choose protocol type"
          options={[
            {"CCSDS Space Packet", "ccsds"},
            {"Length-Prefixed", "length"},
            {"Template (Generic)", "template"},
            {"Terminated", "terminated"},
            {"Fixed-Size", "fixed"},
            {"CRC Validation", "crc"}
          ]}
        />

        <.input
          field={@form[:protocol_direction]}
          type="select"
          label="Protocol Direction"
          options={[
            {"READ (incoming data)", "read"},
            {"WRITE (outgoing data)", "write"},
            {"READ/WRITE (bidirectional)", "read_write"}
          ]}
        />

        <%!-- Protocol-specific configuration fields --%>
        <%= if @protocol_type == "template" do %>
          <div class="space-y-4 rounded-lg bg-blue-50 p-4 border border-blue-200">
            <p class="text-sm font-semibold text-blue-900">Template Protocol Configuration</p>

            <.input
              field={@form[:sync_pattern_hex]}
              type="text"
              label="Sync Pattern (Hex)"
              placeholder="1ACFFC1D"
            />
            <p class="mt-1 text-xs text-gray-600">
              CCSDS standard: 1ACFFC1D
            </p>

            <div class="grid grid-cols-2 gap-4">
              <.input
                field={@form[:header_length]}
                type="number"
                label="Header Length (bytes)"
                placeholder="6"
              />
              <.input
                field={@form[:length_offset]}
                type="number"
                label="Length Offset (bytes)"
                placeholder="4"
              />
            </div>

            <div class="grid grid-cols-2 gap-4">
              <.input
                field={@form[:length_bit_size]}
                type="number"
                label="Length Field Size (bits)"
                placeholder="16"
              />
              <.input
                field={@form[:length_value_offset]}
                type="number"
                label="Length Value Offset"
                placeholder="1"
              />
            </div>

            <.input
              field={@form[:length_endian]}
              type="select"
              label="Endianness"
              options={[
                {"Big Endian", "big"},
                {"Little Endian", "little"}
              ]}
            />
          </div>
        <% end %>

        <%= if @protocol_type == "length" do %>
          <div class="space-y-4 rounded-lg bg-green-50 p-4 border border-green-200">
            <p class="text-sm font-semibold text-green-900">Length Protocol Configuration</p>

            <div class="grid grid-cols-2 gap-4">
              <.input
                field={@form[:length_bit_offset]}
                type="number"
                label="Length Bit Offset"
                placeholder="0"
              />
              <.input
                field={@form[:length_bit_size]}
                type="number"
                label="Length Bit Size"
                placeholder="32"
              />
            </div>

            <.input
              field={@form[:sync_pattern_hex]}
              type="text"
              label="Sync Pattern (Hex, optional)"
              placeholder="AABB"
            />

            <.input
              field={@form[:length_endian]}
              type="select"
              label="Endianness"
              options={[
                {"Big Endian", "big"},
                {"Little Endian", "little"}
              ]}
            />
          </div>
        <% end %>

        <%= if @protocol_type == "terminated" do %>
          <div class="space-y-4 rounded-lg bg-purple-50 p-4 border border-purple-200">
            <p class="text-sm font-semibold text-purple-900">Terminated Protocol Configuration</p>

            <.input
              field={@form[:terminator_hex]}
              type="text"
              label="Terminator (Hex)"
              placeholder="0A"
            />
            <p class="mt-1 text-xs text-gray-600">
              Common: 0A (newline), 0D0A (CRLF)
            </p>

            <.input
              field={@form[:strip_terminator]}
              type="checkbox"
              label="Strip terminator from packets"
            />
          </div>
        <% end %>

        <%= if @protocol_type == "fixed" do %>
          <div class="space-y-4 rounded-lg bg-yellow-50 p-4 border border-yellow-200">
            <p class="text-sm font-semibold text-yellow-900">Fixed Protocol Configuration</p>

            <.input
              field={@form[:packet_size]}
              type="number"
              label="Packet Size (bytes)"
              placeholder="1024"
            />
          </div>
        <% end %>

        <%= if @protocol_type == "crc" do %>
          <div class="space-y-4 rounded-lg bg-red-50 p-4 border border-red-200">
            <p class="text-sm font-semibold text-red-900">CRC Protocol Configuration</p>

            <.input
              field={@form[:crc_algorithm]}
              type="select"
              label="CRC Algorithm"
              options={[
                {"CRC-16-CCITT (CCSDS standard)", "crc16_ccitt"},
                {"CRC-32", "crc32"},
                {"CRC-16-XMODEM", "crc16_xmodem"},
                {"CRC-8", "crc8"},
                {"XOR Checksum", "xor_checksum"}
              ]}
            />

            <.input
              field={@form[:crc_endian]}
              type="select"
              label="CRC Byte Order"
              options={[
                {"Big Endian", "big"},
                {"Little Endian", "little"}
              ]}
            />

            <.input
              field={@form[:crc_on_failure]}
              type="select"
              label="On CRC Failure"
              options={[
                {"Skip packet (log warning)", "skip"},
                {"Disconnect (trigger reconnect)", "disconnect"},
                {"Pass packet anyway (log warning)", "pass"}
              ]}
            />
            <p class="mt-1 text-xs text-gray-600">
              Skip is recommended for noisy links. Disconnect for strict validation.
            </p>
          </div>
        <% end %>

        <%= if @protocol_type == "ccsds" do %>
          <div class="space-y-4 rounded-lg bg-indigo-50 p-4 border border-indigo-200">
            <p class="text-sm font-semibold text-indigo-900">CCSDS Space Packet Configuration</p>

            <.input
              field={@form[:sync_pattern_hex]}
              type="text"
              label="Sync Pattern (Hex)"
              placeholder="1ACFFC1D"
            />
            <p class="mt-1 text-xs text-gray-600">
              CCSDS standard ASM: 1ACFFC1D
            </p>

            <.input
              field={@form[:include_sync]}
              type="checkbox"
              label="Include sync pattern when writing packets"
              checked={@form[:include_sync].value != false}
            />
            <p class="mt-1 text-xs text-gray-600">
              Sync pattern is always stripped from incoming packets for proper header parsing.
            </p>

            <div class="border-t border-indigo-200 pt-4 mt-4">
              <p class="text-sm font-medium text-indigo-800 mb-3">CRC Validation (Optional)</p>

              <.input
                field={@form[:ccsds_crc_enabled]}
                type="checkbox"
                label="Enable CRC validation"
              />

              <%= if @ccsds_crc_enabled do %>
                <div class="mt-3 space-y-3 pl-4 border-l-2 border-indigo-200">
                  <.input
                    field={@form[:ccsds_crc_algorithm]}
                    type="select"
                    label="CRC Algorithm"
                    options={[
                      {"CRC-16-CCITT (CCSDS standard)", "crc16_ccitt"},
                      {"CRC-32", "crc32"},
                      {"CRC-16-XMODEM", "crc16_xmodem"}
                    ]}
                  />

                  <.input
                    field={@form[:ccsds_crc_endian]}
                    type="select"
                    label="CRC Byte Order"
                    options={[
                      {"Big Endian", "big"},
                      {"Little Endian", "little"}
                    ]}
                  />

                  <.input
                    field={@form[:ccsds_crc_on_failure]}
                    type="select"
                    label="On CRC Failure"
                    options={[
                      {"Skip packet (log warning)", "skip"},
                      {"Disconnect (trigger reconnect)", "disconnect"},
                      {"Pass packet anyway (log warning)", "pass"}
                    ]}
                  />
                </div>
              <% end %>
            </div>
          </div>
        <% end %>

        <:actions>
          <.button phx-disable-with="Saving...">Save Protocol</.button>
        </:actions>
      </.simple_form>
    </div>
    """
  end

  @impl true
  def update(%{protocol: protocol} = assigns, socket) do
    # Extract protocol config fields for form display
    protocol_config = protocol.protocol_config || %{}

    # Populate form fields from protocol_config
    protocol_with_fields =
      protocol
      |> Map.put(:sync_pattern_hex, protocol_config["sync_pattern_hex"])
      |> Map.put(:terminator_hex, protocol_config["terminator_hex"])
      |> Map.put(:header_length, protocol_config["header_length"])
      |> Map.put(:length_offset, protocol_config["length_offset"])
      |> Map.put(:length_bit_size, protocol_config["length_bit_size"])
      |> Map.put(:length_value_offset, protocol_config["length_value_offset"])
      |> Map.put(:length_bit_offset, protocol_config["length_bit_offset"])
      |> Map.put(:length_endian, protocol_config["length_endian"])
      |> Map.put(:strip_terminator, protocol_config["strip_terminator"])
      |> Map.put(:packet_size, protocol_config["packet_size"])
      # CRC protocol fields
      |> Map.put(:crc_algorithm, protocol_config["algorithm"])
      |> Map.put(:crc_endian, protocol_config["endian"])
      |> Map.put(:crc_on_failure, protocol_config["on_failure"])
      # CCSDS protocol fields
      |> Map.put(:include_sync, Map.get(protocol_config, "include_sync", true))
      |> Map.put(:ccsds_crc_enabled, Map.get(protocol_config, "crc_enabled", false))
      |> Map.put(:ccsds_crc_algorithm, protocol_config["crc_algorithm"])
      |> Map.put(:ccsds_crc_endian, protocol_config["crc_endian"])
      |> Map.put(:ccsds_crc_on_failure, protocol_config["crc_on_failure"])

    changeset = Interfaces.change_protocol(protocol_with_fields)

    # Track CCSDS CRC enabled state for conditional rendering
    ccsds_crc_enabled = Map.get(protocol_config, "crc_enabled", false)

    {:ok,
     socket
     |> assign(assigns)
     |> assign(:protocol_type, protocol.protocol_type)
     |> assign(:ccsds_crc_enabled, ccsds_crc_enabled)
     |> assign_form(changeset)}
  end

  @impl true
  def handle_event("validate", %{"interface_protocol" => protocol_params}, socket) do
    # Update reactive assigns
    protocol_type = Map.get(protocol_params, "protocol_type")
    ccsds_crc_enabled = Map.get(protocol_params, "ccsds_crc_enabled") == "true"

    changeset =
      socket.assigns.protocol
      |> Interfaces.change_protocol(protocol_params)
      |> Map.put(:action, :validate)

    {:noreply,
     socket
     |> assign(:protocol_type, protocol_type)
     |> assign(:ccsds_crc_enabled, ccsds_crc_enabled)
     |> assign_form(changeset)}
  end

  def handle_event("save", %{"interface_protocol" => protocol_params}, socket) do
    save_protocol(socket, socket.assigns.action, protocol_params)
  end

  defp save_protocol(socket, :edit, protocol_params) do
    params_with_config = build_protocol_config(protocol_params)

    case Interfaces.update_protocol(socket.assigns.protocol, params_with_config) do
      {:ok, protocol} ->
        notify_parent({:saved, protocol})

        {:noreply,
         socket
         |> put_flash(:info, "Protocol updated successfully")
         |> push_patch(to: socket.assigns.patch)}

      {:error, %Ecto.Changeset{} = changeset} ->
        {:noreply, assign_form(socket, changeset)}
    end
  end

  defp save_protocol(socket, :new, protocol_params) do
    params_with_config = build_protocol_config(protocol_params)

    case Interfaces.add_protocol(socket.assigns.interface, params_with_config) do
      {:ok, protocol} ->
        notify_parent({:saved, protocol})

        {:noreply,
         socket
         |> put_flash(:info, "Protocol created successfully")
         |> push_patch(to: socket.assigns.patch)}

      {:error, %Ecto.Changeset{} = changeset} ->
        {:noreply, assign_form(socket, changeset)}
    end
  end

  # Build protocol_config map from individual form fields
  # Store hex strings directly in the database (not binary) since JSONB cannot store binary data
  defp build_protocol_config(params) do
    protocol_type = Map.get(params, "protocol_type")

    protocol_config =
      case protocol_type do
        "template" ->
          %{
            "sync_pattern_hex" => normalize_hex(params["sync_pattern_hex"]),
            "header_length" => parse_int(params["header_length"]),
            "length_offset" => parse_int(params["length_offset"]),
            "length_bit_size" => parse_int(params["length_bit_size"]),
            "length_value_offset" => parse_int(params["length_value_offset"]),
            "length_endian" => params["length_endian"] || "big"
          }
          |> Enum.reject(fn {_k, v} -> is_nil(v) or v == "" end)
          |> Map.new()

        "length" ->
          %{
            "length_bit_offset" => parse_int(params["length_bit_offset"]),
            "length_bit_size" => parse_int(params["length_bit_size"]),
            "length_endian" => params["length_endian"] || "big",
            "sync_pattern_hex" => normalize_hex(params["sync_pattern_hex"])
          }
          |> Enum.reject(fn {_k, v} -> is_nil(v) or v == "" end)
          |> Map.new()

        "terminated" ->
          %{
            "terminator_hex" => normalize_hex(params["terminator_hex"]),
            "strip_terminator" => params["strip_terminator"] == "true"
          }
          |> Enum.reject(fn {_k, v} -> is_nil(v) or v == "" end)
          |> Map.new()

        "fixed" ->
          %{
            "packet_size" => parse_int(params["packet_size"])
          }
          |> Enum.reject(fn {_k, v} -> is_nil(v) end)
          |> Map.new()

        "crc" ->
          %{
            "algorithm" => params["crc_algorithm"] || "crc16_ccitt",
            "endian" => params["crc_endian"] || "big",
            "on_failure" => params["crc_on_failure"] || "skip"
          }

        "ccsds" ->
          crc_enabled = params["ccsds_crc_enabled"] == "true"
          include_sync = Map.get(params, "include_sync", "true") == "true"

          base_config = %{
            "sync_pattern_hex" => normalize_hex(params["sync_pattern_hex"]) || "1ACFFC1D",
            "include_sync" => include_sync,
            # Always discard sync - required for proper CCSDS header parsing
            "discard_sync" => true,
            "crc_enabled" => crc_enabled
          }

          if crc_enabled do
            base_config
            |> Map.put("crc_algorithm", params["ccsds_crc_algorithm"] || "crc16_ccitt")
            |> Map.put("crc_endian", params["ccsds_crc_endian"] || "big")
            |> Map.put("crc_on_failure", params["ccsds_crc_on_failure"] || "skip")
          else
            base_config
          end

        _ ->
          %{}
      end

    # Remove protocol config form fields and add the built config
    params
    |> Map.drop([
      "sync_pattern_hex",
      "terminator_hex",
      "header_length",
      "length_offset",
      "length_bit_size",
      "length_value_offset",
      "length_bit_offset",
      "length_endian",
      "strip_terminator",
      "packet_size",
      "crc_algorithm",
      "crc_endian",
      "crc_on_failure",
      # CCSDS specific fields
      "include_sync",
      "ccsds_crc_enabled",
      "ccsds_crc_algorithm",
      "ccsds_crc_endian",
      "ccsds_crc_on_failure"
    ])
    |> Map.put("protocol_config", protocol_config)
  end

  # Normalize hex string (uppercase, remove spaces)
  defp normalize_hex(nil), do: nil
  defp normalize_hex(""), do: nil

  defp normalize_hex(hex_string) when is_binary(hex_string) do
    hex_string
    |> String.replace(~r/\s/, "")
    |> String.upcase()
    |> case do
      "" -> nil
      normalized -> normalized
    end
  end

  # Parse integer from string
  defp parse_int(nil), do: nil
  defp parse_int(""), do: nil

  defp parse_int(value) when is_binary(value) do
    case Integer.parse(value) do
      {int, _} -> int
      :error -> nil
    end
  end

  defp parse_int(value) when is_integer(value), do: value

  defp assign_form(socket, %Ecto.Changeset{} = changeset) do
    assign(socket, :form, to_form(changeset))
  end

  defp notify_parent(msg), do: send(self(), {__MODULE__, msg})
end
