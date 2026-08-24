defmodule CadenceWeb.NoOrganizationController do
  use CadenceWeb, :controller

  import Phoenix.LiveView.Controller, only: [live_render: 3]

  alias CadenceWeb.NoOrganizationLive.Presentation

  def show(conn, _params) do
    pending_invitations_count = count_pending_invitations(conn.assigns[:current_scope])

    conn
    |> put_layout(html: {CadenceWeb.Layouts, :auth})
    |> live_render(CadenceWeb.NoOrganizationLive,
      session: live_session(conn, Presentation.build(pending_invitations_count)),
      container: {:div, class: "contents"}
    )
  end

  defp count_pending_invitations(%Cadence.Auth.Scope{user: %{user_id: user_id}})
       when is_binary(user_id) do
    user_id
    |> Cadence.Notifications.list_notifications(only_unread: true)
    |> Enum.count(&(&1.kind == :organization_invitation))
  end

  defp count_pending_invitations(_other), do: 0

  defp live_session(conn, presentation) do
    %{
      "admin_mode_expires_at" => get_session(conn, :admin_mode_expires_at),
      "current_organization_id" => get_session(conn, :current_organization_id),
      "user_session_token" => get_session(conn, :user_session_token),
      "presentation" => presentation
    }
  end
end
