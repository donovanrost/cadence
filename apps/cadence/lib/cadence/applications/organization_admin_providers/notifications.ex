defmodule Cadence.Applications.OrganizationAdminProviders.Notifications do
  @moduledoc "Compatibility destination and recipient bell context; the host owns both presentations."
  def props(_scope), do: %{}

  def bell_props(%Cadence.Auth.Scope{user: %{user_id: user_id}}) do
    %{
      context: %{
        version: 1,
        user: %{user_id: user_id},
        unread_count: Cadence.Notifications.count_unread_notifications(user_id),
        notifications:
          Enum.map(Cadence.Notifications.list_notifications(user_id, limit: 5), fn n ->
            %{
              notification_id: n.notification_id,
              title: n.title,
              body: n.body,
              read_at: if(n.read_at, do: DateTime.to_iso8601(n.read_at), else: nil)
            }
          end)
      }
    }
  end
end
