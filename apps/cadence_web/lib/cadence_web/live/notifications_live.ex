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
      <.vue
        id="notifications-page-component"
        v-component="NotificationsPage"
        presentation={@notifications_page_presentation}
        v-on:accept-invitation={JS.push("accept_invitation")}
        v-on:mark-read={JS.push("mark_read")}
        v-ssr={false}
        class="contents"
      />
    </Layouts.app>
    """
  end

  @doc false
  def federated_presentation(%Cadence.Auth.Scope{user: %{user_id: user_id}}) do
    Cadence.Notifications.list_notifications(user_id)
    |> Enum.map(&notification_row/1)
    |> page_presentation()
  end

  @doc false
  def presentation_attrs(attrs) when is_map(attrs) do
    Enum.reduce(attrs, %{}, fn
      {_name, value}, rendered when value in [nil, false] ->
        rendered

      {name, true}, rendered ->
        Map.put(rendered, name, "")

      {name, value}, rendered ->
        Map.put(rendered, name, to_string(value))
    end)
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
    notification_rows = Enum.map(notifications, &notification_row/1)

    socket
    |> assign(:notifications, notifications)
    |> assign(:notifications_page_presentation, page_presentation(notification_rows))
  end

  defp page_presentation(notification_rows) do
    notifications_empty? = notification_rows == []

    %{
      "root" => %{
        "attrs" =>
          presentation_attrs(%{
            "id" => "notifications-page",
            "class" => "space-y-4 max-w-2xl mx-auto"
          })
      },
      "header" => %{
        "attrs" => presentation_attrs(%{"class" => "border-b border-primary/20 pb-4"}),
        "body" => %{"attrs" => presentation_attrs(%{"class" => false})},
        "content" => %{"attrs" => presentation_attrs(%{})},
        "title" => %{
          "attrs" =>
            presentation_attrs(%{
              "class" => "mt-2 text-2xl font-bold text-base-content tracking-tight"
            }),
          "text" => "Notifications"
        },
        "subtitle" => %{
          "attrs" =>
            presentation_attrs(%{
              "class" => "mt-1 max-w-3xl text-sm text-base-content/70"
            }),
          "text" => "Invitations, access grants, and system notices."
        }
      },
      "empty_state" => empty_state_presentation(notifications_empty?),
      "panel" => panel_presentation(notifications_empty?, notification_rows)
    }
  end

  defp empty_state_presentation(true) do
    %{
      "wrapper" => %{
        "attrs" => presentation_attrs(%{"id" => "notifications-empty-state"})
      },
      "body" => %{
        "attrs" =>
          presentation_attrs(%{
            "class" =>
              "rounded border border-dashed border-base-300/60 bg-base-100/30 p-8 text-center"
          })
      },
      "icon" => %{
        "attrs" =>
          presentation_attrs(%{
            "class" => "hero-bell mx-auto h-10 w-10 text-base-content/30 block"
          })
      },
      "title" => %{
        "attrs" => presentation_attrs(%{"class" => "hud-label mt-3"}),
        "text" => "No notifications"
      },
      "description" => %{
        "attrs" =>
          presentation_attrs(%{
            "class" => "mt-2 max-w-md mx-auto text-sm text-base-content/70"
          }),
        "text" => "All caught up."
      }
    }
  end

  defp empty_state_presentation(false), do: nil

  defp panel_presentation(false, notification_rows) do
    %{
      "attrs" => presentation_attrs(%{"id" => "notifications-panel-component"}),
      "notifications" => notification_rows
    }
  end

  defp panel_presentation(true, _notification_rows), do: nil

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
