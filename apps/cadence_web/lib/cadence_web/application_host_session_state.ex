defmodule CadenceWeb.ApplicationHostSessionState do
  @moduledoc """
  The application-host bridge's per-browser-session state, shared by the bridge
  (`CadenceWeb.Plugs.ApplicationHostSession`, `ApplicationHostController`) and the console's
  surface host (§11 L9), so both mint and pin it the same way:

  - the host session id (`x-cadence-poc-session` on non-GET bridge calls), one per cookie
    session AND per minting host: the legacy application host and the console's surface host
    each mint their own, so the bridge knows which host a call came through
    (`ActionRequest.origin`, the save trail's `via`; set by the host, never the client);
  - the pinned host scopes (§11 L19b): the scope document and mission of each catalog this
    session loaded, the 16 most recent, as digests (the cookie stays small). The bridge's
    query and actions must name one of them, so surfaces at several scopes stay open at once;
    a scope this session never loaded (or one pushed out) still gets `host_session_mismatch`.
  """

  import Plug.Conn

  @session_key :application_host_session_id
  @console_session_key :application_host_console_session_id
  @host_context_key :application_host_context
  @host_mission_key :application_host_mission_id
  @scopes_key :application_host_scopes
  @max_scopes 16

  @spec session_key() :: atom()
  def session_key, do: @session_key

  @spec console_session_key() :: atom()
  def console_session_key, do: @console_session_key

  @spec host_context_key() :: atom()
  def host_context_key, do: @host_context_key

  @spec host_mission_key() :: atom()
  def host_mission_key, do: @host_mission_key

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

  @doc """
  Which host minted the session id a bridge call carries: `:legacy_host` or `:console`, or
  `:error` when it matches neither.
  """
  @spec origin(Plug.Conn.t(), binary() | nil) :: {:ok, :legacy_host | :console} | :error
  def origin(conn, header_id) when is_binary(header_id) and header_id != "" do
    cond do
      header_id == get_session(conn, @session_key) -> {:ok, :legacy_host}
      header_id == get_session(conn, @console_session_key) -> {:ok, :console}
      true -> :error
    end
  end

  def origin(_conn, _header_id), do: :error

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
