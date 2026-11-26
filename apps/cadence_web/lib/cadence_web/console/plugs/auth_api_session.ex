defmodule CadenceWeb.Console.Plugs.AuthAPISession do
  @moduledoc """
  Session handling for `/api/v1/auth` (L5: sign-in and invitation links), which work
  signed out. CSRF is enforced on unsafe methods exactly like the rest of the console API (the
  `x-csrf-token` header, from the page's `csrf-token` meta); a valid session is optional and, when
  present, assigns `current_scope` (otherwise `nil`).
  """

  import Plug.Conn

  alias CadenceWeb.Console.{Access, Problem}

  def init(opts), do: opts

  def call(conn, _opts) do
    case protect_from_forgery(conn) do
      {:ok, conn} -> assign(conn, :current_scope, scope(conn))
      {:error, reason} -> Problem.respond(conn, reason)
    end
  end

  defp scope(conn) do
    with {:ok, credentials} <- Access.credentials_from_session(get_session(conn)),
         {:ok, scope} <- Access.authenticate(credentials) do
      scope
    else
      _signed_out -> nil
    end
  end

  defp protect_from_forgery(conn) do
    {:ok, Plug.CSRFProtection.call(conn, Plug.CSRFProtection.init([]))}
  rescue
    Plug.CSRFProtection.InvalidCSRFTokenError -> {:error, :invalid_csrf}
  end
end
