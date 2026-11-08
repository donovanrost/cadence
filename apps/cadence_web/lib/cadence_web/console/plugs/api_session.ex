defmodule CadenceWeb.Console.Plugs.APISession do
  @moduledoc """
  Session authentication for `/api/console/v1`.

  Enforces CSRF on unsafe methods (token in the `x-csrf-token` header), then
  authenticates the browser session cookie. Failures are JSON problems, never
  redirects or HTML, so the SPA can react to them.
  """

  import Plug.Conn

  alias CadenceWeb.Console.Access
  alias CadenceWeb.Console.Problem

  def init(opts), do: opts

  def call(conn, _opts) do
    with {:ok, conn} <- protect_from_forgery(conn),
         {:ok, credentials} <- Access.credentials_from_session(get_session(conn)),
         {:ok, scope} <- Access.authenticate(credentials) do
      conn
      |> assign(:console_credentials, credentials)
      |> assign(:current_scope, scope)
    else
      {:error, reason} -> Problem.respond(conn, reason)
    end
  end

  defp protect_from_forgery(conn) do
    {:ok, Plug.CSRFProtection.call(conn, Plug.CSRFProtection.init([]))}
  rescue
    Plug.CSRFProtection.InvalidCSRFTokenError -> {:error, :invalid_csrf}
  end
end
