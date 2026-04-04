defmodule CadenceWeb.Plugs.FetchBrowserCurrentScope do
  @moduledoc false

  import Plug.Conn

  def init(opts), do: opts

  def call(conn, _opts) do
    case get_session(conn, :user_session_token) do
      session_token when is_binary(session_token) ->
        case Cadence.authenticate_api_token(session_token) do
          {:ok, current_scope} ->
            assign(conn, :current_scope, current_scope)

          {:error, _reason} ->
            conn
            |> delete_session(:user_session_token)
            |> assign(:current_scope, nil)
        end

      _other ->
        assign(conn, :current_scope, nil)
    end
  end
end
