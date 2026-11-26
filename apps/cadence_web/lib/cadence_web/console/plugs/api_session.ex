defmodule CadenceWeb.Console.Plugs.APISession do
  @moduledoc """
  Authentication for the console API (`/api/console/v1`, the one public API; #747, #753).

  - **A service identity** sends `Authorization: Bearer <token>`. That request is authenticated by
    the token alone: no CSRF, and the session cookie is ignored. An invalid token is 401 and never
    falls back to the cookie. The action must be listed in `CadenceWeb.Console.ServiceAccess`,
    otherwise 403 `service_not_allowed`.
  - **A person** (the browser, and any script or seed acting as a person) uses the session cookie,
    with CSRF enforced on unsafe methods (`x-csrf-token`). There are no personal bearer tokens.

  Failures are JSON problems, never redirects or HTML, so the SPA can react to them.
  """

  import Plug.Conn

  alias CadenceWeb.Console.{Access, Problem, ServiceAccess}

  def init(opts), do: opts

  def call(conn, _opts) do
    case get_req_header(conn, "authorization") do
      [] -> session(conn)
      ["Bearer " <> token] -> bearer(conn, String.trim(token))
      _other -> Problem.respond(conn, :unauthenticated)
    end
  end

  defp bearer(conn, token) do
    with {:ok, credentials} <- Access.credentials_from_bearer(token),
         {:ok, scope} <- Access.authenticate(credentials),
         :ok <- service_access(conn) do
      conn
      |> assign(:console_credentials, credentials)
      |> assign(:current_scope, scope)
    else
      {:error, {:service_not_allowed, action}} ->
        Problem.respond(conn, :service_not_allowed, %{action: action})

      {:error, reason} ->
        Problem.respond(conn, reason)
    end
  end

  defp service_access(conn) do
    case ServiceAccess.check(conn) do
      :ok -> :ok
      {:error, action} -> {:error, {:service_not_allowed, action}}
    end
  end

  defp session(conn) do
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
