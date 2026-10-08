defmodule CadenceWeb.Plugs.ApplicationHostCSRF do
  @moduledoc false

  import Plug.Conn

  @problem_schema "cadence.application-host-problem.v1"

  def init(opts), do: opts

  def call(conn, opts) do
    if json_browser_request?(conn) do
      conn
      |> Phoenix.Controller.protect_from_forgery(opts)
      |> put_private(:plug_skip_csrf_protection, true)
    else
      conn
    end
  rescue
    Plug.CSRFProtection.InvalidCSRFTokenError ->
      conn
      |> put_status(:forbidden)
      |> Phoenix.Controller.json(problem(conn))
      |> halt()
  end

  defp problem(%{request_path: "/api/cadence/contact-workspace/v1/" <> _}) do
    %{"code" => "invalid_csrf"}
  end

  defp problem(_conn) do
    %{
      "schema" => @problem_schema,
      "code" => "invalid_csrf",
      "message" => "The request CSRF token is invalid."
    }
  end

  defp json_browser_request?(%Plug.Conn{request_path: request_path}) do
    String.starts_with?(request_path, [
      "/api/cadence/application-host/v1/",
      "/api/cadence/contact-workspace/v1/"
    ])
  end
end
