defmodule CadenceWeb.InterfaceLive.ProtocolConfigComponent do
  @moduledoc """
  LiveComponent for configuring SDLP protocol settings on an interface.

  Provides inline editing for:
  - Framing mode (none/sdlp)
  - SDLP profile (TM, AOS, USLP)
  - Frame settings (frame_size, secondary_header_length, ocf_length)
  - SDU mappings (SCID/VCID routing)
  - Uplink defaults
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
            <form phx-change="update_sdlp" phx-target={@myself} class="space-y-4">
              <div class="grid grid-cols-2 gap-4">
                <div class="fieldset">
                  <label class="hud-label block mb-1.5">Profile</label>
                  <select name="profile" class="w-full select select-sm" value={@profile}>
                    <%= for {label, value} <- @profile_options do %>
                      <option value={value} selected={@profile == value}>{label}</option>
                    <% end %>
                  </select>
                </div>

                <div class="fieldset">
                  <label class="hud-label block mb-1.5">Default SDU Type</label>
                  <select name="default_sdu_type" class="w-full select select-sm">
                    <option value="" selected={is_nil(@default_sdu_type)}>None (require mapping)</option>
                    <%= for {label, value} <- @sdu_type_options do %>
                      <option value={value} selected={@default_sdu_type == value}>{label}</option>
                    <% end %>
                  </select>
                </div>
              </div>

              <div class="grid grid-cols-3 gap-4">
                <div class="fieldset">
                  <label class="hud-label block mb-1.5">Frame Size (bytes)</label>
                  <input
                    type="number"
                    name="frame_size"
                    value={@frame_size}
                    placeholder="e.g., 1115"
                    class="w-full input input-sm"
                    min="0"
                  />
                </div>

                <div class="fieldset">
                  <label class="hud-label block mb-1.5">Secondary Header Length</label>
                  <input
                    type="number"
                    name="secondary_header_length"
                    value={@secondary_header_length}
                    placeholder="0"
                    class="w-full input input-sm"
                    min="0"
                  />
                </div>

                <div class="fieldset">
                  <label class="hud-label block mb-1.5">OCF Length</label>
                  <input
                    type="number"
                    name="ocf_length"
                    value={@ocf_length}
                    placeholder="0"
                    class="w-full input input-sm"
                    min="0"
                  />
                </div>
              </div>

              <%!-- OID Validation (collapsible) --%>
              <details class="collapse collapse-arrow border border-base-300 bg-base-200/30">
                <summary class="collapse-title text-sm font-medium py-2 min-h-0">
                  OID Validation
                </summary>
                <div class="collapse-content">
                  <div class="flex items-center gap-4 pt-2">
                    <label class="flex items-center gap-2 cursor-pointer">
                      <input
                        type="checkbox"
                        name="oid_validation"
                        checked={@oid_validation}
                        class="checkbox checkbox-sm checkbox-primary"
                      />
                      <span class="text-sm">Enable OID Validation</span>
                    </label>
                    <%= if @oid_validation do %>
                      <div class="fieldset flex-1">
                        <label class="hud-label block mb-1">Prefix Bytes</label>
                        <input
                          type="number"
                          name="oid_validation_prefix_bytes"
                          value={@oid_validation_prefix_bytes}
                          placeholder="0"
                          class="w-24 input input-sm"
                          min="0"
                        />
                      </div>
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
                    <div class="fieldset">
                      <label class="hud-label block mb-1.5">Uplink SCID</label>
                      <input
                        type="number"
                        name="uplink_scid"
                        value={@uplink_scid}
                        placeholder="e.g., 42"
                        class="w-full input input-sm"
                        min="0"
                      />
                    </div>

                    <div class="fieldset">
                      <label class="hud-label block mb-1.5">Uplink VCID</label>
                      <input
                        type="number"
                        name="uplink_vcid"
                        value={@uplink_vcid}
                        placeholder="e.g., 0"
                        class="w-full input input-sm"
                        min="0"
                      />
                    </div>

                    <%= if @profile in ["aos", "uslp"] do %>
                      <div class="fieldset">
                        <label class="hud-label block mb-1.5">Uplink MAP ID</label>
                        <input
                          type="number"
                          name="uplink_map_id"
                          value={@uplink_map_id}
                          placeholder="Optional"
                          class="w-full input input-sm"
                          min="0"
                        />
                      </div>
                    <% end %>
                  </div>
                </div>
              </details>
            </form>

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
                type="button"
                phx-click="save_config"
                phx-target={@myself}
                class="btn btn-primary"
                disabled={!@has_changes}
              >
                <%= if @saving do %>
                  <span class="loading loading-spinner loading-sm"></span>
                  Saving...
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
    sdlp_config = config["sdlp"] || %{}

    sdlp_enabled = config["framing"] == "sdlp"

    {:ok,
     socket
     |> assign(assigns)
     |> assign(:profile_options, @profiles)
     |> assign(:sdu_type_options, @sdu_types)
     |> assign(:direction_options, @directions)
     |> assign(:sdlp_enabled, sdlp_enabled)
     |> assign(:profile, sdlp_config["profile"] || "tm")
     |> assign(:default_sdu_type, sdlp_config["default_sdu_type"])
     |> assign(:frame_size, sdlp_config["frame_size"])
     |> assign(:secondary_header_length, sdlp_config["secondary_header_length"])
     |> assign(:ocf_length, sdlp_config["ocf_length"])
     |> assign(:oid_validation, sdlp_config["oid_validation"] || false)
     |> assign(:oid_validation_prefix_bytes, sdlp_config["oid_validation_prefix_bytes"])
     |> assign(:uplink_scid, sdlp_config["uplink_scid"])
     |> assign(:uplink_vcid, sdlp_config["uplink_vcid"])
     |> assign(:uplink_map_id, sdlp_config["uplink_map_id"])
     |> assign(:sdu_mappings, sdlp_config["sdu_mapping"] || [])
     |> assign(:editing_index, nil)
     |> assign(:has_changes, false)
     |> assign(:saving, false)
     |> assign(:original_config, config)}
  end

  @impl true
  def handle_event("set_framing_mode", %{"mode" => mode}, socket) do
    sdlp_enabled = mode == "sdlp"

    {:noreply,
     socket
     |> assign(:sdlp_enabled, sdlp_enabled)
     |> assign(:has_changes, true)}
  end

  def handle_event("update_sdlp", params, socket) do
    {:noreply,
     socket
     |> assign(:profile, params["profile"] || socket.assigns.profile)
     |> assign(:default_sdu_type, empty_to_nil(params["default_sdu_type"]))
     |> assign(:frame_size, parse_int(params["frame_size"]))
     |> assign(:secondary_header_length, parse_int(params["secondary_header_length"]))
     |> assign(:ocf_length, parse_int(params["ocf_length"]))
     |> assign(:oid_validation, params["oid_validation"] == "true")
     |> assign(:oid_validation_prefix_bytes, parse_int(params["oid_validation_prefix_bytes"]))
     |> assign(:uplink_scid, parse_int(params["uplink_scid"]))
     |> assign(:uplink_vcid, parse_int(params["uplink_vcid"]))
     |> assign(:uplink_map_id, parse_int(params["uplink_map_id"]))
     |> assign(:has_changes, true)}
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

  def handle_event("update_mapping_field", %{"index" => index, "field" => field, "value" => value}, socket) do
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
        socket.assigns.editing_index == index -> nil
        socket.assigns.editing_index && socket.assigns.editing_index > index -> socket.assigns.editing_index - 1
        true -> socket.assigns.editing_index
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

  defp build_config(assigns) do
    base_config = assigns.original_config || %{}

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
      |> Map.put("sdlp", sdlp_config)
    else
      base_config
      |> Map.delete("framing")
      |> Map.delete("sdlp")
    end
  end

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
