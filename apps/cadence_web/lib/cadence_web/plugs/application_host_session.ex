defmodule CadenceWeb.Plugs.ApplicationHostSession do
  @moduledoc false

  import Plug.Conn

  @session_key :application_host_session_id
  @session_header "x-cadence-poc-session"
  @problem_schema "cadence.application-host-problem.v1"

  def init(opts), do: opts

  def call(conn, _opts) do
    case get_session(conn, @session_key) do
      session_id when is_binary(session_id) and session_id != "" ->
        validate_request_session(conn, session_id)

      _other ->
        if conn.method == "GET" do
          issue_session(conn)
        else
          invalid_session(conn)
        end
    end
  end

  defp validate_request_session(%Plug.Conn{method: "GET"} = conn, session_id) do
    assign(conn, @session_key, session_id)
  end

  defp validate_request_session(conn, session_id) do
    case get_req_header(conn, @session_header) do
      [^session_id] -> assign(conn, @session_key, session_id)
      _other -> invalid_session(conn)
    end
  end

  defp issue_session(conn) do
    session_id =
      32
      |> :crypto.strong_rand_bytes()
      |> Base.url_encode64(padding: false)

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
