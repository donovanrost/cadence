defmodule CadenceWeb.Console.SPAController do
  @moduledoc """
  Serves the console SPA document for every `/console/*` path. Authentication
  is enforced by the router pipeline (unauthenticated GETs redirect to
  `/console/sign-in` and return here after signing in).
  """

  use CadenceWeb, :controller

  alias CadenceWeb.Console.Shell

  @doc "The site root opens the console, which picks the organization and mission."
  def root(conn, _params), do: redirect(conn, to: "/console")

  def index(conn, _params) do
    conn = put_resp_header(conn, "cache-control", "no-store")

    case Shell.render(get_csrf_token()) do
      {:ok, html} ->
        conn
        |> put_resp_content_type("text/html")
        |> send_resp(200, html)

      {:error, {:unavailable, message}} ->
        conn
        |> put_resp_content_type("text/plain")
        |> send_resp(503, message)
    end
  end
end
