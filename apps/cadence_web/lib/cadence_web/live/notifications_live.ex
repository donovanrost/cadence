defmodule CadenceWeb.NotificationsLive do
  @moduledoc false
  use CadenceWeb, :live_view

  alias Cadence.Notifications.Notification

  @impl true
  def mount(_params, _session, socket) do
    user_id = socket.assigns.current_scope.user.user_id

    {:ok,
     socket
     |> assign(:page_title, "Notifications")
     |> assign(:notifications, Cadence.list_notifications(user_id))}
  end

  @impl true
  def handle_event("accept_invitation", %{"notification_id" => id}, socket) do
    user_id = socket.assigns.current_scope.user.user_id

    with {:ok, notification} <- Cadence.fetch_notification(id),
         true <- notification.user_id == user_id,
         :organization_invitation <- notification.kind,
         invitation_id when is_binary(invitation_id) <-
           Map.get(notification.metadata, "organization_invitation_id") do
      case Cadence.accept_invitation_as_user(user_id, invitation_id) do
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
           |> assign(:notifications, Cadence.list_notifications(user_id))}
      end
    else
      _other ->
        {:noreply,
         socket
         |> put_flash(:error, "That notification is no longer available.")
         |> assign(:notifications, Cadence.list_notifications(user_id))}
    end
  end

  @impl true
  def handle_event("mark_read", %{"notification_id" => id}, socket) do
    user_id = socket.assigns.current_scope.user.user_id

    case Cadence.mark_notification_read(id, user_id) do
      {:ok, updated} ->
        {:noreply,
         socket
         |> assign(:notifications, replace_in_list(socket.assigns.notifications, updated))}

      {:error, _reason} ->
        {:noreply, socket}
    end
  end

  @impl true
  def handle_info({:notification_created, %Notification{} = n}, socket) do
    {:noreply, assign(socket, :notifications, [n | socket.assigns.notifications])}
  end

  @impl true
  def handle_info({:notification_updated, %Notification{} = n}, socket) do
    {:noreply, assign(socket, :notifications, replace_in_list(socket.assigns.notifications, n))}
  end

  @impl true
  def handle_info({:invitation_accepted, _invitation}, socket) do
    user_id = socket.assigns.current_scope.user.user_id
    # After accept_invitation_as_user marks related notifications read, the bell hook
    # already fired; just refresh the full list from DB so stale rows disappear.
    {:noreply, assign(socket, :notifications, Cadence.list_notifications(user_id))}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="space-y-4 max-w-2xl mx-auto">
      <.page_header
        title="Notifications"
        subtitle="Invitations, access grants, and system notices."
      />

      <%= if @notifications == [] do %>
        <.empty_state icon="hero-bell" title="No notifications" description="All caught up." />
      <% else %>
        <div class="space-y-2">
          <.notification_card :for={n <- @notifications} notification={n} />
        </div>
      <% end %>
    </div>
    """
  end

  attr :notification, Notification, required: true

  defp notification_card(assigns) do
    ~H"""
    <%!-- Bespoke card: read/unread state drives the left accent, beyond <.card> accents. --%>
    <div class={[
      "card bg-base-200 border-l-2 transition-all",
      if(is_nil(@notification.read_at), do: "border-l-primary", else: "border-l-base-300")
    ]}>
      <div class="card-body p-4 flex flex-row items-start gap-4">
        <div class="flex-1 min-w-0">
          <p class={[
            "text-sm",
            if(is_nil(@notification.read_at),
              do: "font-bold text-base-content",
              else: "text-base-content/70"
            )
          ]}>
            {@notification.title}
          </p>
          <p :if={@notification.body} class="mt-1 text-xs text-base-content/60">
            {@notification.body}
          </p>
        </div>
        <div class="flex items-center gap-2 flex-shrink-0">
          <.notification_actions notification={@notification} />
        </div>
      </div>
    </div>
    """
  end

  attr :notification, Notification, required: true

  defp notification_actions(assigns) do
    ~H"""
    <%= case @notification.kind do %>
      <% :organization_invitation -> %>
        <.button
          :if={is_nil(@notification.read_at)}
          size={:xs}
          phx-click="accept_invitation"
          phx-value-notification_id={@notification.notification_id}
        >
          Accept
        </.button>
        <span
          :if={@notification.read_at}
          class="text-xs text-base-content/40 uppercase tracking-wide"
        >
          Accepted
        </span>
      <% _ -> %>
        <.button
          :if={is_nil(@notification.read_at)}
          variant={:ghost}
          size={:xs}
          phx-click="mark_read"
          phx-value-notification_id={@notification.notification_id}
        >
          Mark read
        </.button>
    <% end %>
    """
  end

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
