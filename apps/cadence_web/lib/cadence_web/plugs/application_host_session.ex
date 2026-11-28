defmodule CadenceWeb.Plugs.ApplicationHostSession do
  @moduledoc """
  The bridge's host session check. Every bridge call must carry (`x-cadence-poc-session`) the
  host session id this browser session was given by the console's surface host.
  """

  import Plug.Conn

  alias CadenceWeb.ApplicationHostSessionState

  @session_header "x-cadence-poc-session"
  @problem_schema "cadence.application-host-problem.v1"

  def init(opts), do: opts

  def call(conn, _opts) do
    with [header_id] <- get_req_header(conn, @session_header),
         true <- ApplicationHostSessionState.console_session?(conn, header_id) do
      conn
    else
      _other -> invalid_session(conn)
    end
  end

  defp invalid_session(conn) do
    conn
    |> put_status(:unauthorized)
    |> Phoenix.Controller.json(%{
      "schema" => @problem_schema,
      "code" => "invalid_session",
      "message" => "The authenticated host session is invalid."
    })
    |> halt()
  end
end
