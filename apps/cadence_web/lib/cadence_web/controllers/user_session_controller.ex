defmodule CadenceWeb.UserSessionController do
  use CadenceWeb, :controller

  alias Cadence.Auth.Scope

  def delete(conn, _params) do
    revoke_session_token(conn)

    conn
    |> renew_browser_session()
    |> put_flash(:info, "Session closed.")
    |> redirect(to: ~p"/sign-in")
  end

  def update(conn, %{"organization_id" => organization_id}) when is_binary(organization_id) do
    current_scope = conn.assigns.current_scope

    case authorize_organization_selection(current_scope, organization_id) do
      :ok ->
        conn
        |> put_session(:current_organization_id, organization_id)
        |> redirect(to: ~p"/")

      {:error, _reason} ->
        conn
        |> put_flash(:error, "You do not have access to that organization.")
        |> redirect(to: ~p"/")
    end
  end

  def update(conn, _params) do
    conn
    |> put_flash(:error, "Select a valid organization.")
    |> redirect(to: ~p"/")
  end

  defp authorize_organization_selection(%Scope{} = current_scope, organization_id) do
    if Scope.admin_mode?(current_scope) do
      case Cadence.Organizations.fetch_organization(organization_id) do
        {:ok, _organization} -> :ok
        {:error, reason} -> {:error, reason}
      end
    else
      case Cadence.Accounts.fetch_user_membership(current_scope.user.user_id, organization_id) do
        {:ok, _membership} -> :ok
        {:error, reason} -> {:error, reason}
      end
    end
  end

  defp revoke_session_token(conn) do
    case get_session(conn, :user_session_token) do
      session_token when is_binary(session_token) ->
        CadenceWeb.Endpoint.broadcast(
          CadenceWeb.ConsoleSocket.id_for_session_token(session_token),
          "disconnect",
          %{}
        )

        Cadence.Auth.revoke_user_session(session_token)

      _other ->
        :ok
    end
  end

  defp renew_browser_session(conn) do
    conn
    |> configure_session(renew: true)
    |> clear_session()
  end
end
