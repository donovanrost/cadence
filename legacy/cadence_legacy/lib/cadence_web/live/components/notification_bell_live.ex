defmodule CadenceWeb.NotificationBellLive do
  @moduledoc """
  LiveComponent that provides real-time notification updates.

  Subscribes to the user's notification PubSub topic and updates
  the bell icon and dropdown in real-time.
  """

  use CadenceWeb, :live_component

  alias Cadence.Notifications

  @impl true
  def mount(socket) do
    {:ok, assign(socket, notifications: [], unread_count: 0, subscribed: nil)}
  end

  @impl true
  def update(%{current_user: user} = assigns, socket) do
    if connected?(socket) and socket.assigns[:subscribed] != user.id do
      # Unsubscribe from old user if any
      if socket.assigns[:subscribed] do
        Notifications.unsubscribe(socket.assigns.subscribed)
      end

      # Subscribe to new user's notifications
      Notifications.subscribe(user.id)

      # Load initial notifications
      notifications = Notifications.list_unread(user.id, limit: 7)
      unread_count = Notifications.unread_count(user.id)

      socket =
        socket
        |> assign(assigns)
        |> assign(:subscribed, user.id)
        |> assign(:notifications, notifications)
        |> assign(:unread_count, unread_count)

      {:ok, socket}
    else
      {:ok, assign(socket, assigns)}
    end
  end

  # Handle PubSub messages forwarded from parent LiveView
  def update(%{notification_event: {:notification_created, notification}}, socket) do
    notifications = [notification | socket.assigns.notifications] |> Enum.take(7)
    unread_count = socket.assigns.unread_count + 1

    {:ok,
     socket
     |> assign(:notifications, notifications)
     |> assign(:unread_count, unread_count)}
  end

  def update(%{notification_event: {:notification_read, notification}}, socket) do
    notifications =
      Enum.map(socket.assigns.notifications, fn n ->
        if n.id == notification.id, do: notification, else: n
      end)

    unread_count = max(0, socket.assigns.unread_count - 1)

    {:ok,
     socket
     |> assign(:notifications, notifications)
     |> assign(:unread_count, unread_count)}
  end

  def update(%{notification_event: {:all_notifications_read, _mission_id}}, socket) do
    {:ok,
     socket
     |> assign(:unread_count, 0)
     |> assign(:notifications, mark_all_read_local(socket.assigns.notifications))}
  end

  @impl true
  def handle_event("view_notification", %{"id" => id}, socket) do
    notification = Enum.find(socket.assigns.notifications, &(&1.id == id))

    if notification do
      # Mark as read
      Notifications.mark_read(notification)

      # Navigate to the action URL
      if notification.action_url do
        {:noreply, push_navigate(socket, to: notification.action_url)}
      else
        {:noreply, socket}
      end
    else
      {:noreply, socket}
    end
  end

  def handle_event("mark_all_notifications_read", _params, socket) do
    user_id = socket.assigns.current_user.id
    Notifications.mark_all_read(user_id)

    {:noreply,
     socket
     |> assign(:unread_count, 0)
     |> assign(:notifications, mark_all_read_local(socket.assigns.notifications))}
  end

  defp mark_all_read_local(notifications) do
    now = DateTime.utc_now()
    Enum.map(notifications, &Map.put(&1, :read_at, now))
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div id={@id}>
      <CadenceWeb.NotificationComponents.notification_bell
        id={"#{@id}-bell"}
        unread_count={@unread_count}
        notifications={@notifications}
      />
    </div>
    """
  end
end
