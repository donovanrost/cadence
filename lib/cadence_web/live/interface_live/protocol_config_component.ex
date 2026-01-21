defmodule CadenceWeb.InterfaceLive.ProtocolConfigComponent do
  @moduledoc """
  LiveComponent for configuring SDLP protocol settings on an interface.

  Provides inline editing for:
  - Framing mode (none/sdlp)
  - SDLP profile (TM, AOS, USLP)
  - Frame settings (frame_size, secondary_header_length, ocf_length)
  - SDU mappings (SCID/VCID routing)
  - Uplink defaults
  - COP-1 (FOP) settings
  """

  use CadenceWeb, :live_component

  alias Cadence.Interfaces

  @profiles [
    {"TM (Telemetry)", "tm"},
    {"AOS (Advanced Orbiting Systems)", "aos"},
    {"USLP (Unified Space Link Protocol)", "uslp"}
  ]

  @sdu_types [
    {"Space Packet", "space_packet"},
    {"Encapsulation Packet", "encap"}
  ]

  @directions [
    {"Downlink", "downlink"},
    {"Uplink", "uplink"}
  ]

  @cop1_modes [
    {"Disabled", "disabled"},
    {"FOP (Enabled)", "fop"}
  ]

  @cop1_config_drop_keys [
    "mode",
    :mode,
    "enabled",
    :enabled,
    "window_size",
    :window_size,
    "timeout_ms",
    :timeout_ms,
    "max_retransmit",
    :max_retransmit,
    "initial_seq",
    :initial_seq,
    "apids",
    :apids,
    "report_apids",
    :report_apids,
    "report_apid",
    :report_apid,
    "bypass_flag",
    :bypass_flag,
    "bypass",
    :bypass,
    "control_command_flag",
    :control_command_flag,
    "control_command",
    :control_command,
    "segment_header_flag",
    :segment_header_flag
  ]

  @impl true
  def render(assigns) do
    ~H"""
    <div class="space-y-6">
      <div class="rounded-sm border border-base-300 bg-base-100">
        <div class="flex items-center justify-between border-b border-base-300 px-4 py-3">
          <h3 class="text-sm font-semibold text-base-content">Protocol Configuration</h3>
        </div>

        <div class="p-4 space-y-6">
          <%!-- Framing Mode Toggle --%>
          <div class="flex items-center gap-4">
            <span class="text-sm font-medium text-base-content">Framing Mode:</span>
            <div class="join">
              <button
                type="button"
                phx-click="set_framing_mode"
                phx-value-mode="none"
                phx-target={@myself}
                class={[
                  "join-item btn btn-sm",
                  !@sdlp_enabled && "btn-primary",
                  @sdlp_enabled && "btn-ghost"
                ]}
              >
                None
              </button>
              <button
                type="button"
                phx-click="set_framing_mode"
                phx-value-mode="sdlp"
                phx-target={@myself}
                class={[
                  "join-item btn btn-sm",
                  @sdlp_enabled && "btn-primary",
                  !@sdlp_enabled && "btn-ghost"
                ]}
              >
                SDLP
              </button>
            </div>
          </div>

          <%= if @sdlp_enabled do %>
            <%!-- SDLP Settings Form --%>
            <.form
              for={@protocol_form}
              id="protocol-config-form"
              phx-change="update_sdlp"
              phx-target={@myself}
              class="space-y-4"
            >
              <div class="grid grid-cols-2 gap-4">
                <.input
                  field={@protocol_form[:profile]}
                  type="select"
                  label="Profile"
                  options={@profile_options}
                  class="w-full select select-sm"
                />

                <.input
                  field={@protocol_form[:default_sdu_type]}
                  type="select"
                  label="Default SDU Type"
                  prompt="None (require mapping)"
                  options={@sdu_type_options}
                  class="w-full select select-sm"
                />
              </div>

              <div class="grid grid-cols-3 gap-4">
                <.input
                  field={@protocol_form[:frame_size]}
                  type="number"
                  label="Frame Size (bytes)"
                  placeholder="e.g., 1115"
                  class="w-full input input-sm"
                  min="0"
                />

                <.input
                  field={@protocol_form[:secondary_header_length]}
                  type="number"
                  label="Secondary Header Length"
                  placeholder="0"
                  class="w-full input input-sm"
                  min="0"
                />

                <.input
                  field={@protocol_form[:ocf_length]}
                  type="number"
                  label="OCF Length"
                  placeholder="0"
                  class="w-full input input-sm"
                  min="0"
                />
              </div>

              <%!-- OID Validation (collapsible) --%>
              <details class="collapse collapse-arrow border border-base-300 bg-base-200/30">
                <summary class="collapse-title text-sm font-medium py-2 min-h-0">
                  OID Validation
                </summary>
                <div class="collapse-content">
                  <div class="flex flex-wrap items-center gap-4 pt-2">
                    <.input
                      field={@protocol_form[:oid_validation]}
                      type="checkbox"
                      label="Enable OID Validation"
                    />
                    <%= if @oid_validation do %>
                      <.input
                        field={@protocol_form[:oid_validation_prefix_bytes]}
                        type="number"
                        label="Prefix Bytes"
                        placeholder="0"
                        class="input input-sm w-24"
                        min="0"
                      />
                    <% end %>
                  </div>
                </div>
              </details>

              <%!-- Uplink Defaults (collapsible) --%>
              <details class="collapse collapse-arrow border border-base-300 bg-base-200/30">
                <summary class="collapse-title text-sm font-medium py-2 min-h-0">
                  Uplink Defaults
                </summary>
                <div class="collapse-content">
                  <p class="text-xs text-base-content/60 mb-3 pt-2">
                    Default routing for uplink (command) frames when no mapping matches.
                  </p>
                  <div class="grid grid-cols-3 gap-4">
                    <.input
                      field={@protocol_form[:uplink_scid]}
                      type="number"
                      label="Uplink SCID"
                      placeholder="e.g., 42"
                      class="w-full input input-sm"
                      min="0"
                    />

                    <.input
                      field={@protocol_form[:uplink_vcid]}
                      type="number"
                      label="Uplink VCID"
                      placeholder="e.g., 0"
                      class="w-full input input-sm"
                      min="0"
                    />

                    <%= if @profile in ["aos", "uslp"] do %>
                      <.input
                        field={@protocol_form[:uplink_map_id]}
                        type="number"
                        label="Uplink MAP ID"
                        placeholder="Optional"
                        class="w-full input input-sm"
                        min="0"
                      />
                    <% end %>
                  </div>
                </div>
              </details>

              <%!-- COP-1 (collapsible) --%>
              <details
                id="cop1-config"
                class="collapse collapse-arrow border border-base-300 bg-base-200/30"
              >
                <summary class="collapse-title text-sm font-medium py-2 min-h-0">
                  COP-1 (FOP)
                </summary>
                <div class="collapse-content space-y-4">
                  <p class="text-xs text-base-content/60 pt-2">
                    COP-1 requires SDLP uplink (TC framing) with `frame_size` or
                    `uplink_frame_size` plus `uplink_vcid`.
                  </p>
                  <div class="grid grid-cols-2 gap-4">
                    <.input
                      field={@protocol_form[:cop1_mode]}
                      type="select"
                      label="Mode"
                      options={@cop1_mode_options}
                      class="w-full select select-sm"
                    />

                    <.input
                      field={@protocol_form[:cop1_window_size]}
                      type="number"
                      label="Window Size"
                      placeholder="4"
                      class="w-full input input-sm"
                      min="1"
                    />

                    <.input
                      field={@protocol_form[:cop1_timeout_ms]}
                      type="number"
                      label="Timeout (ms)"
                      placeholder="5000"
                      class="w-full input input-sm"
                      min="1"
                    />

                    <.input
                      field={@protocol_form[:cop1_max_retransmit]}
                      type="number"
                      label="Max Retransmit"
                      placeholder="3"
                      class="w-full input input-sm"
                      min="0"
                    />

                    <.input
                      field={@protocol_form[:cop1_initial_seq]}
                      type="number"
                      label="Initial Seq"
                      placeholder="0"
                      class="w-full input input-sm"
                      min="0"
                    />
                  </div>

                  <div class="grid grid-cols-2 gap-4">
                    <.input
                      field={@protocol_form[:cop1_apids]}
                      type="text"
                      label="Protected APIDs"
                      placeholder="e.g., 1, 2, 42"
                      class="w-full input input-sm"
                    />

                    <.input
                      field={@protocol_form[:cop1_report_apids]}
                      type="text"
                      label="Report APIDs"
                      placeholder="e.g., 2047"
                      class="w-full input input-sm"
                    />
                  </div>

                  <div class="grid grid-cols-3 gap-4">
                    <.input
                      field={@protocol_form[:cop1_bypass_flag]}
                      type="checkbox"
                      label="Bypass Flag"
                    />

                    <.input
                      field={@protocol_form[:cop1_control_command_flag]}
                      type="checkbox"
                      label="Control Command Flag"
                    />

                    <.input
                      field={@protocol_form[:cop1_segment_header_flag]}
                      type="checkbox"
                      label="Segment Header Flag"
                    />
                  </div>

                  <p class="text-xs text-base-content/60">
                    APIDs accept comma-separated lists; leave blank to apply COP-1 to all
                    command APIDs. Report APIDs route downlink CLCW packets into the COP-1
                    handler.
                  </p>
                </div>
              </details>
            </.form>

            <%!-- SDU Mappings Section --%>
            <div class="border-t border-base-300 pt-4">
              <div class="flex items-center justify-between mb-3">
                <div>
                  <h4 class="text-sm font-semibold text-base-content">SDU Mappings</h4>
                  <p class="text-xs text-base-content/60">
                    Route frames by SCID/VCID to specific SDU processors.
                  </p>
                </div>
                <button
                  type="button"
                  phx-click="add_sdu_mapping"
                  phx-target={@myself}
                  class="btn btn-sm btn-primary btn-soft"
                >
                  <.icon name="hero-plus" class="-ml-0.5 mr-1 h-4 w-4" /> Add Mapping
                </button>
              </div>

              <%= if Enum.empty?(@sdu_mappings) do %>
                <div class="text-sm text-base-content/50 italic py-4 text-center border border-dashed border-base-300 rounded-sm">
                  No SDU mappings defined. Frames will use the default SDU type.
                </div>
              <% else %>
                <div class="overflow-x-auto">
                  <table class="table table-sm">
                    <thead>
                      <tr class="text-xs">
                        <th>SCID</th>
                        <th>VCID</th>
                        <%= if @profile in ["aos", "uslp"] do %>
                          <th>MAP ID</th>
                        <% end %>
                        <th>Direction</th>
                        <th>SDU Type</th>
                        <th class="w-20"></th>
                      </tr>
                    </thead>
                    <tbody>
                      <%= for {mapping, index} <- Enum.with_index(@sdu_mappings) do %>
                        <tr class="hover:bg-base-200/50">
                          <%= if @editing_index == index do %>
                            <%!-- Inline edit mode --%>
                            <td>
                              <input
                                type="number"
                                name="edit_scid"
                                value={mapping["scid"]}
                                phx-blur="update_mapping_field"
                                phx-value-index={index}
                                phx-value-field="scid"
                                phx-target={@myself}
                                class="input input-sm w-20"
                                min="0"
                              />
                            </td>
                            <td>
                              <input
                                type="number"
                                name="edit_vcid"
                                value={mapping["vcid"]}
                                phx-blur="update_mapping_field"
                                phx-value-index={index}
                                phx-value-field="vcid"
                                phx-target={@myself}
                                class="input input-sm w-20"
                                min="0"
                              />
                            </td>
                            <%= if @profile in ["aos", "uslp"] do %>
                              <td>
                                <input
                                  type="number"
                                  name="edit_map_id"
                                  value={mapping["map_id"]}
                                  phx-blur="update_mapping_field"
                                  phx-value-index={index}
                                  phx-value-field="map_id"
                                  phx-target={@myself}
                                  class="input input-sm w-20"
                                  placeholder="-"
                                />
                              </td>
                            <% end %>
                            <td>
                              <select
                                name="edit_direction"
                                phx-change="update_mapping_field"
                                phx-value-index={index}
                                phx-value-field="direction"
                                phx-target={@myself}
                                class="select select-sm w-28"
                              >
                                <%= for {label, value} <- @direction_options do %>
                                  <option value={value} selected={mapping["direction"] == value}>
                                    {label}
                                  </option>
                                <% end %>
                              </select>
                            </td>
                            <td>
                              <select
                                name="edit_type"
                                phx-change="update_mapping_field"
                                phx-value-index={index}
                                phx-value-field="type"
                                phx-target={@myself}
                                class="select select-sm w-32"
                              >
                                <%= for {label, value} <- @sdu_type_options do %>
                                  <option value={value} selected={mapping["type"] == value}>
                                    {label}
                                  </option>
                                <% end %>
                              </select>
                            </td>
                            <td>
                              <button
                                type="button"
                                phx-click="finish_editing"
                                phx-target={@myself}
                                class="btn btn-ghost btn-sm btn-square"
                                title="Done editing"
                              >
                                <.icon name="hero-check" class="h-4 w-4 text-success" />
                              </button>
                            </td>
                          <% else %>
                            <%!-- Read mode --%>
                            <td class="font-mono text-sm">{mapping["scid"]}</td>
                            <td class="font-mono text-sm">{mapping["vcid"]}</td>
                            <%= if @profile in ["aos", "uslp"] do %>
                              <td class="font-mono text-sm text-base-content/60">
                                {mapping["map_id"] || "-"}
                              </td>
                            <% end %>
                            <td>
                              <span class={[
                                "text-xs",
                                mapping["direction"] == "uplink" && "text-accent",
                                mapping["direction"] == "downlink" && "text-info"
                              ]}>
                                <%= if mapping["direction"] == "uplink" do %>
                                  <.icon name="hero-arrow-up" class="h-3 w-3 inline" /> Up
                                <% else %>
                                  <.icon name="hero-arrow-down" class="h-3 w-3 inline" /> Down
                                <% end %>
                              </span>
                            </td>
                            <td class="text-sm">{format_sdu_type(mapping["type"])}</td>
                            <td>
                              <div class="flex gap-1">
                                <button
                                  type="button"
                                  phx-click="edit_mapping"
                                  phx-value-index={index}
                                  phx-target={@myself}
                                  class="btn btn-ghost btn-sm btn-square"
                                  title="Edit"
                                >
                                  <.icon name="hero-pencil" class="h-4 w-4" />
                                </button>
                                <button
                                  type="button"
                                  phx-click="delete_mapping"
                                  phx-value-index={index}
                                  phx-target={@myself}
                                  class="btn btn-ghost btn-sm btn-square text-error"
                                  title="Delete"
                                >
                                  <.icon name="hero-trash" class="h-4 w-4" />
                                </button>
                              </div>
                            </td>
                          <% end %>
                        </tr>
                      <% end %>
                    </tbody>
                  </table>
                </div>
              <% end %>
            </div>

            <%!-- Save Button --%>
            <div class="flex justify-end pt-2 border-t border-base-300">
              <button
                id="protocol-config-save"
                type="button"
                phx-click="save_config"
                phx-target={@myself}
                class="btn btn-primary"
                disabled={!@has_changes}
              >
                <%= if @saving do %>
                  <span class="loading loading-spinner loading-sm"></span> Saving...
                <% else %>
                  Save Protocol Configuration
                <% end %>
              </button>
            </div>
          <% end %>
        </div>
      </div>
    </div>
    """
  end

  @impl true
  def update(%{interface: interface} = assigns, socket) do
    config = interface.config || %{}
    sdlp_config = fetch_config_map(config, ["sdlp", :sdlp])
    cop1_value = fetch_config_value(config, ["cop1", :cop1])
    cop1_config = if is_map(cop1_value), do: cop1_value, else: %{}

    framing = fetch_config_value(config, ["framing", :framing])
    sdlp_enabled = framing in ["sdlp", :sdlp]
    cop1_mode = cop1_mode_from_config(cop1_value)

    {:ok,
     socket
     |> assign(assigns)
     |> assign(:profile_options, @profiles)
     |> assign(:sdu_type_options, @sdu_types)
     |> assign(:direction_options, @directions)
     |> assign(:cop1_mode_options, @cop1_modes)
     |> assign(:sdlp_enabled, sdlp_enabled)
     |> assign(:profile, fetch_config_value(sdlp_config, ["profile", :profile]) || "tm")
     |> assign(
       :default_sdu_type,
       fetch_config_value(sdlp_config, ["default_sdu_type", :default_sdu_type])
     )
     |> assign(
       :frame_size,
       parse_int(fetch_config_value(sdlp_config, ["frame_size", :frame_size]))
     )
     |> assign(
       :secondary_header_length,
       parse_int(
         fetch_config_value(sdlp_config, ["secondary_header_length", :secondary_header_length])
       )
     )
     |> assign(
       :ocf_length,
       parse_int(fetch_config_value(sdlp_config, ["ocf_length", :ocf_length]))
     )
     |> assign(
       :oid_validation,
       parse_bool(fetch_config_value(sdlp_config, ["oid_validation", :oid_validation]))
     )
     |> assign(
       :oid_validation_prefix_bytes,
       parse_int(
         fetch_config_value(sdlp_config, [
           "oid_validation_prefix_bytes",
           :oid_validation_prefix_bytes
         ])
       )
     )
     |> assign(
       :uplink_scid,
       parse_int(fetch_config_value(sdlp_config, ["uplink_scid", :uplink_scid]))
     )
     |> assign(
       :uplink_vcid,
       parse_int(fetch_config_value(sdlp_config, ["uplink_vcid", :uplink_vcid]))
     )
     |> assign(
       :uplink_map_id,
       parse_int(fetch_config_value(sdlp_config, ["uplink_map_id", :uplink_map_id]))
     )
     |> assign(
       :sdu_mappings,
       fetch_config_value(sdlp_config, ["sdu_mapping", :sdu_mapping]) || []
     )
     |> assign(:cop1_mode, cop1_mode)
     |> assign(
       :cop1_window_size,
       parse_int(fetch_config_value(cop1_config, ["window_size", :window_size]))
     )
     |> assign(
       :cop1_timeout_ms,
       parse_int(fetch_config_value(cop1_config, ["timeout_ms", :timeout_ms]))
     )
     |> assign(
       :cop1_max_retransmit,
       parse_int(fetch_config_value(cop1_config, ["max_retransmit", :max_retransmit]))
     )
     |> assign(
       :cop1_initial_seq,
       parse_int(fetch_config_value(cop1_config, ["initial_seq", :initial_seq]))
     )
     |> assign(:cop1_apids, apids_to_string(fetch_config_value(cop1_config, ["apids", :apids])))
     |> assign(
       :cop1_report_apids,
       apids_to_string(
         fetch_config_value(cop1_config, [
           "report_apids",
           :report_apids,
           "report_apid",
           :report_apid
         ])
       )
     )
     |> assign(
       :cop1_bypass_flag,
       flag_enabled?(
         fetch_config_value(cop1_config, ["bypass_flag", :bypass_flag, "bypass", :bypass])
       )
     )
     |> assign(
       :cop1_control_command_flag,
       flag_enabled?(
         fetch_config_value(cop1_config, [
           "control_command_flag",
           :control_command_flag,
           "control_command",
           :control_command
         ])
       )
     )
     |> assign(
       :cop1_segment_header_flag,
       flag_enabled?(
         fetch_config_value(cop1_config, ["segment_header_flag", :segment_header_flag])
       )
     )
     |> assign(:editing_index, nil)
     |> assign(:has_changes, false)
     |> assign(:saving, false)
     |> assign(:original_config, config)
     |> assign_form()}
  end

  @impl true
  def handle_event("set_framing_mode", %{"mode" => mode}, socket) do
    sdlp_enabled = mode == "sdlp"

    {:noreply,
     socket
     |> assign(:sdlp_enabled, sdlp_enabled)
     |> assign(:has_changes, true)}
  end

  def handle_event("update_sdlp", %{"protocol" => params}, socket) do
    {:noreply, update_protocol_assigns(socket, params)}
  end

  def handle_event("update_sdlp", params, socket) do
    {:noreply, update_protocol_assigns(socket, params)}
  end

  def handle_event("add_sdu_mapping", _params, socket) do
    new_mapping = %{
      "scid" => nil,
      "vcid" => nil,
      "map_id" => nil,
      "direction" => "downlink",
      "type" => "space_packet"
    }

    mappings = socket.assigns.sdu_mappings ++ [new_mapping]
    new_index = length(mappings) - 1

    {:noreply,
     socket
     |> assign(:sdu_mappings, mappings)
     |> assign(:editing_index, new_index)
     |> assign(:has_changes, true)}
  end

  def handle_event("edit_mapping", %{"index" => index}, socket) do
    {:noreply, assign(socket, :editing_index, String.to_integer(index))}
  end

  def handle_event("finish_editing", _params, socket) do
    {:noreply, assign(socket, :editing_index, nil)}
  end

  def handle_event(
        "update_mapping_field",
        %{"index" => index, "field" => field, "value" => value},
        socket
      ) do
    index = String.to_integer(index)
    mappings = socket.assigns.sdu_mappings

    updated_value =
      case field do
        f when f in ["scid", "vcid", "map_id"] -> parse_int(value)
        _ -> value
      end

    updated_mapping = Map.put(Enum.at(mappings, index), field, updated_value)
    updated_mappings = List.replace_at(mappings, index, updated_mapping)

    {:noreply,
     socket
     |> assign(:sdu_mappings, updated_mappings)
     |> assign(:has_changes, true)}
  end

  def handle_event("delete_mapping", %{"index" => index}, socket) do
    index = String.to_integer(index)
    mappings = List.delete_at(socket.assigns.sdu_mappings, index)

    editing_index =
      cond do
        socket.assigns.editing_index == index ->
          nil

        socket.assigns.editing_index && socket.assigns.editing_index > index ->
          socket.assigns.editing_index - 1

        true ->
          socket.assigns.editing_index
      end

    {:noreply,
     socket
     |> assign(:sdu_mappings, mappings)
     |> assign(:editing_index, editing_index)
     |> assign(:has_changes, true)}
  end

  def handle_event("save_config", _params, socket) do
    socket = assign(socket, :saving, true)

    config = build_config(socket.assigns)

    case Interfaces.update_interface(socket.assigns.interface, %{config: config}) do
      {:ok, interface} ->
        notify_parent({:config_saved, interface})

        {:noreply,
         socket
         |> assign(:saving, false)
         |> assign(:has_changes, false)
         |> assign(:original_config, config)
         |> put_flash(:info, "Protocol configuration saved")}

      {:error, _changeset} ->
        {:noreply,
         socket
         |> assign(:saving, false)
         |> put_flash(:error, "Failed to save protocol configuration")}
    end
  end

  defp update_protocol_assigns(socket, params) do
    socket
    |> assign(:profile, params["profile"] || socket.assigns.profile)
    |> assign(:default_sdu_type, empty_to_nil(params["default_sdu_type"]))
    |> assign(:frame_size, parse_int(params["frame_size"]))
    |> assign(:secondary_header_length, parse_int(params["secondary_header_length"]))
    |> assign(:ocf_length, parse_int(params["ocf_length"]))
    |> assign(:oid_validation, parse_bool(params["oid_validation"]))
    |> assign(:oid_validation_prefix_bytes, parse_int(params["oid_validation_prefix_bytes"]))
    |> assign(:uplink_scid, parse_int(params["uplink_scid"]))
    |> assign(:uplink_vcid, parse_int(params["uplink_vcid"]))
    |> assign(:uplink_map_id, parse_int(params["uplink_map_id"]))
    |> assign(:cop1_mode, params["cop1_mode"] || socket.assigns.cop1_mode || "disabled")
    |> assign(:cop1_window_size, parse_int(params["cop1_window_size"]))
    |> assign(:cop1_timeout_ms, parse_int(params["cop1_timeout_ms"]))
    |> assign(:cop1_max_retransmit, parse_int(params["cop1_max_retransmit"]))
    |> assign(:cop1_initial_seq, parse_int(params["cop1_initial_seq"]))
    |> assign(:cop1_apids, normalize_apids_input(params["cop1_apids"]))
    |> assign(:cop1_report_apids, normalize_apids_input(params["cop1_report_apids"]))
    |> assign(:cop1_bypass_flag, parse_bool(params["cop1_bypass_flag"]))
    |> assign(:cop1_control_command_flag, parse_bool(params["cop1_control_command_flag"]))
    |> assign(:cop1_segment_header_flag, parse_bool(params["cop1_segment_header_flag"]))
    |> assign(:has_changes, true)
    |> assign_form()
  end

  defp build_config(assigns) do
    base_config = assigns.original_config || %{}

    base_config =
      if assigns.sdlp_enabled do
        sdlp_config =
          %{
            "profile" => assigns.profile,
            "default_sdu_type" => assigns.default_sdu_type,
            "frame_size" => assigns.frame_size,
            "secondary_header_length" => assigns.secondary_header_length,
            "ocf_length" => assigns.ocf_length,
            "oid_validation" => assigns.oid_validation,
            "oid_validation_prefix_bytes" => assigns.oid_validation_prefix_bytes,
            "uplink_scid" => assigns.uplink_scid,
            "uplink_vcid" => assigns.uplink_vcid,
            "uplink_map_id" => assigns.uplink_map_id,
            "sdu_mapping" => filter_valid_mappings(assigns.sdu_mappings)
          }
          |> Enum.reject(fn {_k, v} -> is_nil(v) end)
          |> Map.new()

        base_config
        |> Map.put("framing", "sdlp")
        |> Map.delete(:framing)
        |> Map.put("sdlp", sdlp_config)
        |> Map.delete(:sdlp)
      else
        base_config
        |> Map.delete("framing")
        |> Map.delete(:framing)
        |> Map.delete("sdlp")
        |> Map.delete(:sdlp)
      end

    put_cop1_config(base_config, assigns)
  end

  defp put_cop1_config(base_config, assigns) do
    cop1_existing =
      case fetch_config_value(base_config, ["cop1", :cop1]) do
        value when is_map(value) -> value
        _ -> %{}
      end

    cop1_updates =
      %{
        "mode" => if(assigns.cop1_mode == "fop", do: "fop", else: nil),
        "window_size" => assigns.cop1_window_size,
        "timeout_ms" => assigns.cop1_timeout_ms,
        "max_retransmit" => assigns.cop1_max_retransmit,
        "initial_seq" => assigns.cop1_initial_seq,
        "apids" => parse_apids_input(assigns.cop1_apids),
        "report_apids" => parse_apids_input(assigns.cop1_report_apids),
        "bypass_flag" => bool_to_flag(assigns.cop1_bypass_flag),
        "control_command_flag" => bool_to_flag(assigns.cop1_control_command_flag),
        "segment_header_flag" => bool_to_flag(assigns.cop1_segment_header_flag)
      }
      |> Enum.reject(fn {_k, v} -> is_nil(v) end)
      |> Map.new()

    cop1_config =
      cop1_existing
      |> drop_config_keys(@cop1_config_drop_keys)
      |> Map.merge(cop1_updates)

    if map_size(cop1_config) == 0 do
      base_config
      |> Map.delete("cop1")
      |> Map.delete(:cop1)
    else
      base_config
      |> Map.delete(:cop1)
      |> Map.put("cop1", cop1_config)
    end
  end

  defp assign_form(socket) do
    assign(socket, :protocol_form, to_form(protocol_form_data(socket.assigns), as: :protocol))
  end

  defp protocol_form_data(assigns) do
    %{
      "profile" => Map.get(assigns, :profile),
      "default_sdu_type" => Map.get(assigns, :default_sdu_type),
      "frame_size" => Map.get(assigns, :frame_size),
      "secondary_header_length" => Map.get(assigns, :secondary_header_length),
      "ocf_length" => Map.get(assigns, :ocf_length),
      "oid_validation" => Map.get(assigns, :oid_validation),
      "oid_validation_prefix_bytes" => Map.get(assigns, :oid_validation_prefix_bytes),
      "uplink_scid" => Map.get(assigns, :uplink_scid),
      "uplink_vcid" => Map.get(assigns, :uplink_vcid),
      "uplink_map_id" => Map.get(assigns, :uplink_map_id),
      "cop1_mode" => Map.get(assigns, :cop1_mode),
      "cop1_window_size" => Map.get(assigns, :cop1_window_size),
      "cop1_timeout_ms" => Map.get(assigns, :cop1_timeout_ms),
      "cop1_max_retransmit" => Map.get(assigns, :cop1_max_retransmit),
      "cop1_initial_seq" => Map.get(assigns, :cop1_initial_seq),
      "cop1_apids" => Map.get(assigns, :cop1_apids),
      "cop1_report_apids" => Map.get(assigns, :cop1_report_apids),
      "cop1_bypass_flag" => Map.get(assigns, :cop1_bypass_flag),
      "cop1_control_command_flag" => Map.get(assigns, :cop1_control_command_flag),
      "cop1_segment_header_flag" => Map.get(assigns, :cop1_segment_header_flag)
    }
  end

  defp fetch_config_value(config, keys) when is_map(config) and is_list(keys) do
    Enum.find_value(keys, fn key -> Map.get(config, key) end)
  end

  defp fetch_config_value(_config, _keys), do: nil

  defp fetch_config_map(config, keys) do
    case fetch_config_value(config, keys) do
      value when is_map(value) -> value
      _ -> %{}
    end
  end

  defp cop1_mode_from_config(config) when is_map(config) do
    case fetch_config_value(config, ["mode", :mode]) do
      "fop" ->
        "fop"

      :fop ->
        "fop"

      _ ->
        if(fetch_config_value(config, ["enabled", :enabled]) == true, do: "fop", else: "disabled")
    end
  end

  defp cop1_mode_from_config(config) when config in ["fop", :fop], do: "fop"
  defp cop1_mode_from_config(_config), do: "disabled"

  defp drop_config_keys(config, keys) when is_map(config), do: Map.drop(config, keys)
  defp drop_config_keys(config, _keys), do: config

  defp flag_enabled?(value) when value in [1, "1", true, "true"], do: true
  defp flag_enabled?(_value), do: false

  defp normalize_apids_input(nil), do: nil

  defp normalize_apids_input(value) when is_binary(value) do
    trimmed = String.trim(value)
    if trimmed == "", do: nil, else: trimmed
  end

  defp normalize_apids_input(value), do: value

  defp parse_apids_input(nil), do: nil
  defp parse_apids_input(""), do: nil

  defp parse_apids_input(value) when is_binary(value) do
    value
    |> String.split([",", " ", "\n", "\t"], trim: true)
    |> Enum.map(&parse_int/1)
    |> Enum.filter(&is_integer/1)
    |> case do
      [] -> nil
      apids -> apids
    end
  end

  defp parse_apids_input(value) when is_list(value) do
    value
    |> Enum.map(&parse_int/1)
    |> Enum.filter(&is_integer/1)
    |> case do
      [] -> nil
      apids -> apids
    end
  end

  defp parse_apids_input(_value), do: nil

  defp apids_to_string(nil), do: nil

  defp apids_to_string(apids) when is_list(apids) do
    Enum.map_join(apids, ", ", &to_string/1)
  end

  defp apids_to_string(value), do: to_string(value)

  defp parse_bool(value) when value in [true, "true", 1, "1"], do: true
  defp parse_bool(_value), do: false

  defp bool_to_flag(true), do: 1
  defp bool_to_flag(_value), do: nil

  defp filter_valid_mappings(mappings) do
    mappings
    |> Enum.filter(fn m ->
      m["scid"] && m["vcid"] && m["direction"] && m["type"]
    end)
    |> Enum.map(fn m ->
      m
      |> Enum.reject(fn {_k, v} -> is_nil(v) end)
      |> Map.new()
    end)
  end

  defp parse_int(nil), do: nil
  defp parse_int(""), do: nil

  defp parse_int(value) when is_binary(value) do
    case Integer.parse(value) do
      {int, ""} -> int
      _ -> nil
    end
  end

  defp parse_int(value) when is_integer(value), do: value
  defp parse_int(_), do: nil

  defp empty_to_nil(""), do: nil
  defp empty_to_nil(value), do: value

  defp format_sdu_type("space_packet"), do: "Space Packet"
  defp format_sdu_type("encap"), do: "Encap"
  defp format_sdu_type(type), do: type || "-"

  defp notify_parent(msg), do: send(self(), {__MODULE__, msg})
end
