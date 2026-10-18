defmodule CadenceWeb.NoOrganizationController do
  use CadenceWeb, :controller

  import Phoenix.LiveView.Controller, only: [live_render: 3]

  def show(conn, _params) do
    pending_invitations_count = count_pending_invitations(conn.assigns[:current_scope])

    conn
    |> put_layout(false)
    |> live_render(CadenceWeb.NoOrganizationLive,
      session:
        live_session(conn, %{
          version: 1,
          pending_invitations_count: pending_invitations_count,
          csrf_token: Plug.CSRFProtection.get_csrf_token()
        }),
      container: {:div, class: "contents"}
    )
  end

  defp count_pending_invitations(%Cadence.Auth.Scope{user: %{user_id: user_id}})
       when is_binary(user_id) do
    Cadence.Accounts.count_pending_invitations_for_user(user_id)
  end

  defp count_pending_invitations(_other), do: 0

  defp live_session(conn, page) do
    %{
      "admin_mode_expires_at" => get_session(conn, :admin_mode_expires_at),
      "current_organization_id" => get_session(conn, :current_organization_id),
      "user_session_token" => get_session(conn, :user_session_token),
      "page" => page
    }
  end
end
