defmodule CadenceWeb.LinkLive.ProtocolConfigComponent do
  @moduledoc """
  LiveComponent for configuring SDLP protocol settings on a link.

  Provides inline editing for:
  - Framing mode (none/sdlp)
  - SDLP profile (TM, AOS, USLP)
  - Frame settings (frame_size, secondary_header_length, ocf_length)
  - SDU mappings (SCID/VCID routing)
  - Uplink defaults
  - COP-1 (FOP) settings
  """

  use CadenceWeb, :live_component

  alias Cadence.Links
  alias Cadence.Links.ProtocolConfig

  @profiles [
    {"TM (Telemetry)", "tm"},
    {"AOS (Advanced Orbiting Systems)", "aos"},
    {"USLP (Unified Space Link Protocol)", "uslp"}
  ]

  @uplink_profiles [
    {"TC (Telecommand)", "tc"},
    {"USLP (Unified Space Link Protocol)", "uslp"}
  ]

  @sdu_types [
    {"Space Packet", "space_packet"},
    {"Encapsulation Packet", "encap"}
  ]

  @segmentation_strategies [
    {"Auto (segment when needed)", "auto"},
    {"Disabled", "disabled"}
  ]

  @segmentation_modes [
    {"Standard (with segment header)", "standard"},
    {"Legacy - No Segment Header", "legacy_no_segment_header"},
    {"Legacy - Always Segment Header", "legacy_always_segment_header"}
  ]

  @cop1_restart_policies [
    {"Hold (wait for operator)", "hold"},
    {"Resync (automatic recovery)", "resync"}
  ]

  @cop1_config_drop_keys [
    "window_size",
    :window_size,
    "timeout_ms",
    :timeout_ms,
    "max_retransmit",
    :max_retransmit,
    "restart_policy",
    :restart_policy,
    "apids",
    :apids,
    "report_apids",
    :report_apids,
    "report_apid",
    :report_apid
  ]

  @impl true
  def render(assigns) do
    # Filter mappings by direction for display in separate sections
    assigns =
      assigns
      |> Map.put(
        :downlink_mappings,
        assigns.sdu_mappings
        |> Enum.with_index()
        |> Enum.filter(fn {m, _idx} -> m["direction"] == "downlink" end)
      )
      |> Map.put(
        :uplink_mappings,
        assigns.sdu_mappings
        |> Enum.with_index()
        |> Enum.filter(fn {m, _idx} -> m["direction"] == "uplink" end)
      )

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
              <%!-- Global Defaults Section --%>
              <details open class="border border-base-300 rounded-sm bg-base-200/30">
                <summary class="flex items-center gap-2 px-4 py-3 cursor-pointer text-sm font-semibold text-base-content hover:bg-base-200/50">
                  <.icon name="hero-cog-6-tooth" class="h-4 w-4" /> Global Defaults
                </summary>
                <div class="px-4 pb-4">
                  <div class="max-w-xs">
                    <.input
                      field={@protocol_form[:default_sdu_type]}
                      type="select"
                      label="Default SDU Type"
                      prompt="None (require mapping)"
                      options={@sdu_type_options}
                      class="w-full select select-sm"
                    />
                  </div>
                  <p class="text-xs text-base-content/60 mt-2">
                    Fallback SDU type when no SCID/VCID mapping matches (applies to both directions).
                  </p>
                </div>
              </details>

              <%!-- Downlink (Telemetry) Section --%>
              <details open class="border border-info/30 rounded-sm bg-info/5">
                <summary class="flex items-center gap-2 px-4 py-3 cursor-pointer text-sm font-semibold text-info hover:bg-info/10">
                  <.icon name="hero-arrow-down" class="h-4 w-4" /> Downlink (Telemetry)
                </summary>
                <div class="px-4 pb-4 space-y-4">
                  <%!-- Profile Selection --%>
                  <div class="max-w-xs">
                    <.input
                      field={@protocol_form[:profile]}
                      type="select"
                      label="Profile"
                      options={@profile_options}
                      class="w-full select select-sm"
                    />
                  </div>

                  <%!-- Frame Settings --%>
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

                  <%!-- OID Validation --%>
                  <div class="flex flex-wrap items-center gap-4 pt-2 border-t border-info/20">
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

                  <%!-- Downlink Mappings --%>
                  <div class="pt-2 border-t border-info/20">
                    <div class="flex items-center justify-between mb-3">
                      <div>
                        <h4 class="text-sm font-medium text-base-content">Downlink Mappings</h4>
                        <p class="text-xs text-base-content/60">
                          Route received frames by SCID/VCID to SDU processors.
                        </p>
                      </div>
                      <button
                        type="button"
                        phx-click="add_sdu_mapping"
                        phx-value-direction="downlink"
                        phx-target={@myself}
                        class="btn btn-sm btn-info btn-soft"
                      >
                        <.icon name="hero-plus" class="-ml-0.5 mr-1 h-4 w-4" /> Add Mapping
                      </button>
                    </div>

                    <.render_mappings_table
                      mappings={@downlink_mappings}
                      show_map_id={@profile in ["aos", "uslp"]}
                      editing_index={@editing_index}
                      sdu_type_options={@sdu_type_options}
                      myself={@myself}
                      empty_message="No downlink mappings. Received frames use default SDU type."
                    />
                  </div>
                </div>
              </details>

              <%!-- Uplink (Commanding) Section --%>
              <details open class="border border-accent/30 rounded-sm bg-accent/5">
                <summary class="flex items-center gap-2 px-4 py-3 cursor-pointer text-sm font-semibold text-accent hover:bg-accent/10">
                  <.icon name="hero-arrow-up" class="h-4 w-4" /> Uplink (Commanding)
                </summary>
                <div class="px-4 pb-4 space-y-4">
                  <%!-- Profile Selection --%>
                  <div class="max-w-xs">
                    <.input
                      field={@protocol_form[:uplink_profile]}
                      type="select"
                      label="Profile"
                      options={@uplink_profile_options}
                      class="w-full select select-sm"
                    />
                  </div>

                  <%!-- Default Addressing --%>
                  <div>
                    <h4 class="text-sm font-medium text-base-content mb-2">Default Addressing</h4>
                    <p class="text-xs text-base-content/60 mb-3">
                      SCID/VCID defaults are derived from the link and channel. MAP ID is taken
                      from the channel when applicable.
                    </p>
                  </div>

                  <%!-- Segmentation Settings --%>
                  <div class="pt-4 border-t border-accent/20">
                    <h4 class="text-sm font-medium text-base-content mb-2">Segmentation</h4>
                    <p class="text-xs text-base-content/60 mb-3">
                      Configure how commands are segmented into TC transfer frames.
                    </p>
                    <div class="grid grid-cols-2 gap-4">
                      <.input
                        field={@protocol_form[:segmentation_strategy]}
                        type="select"
                        label="Strategy"
                        options={@segmentation_strategy_options}
                        class="w-full select select-sm"
                      />

                      <.input
                        field={@protocol_form[:segmentation_mode]}
                        type="select"
                        label="Mode"
                        options={@segmentation_mode_options}
                        class="w-full select select-sm"
                      />

                      <.input
                        field={@protocol_form[:max_segments_per_command]}
                        type="number"
                        label="Max Segments Per Command"
                        placeholder="10"
                        class="w-full input input-sm"
                        min="1"
                      />

                      <.input
                        field={@protocol_form[:max_command_bytes]}
                        type="number"
                        label="Max Command Bytes"
                        placeholder="4096"
                        class="w-full input input-sm"
                        min="1"
                      />
                    </div>
                    <p class="text-xs text-base-content/60 mt-2">
                      Mode determines the segment header flag: "Standard" and "Legacy Always"
                      set flag=1; "Legacy No Segment Header" sets flag=0.
                    </p>
                  </div>

                  <%!-- COP-1 Reliability Settings --%>
                  <div class="pt-4 border-t border-accent/20">
                    <h4 class="text-sm font-medium text-base-content mb-2">COP-1 Reliability</h4>
                    <p class="text-xs text-base-content/60 mb-3">
                      Default COP-1 (FOP) settings for command delivery reliability.
                      Route-level cop1_mode (fop/bypass) is configured per route.
                    </p>
                    <div class="grid grid-cols-2 gap-4">
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
                        field={@protocol_form[:cop1_restart_policy]}
                        type="select"
                        label="Restart Policy"
                        options={@cop1_restart_policy_options}
                        class="w-full select select-sm"
                      />
                    </div>

                    <div class="grid grid-cols-2 gap-4 mt-4">
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

                    <p class="text-xs text-base-content/60 mt-2">
                      APIDs accept comma-separated lists; leave blank to apply COP-1 to all
                      command APIDs. Report APIDs route downlink CLCW packets into the COP-1
                      handler.
                    </p>
                  </div>

                  <%!-- Uplink Mappings --%>
                  <div class="pt-4 border-t border-accent/20">
                    <div class="flex items-center justify-between mb-3">
                      <div>
                        <h4 class="text-sm font-medium text-base-content">Uplink Mappings</h4>
                        <p class="text-xs text-base-content/60">
                          Route commands by SCID/VCID to SDU processors.
                        </p>
                      </div>
                      <button
                        type="button"
                        phx-click="add_sdu_mapping"
                        phx-value-direction="uplink"
                        phx-target={@myself}
                        class="btn btn-sm btn-accent btn-soft"
                      >
                        <.icon name="hero-plus" class="-ml-0.5 mr-1 h-4 w-4" /> Add Mapping
                      </button>
                    </div>

                    <.render_mappings_table
                      mappings={@uplink_mappings}
                      show_map_id={@uplink_profile == "uslp"}
                      editing_index={@editing_index}
                      sdu_type_options={@sdu_type_options}
                      myself={@myself}
                      empty_message="No uplink mappings. Commands use default addressing."
                    />
                  </div>
                </div>
              </details>
            </.form>

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

  defp render_mappings_table(assigns) do
    ~H"""
    <%= if Enum.empty?(@mappings) do %>
      <div class="text-sm text-base-content/50 italic py-4 text-center border border-dashed border-base-300 rounded-sm">
        {@empty_message}
      </div>
    <% else %>
      <div class="overflow-x-auto">
        <table class="table table-sm">
          <thead>
            <tr class="text-xs">
              <th>SCID</th>
              <th>VCID</th>
              <%= if @show_map_id do %>
                <th>MAP ID</th>
              <% end %>
              <th>SDU Type</th>
              <th class="w-20"></th>
            </tr>
          </thead>
          <tbody>
            <%= for {mapping, original_index} <- @mappings do %>
              <tr class="hover:bg-base-200/50">
                <%= if @editing_index == original_index do %>
                  <%!-- Inline edit mode --%>
                  <td>
                    <input
                      type="number"
                      name="edit_scid"
                      value={mapping["scid"]}
                      phx-blur="update_mapping_field"
                      phx-value-index={original_index}
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
                      phx-value-index={original_index}
                      phx-value-field="vcid"
                      phx-target={@myself}
                      class="input input-sm w-20"
                      min="0"
                    />
                  </td>
                  <%= if @show_map_id do %>
                    <td>
                      <input
                        type="number"
                        name="edit_map_id"
                        value={mapping["map_id"]}
                        phx-blur="update_mapping_field"
                        phx-value-index={original_index}
                        phx-value-field="map_id"
                        phx-target={@myself}
                        class="input input-sm w-20"
                        placeholder="-"
                      />
                    </td>
                  <% end %>
                  <td>
                    <select
                      name="edit_type"
                      phx-change="update_mapping_field"
                      phx-value-index={original_index}
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
                  <%= if @show_map_id do %>
                    <td class="font-mono text-sm text-base-content/60">
                      {mapping["map_id"] || "-"}
                    </td>
                  <% end %>
                  <td class="text-sm">{format_sdu_type(mapping["type"])}</td>
                  <td>
                    <div class="flex gap-1">
                      <button
                        type="button"
                        phx-click="edit_mapping"
                        phx-value-index={original_index}
                        phx-target={@myself}
                        class="btn btn-ghost btn-sm btn-square"
                        title="Edit"
                      >
                        <.icon name="hero-pencil" class="h-4 w-4" />
                      </button>
                      <button
                        type="button"
                        phx-click="delete_mapping"
                        phx-value-index={original_index}
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
    """
  end

  @impl true
  def update(%{link: link} = assigns, socket) do
    org_id = assigns.current_scope.current_organization.id
    mission_id = assigns.mission.id

    # Load existing config or create a new one
    {protocol_config, is_new} =
      case Links.get_protocol_config_for_link(org_id, mission_id, link.id) do
        {:ok, config} -> {config, false}
        {:error, :not_found} -> {%ProtocolConfig{link_id: link.id, config: %{}}, true}
      end

    config = protocol_config.config || %{}
    parsed = parse_protocol_config(config)

    # Check if this is initial mount or a subsequent update
    is_initial = not Map.has_key?(socket.assigns, :original_config)

    socket =
      socket
      |> assign(assigns)
      |> assign(:protocol_config, protocol_config)
      |> assign(:is_new, is_new)
      |> assign_options()

    socket =
      if is_initial do
        # Full initialization on first mount
        socket
        |> assign_sdlp_config(parsed)
        |> assign_segmentation_config(parsed)
        |> assign_cop1_config(parsed)
        |> assign(:editing_index, nil)
        |> assign(:has_changes, false)
        |> assign(:saving, false)
        |> assign(:original_config, config)
        |> assign_form()
      else
        # Preserve UI state on subsequent updates
        socket
      end

    {:ok, socket}
  end

  defp parse_protocol_config(config) do
    sdlp_config = fetch_config_map(config, ["sdlp", :sdlp])
    tc_config = fetch_config_map(config, ["tc", :tc])
    uslp_config = fetch_config_map(config, ["uslp", :uslp])
    cop1_value = fetch_config_value(config, ["cop1", :cop1])
    cop1_config = if is_map(cop1_value), do: cop1_value, else: %{}

    framing = fetch_config_value(config, ["framing", :framing])
    sdlp_enabled = framing in ["sdlp", :sdlp]

    tc_segmentation = fetch_config_map(tc_config, ["segmentation", :segmentation])
    uslp_segmentation = fetch_config_map(uslp_config, ["segmentation", :segmentation])

    segmentation_config =
      if map_size(tc_segmentation) > 0, do: tc_segmentation, else: uslp_segmentation

    %{
      sdlp_config: sdlp_config,
      tc_config: tc_config,
      uslp_config: uslp_config,
      cop1_config: cop1_config,
      segmentation_config: segmentation_config,
      sdlp_enabled: sdlp_enabled
    }
  end

  defp assign_options(socket) do
    socket
    |> assign(:profile_options, @profiles)
    |> assign(:uplink_profile_options, @uplink_profiles)
    |> assign(:sdu_type_options, @sdu_types)
    |> assign(:segmentation_strategy_options, @segmentation_strategies)
    |> assign(:segmentation_mode_options, @segmentation_modes)
    |> assign(:cop1_restart_policy_options, @cop1_restart_policies)
  end

  defp assign_sdlp_config(socket, parsed) do
    %{
      sdlp_config: sdlp,
      tc_config: _tc_config,
      uslp_config: uslp,
      sdlp_enabled: sdlp_enabled
    } = parsed

    socket
    |> assign(:sdlp_enabled, sdlp_enabled)
    |> assign(:profile, fetch_config_value(sdlp, ["profile", :profile]) || "tm")
    |> assign(
      :default_sdu_type,
      fetch_config_value(sdlp, ["default_sdu_type", :default_sdu_type])
    )
    |> assign(:frame_size, parse_int(fetch_config_value(sdlp, ["frame_size", :frame_size])))
    |> assign(
      :secondary_header_length,
      parse_int(fetch_config_value(sdlp, ["secondary_header_length", :secondary_header_length]))
    )
    |> assign(:ocf_length, parse_int(fetch_config_value(sdlp, ["ocf_length", :ocf_length])))
    |> assign(
      :oid_validation,
      parse_bool(fetch_config_value(sdlp, ["oid_validation", :oid_validation]))
    )
    |> assign(
      :oid_validation_prefix_bytes,
      parse_int(
        fetch_config_value(sdlp, ["oid_validation_prefix_bytes", :oid_validation_prefix_bytes])
      )
    )
    |> assign(
      :uplink_scid,
      nil
    )
    |> assign(
      :uplink_vcid,
      nil
    )
    |> assign(
      :uplink_map_id,
      parse_int(
        fetch_config_value(uslp, ["default_map_id", :default_map_id]) ||
          fetch_config_value(sdlp, ["uplink_map_id", :uplink_map_id])
      )
    )
    |> assign(:sdu_mappings, fetch_config_value(sdlp, ["sdu_mapping", :sdu_mapping]) || [])
    |> assign(
      :uplink_profile,
      fetch_config_value(sdlp, ["uplink_profile", :uplink_profile]) || "tc"
    )
  end

  defp assign_segmentation_config(socket, parsed) do
    %{segmentation_config: seg, cop1_config: cop1} = parsed
    segmentation_mode = derive_segmentation_mode(seg, cop1)

    socket
    |> assign(:segmentation_strategy, fetch_config_value(seg, ["strategy", :strategy]) || "auto")
    |> assign(:segmentation_mode, segmentation_mode)
    |> assign(
      :max_segments_per_command,
      parse_int(fetch_config_value(seg, ["max_segments_per_command", :max_segments_per_command]))
    )
    |> assign(
      :max_command_bytes,
      parse_int(fetch_config_value(seg, ["max_command_bytes", :max_command_bytes]))
    )
  end

  defp assign_cop1_config(socket, parsed) do
    %{cop1_config: cop1} = parsed

    socket
    |> assign(
      :cop1_window_size,
      parse_int(fetch_config_value(cop1, ["window_size", :window_size]))
    )
    |> assign(:cop1_timeout_ms, parse_int(fetch_config_value(cop1, ["timeout_ms", :timeout_ms])))
    |> assign(
      :cop1_max_retransmit,
      parse_int(fetch_config_value(cop1, ["max_retransmit", :max_retransmit]))
    )
    |> assign(
      :cop1_restart_policy,
      fetch_config_value(cop1, ["restart_policy", :restart_policy]) || "hold"
    )
    |> assign(:cop1_apids, apids_to_string(fetch_config_value(cop1, ["apids", :apids])))
    |> assign(
      :cop1_report_apids,
      apids_to_string(
        fetch_config_value(cop1, ["report_apids", :report_apids, "report_apid", :report_apid])
      )
    )
  end

  # Derive segmentation mode from config with backward compatibility for old cop1 flags
  defp derive_segmentation_mode(segmentation_config, cop1_config) do
    case fetch_config_value(segmentation_config, ["mode", :mode]) do
      nil ->
        # Backward compatibility: derive from cop1 segment_header_flag
        case fetch_config_value(cop1_config, ["segment_header_flag", :segment_header_flag]) do
          flag when flag in [0, "0", false, "false"] -> "legacy_no_segment_header"
          _ -> "standard"
        end

      mode when is_binary(mode) ->
        mode

      mode when is_atom(mode) ->
        Atom.to_string(mode)
    end
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

  def handle_event("add_sdu_mapping", params, socket) do
    direction = params["direction"] || "downlink"

    new_mapping = %{
      "scid" => nil,
      "vcid" => nil,
      "map_id" => nil,
      "direction" => direction,
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
    scope = socket.assigns.current_scope
    mission = socket.assigns.mission
    org_id = scope.current_organization.id
    link = socket.assigns.link

    case Bodyguard.permit(Cadence.Missions.Policy, :manage_targets, scope, mission) do
      :ok ->
        config = build_config(socket.assigns)
        attrs = %{config: config, link_id: link.id}

        result =
          if socket.assigns.is_new do
            Links.create_protocol_config(org_id, mission.id, attrs)
          else
            Links.update_protocol_config(
              org_id,
              mission.id,
              socket.assigns.protocol_config,
              %{config: config}
            )
          end

        case result do
          {:ok, protocol_config} ->
            notify_parent({:config_saved, protocol_config})

            {:noreply,
             socket
             |> assign(:saving, false)
             |> assign(:has_changes, false)
             |> assign(:is_new, false)
             |> assign(:protocol_config, protocol_config)
             |> assign(:original_config, config)
             |> put_flash(:info, "Protocol configuration saved")}

          {:error, _changeset} ->
            {:noreply,
             socket
             |> assign(:saving, false)
             |> put_flash(:error, "Failed to save protocol configuration")}
        end

      {:error, _} ->
        {:noreply,
         socket
         |> assign(:saving, false)
         |> put_flash(:error, "You don't have permission to update protocol config")}
    end
  end

  defp update_protocol_assigns(socket, params) do
    socket
    |> assign(:profile, params["profile"] || socket.assigns.profile)
    |> assign(:uplink_profile, params["uplink_profile"] || socket.assigns.uplink_profile)
    |> assign(:default_sdu_type, empty_to_nil(params["default_sdu_type"]))
    |> assign(:frame_size, parse_int(params["frame_size"]))
    |> assign(:secondary_header_length, parse_int(params["secondary_header_length"]))
    |> assign(:ocf_length, parse_int(params["ocf_length"]))
    |> assign(:oid_validation, parse_bool(params["oid_validation"]))
    |> assign(:oid_validation_prefix_bytes, parse_int(params["oid_validation_prefix_bytes"]))
    |> assign(:uplink_map_id, parse_int(params["uplink_map_id"]))
    # Segmentation settings
    |> assign(
      :segmentation_strategy,
      params["segmentation_strategy"] || socket.assigns.segmentation_strategy || "auto"
    )
    |> assign(
      :segmentation_mode,
      params["segmentation_mode"] || socket.assigns.segmentation_mode || "standard"
    )
    |> assign(:max_segments_per_command, parse_int(params["max_segments_per_command"]))
    |> assign(:max_command_bytes, parse_int(params["max_command_bytes"]))
    # COP-1 reliability settings
    |> assign(:cop1_window_size, parse_int(params["cop1_window_size"]))
    |> assign(:cop1_timeout_ms, parse_int(params["cop1_timeout_ms"]))
    |> assign(:cop1_max_retransmit, parse_int(params["cop1_max_retransmit"]))
    |> assign(
      :cop1_restart_policy,
      params["cop1_restart_policy"] || socket.assigns.cop1_restart_policy || "hold"
    )
    |> assign(:cop1_apids, normalize_apids_input(params["cop1_apids"]))
    |> assign(:cop1_report_apids, normalize_apids_input(params["cop1_report_apids"]))
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
            "uplink_profile" => assigns.uplink_profile,
            "default_sdu_type" => assigns.default_sdu_type,
            "frame_size" => assigns.frame_size,
            "secondary_header_length" => assigns.secondary_header_length,
            "ocf_length" => assigns.ocf_length,
            "oid_validation" => assigns.oid_validation,
            "oid_validation_prefix_bytes" => assigns.oid_validation_prefix_bytes,
            "sdu_mapping" => filter_valid_mappings(assigns.sdu_mappings)
          }
          |> Enum.reject(fn {_k, v} -> is_nil(v) end)
          |> Map.new()

        # Build TC config with segmentation
        tc_config = build_tc_section_config(assigns)

        # Build USLP config if profile is uslp or aos
        uslp_config =
          if assigns.profile in ["uslp", "aos"] do
            build_uslp_section_config(assigns)
          else
            nil
          end

        base_config
        |> Map.put("framing", "sdlp")
        |> Map.delete(:framing)
        |> Map.put("sdlp", sdlp_config)
        |> Map.delete(:sdlp)
        |> put_non_nil("tc", tc_config)
        |> Map.delete(:tc)
        |> put_non_nil("uslp", uslp_config)
        |> Map.delete(:uslp)
      else
        base_config
        |> Map.delete("framing")
        |> Map.delete(:framing)
        |> Map.delete("sdlp")
        |> Map.delete(:sdlp)
        |> Map.delete("tc")
        |> Map.delete(:tc)
        |> Map.delete("uslp")
        |> Map.delete(:uslp)
      end

    put_cop1_config(base_config, assigns)
  end

  defp build_tc_section_config(assigns) do
    segmentation =
      %{
        "strategy" => assigns.segmentation_strategy,
        "mode" => assigns.segmentation_mode,
        "max_segments_per_command" => assigns.max_segments_per_command,
        "max_command_bytes" => assigns.max_command_bytes
      }
      |> Enum.reject(fn {_k, v} -> is_nil(v) end)
      |> Map.new()

    config =
      %{
        "segmentation" => if(map_size(segmentation) > 0, do: segmentation, else: nil)
      }
      |> Enum.reject(fn {_k, v} -> is_nil(v) end)
      |> Map.new()

    if map_size(config) > 0, do: config, else: nil
  end

  defp build_uslp_section_config(assigns) do
    segmentation =
      %{
        "strategy" => assigns.segmentation_strategy,
        "mode" => assigns.segmentation_mode
      }
      |> Enum.reject(fn {_k, v} -> is_nil(v) end)
      |> Map.new()

    config =
      %{
        "default_map_id" => assigns.uplink_map_id,
        "segmentation" => if(map_size(segmentation) > 0, do: segmentation, else: nil)
      }
      |> Enum.reject(fn {_k, v} -> is_nil(v) end)
      |> Map.new()

    if map_size(config) > 0, do: config, else: nil
  end

  defp put_non_nil(map, _key, nil), do: map
  defp put_non_nil(map, key, value), do: Map.put(map, key, value)

  defp put_cop1_config(base_config, assigns) do
    cop1_existing =
      case fetch_config_value(base_config, ["cop1", :cop1]) do
        value when is_map(value) -> value
        _ -> %{}
      end

    # Build new COP-1 config with only reliability settings
    cop1_updates =
      %{
        "window_size" => assigns.cop1_window_size,
        "timeout_ms" => assigns.cop1_timeout_ms,
        "max_retransmit" => assigns.cop1_max_retransmit,
        "restart_policy" => assigns.cop1_restart_policy,
        "apids" => parse_apids_input(assigns.cop1_apids),
        "report_apids" => parse_apids_input(assigns.cop1_report_apids)
      }
      |> Enum.reject(fn {_k, v} -> is_nil(v) end)
      |> Map.new()

    # Remove old flag fields and other deprecated keys from existing config
    deprecated_keys = [
      "mode",
      :mode,
      "enabled",
      :enabled,
      "initial_seq",
      :initial_seq,
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

    cop1_config =
      cop1_existing
      |> drop_config_keys(@cop1_config_drop_keys)
      |> drop_config_keys(deprecated_keys)
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
      "uplink_profile" => Map.get(assigns, :uplink_profile),
      "default_sdu_type" => Map.get(assigns, :default_sdu_type),
      "frame_size" => Map.get(assigns, :frame_size),
      "secondary_header_length" => Map.get(assigns, :secondary_header_length),
      "ocf_length" => Map.get(assigns, :ocf_length),
      "oid_validation" => Map.get(assigns, :oid_validation),
      "oid_validation_prefix_bytes" => Map.get(assigns, :oid_validation_prefix_bytes),
      "uplink_map_id" => Map.get(assigns, :uplink_map_id),
      # Segmentation settings
      "segmentation_strategy" => Map.get(assigns, :segmentation_strategy),
      "segmentation_mode" => Map.get(assigns, :segmentation_mode),
      "max_segments_per_command" => Map.get(assigns, :max_segments_per_command),
      "max_command_bytes" => Map.get(assigns, :max_command_bytes),
      # COP-1 reliability settings
      "cop1_window_size" => Map.get(assigns, :cop1_window_size),
      "cop1_timeout_ms" => Map.get(assigns, :cop1_timeout_ms),
      "cop1_max_retransmit" => Map.get(assigns, :cop1_max_retransmit),
      "cop1_restart_policy" => Map.get(assigns, :cop1_restart_policy),
      "cop1_apids" => Map.get(assigns, :cop1_apids),
      "cop1_report_apids" => Map.get(assigns, :cop1_report_apids)
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

  defp drop_config_keys(config, keys) when is_map(config), do: Map.drop(config, keys)
  defp drop_config_keys(config, _keys), do: config

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

  defp filter_valid_mappings(mappings) do
    mappings
    |> Enum.filter(fn m ->
      m["vcid"] && m["direction"] && m["type"]
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
