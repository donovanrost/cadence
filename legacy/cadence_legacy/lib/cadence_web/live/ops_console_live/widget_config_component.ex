defmodule CadenceWeb.OpsConsoleLive.WidgetConfigComponent do
  @moduledoc """
  Component for configuring existing widgets.

  Displays a form based on widget type to edit widget settings.
  Uses dynamic telemetry discovery from the mission's active definition set.
  """

  use CadenceWeb, :live_component

  @impl true
  def mount(socket) do
    {:ok, assign(socket, :filter, "")}
  end

  @impl true
  def update(assigns, socket) do
    {:ok, assign(socket, assigns)}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="widget-config">
      <h2 class="text-xl font-bold mb-4">Configure Widget</h2>

      <.form for={%{}} phx-submit="save_config" phx-target={@myself} class="space-y-4">
        <input type="hidden" name="widget_id" value={@widget.id} />
        <input type="hidden" name="widget_type" value={@widget.type} />

        <.input
          name="title"
          type="text"
          label="Widget Title"
          value={@widget.config["title"] || ""}
        />

        <%= case @widget.type do %>
          <% "value_display" -> %>
            <.value_display_config
              widget={@widget}
              targets={@targets}
              telemetry_catalog={@telemetry_catalog}
              filter={@filter}
              myself={@myself}
            />
          <% "line_chart" -> %>
            <.line_chart_config
              widget={@widget}
              targets={@targets}
              telemetry_catalog={@telemetry_catalog}
              filter={@filter}
              myself={@myself}
            />
          <% "gauge" -> %>
            <.gauge_config
              widget={@widget}
              targets={@targets}
              telemetry_catalog={@telemetry_catalog}
              filter={@filter}
              myself={@myself}
            />
          <% "table" -> %>
            <.table_config
              widget={@widget}
              targets={@targets}
              telemetry_catalog={@telemetry_catalog}
              filter={@filter}
              myself={@myself}
            />
          <% _ -> %>
            <p class="text-base-content/50">
              No configuration options available for this widget type.
            </p>
        <% end %>

        <div class="flex justify-between items-center mt-6">
          <div class="flex gap-2">
            <button
              type="button"
              phx-click="delete_widget"
              phx-target={@myself}
              class="btn btn-error btn-outline btn-sm"
            >
              Delete
            </button>
            <button
              type="button"
              phx-click="duplicate_widget"
              phx-target={@myself}
              class="btn btn-ghost btn-sm"
              title="Create a copy of this widget"
            >
              <.icon name="hero-document-duplicate" class="h-4 w-4" /> Duplicate
            </button>
          </div>
          <div class="flex gap-2">
            <button type="button" phx-click="cancel" phx-target={@myself} class="btn btn-ghost">
              Cancel
            </button>
            <button type="submit" class="btn btn-primary">
              Save Changes
            </button>
          </div>
        </div>
      </.form>
    </div>
    """
  end

  # Value Display configuration
  defp value_display_config(assigns) do
    telemetry_item = assigns.widget.config["telemetry_item"] || %{}
    current_value = build_current_item_value(telemetry_item)
    item_options = build_item_options(assigns.targets, assigns.telemetry_catalog, assigns.filter)

    assigns =
      assigns
      |> assign(:telemetry_item, telemetry_item)
      |> assign(:current_value, current_value)
      |> assign(:item_options, item_options)

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
              <option value={value} selected={value == @current_value}>{label}</option>
            <% end %>
          </select>
        </div>
      <% end %>

      <.input
        name="unit"
        type="text"
        label="Unit"
        value={@widget.config["unit"] || ""}
        placeholder="e.g., °C"
      />

      <.input
        name="precision"
        type="number"
        label="Decimal Precision"
        value={@widget.config["precision"] || 2}
      />

      <div class="form-control">
        <label class="label cursor-pointer justify-start gap-2">
          <input
            type="checkbox"
            name="show_trend"
            class="checkbox checkbox-sm"
            checked={@widget.config["show_trend"] != false}
          />
          <span class="label-text">Show trend indicator</span>
        </label>
      </div>
    </div>
    """
  end

  # Line Chart configuration
  defp line_chart_config(assigns) do
    telemetry_items = assigns.widget.config["telemetry_items"] || []
    y_axis = assigns.widget.config["y_axis"] || %{}
    filtered_packets = filter_packets(assigns.telemetry_catalog.packets, assigns.filter)
    filtered_derived = filter_derived(assigns.telemetry_catalog.derived_items, assigns.filter)

    assigns =
      assigns
      |> assign(:telemetry_items, telemetry_items)
      |> assign(:y_axis, y_axis)
      |> assign(:filtered_packets, filtered_packets)
      |> assign(:filtered_derived, filtered_derived)

    ~H"""
    <div class="space-y-4">
      <div class="form-control">
        <label class="label">
          <span class="label-text">Telemetry Items</span>
        </label>
        <p class="text-sm text-base-content/50 mb-2">
          Currently plotting {length(@telemetry_items)} item(s).
          Select items to add/remove from the chart.
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
                          checked={
                            item_selected?(
                              @telemetry_items,
                              target.identifier,
                              packet.name,
                              item.name
                            )
                          }
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
                          checked={
                            item_selected?(@telemetry_items, target.identifier, "DERIVED", item.name)
                          }
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
        <.input
          name="y_min"
          type="number"
          label="Y-Axis Min"
          value={@y_axis["min"] || ""}
          placeholder="Auto"
        />
        <.input
          name="y_max"
          type="number"
          label="Y-Axis Max"
          value={@y_axis["max"] || ""}
          placeholder="Auto"
        />
      </div>
      <p class="text-xs text-base-content/50 -mt-2">
        Leave empty for auto-scaling based on data
      </p>

      <.input
        name="y_unit"
        type="text"
        label="Y-Axis Unit"
        value={@y_axis["unit"] || ""}
        placeholder="e.g., °C, V, mA"
      />

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
        value={to_string(@widget.config["time_window"] || 60)}
      />
    </div>
    """
  end

  # Gauge configuration
  defp gauge_config(assigns) do
    telemetry_item = assigns.widget.config["telemetry_item"] || %{}
    current_value = build_current_item_value(telemetry_item)
    item_options = build_item_options(assigns.targets, assigns.telemetry_catalog, assigns.filter)

    assigns =
      assigns
      |> assign(:telemetry_item, telemetry_item)
      |> assign(:current_value, current_value)
      |> assign(:item_options, item_options)

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
              <option value={value} selected={value == @current_value}>{label}</option>
            <% end %>
          </select>
        </div>
      <% end %>

      <div class="grid grid-cols-2 gap-4">
        <.input
          name="min_value"
          type="number"
          label="Min Value"
          value={@widget.config["min_value"] || 0}
        />
        <.input
          name="max_value"
          type="number"
          label="Max Value"
          value={@widget.config["max_value"] || 100}
        />
      </div>

      <.input name="unit" type="text" label="Unit" value={@widget.config["unit"] || ""} />
    </div>
    """
  end

  # Table configuration
  defp table_config(assigns) do
    current_value = build_current_packet_value(assigns.widget.config)

    packet_options =
      build_packet_options(assigns.targets, assigns.telemetry_catalog, assigns.filter)

    assigns =
      assigns
      |> assign(:current_value, current_value)
      |> assign(:packet_options, packet_options)

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
              <option value={value} selected={value == @current_value}>{label}</option>
            <% end %>
          </select>
          <p class="text-xs text-base-content/50 mt-1">Shows all items in the selected packet</p>
        </div>
      <% end %>
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

  # Helper to check if an item is selected in the telemetry_items list
  defp item_selected?(telemetry_items, target, packet, item) do
    Enum.any?(telemetry_items, fn ti ->
      ti["target"] == target && ti["packet"] == packet && ti["item"] == item
    end)
  end

  # Build current item value string from telemetry_item map
  defp build_current_item_value(%{"target" => t, "packet" => p, "item" => i})
       when is_binary(t) and is_binary(p) and is_binary(i) do
    "#{t}:#{p}:#{i}"
  end

  defp build_current_item_value(_), do: ""

  # Build current packet value string from config
  defp build_current_packet_value(%{"target" => t, "packet" => p})
       when is_binary(t) and is_binary(p) do
    "#{t}:#{p}"
  end

  defp build_current_packet_value(_), do: ""

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
  def handle_event("filter_items", %{"filter_input" => filter}, socket) do
    {:noreply, assign(socket, :filter, filter)}
  end

  def handle_event("cancel", _params, socket) do
    send(self(), {:close_widget_config})
    {:noreply, socket}
  end

  def handle_event("delete_widget", _params, socket) do
    send(self(), {:delete_widget, socket.assigns.widget.id})
    {:noreply, socket}
  end

  def handle_event("duplicate_widget", _params, socket) do
    widget = socket.assigns.widget
    send(self(), {:duplicate_widget, widget.type, widget.config})
    {:noreply, socket}
  end

  def handle_event("save_config", params, socket) do
    widget_id = params["widget_id"]
    widget_type = params["widget_type"]

    config = build_config(widget_type, params, socket.assigns.telemetry_catalog)

    send(self(), {:update_widget_config, widget_id, config})

    {:noreply, socket}
  end

  defp build_config("value_display", params, _catalog) do
    {target, packet, item} = parse_telemetry_item(params["telemetry_item"])

    %{
      "title" => params["title"],
      "telemetry_item" => %{
        "target" => target,
        "packet" => packet,
        "item" => item
      },
      "unit" => params["unit"],
      "precision" => parse_integer(params["precision"], 2),
      "show_trend" => params["show_trend"] == "on"
    }
  end

  defp build_config("line_chart", params, _catalog) do
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
      "time_window" => parse_integer(params["time_window"], 60)
    }
  end

  defp build_config("gauge", params, _catalog) do
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

  defp build_config("table", params, catalog) do
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

  defp build_config(_type, params, _catalog) do
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
