defmodule CadenceWeb.ApplicationHostSessionState do
  @moduledoc """
  The application-host bridge's per-browser-session state, shared by the bridge
  (`CadenceWeb.Plugs.ApplicationHostSession`, `ApplicationHostController`) and the console's
  surface host (§11 L9), so both mint and pin it the same way:

  - the host session id (`x-cadence-poc-session` on non-GET bridge calls), one per cookie
    session;
  - the pinned host scope: the scope document and mission of the most recently loaded catalog.
    The bridge's query and actions must match it, so one scope at a time per browser session
    (a second scope re-pins; the other surface re-requests its catalog).
  """

  import Plug.Conn

  @session_key :application_host_session_id
  @host_context_key :application_host_context
  @host_mission_key :application_host_mission_id

  @spec session_key() :: atom()
  def session_key, do: @session_key

  @spec host_context_key() :: atom()
  def host_context_key, do: @host_context_key

  @spec host_mission_key() :: atom()
  def host_mission_key, do: @host_mission_key

  @doc "A new random host session id."
  @spec mint_session_id() :: binary()
  def mint_session_id, do: 32 |> :crypto.strong_rand_bytes() |> Base.url_encode64(padding: false)

  @doc "The browser session's host session id, minted and stored if it has none."
  @spec ensure_session_id(Plug.Conn.t()) :: {Plug.Conn.t(), binary()}
  def ensure_session_id(conn) do
    case get_session(conn, @session_key) do
      id when is_binary(id) and id != "" ->
        {conn, id}

      _none ->
        id = mint_session_id()
        {put_session(conn, @session_key, id), id}
    end
  end

  @doc "Pins the host scope the bridge's query and actions must match."
  @spec pin_scope(Plug.Conn.t(), map(), binary() | nil) :: Plug.Conn.t()
  def pin_scope(conn, scope_document, mission_id) do
    conn = put_session(conn, @host_context_key, scope_document)

    if is_binary(mission_id),
      do: put_session(conn, @host_mission_key, mission_id),
      else: delete_session(conn, @host_mission_key)
  end
end
