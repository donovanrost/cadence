defmodule CadenceWeb.Console.NotFoundController do
  @moduledoc "JSON 404 for unknown `/api/console/v1` routes (instead of the HTML error page)."

  use CadenceWeb, :controller

  alias CadenceWeb.Console.Problem

  def show(conn, _params), do: Problem.respond(conn, :not_found)
end
