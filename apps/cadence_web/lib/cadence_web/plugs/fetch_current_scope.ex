defmodule CadenceWeb.Plugs.FetchCurrentScope do
  @moduledoc false

  import Plug.Conn

  def init(opts), do: opts

  def call(conn, _opts) do
    case get_req_header(conn, "authorization") do
      [] ->
        assign(conn, :current_scope, nil)

      ["Bearer " <> api_token] ->
        case Cadence.Auth.authenticate_api_token(api_token) do
          {:ok, current_scope} ->
            assign(conn, :current_scope, current_scope)

          {:error, _reason} ->
            unauthorized(conn)
        end

      _other ->
        unauthorized(conn)
    end
  end

  defp unauthorized(conn) do
    conn
    |> put_status(:unauthorized)
    |> Phoenix.Controller.json(%{errors: [%{reason: "unauthenticated"}]})
    |> halt()
  end
end
