defmodule CadenceWeb.NotificationsLive do
  @moduledoc false
  use CadenceWeb, :live_view

  alias Cadence.Notifications.Notification
  alias Phoenix.LiveView.JS

  @impl true
  def mount(_params, _session, socket) do
    user_id = socket.assigns.current_scope.user.user_id

    {:ok,
     socket
     |> assign(:page_title, "Notifications")
     |> assign_notifications(Cadence.Notifications.list_notifications(user_id))}
  end

  @impl true
  def handle_event("accept_invitation", %{"notification_id" => id}, socket) do
    user_id = socket.assigns.current_scope.user.user_id

    with {:ok, notification} <- Cadence.Notifications.fetch_notification(id),
         true <- notification.user_id == user_id,
         :organization_invitation <- notification.kind,
         invitation_id when is_binary(invitation_id) <-
           Map.get(notification.metadata, "organization_invitation_id") do
      case Cadence.Accounts.accept_invitation_as_user(user_id, invitation_id) do
        {:ok, %{invitation: _invitation}} ->
          org_name =
            Map.get(notification.metadata, "organization_display_name", "the organization")

          {:noreply,
           socket
           |> put_flash(:info, "Joined #{org_name}.")
           |> push_navigate(to: ~p"/")}

        {:error, reason} ->
          {:noreply,
           socket
           |> put_flash(:error, accept_error_message(reason))
           |> assign_notifications(Cadence.Notifications.list_notifications(user_id))}
      end
    else
      _other ->
        {:noreply,
         socket
         |> put_flash(:error, "That notification is no longer available.")
         |> assign_notifications(Cadence.Notifications.list_notifications(user_id))}
    end
  end

  @impl true
  def handle_event("mark_read", %{"notification_id" => id}, socket) do
    mark_notification_read(socket, id)
  end

  @impl true
  def handle_info({:notification_created, %Notification{} = n}, socket) do
    {:noreply, assign_notifications(socket, [n | socket.assigns.notifications])}
  end

  @impl true
  def handle_info({:notification_updated, %Notification{} = n}, socket) do
    {:noreply, assign_notifications(socket, replace_in_list(socket.assigns.notifications, n))}
  end

  @impl true
  def handle_info({:invitation_accepted, _invitation}, socket) do
    user_id = socket.assigns.current_scope.user.user_id
    # After accept_invitation_as_user marks related notifications read, the bell hook
    # already fired; just refresh the full list from DB so stale rows disappear.
    {:noreply, assign_notifications(socket, Cadence.Notifications.list_notifications(user_id))}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_scope}>
      <div id="notifications-page" class="space-y-4 max-w-2xl mx-auto">
        <.page_header
          title="Notifications"
          subtitle="Invitations, access grants, and system notices."
        />

        <div :if={@notifications_empty?} id="notifications-empty-state">
          <.empty_state icon="hero-bell" title="No notifications" description="All caught up." />
        </div>

        <.vue
          :if={!@notifications_empty?}
          id="notifications-panel-component"
          v-component="NotificationsPanel"
          notifications={@notification_rows}
          v-on:accept-invitation={JS.push("accept_invitation")}
          v-on:mark-read={JS.push("mark_read")}
          v-ssr={false}
        />
      </div>
    </Layouts.app>
    """
  end

  defp mark_notification_read(socket, id) do
    user_id = socket.assigns.current_scope.user.user_id

    case Cadence.Notifications.mark_notification_read(id, user_id) do
      {:ok, updated} ->
        {:noreply,
         assign_notifications(
           socket,
           replace_in_list(socket.assigns.notifications, updated)
         )}

      {:error, _reason} ->
        {:noreply, socket}
    end
  end

  defp assign_notifications(socket, notifications) do
    socket
    |> assign(:notifications, notifications)
    |> assign(:notification_rows, Enum.map(notifications, &notification_row/1))
    |> assign(:notifications_empty?, notifications == [])
  end

  defp notification_row(%Notification{} = notification) do
    notification_id = notification.notification_id
    {action, action_label} = notification_action(notification)

    %{
      id: "notification-#{notification_id}",
      notification_id: notification_id,
      kind: Atom.to_string(notification.kind),
      title: notification.title,
      body: notification.body,
      unread: Notification.unread?(notification),
      action: action,
      action_label: action_label,
      state_label: notification_state_label(notification)
    }
  end

  defp notification_action(%Notification{kind: :organization_invitation, read_at: nil}),
    do: {"accept_invitation", "Accept"}

  defp notification_action(%Notification{read_at: nil}),
    do: {"mark_read", "Mark read"}

  defp notification_action(%Notification{}), do: {nil, nil}

  defp notification_state_label(%Notification{
         kind: :organization_invitation,
         read_at: %DateTime{}
       }),
       do: "Accepted"

  defp notification_state_label(%Notification{}), do: nil

  defp replace_in_list(list, %Notification{} = n) do
    Enum.map(list, fn existing ->
      if existing.notification_id == n.notification_id, do: n, else: existing
    end)
  end

  defp accept_error_message(:email_mismatch),
    do: "That invitation was sent to a different email address."

  defp accept_error_message(:invitation_not_pending),
    do: "That invitation is no longer available."

  defp accept_error_message(:invitation_expired),
    do: "That invitation has expired."

  defp accept_error_message(:invitation_not_found),
    do: "That invitation could not be found."

  defp accept_error_message(_other),
    do: "We couldn't accept that invitation."
end
