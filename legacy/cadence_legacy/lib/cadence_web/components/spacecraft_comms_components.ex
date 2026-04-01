defmodule CadenceWeb.SpacecraftCommsComponents do
  @moduledoc """
  Reusable components for Spacecraft-centric Communications UI.
  """
  use Phoenix.Component

  use Phoenix.VerifiedRoutes,
    endpoint: CadenceWeb.Endpoint,
    router: CadenceWeb.Router,
    statics: CadenceWeb.static_paths()

  import CadenceWeb.CoreComponents
  import CadenceWeb.LinkComponents

  @doc """
  Renders a protocol summary card showing the link's protocol configuration at a glance.

  ## Attributes

  - `protocol_config` - The ProtocolConfig struct (with :config map)
  - `on_edit` - Optional click handler for edit button
  """
  attr :protocol_config, :map, default: nil
  attr :on_edit, :any, default: nil

  def protocol_summary_card(assigns) do
    config = if assigns.protocol_config, do: assigns.protocol_config.config || %{}, else: %{}

    assigns =
      assigns
      |> assign(:config, config)
      |> assign(:profile, Map.get(config, "profile", "tm"))
      |> assign(:frame_size, Map.get(config, "frame_size"))
      |> assign(:uplink_profile, Map.get(config, "uplink_profile", "tc"))
      |> assign(:cop1_enabled, cop1_enabled?(config))

    ~H"""
    <div class="card bg-base-200">
      <div class="card-body p-4">
        <div class="flex items-center justify-between mb-3">
          <h3 class="card-title text-base">Protocol Defaults</h3>
          <%= if @on_edit do %>
            <button type="button" phx-click={@on_edit} class="btn btn-sm btn-ghost">
              <.icon name="hero-pencil-square" class="h-4 w-4" /> Edit
            </button>
          <% end %>
        </div>

        <%= if @protocol_config do %>
          <div class="grid grid-cols-2 md:grid-cols-4 gap-4 text-sm">
            <div>
              <span class="text-base-content/60 block text-xs">Downlink Profile</span>
              <span class="font-medium uppercase">{@profile}</span>
            </div>
            <div>
              <span class="text-base-content/60 block text-xs">Frame Size</span>
              <span class="font-medium font-mono">{@frame_size || "Not set"}</span>
            </div>
            <div>
              <span class="text-base-content/60 block text-xs">Uplink Profile</span>
              <span class="font-medium uppercase">{@uplink_profile}</span>
            </div>
            <div>
              <span class="text-base-content/60 block text-xs">COP-1</span>
              <span class={[
                "font-medium",
                @cop1_enabled && "text-success",
                !@cop1_enabled && "text-base-content/50"
              ]}>
                {if @cop1_enabled, do: "Enabled", else: "Disabled"}
              </span>
            </div>
          </div>
        <% else %>
          <div class="text-center py-4 text-base-content/50">
            <.icon name="hero-cog-6-tooth" class="h-8 w-8 mx-auto mb-2" />
            <p class="text-sm">No protocol configuration</p>
          </div>
        <% end %>
      </div>
    </div>
    """
  end

  defp cop1_enabled?(config) do
    window_size = Map.get(config, "cop1_window_size")
    is_integer(window_size) and window_size > 0
  end

  @doc """
  Renders a table of channels for a spacecraft target.

  ## Attributes

  - `channels` - List of Channel structs
  - `mission` - The mission
  - `target` - The target (for navigation)
  - `on_delete` - Optional delete handler
  """
  attr :channels, :list, required: true
  attr :mission, :map, required: true
  attr :target, :map, required: true
  attr :on_delete, :any, default: nil

  def channels_table(assigns) do
    ~H"""
    <div class="overflow-x-auto bg-base-200 rounded-lg">
      <table class="table table-sm">
        <thead>
          <tr class="text-base-content/60">
            <th>VCID</th>
            <th>Direction</th>
            <th>Enabled</th>
            <th>Overrides</th>
            <th>Bindings</th>
            <th class="text-right">Actions</th>
          </tr>
        </thead>
        <tbody>
          <%= for channel <- @channels do %>
            <tr class="hover:bg-base-300/50">
              <td class="font-mono font-semibold">
                {channel.vcid}
                <%= if channel.map_id do %>
                  <span class="text-base-content/50 text-xs ml-1">(MAP {channel.map_id})</span>
                <% end %>
              </td>
              <td>
                <.direction_badge direction={channel.direction} />
              </td>
              <td>
                <.enabled_indicator enabled={channel.enabled} />
              </td>
              <td>
                <.overrides_count channel={channel} />
              </td>
              <td>
                <.bindings_summary bindings={channel.bindings || []} />
              </td>
              <td class="text-right space-x-2">
                <.link
                  navigate={~p"/missions/#{@mission}/targets/#{@target}/comms/channels/#{channel}"}
                  class="link link-primary text-sm"
                >
                  View
                </.link>
                <.link
                  patch={~p"/missions/#{@mission}/targets/#{@target}/comms/channels/#{channel}/edit"}
                  class="link link-primary text-sm"
                >
                  Edit
                </.link>
                <%= if @on_delete do %>
                  <button
                    type="button"
                    phx-click={@on_delete}
                    phx-value-id={channel.id}
                    data-confirm="Are you sure you want to delete this channel?"
                    class="link link-error text-sm"
                  >
                    Delete
                  </button>
                <% end %>
              </td>
            </tr>
          <% end %>
        </tbody>
      </table>

      <%= if @channels == [] do %>
        <div class="text-center py-8 text-base-content/50">
          <.icon name="hero-signal" class="h-8 w-8 mx-auto mb-2" />
          <p class="text-sm">No channels configured</p>
        </div>
      <% end %>
    </div>
    """
  end

  @doc """
  Renders the overrides count for a channel.
  """
  attr :channel, :map, required: true

  def overrides_count(assigns) do
    count =
      case assigns.channel.protocol_config do
        %{overrides: overrides} when is_map(overrides) ->
          map_size(overrides)

        _ ->
          0
      end

    assigns = assign(assigns, :count, count)

    ~H"""
    <span class={[
      "text-sm",
      @count > 0 && "font-medium text-warning",
      @count == 0 && "text-base-content/50"
    ]}>
      {if @count > 0, do: "#{@count} override#{if @count > 1, do: "s"}", else: "None"}
    </span>
    """
  end

  @doc """
  Renders the primary channel selector with dropdowns for uplink and downlink.

  ## Attributes

  - `channels` - List of all channels for this link
  - `primary_uplink` - The current primary uplink ChannelTarget (or nil)
  - `primary_downlink` - The current primary downlink ChannelTarget (or nil)
  """
  attr :channels, :list, required: true
  attr :primary_uplink, :map, default: nil
  attr :primary_downlink, :map, default: nil

  def primary_channel_selector(assigns) do
    uplink_channels =
      Enum.filter(assigns.channels, &(&1.direction in [:uplink, :both]))

    downlink_channels =
      Enum.filter(assigns.channels, &(&1.direction in [:downlink, :both]))

    assigns =
      assigns
      |> assign(:uplink_channels, uplink_channels)
      |> assign(:downlink_channels, downlink_channels)

    ~H"""
    <div class="card bg-base-200">
      <div class="card-body p-4">
        <h3 class="card-title text-base mb-3">Primary Channel Mappings</h3>

        <div class="grid grid-cols-1 md:grid-cols-2 gap-4">
          <div>
            <label class="label">
              <span class="label-text text-sm">Primary Uplink Channel</span>
            </label>
            <select
              name="primary_uplink_channel"
              phx-change="set_primary_uplink"
              class="select select-bordered select-sm w-full"
            >
              <option value="">None</option>
              <%= for channel <- @uplink_channels do %>
                <option
                  value={channel.id}
                  selected={@primary_uplink && channel.vcid == @primary_uplink.vcid}
                >
                  VCID {channel.vcid} {if channel.map_id, do: "(MAP #{channel.map_id})"}
                </option>
              <% end %>
            </select>
            <p class="text-xs text-base-content/50 mt-1">
              Default channel for sending commands to this spacecraft
            </p>
          </div>

          <div>
            <label class="label">
              <span class="label-text text-sm">Primary Downlink Channel</span>
            </label>
            <select
              name="primary_downlink_channel"
              phx-change="set_primary_downlink"
              class="select select-bordered select-sm w-full"
            >
              <option value="">None</option>
              <%= for channel <- @downlink_channels do %>
                <option
                  value={channel.id}
                  selected={@primary_downlink && channel.vcid == @primary_downlink.vcid}
                >
                  VCID {channel.vcid} {if channel.map_id, do: "(MAP #{channel.map_id})"}
                </option>
              <% end %>
            </select>
            <p class="text-xs text-base-content/50 mt-1">
              Primary channel for receiving telemetry from this spacecraft
            </p>
          </div>
        </div>
      </div>
    </div>
    """
  end

  @doc """
  Renders the active binding selector for a channel.

  ## Attributes

  - `channel` - The channel
  - `bindings` - List of bindings for this channel
  - `active_uplink` - Current active uplink binding (or nil)
  - `active_downlink` - Current active downlink binding (or nil)
  """
  attr :channel, :map, required: true
  attr :bindings, :list, required: true
  attr :active_uplink, :map, default: nil
  attr :active_downlink, :map, default: nil

  def active_binding_selector(assigns) do
    uplink_bindings =
      Enum.filter(assigns.bindings, &(&1.direction in [:uplink, :both]))

    downlink_bindings =
      Enum.filter(assigns.bindings, &(&1.direction in [:downlink, :both]))

    assigns =
      assigns
      |> assign(:uplink_bindings, uplink_bindings)
      |> assign(:downlink_bindings, downlink_bindings)
      |> assign(:show_uplink, assigns.channel.direction in [:uplink, :both])
      |> assign(:show_downlink, assigns.channel.direction in [:downlink, :both])

    ~H"""
    <div class="card bg-base-200">
      <div class="card-body p-4">
        <h3 class="card-title text-base mb-3">Active Bindings</h3>

        <div class="grid grid-cols-1 md:grid-cols-2 gap-4">
          <%= if @show_uplink do %>
            <div>
              <label class="label">
                <span class="label-text text-sm">Active Uplink Binding</span>
              </label>
              <select
                name="active_uplink_binding"
                phx-change="set_active_uplink"
                class="select select-bordered select-sm w-full"
              >
                <option value="">None (use priority)</option>
                <%= for binding <- @uplink_bindings do %>
                  <option
                    value={binding.id}
                    selected={@active_uplink && @active_uplink.binding_id == binding.id}
                  >
                    {binding.interface.name} (Priority {binding.priority})
                  </option>
                <% end %>
              </select>
              <p class="text-xs text-base-content/50 mt-1">
                Override binding selection for uplink
              </p>
            </div>
          <% end %>

          <%= if @show_downlink do %>
            <div>
              <label class="label">
                <span class="label-text text-sm">Active Downlink Binding</span>
              </label>
              <select
                name="active_downlink_binding"
                phx-change="set_active_downlink"
                class="select select-bordered select-sm w-full"
              >
                <option value="">None (use priority)</option>
                <%= for binding <- @downlink_bindings do %>
                  <option
                    value={binding.id}
                    selected={@active_downlink && @active_downlink.binding_id == binding.id}
                  >
                    {binding.interface.name} (Priority {binding.priority})
                  </option>
                <% end %>
              </select>
              <p class="text-xs text-base-content/50 mt-1">
                Override binding selection for downlink
              </p>
            </div>
          <% end %>
        </div>

        <%= if @bindings == [] do %>
          <div class="text-center py-4 text-base-content/50">
            <p class="text-sm">No bindings configured. Add a binding first.</p>
          </div>
        <% end %>
      </div>
    </div>
    """
  end

  @doc """
  Renders effective config summary for a channel.

  Shows inherited values from link protocol config with channel overrides highlighted.

  ## Attributes

  - `link_config` - The link's ProtocolConfig struct
  - `channel_config` - The channel's ChannelProtocolConfig struct (or nil)
  """
  attr :link_config, :map, default: nil
  attr :channel_config, :map, default: nil

  def effective_config_summary(assigns) do
    base = if assigns.link_config, do: assigns.link_config.config || %{}, else: %{}
    overrides = if assigns.channel_config, do: assigns.channel_config.overrides || %{}, else: %{}
    merged = Map.merge(base, overrides)

    display_fields = [
      {"profile", "Profile", &String.upcase/1},
      {"frame_size", "Frame Size", &to_string/1},
      {"uplink_profile", "Uplink Profile", &String.upcase/1},
      {"cop1_window_size", "COP-1 Window", &to_string/1},
      {"cop1_timeout_ms", "COP-1 Timeout", &"#{&1}ms"},
      {"cop1_max_retransmit", "COP-1 Max Retries", &to_string/1}
    ]

    items =
      Enum.map(display_fields, fn {key, label, formatter} ->
        value = Map.get(merged, key)
        overridden = Map.has_key?(overrides, key)
        %{key: key, label: label, value: value, overridden: overridden, formatter: formatter}
      end)
      |> Enum.filter(& &1.value)

    assigns = assign(assigns, :items, items)

    ~H"""
    <div class="card bg-base-200">
      <div class="card-body p-4">
        <h3 class="card-title text-base mb-3">Effective Configuration</h3>

        <%= if @items == [] do %>
          <p class="text-sm text-base-content/50">No configuration settings</p>
        <% else %>
          <div class="grid grid-cols-2 md:grid-cols-3 gap-3 text-sm">
            <%= for item <- @items do %>
              <div class={[item.overridden && "border-l-2 border-warning pl-2"]}>
                <span class="text-base-content/60 block text-xs">{item.label}</span>
                <span class={["font-medium", item.overridden && "text-warning"]}>
                  {item.formatter.(item.value)}
                </span>
                <%= if item.overridden do %>
                  <span class="text-xs text-warning ml-1">(override)</span>
                <% end %>
              </div>
            <% end %>
          </div>
        <% end %>
      </div>
    </div>
    """
  end

  @doc """
  Renders a simplified channel header with back navigation.

  ## Attributes

  - `channel` - The Channel struct
  - `target` - The Target
  - `mission` - The Mission
  """
  attr :channel, :map, required: true
  attr :target, :map, required: true
  attr :mission, :map, required: true

  def channel_header(assigns) do
    ~H"""
    <div class="flex items-center gap-4 mb-6">
      <.link
        navigate={~p"/missions/#{@mission}/targets/#{@target}/comms"}
        class="btn btn-ghost btn-sm"
      >
        <.icon name="hero-arrow-left" class="h-4 w-4" /> Back
      </.link>

      <div class="flex-1">
        <div class="flex items-center gap-3">
          <.channel_id channel={@channel} />
          <.direction_badge direction={@channel.direction} />
          <.enabled_indicator enabled={@channel.enabled} />
        </div>
        <div class="text-sm text-base-content/60 mt-1">
          Spacecraft: {@target.name}
        </div>
      </div>
    </div>
    """
  end

  @doc """
  Renders a no-communications message when a spacecraft has no link configured.
  """
  attr :target, :map, required: true
  attr :mission, :map, required: true

  def no_comms_configured(assigns) do
    ~H"""
    <div class="text-center py-12 border border-dashed border-base-300 rounded-lg bg-base-200/30">
      <.icon name="hero-signal-slash" class="mx-auto h-12 w-12 text-base-content/30" />
      <h3 class="mt-4 text-lg font-semibold text-base-content">No Communications Configured</h3>
      <p class="mt-2 text-sm text-base-content/60 max-w-md mx-auto">
        This spacecraft doesn't have an SCID configured yet.
        Edit the target to set a Spacecraft ID (SCID), and the communications
        link will be automatically created.
      </p>
      <div class="mt-6">
        <.link
          patch={~p"/missions/#{@mission}/targets/#{@target}/edit"}
          class="btn btn-primary"
        >
          <.icon name="hero-pencil-square" class="-ml-0.5 mr-1.5 h-5 w-5" /> Configure SCID
        </.link>
      </div>
    </div>
    """
  end
end
