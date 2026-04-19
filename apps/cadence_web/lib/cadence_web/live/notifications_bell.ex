defmodule CadenceWeb.NotificationsBell do
  @moduledoc """
  on_mount/after-auth helper that wires a user's notifications into any
  LiveView that uses a sidebar/shell layout with a bell icon.

  Assigns `:unread_notifications_count` and `:recent_notifications` on the
  socket, subscribes to the user's notifications PubSub topic, and attaches
  a `handle_info` hook that keeps those assigns fresh when notifications
  arrive, update, or are dismissed by acceptance.
  """

  import Phoenix.Component
  alias Cadence.Notifications
  alias Cadence.Notifications.Notification

  @recent_limit 5

  @spec attach(Phoenix.LiveView.Socket.t()) :: Phoenix.LiveView.Socket.t()
  def attach(%{assigns: %{current_scope: %{user: %{user_id: user_id}}}} = socket)
      when is_binary(user_id) do
    if Phoenix.LiveView.connected?(socket) do
      Notifications.subscribe(user_id)

      socket
      |> assign_counts(user_id)
      |> Phoenix.LiveView.attach_hook(
        :notifications_bell,
        :handle_info,
        &handle_notifications_event/2
      )
    else
      assign_counts(socket, user_id)
    end
  end

  def attach(socket) do
    socket
    |> assign(:unread_notifications_count, 0)
    |> assign(:recent_notifications, [])
  end

  defp assign_counts(socket, user_id) do
    socket
    |> assign(
      :unread_notifications_count,
      Notifications.count_unread_notifications(user_id)
    )
    |> assign(
      :recent_notifications,
      Notifications.list_notifications(user_id, limit: @recent_limit)
    )
  end

  defp handle_notifications_event({:notification_created, %Notification{} = n}, socket) do
    {:cont, prepend_recent(socket, n)}
  end

  defp handle_notifications_event({:notification_updated, %Notification{} = n}, socket) do
    {:cont, replace_or_recompute(socket, n)}
  end

  defp handle_notifications_event({:invitation_accepted, _invitation}, socket) do
    {:cont, refresh_from_db(socket)}
  end

  defp handle_notifications_event(_other, socket), do: {:cont, socket}

  defp prepend_recent(socket, %Notification{} = n) do
    recent =
      [
        n
        | Enum.reject(
            socket.assigns.recent_notifications,
            &(&1.notification_id == n.notification_id)
          )
      ]
      |> Enum.take(@recent_limit)

    unread_delta = if Notification.unread?(n), do: 1, else: 0

    socket
    |> assign(:recent_notifications, recent)
    |> assign(
      :unread_notifications_count,
      socket.assigns.unread_notifications_count + unread_delta
    )
  end

  defp replace_or_recompute(socket, %Notification{} = n) do
    recent =
      Enum.map(socket.assigns.recent_notifications, fn existing ->
        if existing.notification_id == n.notification_id, do: n, else: existing
      end)

    count =
      case socket.assigns[:current_scope] do
        %{user: %{user_id: user_id}} when is_binary(user_id) ->
          Notifications.count_unread_notifications(user_id)

        _ ->
          socket.assigns.unread_notifications_count
      end

    socket
    |> assign(:recent_notifications, recent)
    |> assign(:unread_notifications_count, count)
  end

  defp refresh_from_db(socket) do
    case socket.assigns[:current_scope] do
      %{user: %{user_id: user_id}} when is_binary(user_id) ->
        assign_counts(socket, user_id)

      _ ->
        socket
    end
  end
end
