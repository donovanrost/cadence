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
    |> redirect(to: sign_in_path(conn.request_path))
    |> halt()
  end

  # The console bounces straight to its own sign-in (one hop; the stored return target still
  # applies). Legacy pages keep /sign-in, which redirects there too (L5).
  defp sign_in_path("/console" <> _rest), do: "/console/sign-in"
  defp sign_in_path(_legacy), do: "/sign-in"

  defp maybe_store_return_to(%Plug.Conn{method: "GET"} = conn) do
    if application_host_json_path?(conn.request_path) do
      conn
    else
      put_session(conn, :user_return_to, requested_path(conn))
    end
  end

  defp maybe_store_return_to(conn), do: conn

  defp requested_path(%Plug.Conn{query_string: ""} = conn), do: conn.request_path
  defp requested_path(conn), do: conn.request_path <> "?" <> conn.query_string

  defp application_host_json_path?(request_path) do
    String.starts_with?(request_path, [
      "/api/cadence/application-host/",
      "/api/cadence/contact-workspace/"
    ])
  end
end
