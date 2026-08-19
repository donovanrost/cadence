defmodule CadenceWeb.Plugs.FetchBrowserCurrentScope do
  @moduledoc false

  import Plug.Conn

  def init(opts), do: opts

  def call(conn, _opts) do
    case get_session(conn, :user_session_token) do
      session_token when is_binary(session_token) ->
        case Cadence.Auth.authenticate_browser_session(session_token,
               current_organization_id: get_session(conn, :current_organization_id),
               admin_mode?:
                 CadenceWeb.AdminMode.active?(get_session(conn, :admin_mode_expires_at))
             ) do
          {:ok, current_scope} ->
            conn
            |> sync_current_organization(current_scope.organization_id)
            |> assign(:current_scope, current_scope)

          {:error, _reason} ->
            conn
            |> delete_session(:user_session_token)
            |> delete_session(:current_organization_id)
            |> delete_session(:admin_mode_expires_at)
            |> assign(:current_scope, nil)
        end

      _other ->
        assign(conn, :current_scope, nil)
    end
  end

  defp sync_current_organization(conn, nil) do
    delete_session(conn, :current_organization_id)
  end

  defp sync_current_organization(conn, organization_id) when is_binary(organization_id) do
    case get_session(conn, :current_organization_id) do
      ^organization_id -> conn
      _other -> put_session(conn, :current_organization_id, organization_id)
    end
  end
end
