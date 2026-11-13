defmodule CadenceWeb.ApplicationHostSessionState do
  @moduledoc """
  The application-host bridge's per-browser-session state, shared by the bridge
  (`CadenceWeb.Plugs.ApplicationHostSession`, `ApplicationHostController`) and the console's
  surface host (§11 L9), so both mint and pin it the same way:

  - the host session id (`x-cadence-poc-session` on non-GET bridge calls), one per cookie
    session;
  - the pinned host scopes (§11 L19b): the scope document and mission of each catalog this
    session loaded, the 16 most recent, as digests (the cookie stays small). The bridge's
    query and actions must name one of them, so surfaces at several scopes stay open at once;
    a scope this session never loaded (or one pushed out) still gets `host_session_mismatch`.
  """

  import Plug.Conn

  @session_key :application_host_session_id
  @host_context_key :application_host_context
  @host_mission_key :application_host_mission_id
  @scopes_key :application_host_scopes
  @max_scopes 16

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

  @doc "Pins a host scope the bridge's query and actions may name (the most recent first)."
  @spec pin_scope(Plug.Conn.t(), map(), binary() | nil) :: Plug.Conn.t()
  def pin_scope(conn, scope_document, mission_id) do
    digest = digest(scope_document, mission_id)
    pinned = conn |> pinned() |> List.delete(digest)

    conn
    # The single-scope keys before L19b.
    |> delete_session(@host_context_key)
    |> delete_session(@host_mission_key)
    |> put_session(@scopes_key, Enum.take([digest | pinned], @max_scopes))
  end

  @doc "Whether this browser session loaded a catalog at the scope (and mission)."
  @spec pinned?(Plug.Conn.t(), map(), binary() | nil) :: boolean()
  def pinned?(conn, scope_document, mission_id),
    do: digest(scope_document, mission_id) in pinned(conn)

  defp pinned(conn) do
    case get_session(conn, @scopes_key) do
      list when is_list(list) -> Enum.filter(list, &is_binary/1)
      _none -> []
    end
  end

  defp digest(scope_document, mission_id),
    do:
      :sha256
      |> :crypto.hash(:erlang.term_to_binary({scope_document, mission_id}, [:deterministic]))
      |> Base.url_encode64(padding: false)
end
