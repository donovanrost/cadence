defmodule CadenceWeb.LinkComponents do
  @moduledoc """
  Reusable components for Links, Channels, and Bindings configuration UI.
  """
  use Phoenix.Component

  use Phoenix.VerifiedRoutes,
    endpoint: CadenceWeb.Endpoint,
    router: CadenceWeb.Router,
    statics: CadenceWeb.static_paths()

  import CadenceWeb.CoreComponents

  @doc """
  Renders a direction badge (uplink/downlink/both) with appropriate icon.
  """
  attr :direction, :atom, required: true

  def direction_badge(assigns) do
    {color, icon, label} =
      case assigns.direction do
        :uplink -> {"blue", "hero-arrow-up", "Uplink"}
        :downlink -> {"green", "hero-arrow-down", "Downlink"}
        :both -> {"purple", "hero-arrows-up-down", "Both"}
        _ -> {"gray", "hero-minus", "Unknown"}
      end

    assigns =
      assigns
      |> assign(:color, color)
      |> assign(:icon, icon)
      |> assign(:label, label)

    ~H"""
    <span class={[
      "inline-flex items-center gap-1 px-2 py-0.5 rounded-md text-xs font-medium",
      badge_color_classes(@color)
    ]}>
      <.icon name={@icon} class="h-3 w-3" />
      {@label}
    </span>
    """
  end

  @doc """
  Renders a transport type badge (tcp/udp/serial/file/s3/replay).
  """
  attr :type, :atom, required: true

  def transport_type_badge(assigns) do
    {color, label} =
      case assigns.type do
        :tcp -> {"cyan", "TCP"}
        :udp -> {"indigo", "UDP"}
        :serial -> {"yellow", "Serial"}
        :file -> {"gray", "File"}
        :s3 -> {"orange", "S3"}
        :replay -> {"pink", "Replay"}
        _ -> {"gray", String.upcase(to_string(assigns.type))}
      end

    assigns =
      assigns
      |> assign(:color, color)
      |> assign(:label, label)

    ~H"""
    <span class={[
      "inline-flex items-center px-2 py-0.5 rounded-md text-xs font-medium",
      badge_color_classes(@color)
    ]}>
      {@label}
    </span>
    """
  end

  @doc """
  Renders a role badge (primary/backup/replay/any).
  """
  attr :role, :atom, required: true

  def role_badge(assigns) do
    {color, label} =
      case assigns.role do
        :primary -> {"green", "Primary"}
        :backup -> {"yellow", "Backup"}
        :replay -> {"purple", "Replay"}
        :any -> {"gray", "Any"}
        _ -> {"gray", String.capitalize(to_string(assigns.role))}
      end

    assigns =
      assigns
      |> assign(:color, color)
      |> assign(:label, label)

    ~H"""
    <span class={[
      "inline-flex items-center px-2 py-0.5 rounded-md text-xs font-medium",
      badge_color_classes(@color)
    ]}>
      {@label}
    </span>
    """
  end

  @doc """
  Renders a desired state badge (active/inactive/draining).
  """
  attr :state, :atom, required: true

  def state_badge(assigns) do
    {color, icon, label} =
      case assigns.state do
        :active -> {"green", "hero-play", "Active"}
        :inactive -> {"gray", "hero-pause", "Inactive"}
        :draining -> {"yellow", "hero-arrow-right-on-rectangle", "Draining"}
        _ -> {"gray", "hero-question-mark-circle", "Unknown"}
      end

    assigns =
      assigns
      |> assign(:color, color)
      |> assign(:icon, icon)
      |> assign(:label, label)

    ~H"""
    <span class={[
      "inline-flex items-center gap-1 px-2 py-0.5 rounded-md text-xs font-medium",
      badge_color_classes(@color)
    ]}>
      <.icon name={@icon} class="h-3 w-3" />
      {@label}
    </span>
    """
  end

  @doc """
  Renders a channel identifier (SCID/VCID/MAP).
  """
  attr :channel, :map, required: true

  def channel_id(assigns) do
    ~H"""
    <span class="font-mono text-sm">
      <span class="text-base-content/60">SCID:</span>
      <span class="font-semibold">{@channel.scid}</span>
      <span class="text-base-content/40 mx-1">/</span>
      <span class="text-base-content/60">VCID:</span>
      <span class="font-semibold">{@channel.vcid}</span>
      <%= if @channel.map_id do %>
        <span class="text-base-content/40 mx-1">/</span>
        <span class="text-base-content/60">MAP:</span>
        <span class="font-semibold">{@channel.map_id}</span>
      <% end %>
    </span>
    """
  end

  @doc """
  Renders an enabled/disabled indicator.
  """
  attr :enabled, :boolean, required: true

  def enabled_indicator(assigns) do
    ~H"""
    <%= if @enabled do %>
      <span class="inline-flex items-center gap-1 text-success text-xs">
        <span class="h-2 w-2 rounded-full bg-success"></span> Enabled
      </span>
    <% else %>
      <span class="inline-flex items-center gap-1 text-base-content/50 text-xs">
        <span class="h-2 w-2 rounded-full bg-base-content/30"></span> Disabled
      </span>
    <% end %>
    """
  end

  @doc """
  Renders a bindings summary for a channel or interface.
  """
  attr :bindings, :list, required: true
  attr :show_interface, :boolean, default: true

  def bindings_summary(assigns) do
    active_count = Enum.count(assigns.bindings, &(&1.desired_state == :active))
    total_count = length(assigns.bindings)

    assigns =
      assigns
      |> assign(:active_count, active_count)
      |> assign(:total_count, total_count)

    ~H"""
    <div class="text-sm">
      <span class={[
        "font-medium",
        @active_count > 0 && "text-success",
        @active_count == 0 && "text-base-content/50"
      ]}>
        {@active_count} active
      </span>
      <span class="text-base-content/40">
        / {@total_count} total
      </span>
    </div>
    """
  end

  @doc """
  Renders a table of bindings for a channel.
  """
  attr :bindings, :list, required: true
  attr :mission, :map, required: true
  attr :link_id, :string, required: true
  attr :channel_id, :string, required: true
  attr :on_delete, :any, default: nil

  def bindings_table(assigns) do
    ~H"""
    <div class="overflow-x-auto">
      <table class="table table-sm">
        <thead>
          <tr class="text-base-content/60">
            <th>Interface</th>
            <th>Direction</th>
            <th>Role</th>
            <th>Priority</th>
            <th>State</th>
            <th class="text-right">Actions</th>
          </tr>
        </thead>
        <tbody>
          <%= for binding <- @bindings do %>
            <tr class="hover:bg-base-200/50">
              <td class="font-medium">
                {binding.interface.name}
              </td>
              <td>
                <.direction_badge direction={binding.direction} />
              </td>
              <td>
                <.role_badge role={binding.role} />
              </td>
              <td class="font-mono text-sm">
                {binding.priority}
              </td>
              <td>
                <.state_badge state={binding.desired_state} />
              </td>
              <td class="text-right">
                <.link
                  navigate={
                    ~p"/missions/#{@mission}/links/#{@link_id}/channels/#{@channel_id}/bindings/#{binding.id}/edit"
                  }
                  class="link link-primary text-sm"
                >
                  Edit
                </.link>
                <%= if @on_delete do %>
                  <button
                    type="button"
                    phx-click={@on_delete}
                    phx-value-id={binding.id}
                    data-confirm="Are you sure you want to delete this binding?"
                    class="link link-error text-sm ml-2"
                  >
                    Delete
                  </button>
                <% end %>
              </td>
            </tr>
          <% end %>
        </tbody>
      </table>
      <%= if @bindings == [] do %>
        <div class="text-center py-8 text-base-content/50">
          <.icon name="hero-link-slash" class="h-8 w-8 mx-auto mb-2" />
          <p class="text-sm">No bindings configured</p>
        </div>
      <% end %>
    </div>
    """
  end

  # Helper function for badge color classes - uses pattern matching for clarity
  @badge_colors %{
    "blue" => "bg-blue-100 text-blue-700 dark:bg-blue-900/30 dark:text-blue-400",
    "green" => "bg-green-100 text-green-700 dark:bg-green-900/30 dark:text-green-400",
    "purple" => "bg-purple-100 text-purple-700 dark:bg-purple-900/30 dark:text-purple-400",
    "cyan" => "bg-cyan-100 text-cyan-700 dark:bg-cyan-900/30 dark:text-cyan-400",
    "indigo" => "bg-indigo-100 text-indigo-700 dark:bg-indigo-900/30 dark:text-indigo-400",
    "yellow" => "bg-yellow-100 text-yellow-700 dark:bg-yellow-900/30 dark:text-yellow-400",
    "orange" => "bg-orange-100 text-orange-700 dark:bg-orange-900/30 dark:text-orange-400",
    "pink" => "bg-pink-100 text-pink-700 dark:bg-pink-900/30 dark:text-pink-400",
    "gray" => "bg-gray-100 text-gray-700 dark:bg-gray-900/30 dark:text-gray-400"
  }

  defp badge_color_classes(color) do
    Map.get(@badge_colors, color, @badge_colors["gray"])
  end
end
