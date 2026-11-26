defmodule CadenceWeb.ApplicationHostSessionState do
  @moduledoc """
  The application-host bridge's per-browser-session state, minted by the console's surface host
  (§11 L9) and checked by the bridge (`CadenceWeb.Plugs.ApplicationHostSession`,
  `ApplicationHostController`):

  - the host session id (`x-cadence-poc-session` on bridge calls), one per cookie session;
  - the pinned host scopes (§11 L19b): the scope document and mission of each catalog this
    session loaded, the 16 most recent, as digests (the cookie stays small). The bridge's
    query and actions must name one of them, so surfaces at several scopes stay open at once;
    a scope this session never loaded (or one pushed out) still gets `host_session_mismatch`.
  """

  import Plug.Conn

  @console_session_key :application_host_console_session_id
  @scopes_key :application_host_scopes
  @max_scopes 16

  @doc "A new random host session id."
  @spec mint_session_id() :: binary()
  def mint_session_id, do: 32 |> :crypto.strong_rand_bytes() |> Base.url_encode64(padding: false)

  @doc "The browser session's console host session id (the console's surface host), minted if none."
  @spec ensure_console_session_id(Plug.Conn.t()) :: {Plug.Conn.t(), binary()}
  def ensure_console_session_id(conn) do
    case get_session(conn, @console_session_key) do
      id when is_binary(id) and id != "" ->
        {conn, id}

      _none ->
        id = mint_session_id()
        {put_session(conn, @console_session_key, id), id}
    end
  end

  @doc "Whether the id is this browser session's console host session id."
  @spec console_session?(Plug.Conn.t(), binary() | nil) :: boolean()
  def console_session?(conn, header_id) when is_binary(header_id) and header_id != "",
    do: secure_equal?(header_id, get_session(conn, @console_session_key))

  def console_session?(_conn, _header_id), do: false

  defp secure_equal?(left, right) when is_binary(left) and is_binary(right),
    do: Plug.Crypto.secure_compare(left, right)

  defp secure_equal?(_left, _right), do: false

  @doc "Pins a host scope the bridge's query and actions may name (the most recent first)."
  @spec pin_scope(Plug.Conn.t(), map(), binary() | nil) :: Plug.Conn.t()
  def pin_scope(conn, scope_document, mission_id) do
    digest = digest(scope_document, mission_id)
    pinned = conn |> pinned() |> List.delete(digest)

    put_session(conn, @scopes_key, Enum.take([digest | pinned], @max_scopes))
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
