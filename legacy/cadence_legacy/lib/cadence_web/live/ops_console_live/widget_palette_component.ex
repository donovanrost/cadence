defmodule CadenceWeb.OpsConsoleLive.WidgetPaletteComponent do
  @moduledoc """
  Component for selecting and adding widgets to the dashboard.

  Displays available widget types with previews and allows users
  to configure and add them to the grid. Uses dynamic telemetry
  discovery from the mission's active definition set.
  """

  use CadenceWeb, :live_component

  @widget_types [
    # Telemetry widgets
    %{
      type: "line_chart",
      name: "Line Chart",
      description: "Real-time line chart for telemetry trends",
      icon: "hero-chart-bar",
      default_size: %{w: 6, h: 3},
      category: :telemetry
    },
    %{
      type: "value_display",
      name: "Value Display",
      description: "Current value with limits coloring",
      icon: "hero-hashtag",
      default_size: %{w: 3, h: 2},
      category: :telemetry
    },
    %{
      type: "gauge",
      name: "Gauge",
      description: "Radial gauge with thresholds",
      icon: "hero-signal",
      default_size: %{w: 3, h: 3},
      category: :telemetry
    },
    %{
      type: "table",
      name: "Data Table",
      description: "Tabular view of multiple telemetry items",
      icon: "hero-table-cells",
      default_size: %{w: 6, h: 4},
      category: :telemetry
    },
    # Operations widgets
    %{
      type: "command",
      name: "Command Button",
      description: "Quick-send a single command with one click",
      icon: "hero-play",
      default_size: %{w: 3, h: 2},
      category: :operations
    },
    %{
      type: "procedure",
      name: "Procedure Status",
      description: "Monitor and control running procedure execution",
      icon: "hero-clipboard-document-check",
      default_size: %{w: 4, h: 4},
      category: :operations
    },
    %{
      type: "fleet_health",
      name: "Fleet Health",
      description: "Aggregated constellation health overview",
      icon: "hero-server-stack",
      default_size: %{w: 4, h: 3},
      category: :operations
    },
    %{
      type: "alarm",
      name: "Alarm Summary",
      description: "Filtered alarm list with inline actions",
      icon: "hero-bell-alert",
      default_size: %{w: 4, h: 4},
      category: :operations
    }
  ]

  @impl true
  def mount(socket) do
    {:ok,
     socket
     |> assign(:widget_types, @widget_types)
     |> assign(:selected_type, nil)
     |> assign(:step, :select_type)
     |> assign(:config, %{})
     |> assign(:filter, "")}
  end

  @impl true
  def update(assigns, socket) do
    {:ok, assign(socket, assigns)}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="widget-palette">
      <h2 class="text-xl font-bold mb-4">Add Widget</h2>

      <%= if @step == :select_type do %>
        <div class="grid grid-cols-2 gap-4">
          <%= for widget_type <- @widget_types do %>
            <button
              type="button"
              phx-click="select_type"
              phx-value-type={widget_type.type}
              phx-target={@myself}
              class="card bg-base-200 hover:bg-base-300 cursor-pointer transition-colors p-4 text-left"
            >
              <div class="flex items-start gap-3">
                <div class="p-2 rounded-lg bg-primary/10">
                  <.icon name={widget_type.icon} class="h-6 w-6 text-primary" />
                </div>
                <div>
                  <h3 class="font-semibold">{widget_type.name}</h3>
                  <p class="text-sm text-base-content/70">{widget_type.description}</p>
                </div>
              </div>
            </button>
          <% end %>
        </div>
      <% else %>
        <div class="space-y-4">
          <button
            type="button"
            phx-click="back_to_types"
            phx-target={@myself}
            class="btn btn-ghost btn-sm"
          >
            <.icon name="hero-arrow-left" class="h-4 w-4" /> Back
          </button>

          <.form for={%{}} phx-submit="add_widget" phx-target={@myself} class="space-y-4">
            <.input
              name="title"
              type="text"
              label="Widget Title"
              value={@config["title"] || ""}
              required
            />

            <%= case @selected_type do %>
              <% "line_chart" -> %>
                <.line_chart_config
                  targets={@targets}
                  telemetry_catalog={@telemetry_catalog}
                  filter={@filter}
                  myself={@myself}
                />
              <% "value_display" -> %>
                <.single_item_config
                  targets={@targets}
                  telemetry_catalog={@telemetry_catalog}
                  filter={@filter}
                  myself={@myself}
                  show_precision={true}
                  show_trend={true}
                />
              <% "gauge" -> %>
                <.single_item_config
                  targets={@targets}
                  telemetry_catalog={@telemetry_catalog}
                  filter={@filter}
                  myself={@myself}
                  show_min_max={true}
                />
              <% "table" -> %>
                <.table_config
                  targets={@targets}
                  telemetry_catalog={@telemetry_catalog}
                  filter={@filter}
                  myself={@myself}
                />
              <% "command" -> %>
                <.command_config targets={@targets} />
              <% "procedure" -> %>
                <.procedure_config />
              <% "fleet_health" -> %>
                <.fleet_health_config />
              <% "alarm" -> %>
                <.alarm_config />
              <% _ -> %>
                <p class="text-base-content/50">No additional configuration needed.</p>
            <% end %>

            <div class="flex justify-end gap-2 mt-6">
              <button type="button" phx-click="cancel" phx-target={@myself} class="btn btn-ghost">
                Cancel
              </button>
              <button type="submit" class="btn btn-primary">
                Add Widget
              </button>
            </div>
          </.form>
        </div>
      <% end %>
    </div>
    """
  end

  # Line chart configuration - multi-select telemetry items
  defp line_chart_config(assigns) do
    filtered_packets = filter_packets(assigns.telemetry_catalog.packets, assigns.filter)
    filtered_derived = filter_derived(assigns.telemetry_catalog.derived_items, assigns.filter)
    assigns = assign(assigns, :filtered_packets, filtered_packets)
    assigns = assign(assigns, :filtered_derived, filtered_derived)

    ~H"""
    <div class="space-y-4">
      <div class="form-control">
        <label class="label">
          <span class="label-text">Telemetry Items</span>
        </label>
        <p class="text-sm text-base-content/50 mb-2">
          Select the telemetry items to plot on this chart.
        </p>

        <.no_catalog_warning :if={@telemetry_catalog.packets == []} />

        <%= if @telemetry_catalog.packets != [] do %>
          <input
            type="text"
            name="filter_input"
            value={@filter}
            placeholder="Search items..."
            phx-change="filter_items"
            phx-target={@myself}
            phx-debounce="150"
            class="input input-sm input-bordered w-full mb-2"
          />

          <div class="bg-base-200 rounded-lg p-4 max-h-64 overflow-y-auto">
            <%= for target <- @targets do %>
              <div class="mb-4">
                <h4 class="font-semibold text-sm mb-2">{target.name}</h4>

                <%= for packet <- @filtered_packets do %>
                  <div class="ml-4 mb-2">
                    <p class="text-xs text-base-content/50 mb-1 font-medium">{packet.name}</p>
                    <%= for item <- packet.items do %>
                      <label class="flex items-center gap-2 cursor-pointer py-0.5">
                        <input
                          type="checkbox"
                          name="items[]"
                          value={"#{target.identifier}:#{packet.name}:#{item.name}"}
                          class="checkbox checkbox-sm checkbox-primary"
                        />
                        <span class="text-sm" title={item.description || ""}>
                          {item.name}
                          <%= if item.units do %>
                            <span class="text-base-content/50">({item.units})</span>
                          <% end %>
                        </span>
                      </label>
                    <% end %>
                  </div>
                <% end %>

                <%= if @filtered_derived != [] do %>
                  <div class="ml-4 mb-2">
                    <p class="text-xs text-base-content/50 mb-1 font-medium flex items-center gap-1">
                      DERIVED <span class="badge badge-xs badge-info">calculated</span>
                    </p>
                    <%= for item <- @filtered_derived do %>
                      <label class="flex items-center gap-2 cursor-pointer py-0.5">
                        <input
                          type="checkbox"
                          name="items[]"
                          value={"#{target.identifier}:DERIVED:#{item.name}"}
                          class="checkbox checkbox-sm checkbox-primary"
                        />
                        <span class="text-sm" title={item.expression || ""}>
                          {item.name}
                          <%= if item.units do %>
                            <span class="text-base-content/50">({item.units})</span>
                          <% end %>
                        </span>
                      </label>
                    <% end %>
                  </div>
                <% end %>
              </div>
            <% end %>
          </div>
        <% end %>
      </div>

      <div class="grid grid-cols-2 gap-4">
        <.input name="y_min" type="number" label="Y-Axis Min" value="" placeholder="Auto" />
        <.input name="y_max" type="number" label="Y-Axis Max" value="" placeholder="Auto" />
      </div>
      <p class="text-xs text-base-content/50 -mt-2">
        Leave empty for auto-scaling based on data
      </p>

      <.input name="y_unit" type="text" label="Y-Axis Unit" value="" placeholder="e.g., °C, V, mA" />

      <.input
        name="time_window"
        type="select"
        label="Time Window"
        options={[
          {"1 minute", "60"},
          {"5 minutes", "300"},
          {"15 minutes", "900"},
          {"1 hour", "3600"}
        ]}
        value="60"
      />
    </div>
    """
  end

  # Single item configuration (Value Display, Gauge)
  defp single_item_config(assigns) do
    assigns =
      assigns
      |> assign_new(:show_precision, fn -> false end)
      |> assign_new(:show_trend, fn -> false end)
      |> assign_new(:show_min_max, fn -> false end)

    item_options = build_item_options(assigns.targets, assigns.telemetry_catalog, assigns.filter)
    assigns = assign(assigns, :item_options, item_options)

    ~H"""
    <div class="space-y-4">
      <.no_catalog_warning :if={@telemetry_catalog.packets == []} />

      <%= if @telemetry_catalog.packets != [] do %>
        <div class="form-control">
          <label class="label">
            <span class="label-text">Telemetry Item</span>
          </label>
          <input
            type="text"
            name="filter_input"
            value={@filter}
            placeholder="Search items..."
            phx-change="filter_items"
            phx-target={@myself}
            phx-debounce="150"
            class="input input-sm input-bordered w-full mb-2"
          />
          <select name="telemetry_item" class="select select-bordered w-full" required>
            <option value="">Select item...</option>
            <%= for {label, value} <- @item_options do %>
              <option value={value}>{label}</option>
            <% end %>
          </select>
        </div>
      <% end %>

      <.input name="unit" type="text" label="Unit" value="" placeholder="e.g., °C" />

      <%= if @show_precision do %>
        <.input name="precision" type="number" label="Decimal Precision" value="2" />
      <% end %>

      <%= if @show_trend do %>
        <div class="form-control">
          <label class="label cursor-pointer justify-start gap-2">
            <input type="checkbox" name="show_trend" class="checkbox checkbox-sm" checked />
            <span class="label-text">Show trend indicator</span>
          </label>
        </div>
      <% end %>

      <%= if @show_min_max do %>
        <div class="grid grid-cols-2 gap-4">
          <.input name="min_value" type="number" label="Min Value" value="0" />
          <.input name="max_value" type="number" label="Max Value" value="100" />
        </div>
      <% end %>
    </div>
    """
  end

  # Table configuration - select target and packet
  defp table_config(assigns) do
    packet_options =
      build_packet_options(assigns.targets, assigns.telemetry_catalog, assigns.filter)

    assigns = assign(assigns, :packet_options, packet_options)

    ~H"""
    <div class="space-y-4">
      <.no_catalog_warning :if={@telemetry_catalog.packets == []} />

      <%= if @telemetry_catalog.packets != [] do %>
        <div class="form-control">
          <label class="label">
            <span class="label-text">Target & Packet</span>
          </label>
          <input
            type="text"
            name="filter_input"
            value={@filter}
            placeholder="Search packets..."
            phx-change="filter_items"
            phx-target={@myself}
            phx-debounce="150"
            class="input input-sm input-bordered w-full mb-2"
          />
          <select name="target_packet" class="select select-bordered w-full" required>
            <option value="">Select packet...</option>
            <%= for {label, value} <- @packet_options do %>
              <option value={value}>{label}</option>
            <% end %>
          </select>
          <p class="text-xs text-base-content/50 mt-1">Shows all items in the selected packet</p>
        </div>
      <% end %>
    </div>
    """
  end

  # Command widget configuration
  defp command_config(assigns) do
    target_options =
      Enum.map(assigns.targets, fn target ->
        {target.name, target.identifier}
      end)

    assigns = assign(assigns, :target_options, target_options)

    ~H"""
    <div class="space-y-4">
      <div class="form-control">
        <label class="label">
          <span class="label-text">Target</span>
        </label>
        <select name="target_id" class="select select-bordered w-full" required>
          <option value="">Select target...</option>
          <%= for {label, value} <- @target_options do %>
            <option value={value}>{label}</option>
          <% end %>
        </select>
      </div>

      <.input
        name="command_name"
        type="text"
        label="Command Name"
        value=""
        placeholder="e.g., SAFE_MODE"
        required
      />

      <.input
        name="button_label"
        type="text"
        label="Button Label"
        value=""
        placeholder="e.g., Emergency Safe Mode"
      />

      <div class="form-control">
        <label class="label cursor-pointer justify-start gap-2">
          <input type="checkbox" name="require_confirmation" class="checkbox checkbox-sm" checked />
          <span class="label-text">Require confirmation before sending</span>
        </label>
        <p class="text-xs text-base-content/50 ml-6">
          Recommended for hazardous or irreversible commands
        </p>
      </div>

      <div class="form-control">
        <label class="label cursor-pointer justify-start gap-2">
          <input type="checkbox" name="hazardous" class="checkbox checkbox-sm checkbox-warning" />
          <span class="label-text">Mark as hazardous</span>
        </label>
        <p class="text-xs text-base-content/50 ml-6">
          Displays warning styling on the command button
        </p>
      </div>
    </div>
    """
  end

  # Procedure widget configuration
  defp procedure_config(assigns) do
    ~H"""
    <div class="space-y-4">
      <div class="alert alert-info">
        <.icon name="hero-information-circle" class="h-5 w-5" />
        <span>
          Procedure widgets automatically connect to running procedures.
          Configure which procedure to monitor after adding the widget.
        </span>
      </div>

      <div class="form-control">
        <label class="label cursor-pointer justify-start gap-2">
          <input type="checkbox" name="show_logs" class="checkbox checkbox-sm" checked />
          <span class="label-text">Show log output</span>
        </label>
      </div>

      <div class="form-control">
        <label class="label cursor-pointer justify-start gap-2">
          <input type="checkbox" name="show_controls" class="checkbox checkbox-sm" checked />
          <span class="label-text">Show control buttons (Pause/Resume/Abort)</span>
        </label>
      </div>

      <.input
        name="max_log_lines"
        type="number"
        label="Max Log Lines"
        value="10"
        placeholder="10"
      />
    </div>
    """
  end

  # Fleet Health widget configuration
  defp fleet_health_config(assigns) do
    ~H"""
    <div class="space-y-4">
      <div class="form-control">
        <label class="label">
          <span class="label-text">Group By</span>
        </label>
        <select name="group_by" class="select select-bordered w-full">
          <option value="none">No grouping (flat list)</option>
          <option value="plane" selected>Orbital Plane</option>
          <option value="shell">Shell</option>
          <option value="cluster">Cluster</option>
        </select>
      </div>

      <div class="form-control">
        <label class="label cursor-pointer justify-start gap-2">
          <input type="checkbox" name="show_individual" class="checkbox checkbox-sm" checked />
          <span class="label-text">Show individual vehicles on expand</span>
        </label>
      </div>

      <div class="form-control">
        <label class="label cursor-pointer justify-start gap-2">
          <input type="checkbox" name="show_critical_only" class="checkbox checkbox-sm" />
          <span class="label-text">Show critical/warning only</span>
        </label>
        <p class="text-xs text-base-content/50 ml-6">
          Hide healthy groups to focus on issues
        </p>
      </div>
    </div>
    """
  end

  # Alarm widget configuration
  defp alarm_config(assigns) do
    ~H"""
    <div class="space-y-4">
      <div class="form-control">
        <label class="label">
          <span class="label-text">Severity Filter</span>
        </label>
        <div class="flex flex-wrap gap-2">
          <label class="flex items-center gap-2 cursor-pointer">
            <input
              type="checkbox"
              name="severity_filter[]"
              value="critical"
              class="checkbox checkbox-sm checkbox-error"
              checked
            />
            <span class="text-sm">Critical</span>
          </label>
          <label class="flex items-center gap-2 cursor-pointer">
            <input
              type="checkbox"
              name="severity_filter[]"
              value="warning"
              class="checkbox checkbox-sm checkbox-warning"
              checked
            />
            <span class="text-sm">Warning</span>
          </label>
          <label class="flex items-center gap-2 cursor-pointer">
            <input
              type="checkbox"
              name="severity_filter[]"
              value="info"
              class="checkbox checkbox-sm checkbox-info"
              checked
            />
            <span class="text-sm">Info</span>
          </label>
        </div>
        <p class="text-xs text-base-content/50 mt-1">
          Leave all checked to show all severities
        </p>
      </div>

      <.input
        name="max_alarms"
        type="number"
        label="Max Alarms Displayed"
        value="20"
        placeholder="20"
      />

      <div class="form-control">
        <label class="label cursor-pointer justify-start gap-2">
          <input type="checkbox" name="show_cleared" class="checkbox checkbox-sm" />
          <span class="label-text">Show cleared alarms</span>
        </label>
      </div>

      <div class="form-control">
        <label class="label cursor-pointer justify-start gap-2">
          <input type="checkbox" name="auto_scroll" class="checkbox checkbox-sm" checked />
          <span class="label-text">Auto-scroll to new alarms</span>
        </label>
      </div>
    </div>
    """
  end

  # Warning when no telemetry catalog is available
  defp no_catalog_warning(assigns) do
    ~H"""
    <div class="alert alert-warning">
      <.icon name="hero-exclamation-triangle" class="h-5 w-5" />
      <span>
        No telemetry database published for this mission.
        Import and publish a definition set to configure widgets.
      </span>
    </div>
    """
  end

  # Filter packets by search term
  defp filter_packets(packets, filter) when filter in ["", nil], do: packets

  defp filter_packets(packets, filter) do
    filter_lower = String.downcase(filter)

    packets
    |> Enum.map(fn packet ->
      filtered_items =
        Enum.filter(packet.items, fn item ->
          String.contains?(String.downcase(item.name), filter_lower) ||
            String.contains?(String.downcase(packet.name), filter_lower) ||
            (item.description && String.contains?(String.downcase(item.description), filter_lower))
        end)

      %{packet | items: filtered_items}
    end)
    |> Enum.reject(fn packet -> packet.items == [] end)
  end

  # Filter derived items by search term
  defp filter_derived(derived_items, filter) when filter in ["", nil], do: derived_items

  defp filter_derived(derived_items, filter) do
    filter_lower = String.downcase(filter)

    Enum.filter(derived_items, fn item ->
      String.contains?(String.downcase(item.name), filter_lower) ||
        (item.description && String.contains?(String.downcase(item.description), filter_lower))
    end)
  end

  # Build flat list of item options for single-select dropdown
  defp build_item_options(targets, catalog, filter) do
    filtered_packets = filter_packets(catalog.packets, filter)
    filtered_derived = filter_derived(catalog.derived_items, filter)

    packet_items =
      for target <- targets,
          packet <- filtered_packets,
          item <- packet.items do
        label =
          if item.units do
            "#{target.name} → #{packet.name} → #{item.name} (#{item.units})"
          else
            "#{target.name} → #{packet.name} → #{item.name}"
          end

        {label, "#{target.identifier}:#{packet.name}:#{item.name}"}
      end

    derived_items =
      for target <- targets,
          item <- filtered_derived do
        label =
          if item.units do
            "#{target.name} → DERIVED → #{item.name} (#{item.units})"
          else
            "#{target.name} → DERIVED → #{item.name}"
          end

        {label, "#{target.identifier}:DERIVED:#{item.name}"}
      end

    packet_items ++ derived_items
  end

  # Build packet options for table widget
  defp build_packet_options(targets, catalog, filter) do
    filtered_packets = filter_packets(catalog.packets, filter)

    for target <- targets,
        packet <- filtered_packets do
      item_count = length(packet.items)
      label = "#{target.name} → #{packet.name} (#{item_count} items)"
      {label, "#{target.identifier}:#{packet.name}"}
    end
  end

  @impl true
  def handle_event("select_type", %{"type" => type}, socket) do
    widget_type = Enum.find(@widget_types, &(&1.type == type))

    {:noreply,
     socket
     |> assign(:selected_type, type)
     |> assign(:step, :configure)
     |> assign(:config, %{"title" => widget_type.name})
     |> assign(:filter, "")}
  end

  def handle_event("back_to_types", _params, socket) do
    {:noreply,
     socket
     |> assign(:selected_type, nil)
     |> assign(:step, :select_type)
     |> assign(:config, %{})
     |> assign(:filter, "")}
  end

  def handle_event("filter_items", %{"filter_input" => filter}, socket) do
    {:noreply, assign(socket, :filter, filter)}
  end

  def handle_event("cancel", _params, socket) do
    send(self(), {:close_widget_palette})
    {:noreply, socket}
  end

  def handle_event("add_widget", params, socket) do
    widget_type = Enum.find(@widget_types, &(&1.type == socket.assigns.selected_type))

    config =
      build_widget_config(
        socket.assigns.selected_type,
        params,
        socket.assigns.telemetry_catalog
      )

    widget = %{
      id: "widget-#{System.unique_integer([:positive])}",
      type: socket.assigns.selected_type,
      position: %{
        x: 0,
        y: 0,
        w: widget_type.default_size.w,
        h: widget_type.default_size.h
      },
      config: config
    }

    send(self(), {:add_widget, widget})

    {:noreply, socket}
  end

  defp build_widget_config("line_chart", params, _catalog) do
    items =
      (params["items"] || [])
      |> Enum.map(fn item_str ->
        [target, packet, item] = String.split(item_str, ":")
        %{"target" => target, "packet" => packet, "item" => item}
      end)

    %{
      "title" => params["title"],
      "telemetry_items" => items,
      "y_axis" => %{
        "min" => parse_number(params["y_min"]),
        "max" => parse_number(params["y_max"]),
        "unit" => params["y_unit"]
      },
      "time_window" => String.to_integer(params["time_window"] || "60")
    }
  end

  defp build_widget_config("value_display", params, _catalog) do
    {target, packet, item} = parse_telemetry_item(params["telemetry_item"])

    %{
      "title" => params["title"],
      "telemetry_item" => %{
        "target" => target,
        "packet" => packet,
        "item" => item
      },
      "unit" => params["unit"],
      "precision" => String.to_integer(params["precision"] || "2"),
      "show_trend" => params["show_trend"] == "on"
    }
  end

  defp build_widget_config("gauge", params, _catalog) do
    {target, packet, item} = parse_telemetry_item(params["telemetry_item"])

    %{
      "title" => params["title"],
      "telemetry_item" => %{
        "target" => target,
        "packet" => packet,
        "item" => item
      },
      "min_value" => parse_number(params["min_value"]) || 0,
      "max_value" => parse_number(params["max_value"]) || 100,
      "unit" => params["unit"]
    }
  end

  defp build_widget_config("table", params, catalog) do
    {target, packet_name} = parse_target_packet(params["target_packet"])

    # Find the packet in the catalog and get its items
    items =
      case Enum.find(catalog.packets, &(&1.name == packet_name)) do
        nil ->
          []

        packet ->
          Enum.map(packet.items, fn item ->
            %{
              "name" => item.name,
              "units" => item.units,
              "description" => item.description
            }
          end)
      end

    %{
      "title" => params["title"],
      "target" => target,
      "packet" => packet_name,
      "items" => items
    }
  end

  defp build_widget_config("command", params, _catalog) do
    %{
      "title" => params["title"],
      "target_id" => params["target_id"],
      "command_name" => params["command_name"],
      "button_label" => params["button_label"],
      "require_confirmation" => params["require_confirmation"] == "on",
      "hazardous" => params["hazardous"] == "on"
    }
  end

  defp build_widget_config("procedure", params, _catalog) do
    %{
      "title" => params["title"],
      "show_logs" => params["show_logs"] == "on",
      "show_controls" => params["show_controls"] == "on",
      "max_log_lines" => parse_integer(params["max_log_lines"], 10)
    }
  end

  defp build_widget_config("fleet_health", params, _catalog) do
    %{
      "title" => params["title"],
      "group_by" => params["group_by"] || "plane",
      "show_individual" => params["show_individual"] == "on",
      "show_critical_only" => params["show_critical_only"] == "on"
    }
  end

  defp build_widget_config("alarm", params, _catalog) do
    %{
      "title" => params["title"],
      "severity_filter" => params["severity_filter"] || [],
      "max_alarms" => parse_integer(params["max_alarms"], 20),
      "show_cleared" => params["show_cleared"] == "on",
      "auto_scroll" => params["auto_scroll"] == "on"
    }
  end

  defp build_widget_config(_type, params, _catalog) do
    %{"title" => params["title"]}
  end

  # Parse "TARGET:PACKET:ITEM" string into tuple
  defp parse_telemetry_item(nil), do: {nil, nil, nil}
  defp parse_telemetry_item(""), do: {nil, nil, nil}

  defp parse_telemetry_item(item_str) do
    case String.split(item_str, ":") do
      [target, packet, item] -> {target, packet, item}
      _ -> {nil, nil, nil}
    end
  end

  # Parse "TARGET:PACKET" string into tuple
  defp parse_target_packet(nil), do: {nil, nil}
  defp parse_target_packet(""), do: {nil, nil}

  defp parse_target_packet(str) do
    case String.split(str, ":") do
      [target, packet] -> {target, packet}
      _ -> {nil, nil}
    end
  end

  defp parse_number(nil), do: nil
  defp parse_number(""), do: nil

  defp parse_number(str) when is_binary(str) do
    case Float.parse(str) do
      {num, ""} -> num
      _ -> nil
    end
  end

  defp parse_integer(nil, default), do: default
  defp parse_integer("", default), do: default

  defp parse_integer(str, default) when is_binary(str) do
    case Integer.parse(str) do
      {num, ""} -> num
      _ -> default
    end
  end
end
