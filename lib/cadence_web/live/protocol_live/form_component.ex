defmodule CadenceWeb.ProtocolLive.FormComponent do
  use CadenceWeb, :live_component

  alias Cadence.Interfaces
  alias Cadence.Interfaces.InterfaceProtocol

  @impl true
  def render(assigns) do
    ~H"""
    <div>
      <.header>
        {@title}
        <:subtitle>Configure protocol type and packet framing settings.</:subtitle>
      </.header>

      <%= if @form.source.action in [:insert, :update, :validate] and @form.source.errors != [] do %>
        <div
          id="protocol-form-errors"
          class="mb-4 rounded border border-red-300 bg-red-50 px-3 py-2 text-sm text-red-800"
        >
          <p class="font-medium">Please fix the errors below.</p>
          <ul class="mt-2 list-disc pl-5">
            <%= for {field, {message, _}} <- @form.source.errors do %>
              <li>{String.capitalize(to_string(field))}: {message}</li>
            <% end %>
          </ul>
        </div>
      <% end %>

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
            {"CCSDS SDLP (TM/AOS/USLP)", "ccsds_sdlp"},
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
          <div class="space-y-4 rounded-sm bg-base-200/50 p-4 border border-base-300">
            <p class="text-sm font-semibold text-base-content">Template Protocol Configuration</p>

            <.input
              field={@form[:sync_pattern_hex]}
              type="text"
              label="Sync Pattern (Hex)"
              placeholder="1ACFFC1D"
            />
            <p class="mt-1 text-xs text-base-content/60">
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
          <div class="space-y-4 rounded-sm bg-base-200/50 p-4 border border-base-300">
            <p class="text-sm font-semibold text-base-content">Length Protocol Configuration</p>

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
          <div class="space-y-4 rounded-sm bg-base-200/50 p-4 border border-base-300">
            <p class="text-sm font-semibold text-base-content">Terminated Protocol Configuration</p>

            <.input
              field={@form[:terminator_hex]}
              type="text"
              label="Terminator (Hex)"
              placeholder="0A"
            />
            <p class="mt-1 text-xs text-base-content/60">
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
          <div class="space-y-4 rounded-sm bg-base-200/50 p-4 border border-base-300">
            <p class="text-sm font-semibold text-base-content">Fixed Protocol Configuration</p>

            <.input
              field={@form[:packet_size]}
              type="number"
              label="Packet Size (bytes)"
              placeholder="1024"
            />
          </div>
        <% end %>

        <%= if @protocol_type == "crc" do %>
          <div class="space-y-4 rounded-sm bg-base-200/50 p-4 border border-base-300">
            <p class="text-sm font-semibold text-base-content">CRC Protocol Configuration</p>

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
            <p class="mt-1 text-xs text-base-content/60">
              Skip is recommended for noisy links. Disconnect for strict validation.
            </p>
          </div>
        <% end %>

        <%= if @protocol_type == "ccsds_sdlp" do %>
          <div class="space-y-4 rounded-sm bg-base-200/50 p-4 border border-base-300">
            <p class="text-sm font-semibold text-base-content">
              CCSDS SDLP Configuration
            </p>

            <.input
              field={@form[:sdlp_profile]}
              type="select"
              label="Profile"
              options={[
                {"TM", "tm"},
                {"AOS", "aos"},
                {"USLP", "uslp"}
              ]}
            />

            <div class="grid grid-cols-2 gap-4">
              <.input
                field={@form[:sdlp_frame_size]}
                type="number"
                label="Frame Size (bytes)"
                placeholder="1115"
              />
              <.input
                field={@form[:sdlp_ocf_length]}
                type="number"
                label="OCF Length (bytes)"
                placeholder="4"
              />
            </div>

            <.input
              field={@form[:sdlp_secondary_header_length]}
              type="number"
              label="Secondary Header Length (bytes)"
              placeholder="0"
            />

            <div class="grid grid-cols-2 gap-4">
              <.input
                field={@form[:sdlp_oid_validation]}
                type="select"
                label="OID Idle Data Validation"
                options={[
                  {"None", "none"},
                  {"Prefix Only", "prefix"},
                  {"Strict", "strict"}
                ]}
              />
              <.input
                field={@form[:sdlp_oid_validation_prefix_bytes]}
                type="number"
                label="OID Prefix Bytes (prefix validation)"
                placeholder="10"
              />
            </div>

            <div class="grid grid-cols-2 gap-4">
              <.input
                field={@form[:sdlp_default_sdu_type]}
                type="select"
                label="Default SDU Type"
                options={[
                  {"Space Packet", "space_packet"},
                  {"Encapsulation Packet", "encap"}
                ]}
              />
              <.input
                field={@form[:sdlp_uplink_scid]}
                type="number"
                label="Uplink SCID"
                placeholder="1"
              />
            </div>

            <div class="grid grid-cols-2 gap-4">
              <.input
                field={@form[:sdlp_uplink_vcid]}
                type="number"
                label="Uplink VCID"
                placeholder="0"
              />
              <.input
                field={@form[:sdlp_uplink_map_id]}
                type="number"
                label="Uplink MAP ID"
                placeholder="0"
              />
            </div>

            <.input
              field={@form[:sdlp_sdu_mapping_json]}
              type="textarea"
              label="SDU Mapping (JSON)"
              placeholder={sdu_mapping_placeholder()}
              rows="6"
            />
            <p class="mt-1 text-xs text-base-content/60">
              Provide a JSON array of mapping entries keyed by scid/vcid/map_id/direction.
            </p>

            <div class="grid grid-cols-2 gap-4">
              <.input
                field={@form[:sdlp_default_target_id]}
                type="text"
                label="Default Target ID"
                placeholder="SIM-1"
              />
              <.input
                field={@form[:sdlp_scid_target_map_json]}
                type="textarea"
                label="SCID -> Target ID Map (JSON)"
                placeholder={scid_target_map_placeholder()}
                rows="3"
              />
            </div>

            <div class="grid grid-cols-2 gap-4">
              <.input
                field={@form[:sdlp_vcid_target_map_json]}
                type="textarea"
                label="SCID/VCID Metadata Map (JSON)"
                placeholder={vcid_target_map_placeholder()}
                rows="3"
              />
              <.input
                field={@form[:sdlp_default_vcid_map_json]}
                type="textarea"
                label="Default VCID Metadata Map (JSON)"
                placeholder={default_vcid_map_placeholder()}
                rows="3"
              />
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
      |> Map.put(:sdlp_profile, protocol_config["profile"])
      |> Map.put(:sdlp_frame_size, protocol_config["frame_size"])
      |> Map.put(:sdlp_secondary_header_length, protocol_config["secondary_header_length"])
      |> Map.put(:sdlp_ocf_length, protocol_config["ocf_length"])
      |> Map.put(:sdlp_oid_validation, protocol_config["oid_validation"])
      |> Map.put(
        :sdlp_oid_validation_prefix_bytes,
        protocol_config["oid_validation_prefix_bytes"]
      )
      |> Map.put(:sdlp_default_sdu_type, protocol_config["default_sdu_type"])
      |> Map.put(:sdlp_uplink_scid, protocol_config["uplink_scid"])
      |> Map.put(:sdlp_uplink_vcid, protocol_config["uplink_vcid"])
      |> Map.put(:sdlp_uplink_map_id, protocol_config["uplink_map_id"])
      |> Map.put(:sdlp_sdu_mapping_json, format_sdu_mapping(protocol_config["sdu_mapping"]))
      |> Map.put(:sdlp_default_target_id, protocol_config["default_target_id"])
      |> Map.put(:sdlp_scid_target_map_json, format_json(protocol_config["scid_target_map"]))
      |> Map.put(:sdlp_vcid_target_map_json, format_json(protocol_config["vcid_target_map"]))
      |> Map.put(:sdlp_default_vcid_map_json, format_json(protocol_config["default_vcid_map"]))

    changeset = InterfaceProtocol.changeset(protocol_with_fields, %{})

    {:ok,
     socket
     |> assign(assigns)
     |> assign(:protocol_type, protocol.protocol_type)
     |> assign_form(changeset)}
  end

  @impl true
  def handle_event("validate", %{"interface_protocol" => protocol_params}, socket) do
    # Update reactive assigns
    protocol_type = Map.get(protocol_params, "protocol_type")

    changeset =
      socket.assigns.protocol
      |> InterfaceProtocol.changeset(protocol_params)
      |> Map.put(:action, :validate)

    {:noreply,
     socket
     |> assign(:protocol_type, protocol_type)
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

    protocol_config = config_builder_for_type(protocol_type).(params)

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
      # SDLP fields
      "sdlp_profile",
      "sdlp_frame_size",
      "sdlp_secondary_header_length",
      "sdlp_ocf_length",
      "sdlp_oid_validation",
      "sdlp_oid_validation_prefix_bytes",
      "sdlp_default_sdu_type",
      "sdlp_uplink_scid",
      "sdlp_uplink_vcid",
      "sdlp_uplink_map_id",
      "sdlp_sdu_mapping_json",
      "sdlp_default_target_id",
      "sdlp_scid_target_map_json",
      "sdlp_vcid_target_map_json",
      "sdlp_default_vcid_map_json"
    ])
    |> Map.put("protocol_config", protocol_config)
  end

  defp build_config_template(params) do
    %{
      "sync_pattern_hex" => normalize_hex(params["sync_pattern_hex"]),
      "header_length" => parse_int(params["header_length"]),
      "length_offset" => parse_int(params["length_offset"]),
      "length_bit_size" => parse_int(params["length_bit_size"]),
      "length_value_offset" => parse_int(params["length_value_offset"]),
      "length_endian" => params["length_endian"] || "big"
    }
    |> compact_config()
  end

  defp build_config_length(params) do
    %{
      "length_bit_offset" => parse_int(params["length_bit_offset"]),
      "length_bit_size" => parse_int(params["length_bit_size"]),
      "length_endian" => params["length_endian"] || "big",
      "sync_pattern_hex" => normalize_hex(params["sync_pattern_hex"])
    }
    |> compact_config()
  end

  defp build_config_terminated(params) do
    %{
      "terminator_hex" => normalize_hex(params["terminator_hex"]),
      "strip_terminator" => params["strip_terminator"] == "true"
    }
    |> compact_config()
  end

  defp build_config_fixed(params) do
    %{
      "packet_size" => parse_int(params["packet_size"])
    }
    |> compact_config()
  end

  defp build_config_crc(params) do
    %{
      "algorithm" => params["crc_algorithm"] || "crc16_ccitt",
      "endian" => params["crc_endian"] || "big",
      "on_failure" => params["crc_on_failure"] || "skip"
    }
  end

  defp build_config_sdlp(params) do
    %{
      "profile" => params["sdlp_profile"],
      "frame_size" => parse_int(params["sdlp_frame_size"]),
      "secondary_header_length" => parse_int(params["sdlp_secondary_header_length"]),
      "ocf_length" => parse_int(params["sdlp_ocf_length"]),
      "oid_validation" => params["sdlp_oid_validation"],
      "oid_validation_prefix_bytes" => parse_int(params["sdlp_oid_validation_prefix_bytes"]),
      "default_sdu_type" => params["sdlp_default_sdu_type"],
      "uplink_scid" => parse_int(params["sdlp_uplink_scid"]),
      "uplink_vcid" => parse_int(params["sdlp_uplink_vcid"]),
      "uplink_map_id" => parse_int(params["sdlp_uplink_map_id"]),
      "sdu_mapping" => parse_sdu_mapping(params["sdlp_sdu_mapping_json"]),
      "default_target_id" => params["sdlp_default_target_id"],
      "scid_target_map" => parse_json(params["sdlp_scid_target_map_json"]),
      "vcid_target_map" => parse_json(params["sdlp_vcid_target_map_json"]),
      "default_vcid_map" => parse_json(params["sdlp_default_vcid_map_json"])
    }
    |> compact_config()
  end

  defp config_builder_for_type("template"), do: &build_config_template/1
  defp config_builder_for_type("length"), do: &build_config_length/1
  defp config_builder_for_type("terminated"), do: &build_config_terminated/1
  defp config_builder_for_type("fixed"), do: &build_config_fixed/1
  defp config_builder_for_type("crc"), do: &build_config_crc/1
  defp config_builder_for_type("ccsds_sdlp"), do: &build_config_sdlp/1
  defp config_builder_for_type(_protocol_type), do: fn _params -> %{} end

  defp compact_config(config) do
    config
    |> Enum.reject(fn {_k, v} -> is_nil(v) or v == "" end)
    |> Map.new()
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

  defp parse_sdu_mapping(nil), do: nil
  defp parse_sdu_mapping(""), do: nil

  defp parse_sdu_mapping(value) when is_binary(value) do
    case Jason.decode(value) do
      {:ok, decoded} -> decoded
      _ -> :invalid
    end
  end

  defp parse_json(nil), do: nil
  defp parse_json(""), do: nil

  defp parse_json(value) when is_binary(value) do
    case Jason.decode(value) do
      {:ok, decoded} -> decoded
      _ -> :invalid
    end
  end

  defp format_sdu_mapping(nil), do: nil

  defp format_sdu_mapping(mapping) when is_list(mapping) or is_map(mapping) do
    case Jason.encode(mapping, pretty: true) do
      {:ok, json} -> json
      _ -> nil
    end
  end

  defp format_sdu_mapping(_), do: nil

  defp format_json(nil), do: nil

  defp format_json(value) when is_list(value) or is_map(value) do
    case Jason.encode(value, pretty: true) do
      {:ok, json} -> json
      _ -> nil
    end
  end

  defp format_json(_), do: nil

  defp sdu_mapping_placeholder do
    """
    [
      {"scid": 1, "vcid": 0, "map_id": null, "direction": "downlink", "type": "space_packet"}
    ]
    """
  end

  defp scid_target_map_placeholder do
    """
    {"1": "SIM-1"}
    """
  end

  defp vcid_target_map_placeholder do
    """
    {"1": {"0": {"lane": "payload", "qos": "realtime"}}}
    """
  end

  defp default_vcid_map_placeholder do
    """
    {"0": {"lane": "payload", "qos": "realtime"}}
    """
  end

  defp assign_form(socket, %Ecto.Changeset{} = changeset) do
    assign(socket, :form, to_form(changeset))
  end

  defp notify_parent(msg), do: send(self(), {__MODULE__, msg})
end
