defmodule CadenceWeb.Plugs.FetchBrowserCurrentScope do
  @moduledoc false

  import Plug.Conn

  def init(opts), do: opts

  def call(conn, _opts) do
    CadenceWeb.ScopeLoader.allow_browser_test_sandbox_owner(
      get_session(conn, :browser_test_sandbox_owner_key)
    )

    case get_session(conn, :user_session_token) do
      session_token when is_binary(session_token) ->
        case Cadence.authenticate_api_token(session_token,
               current_organization_id: get_session(conn, :current_organization_id)
             ) do
          {:ok, current_scope} ->
            conn
            |> sync_current_organization(current_scope.organization_id)
            |> assign(:current_scope, current_scope)

          {:error, _reason} ->
            conn
            |> delete_session(:user_session_token)
            |> delete_session(:current_organization_id)
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
