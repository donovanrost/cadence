defmodule Cadence.Applications.OrganizationAdminProviders.Notifications do
  @moduledoc false

  alias Cadence.Notifications.Notification

  @spec presentation(Cadence.Auth.Scope.t()) :: map()
  def presentation(%Cadence.Auth.Scope{user: %{user_id: user_id}}) do
    Cadence.Notifications.list_notifications(user_id)
    |> Enum.map(&notification_row/1)
    |> page_presentation()
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
        "content" => %{"attrs" => %{}},
        "title" => %{
          "attrs" =>
            presentation_attrs(%{
              "class" => "mt-2 text-2xl font-bold text-base-content tracking-tight"
            }),
          "text" => "Notifications"
        },
        "subtitle" => %{
          "attrs" =>
            presentation_attrs(%{"class" => "mt-1 max-w-3xl text-sm text-base-content/70"}),
          "text" => "Invitations, access grants, and system notices."
        }
      },
      "empty_state" => empty_state_presentation(notifications_empty?),
      "panel" => panel_presentation(notifications_empty?, notification_rows)
    }
  end

  defp empty_state_presentation(true) do
    %{
      "wrapper" => %{"attrs" => presentation_attrs(%{"id" => "notifications-empty-state"})},
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
          presentation_attrs(%{"class" => "mt-2 max-w-md mx-auto text-sm text-base-content/70"}),
        "text" => "All caught up."
      }
    }
  end

  defp empty_state_presentation(false), do: nil

  defp panel_presentation(false, notification_rows),
    do: %{
      "attrs" => presentation_attrs(%{"id" => "notifications-panel-component"}),
      "notifications" => notification_rows
    }

  defp panel_presentation(true, _notification_rows), do: nil

  defp notification_row(%Notification{} = notification) do
    {action, action_label} = notification_action(notification)

    %{
      id: "notification-#{notification.notification_id}",
      notification_id: notification.notification_id,
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

  defp notification_action(%Notification{read_at: nil}), do: {"mark_read", "Mark read"}
  defp notification_action(%Notification{}), do: {nil, nil}

  defp notification_state_label(%Notification{
         kind: :organization_invitation,
         read_at: %DateTime{}
       }),
       do: "Accepted"

  defp notification_state_label(%Notification{}), do: nil

  defp presentation_attrs(attrs) do
    Enum.reduce(attrs, %{}, fn
      {_name, value}, rendered when value in [nil, false] -> rendered
      {name, true}, rendered -> Map.put(rendered, name, "")
      {name, value}, rendered -> Map.put(rendered, name, to_string(value))
    end)
  end
end
