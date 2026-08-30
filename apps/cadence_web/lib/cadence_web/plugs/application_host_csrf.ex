defmodule CadenceWeb.Plugs.ApplicationHostCSRF do
  @moduledoc false

  import Plug.Conn

  @problem_schema "cadence.application-host-problem.v1"

  def init(opts), do: opts

  def call(conn, opts) do
    Phoenix.Controller.protect_from_forgery(conn, opts)
  rescue
    Plug.CSRFProtection.InvalidCSRFTokenError ->
      conn
      |> put_status(:forbidden)
      |> Phoenix.Controller.json(%{
        "schema" => @problem_schema,
        "code" => "invalid_csrf",
        "message" => "The request CSRF token is invalid."
      })
      |> halt()
  end
end
