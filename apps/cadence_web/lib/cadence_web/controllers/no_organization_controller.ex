defmodule CadenceWeb.NoOrganizationController do
  use CadenceWeb, :controller

  def show(conn, _params) do
    pending_invitations_count = count_pending_invitations(conn.assigns[:current_scope])

    conn
    |> put_layout(html: {CadenceWeb.Layouts, :auth})
    |> assign(:pending_invitations_count, pending_invitations_count)
    |> render(:show)
  end

  defp count_pending_invitations(%Cadence.Auth.Scope{user: %{user_id: user_id}})
       when is_binary(user_id) do
    user_id
    |> Cadence.Notifications.list_notifications(only_unread: true)
    |> Enum.count(&(&1.kind == :organization_invitation))
  end

  defp count_pending_invitations(_other), do: 0
end
