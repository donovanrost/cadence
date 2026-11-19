defmodule CadenceWeb.ConsoleSocket do
  @moduledoc """
  Session-authenticated socket for the console SPA, mounted at
  `/socket/console`.

  The client connects with `params: {_csrf_token}`; Phoenix only exposes the
  cookie session in `connect_info` when that token is valid, which (together
  with `check_origin`) prevents cross-site websocket hijacking. The socket id is
  derived from the browser session token so signing out can disconnect exactly
  that session's sockets.
  """

  use Phoenix.Socket

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
         console_session_id: session_id(credentials.session_token)
       )}
    else
      _unauthenticated -> :error
    end
  end

  def connect(_params, _socket, _connect_info), do: :error

  @impl true
  def id(socket), do: socket_id(socket.assigns.console_session_id)

  @doc "Socket id for a browser session token; broadcast `disconnect` to it on sign-out."
  @spec id_for_session_token(binary()) :: binary()
  def id_for_session_token(session_token) when is_binary(session_token),
    do: socket_id(session_id(session_token))

  defp socket_id(session_id), do: "console_session:" <> session_id

  defp session_id(session_token) do
    :sha256
    |> :crypto.hash(session_token)
    |> Base.url_encode64(padding: false)
  end
end
