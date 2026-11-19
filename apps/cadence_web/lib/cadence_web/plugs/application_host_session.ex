defmodule CadenceWeb.Plugs.ApplicationHostSession do
  @moduledoc """
  The bridge's host session check. A non-GET call must carry (`x-cadence-poc-session`) a host
  session id this browser session was given by the legacy host or by the console's surface host;
  the plug assigns which (`:application_host_origin`, `:legacy_host | :console`).
  """

  import Plug.Conn

  alias CadenceWeb.ApplicationHostSessionState

  @session_key ApplicationHostSessionState.session_key()
  @origin_key :application_host_origin
  @session_header "x-cadence-poc-session"
  @problem_schema "cadence.application-host-problem.v1"

  def init(opts), do: opts

  def call(conn, _opts) do
    legacy_id = get_session(conn, @session_key)

    cond do
      conn.method == "GET" and is_binary(legacy_id) and legacy_id != "" ->
        assign(conn, @session_key, legacy_id)

      conn.method == "GET" ->
        issue_session(conn)

      true ->
        validate_request_session(conn)
    end
  end

  # A non-GET bridge call carries the host session id its catalog gave it: the legacy host's or
  # the console's. Which one tells the bridge the call's origin (set here, never by the client).
  defp validate_request_session(conn) do
    with [header_id] <- get_req_header(conn, @session_header),
         {:ok, origin} <- ApplicationHostSessionState.origin(conn, header_id) do
      conn
      |> assign(@session_key, header_id)
      |> assign(@origin_key, origin)
    else
      _other -> invalid_session(conn)
    end
  end

  defp issue_session(conn) do
    session_id = ApplicationHostSessionState.mint_session_id()

    conn
    |> put_session(@session_key, session_id)
    |> assign(@session_key, session_id)
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
