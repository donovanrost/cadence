defmodule CadenceWeb.NotificationLive.Index do
  @moduledoc """
  LiveView for the notifications inbox page.

  Displays all notifications for the current user with filtering,
  pagination, and real-time updates via PubSub.
  """
  use CadenceWeb, :live_view

  alias Cadence.Notifications

  import CadenceWeb.NotificationComponents

  @page_size 20

  @impl true
  def mount(_params, _session, socket) do
    user = socket.assigns.current_scope.user

    if connected?(socket) do
      Notifications.subscribe(user.id)
    end

    {:ok,
     socket
     |> assign(:page_title, "Notifications")
     |> assign(:filter, :all)
     |> assign(:page, 0)
     |> assign(:has_more, false)
     |> load_notifications()}
  end

  @impl true
  def handle_params(_params, _url, socket) do
    {:noreply, socket}
  end

  defp load_notifications(socket) do
    user = socket.assigns.current_scope.user
    filter = socket.assigns.filter
    page = socket.assigns.page

    opts = [
      limit: @page_size + 1,
      offset: page * @page_size
    ]

    notifications =
      case filter do
        :all -> Notifications.list_inbox(user.id, opts)
        :unread -> Notifications.list_unread(user.id, opts)
      end

    has_more = length(notifications) > @page_size
    notifications = Enum.take(notifications, @page_size)

    socket
    |> assign(:notifications, notifications)
    |> assign(:has_more, has_more)
    |> assign(:unread_count, Notifications.unread_count(user.id))
  end

  @impl true
  def handle_event("filter", %{"filter" => filter}, socket) do
    filter_atom =
      case filter do
        "unread" -> :unread
        _ -> :all
      end

    {:noreply,
     socket
     |> assign(:filter, filter_atom)
     |> assign(:page, 0)
     |> load_notifications()}
  end

  def handle_event("view_notification", %{"id" => id}, socket) do
    notification = Enum.find(socket.assigns.notifications, &(&1.id == id))

    if notification do
      Notifications.mark_read(notification)

      if notification.action_url do
        {:noreply, push_navigate(socket, to: notification.action_url)}
      else
        {:noreply, load_notifications(socket)}
      end
    else
      {:noreply, socket}
    end
  end

  def handle_event("mark_all_notifications_read", _params, socket) do
    user = socket.assigns.current_scope.user
    Notifications.mark_all_read(user.id)
    {:noreply, load_notifications(socket)}
  end

  def handle_event("archive_notification", %{"id" => id}, socket) do
    notification = Enum.find(socket.assigns.notifications, &(&1.id == id))

    if notification do
      Notifications.archive(notification)
      {:noreply, load_notifications(socket)}
    else
      {:noreply, socket}
    end
  end

  def handle_event("load_more", _params, socket) do
    {:noreply,
     socket
     |> assign(:page, socket.assigns.page + 1)
     |> load_more_notifications()}
  end

  defp load_more_notifications(socket) do
    user = socket.assigns.current_scope.user
    filter = socket.assigns.filter
    page = socket.assigns.page

    opts = [
      limit: @page_size + 1,
      offset: page * @page_size
    ]

    new_notifications =
      case filter do
        :all -> Notifications.list_inbox(user.id, opts)
        :unread -> Notifications.list_unread(user.id, opts)
      end

    has_more = length(new_notifications) > @page_size
    new_notifications = Enum.take(new_notifications, @page_size)

    socket
    |> assign(:notifications, socket.assigns.notifications ++ new_notifications)
    |> assign(:has_more, has_more)
  end

  # Handle PubSub messages for real-time updates
  @impl true
  def handle_info({:notification_created, _notification}, socket) do
    {:noreply, load_notifications(socket)}
  end

  def handle_info({:notification_read, _notification}, socket) do
    {:noreply, load_notifications(socket)}
  end

  def handle_info({:all_notifications_read, _user_id}, socket) do
    {:noreply, load_notifications(socket)}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="max-w-3xl mx-auto">
      <.header>
        Notifications
        <:subtitle>
          {if @unread_count > 0, do: "#{@unread_count} unread", else: "All caught up!"}
        </:subtitle>
        <:actions>
          <button
            :if={@unread_count > 0}
            phx-click="mark_all_notifications_read"
            class="btn btn-ghost btn-sm"
          >
            Mark all as read
          </button>
        </:actions>
      </.header>

      <div class="mt-6">
        <!-- Filters -->
        <div class="flex items-center gap-4 mb-6">
          <div class="flex rounded-lg border border-base-300 p-1">
            <button
              phx-click="filter"
              phx-value-filter="all"
              class={[
                "px-3 py-1.5 text-sm font-medium rounded-md transition-colors",
                @filter == :all && "bg-primary text-primary-content",
                @filter != :all && "hover:bg-base-200"
              ]}
            >
              All
            </button>
            <button
              phx-click="filter"
              phx-value-filter="unread"
              class={[
                "px-3 py-1.5 text-sm font-medium rounded-md transition-colors",
                @filter == :unread && "bg-primary text-primary-content",
                @filter != :unread && "hover:bg-base-200"
              ]}
            >
              Unread
            </button>
          </div>
        </div>
        
    <!-- Notification List -->
        <div class="space-y-3">
          <%= if Enum.empty?(@notifications) do %>
            <div class="card bg-base-100 border border-base-300 p-12">
              <div class="text-center text-base-content/50">
                <.icon name="hero-bell" class="w-12 h-12 mx-auto mb-4 opacity-50" />
                <p class="text-lg font-medium">No notifications</p>
                <p class="text-sm mt-1">
                  {if @filter == :unread,
                    do: "You've read all your notifications",
                    else: "You don't have any notifications yet"}
                </p>
              </div>
            </div>
          <% else %>
            <.notification_card
              :for={notification <- @notifications}
              notification={notification}
            />

            <%= if @has_more do %>
              <div class="text-center py-4">
                <button phx-click="load_more" class="btn btn-ghost btn-sm">
                  Load more
                </button>
              </div>
            <% end %>
          <% end %>
        </div>
      </div>
    </div>
    """
  end
end
