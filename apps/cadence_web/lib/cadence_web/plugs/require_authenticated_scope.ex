defmodule CadenceWeb.Plugs.RequireAuthenticatedScope do
  @moduledoc false

  import Plug.Conn
  import Phoenix.Controller

  def init(opts), do: opts

  def call(%Plug.Conn{assigns: %{current_scope: current_scope}} = conn, _opts)
      when not is_nil(current_scope),
      do: conn

  def call(conn, _opts) do
    conn
    |> maybe_store_return_to()
    |> redirect(to: "/sign-in")
    |> halt()
  end

  defp maybe_store_return_to(%Plug.Conn{method: "GET"} = conn) do
    put_session(conn, :user_return_to, requested_path(conn))
  end

  defp maybe_store_return_to(conn), do: conn

  defp requested_path(%Plug.Conn{query_string: ""} = conn), do: conn.request_path
  defp requested_path(conn), do: conn.request_path <> "?" <> conn.query_string
end
