defmodule CadenceWeb.NotificationComponents do
  @moduledoc """
  LiveView components for displaying notifications.
  """

  use Phoenix.Component
  use CadenceWeb, :verified_routes

  import CadenceWeb.CoreComponents

  @doc """
  Renders the notification bell icon with unread count badge.

  This component should be placed in the header/navbar and will update
  in real-time as notifications are received.
  """
  attr :id, :string, default: "notification-bell"
  attr :unread_count, :integer, default: 0
  attr :notifications, :list, default: []

  def notification_bell(assigns) do
    ~H"""
    <div class="dropdown dropdown-end" id={@id}>
      <div tabindex="0" role="button" class="btn btn-ghost btn-circle">
        <div class="indicator">
          <.icon
            name={if @unread_count > 0, do: "hero-bell-solid", else: "hero-bell"}
            class="h-5 w-5"
          />
          <span
            :if={@unread_count > 0}
            class="badge badge-xs badge-primary indicator-item"
          >
            {format_count(@unread_count)}
          </span>
        </div>
      </div>

      <div
        tabindex="0"
        class="dropdown-content z-[100] card card-compact w-80 bg-base-200 shadow-lg border border-base-300"
      >
        <div class="card-body">
          <div class="flex items-center justify-between mb-2">
            <h3 class="font-semibold">Notifications</h3>
            <button
              :if={@unread_count > 0}
              phx-click="mark_all_notifications_read"
              class="btn btn-ghost btn-xs"
            >
              Mark all read
            </button>
          </div>

          <div class="max-h-96 overflow-y-auto divide-y divide-base-300">
            <%= if Enum.empty?(@notifications) do %>
              <p class="text-center text-base-content/50 py-8">
                No notifications
              </p>
            <% else %>
              <.notification_item
                :for={notification <- @notifications}
                notification={notification}
              />
            <% end %>
          </div>

          <div class="card-actions justify-end mt-2 pt-2 border-t border-base-300">
            <.link navigate={~p"/notifications"} class="btn btn-ghost btn-sm">
              View all
            </.link>
          </div>
        </div>
      </div>
    </div>
    """
  end

  @doc """
  Renders a single notification item in the dropdown.
  """
  attr :notification, :map, required: true

  def notification_item(assigns) do
    ~H"""
    <div
      class={[
        "py-3 px-2 hover:bg-base-300 rounded-lg cursor-pointer transition-colors",
        is_nil(@notification.read_at) && "bg-primary/5"
      ]}
      phx-click="view_notification"
      phx-value-id={@notification.id}
    >
      <div class="flex items-start gap-3">
        <div class={[
          "mt-1 w-2 h-2 rounded-full flex-shrink-0",
          is_nil(@notification.read_at) && "bg-primary",
          @notification.read_at && "bg-transparent"
        ]}>
        </div>

        <div class="flex-1 min-w-0">
          <p class={[
            "text-sm line-clamp-2",
            is_nil(@notification.read_at) && "font-medium"
          ]}>
            {@notification.title}
          </p>
          <p :if={@notification.body} class="text-xs text-base-content/60 mt-1 line-clamp-2">
            {@notification.body}
          </p>
          <div class="flex items-center gap-2 mt-1">
            <span class="text-xs text-base-content/40">
              {format_relative_time(@notification.inserted_at)}
            </span>
            <span
              :if={@notification.mission}
              class="badge badge-xs badge-ghost"
            >
              {@notification.mission.name}
            </span>
          </div>
        </div>
      </div>
    </div>
    """
  end

  @doc """
  Renders a notification card for the full inbox view.
  """
  attr :notification, :map, required: true
  attr :show_archive, :boolean, default: true

  def notification_card(assigns) do
    ~H"""
    <div
      class={[
        "card card-compact bg-base-100 border border-base-300 hover:border-base-400 transition-colors group",
        is_nil(@notification.read_at) && "border-l-4 border-l-primary"
      ]}
    >
      <div class="card-body">
        <div class="flex items-start justify-between gap-4">
          <div class="flex items-start gap-3 flex-1 min-w-0">
            <div class={[
              "mt-1.5 w-2 h-2 rounded-full flex-shrink-0",
              is_nil(@notification.read_at) && "bg-primary",
              @notification.read_at && "bg-transparent"
            ]}>
            </div>

            <div class="flex-1 min-w-0">
              <div class="flex items-center gap-2">
                <h3 class={[
                  "text-sm",
                  is_nil(@notification.read_at) && "font-semibold"
                ]}>
                  {@notification.title}
                </h3>
                <span
                  :if={@notification.severity == "warning"}
                  class="badge badge-xs badge-warning"
                >
                  Warning
                </span>
                <span
                  :if={@notification.severity == "critical"}
                  class="badge badge-xs badge-error"
                >
                  Critical
                </span>
              </div>

              <p :if={@notification.body} class="text-sm text-base-content/70 mt-1">
                {@notification.body}
              </p>

              <div class="flex items-center gap-3 mt-2">
                <span
                  :if={@notification.mission}
                  class="badge badge-sm badge-ghost"
                >
                  {@notification.mission.name}
                </span>
                <span class="text-xs text-base-content/50">
                  {format_relative_time(@notification.inserted_at)}
                </span>
              </div>
            </div>
          </div>

          <div class="flex items-center gap-2">
            <.link
              :if={@notification.action_url}
              navigate={@notification.action_url}
              class="btn btn-ghost btn-sm"
            >
              View
            </.link>
            <button
              :if={@show_archive}
              phx-click="archive_notification"
              phx-value-id={@notification.id}
              class="btn btn-ghost btn-sm opacity-0 group-hover:opacity-100 transition-opacity"
            >
              <.icon name="hero-x-mark" class="w-4 h-4" />
            </button>
          </div>
        </div>
      </div>
    </div>
    """
  end

  defp format_count(count) when count > 99, do: "99+"
  defp format_count(count), do: to_string(count)

  defp format_relative_time(datetime) do
    now = DateTime.utc_now()
    diff_seconds = DateTime.diff(now, datetime)

    cond do
      diff_seconds < 60 -> "just now"
      diff_seconds < 3600 -> "#{div(diff_seconds, 60)}m ago"
      diff_seconds < 86400 -> "#{div(diff_seconds, 3600)}h ago"
      diff_seconds < 604_800 -> "#{div(diff_seconds, 86400)}d ago"
      true -> Calendar.strftime(datetime, "%b %d")
    end
  end
end
