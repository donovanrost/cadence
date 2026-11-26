defmodule CadenceWeb.ConsoleSocket do
  @moduledoc """
  Session-authenticated socket for the console SPA, mounted at
  `/socket`.

  The client connects with `params: {_csrf_token}`; Phoenix only exposes the
  cookie session in `connect_info` when that token is valid, which (together
  with `check_origin`) prevents cross-site websocket hijacking. The socket id is
  derived from the browser session token so signing out can disconnect exactly
  that session's sockets.
  """

  use Phoenix.Socket

  alias Cadence.Accounts.Token
  alias CadenceWeb.Console.Access

  channel("mission:*", CadenceWeb.Console.MissionChannel)
  channel("command_group:*", CadenceWeb.Console.CommandGroupChannel)
  channel("spacecraft:*", CadenceWeb.Console.SpacecraftChannel)
  channel("dashboard:*", CadenceWeb.Console.DashboardChannel)

  @impl true
  def connect(_params, socket, %{session: session}) do
    with {:ok, credentials} <- Access.credentials_from_session(session),
         {:ok, scope} <- Access.authenticate(credentials) do
      {:ok,
       assign(socket,
         console_credentials: credentials,
         user_id: scope.user.user_id,
         console_session_digest: Token.digest(credentials.session_token)
       )}
    else
      _unauthenticated -> :error
    end
  end

  def connect(_params, _socket, _connect_info), do: :error

  @impl true
  def id(socket), do: id_for_token_digest(socket.assigns.console_session_digest)

  @doc "Socket id for a browser session token; broadcast `disconnect` to it on sign-out."
  @spec id_for_session_token(binary()) :: binary()
  def id_for_session_token(session_token) when is_binary(session_token),
    do: id_for_token_digest(Token.digest(session_token))

  @doc """
  Socket id for a session by its stored token digest (`Cadence.Accounts.Token.digest/1`), the one
  derivation every socket id goes through. A session revoked from Account in another browser is
  known only by its digest (#876).
  """
  @spec id_for_token_digest(binary()) :: binary()
  def id_for_token_digest(token_digest) when is_binary(token_digest),
    do: "console_session:" <> token_digest

  @doc "Disconnects the live sockets of each session in `token_digests` (signed out elsewhere)."
  @spec disconnect_sessions([binary()]) :: :ok
  def disconnect_sessions(token_digests) when is_list(token_digests) do
    Enum.each(token_digests, fn digest ->
      CadenceWeb.Endpoint.broadcast(id_for_token_digest(digest), "disconnect", %{})
    end)
  end
end
