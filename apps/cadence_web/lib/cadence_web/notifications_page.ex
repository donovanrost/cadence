defmodule CadenceWeb.NotificationsPage do
  @moduledoc "Core account inbox placement and recipient-pinned action boundary."
  import Phoenix.Component
  alias Cadence.Notifications.Actions
  alias Cadence.Reads.Notifications.Inbox

  def prepare(socket, %{route: "/notifications", params: params}, path) do
    scope = socket.assigns.current_scope
    user_id = scope.user.user_id

    session =
      case socket.assigns[:notifications_session] do
        %{path: ^path, user_id: ^user_id} = existing -> existing
        _ -> %{path: path, user_id: user_id, token: Ecto.UUID.generate()}
      end

    envelope = %{version: 1, page: "notifications", user_id: user_id, action_token: session.token}

    page =
      case read(scope, Map.take(params, ~w(unread before_at before_id))) do
        {:ok, data} -> Map.merge(envelope, %{status: "ready", data: data})
        _ -> Map.put(envelope, :status, "unavailable")
      end

    assign(socket, notifications_page: page, notifications_session: session)
  end

  def prepare(socket, _info, _path),
    do: assign(socket, notifications_page: nil, notifications_session: nil)

  def matches?(socket, token) when is_binary(token) do
    case socket.assigns[:notifications_session] do
      %{token: ^token, path: path, user_id: user_id} ->
        path == socket.assigns.host_path and user_id == socket.assigns.current_scope.user.user_id

      _ ->
        false
    end
  end

  def matches?(_, _), do: false

  def action(socket, event, input) do
    case Actions.execute(socket.assigns.current_scope, event, input) do
      {:ok, data} -> %{status: "ok", data: data}
      {:error, _} -> %{status: "unavailable"}
    end
  end

  defp read(scope, params) do
    Inbox.load(scope, params)
  rescue
    _ -> {:error, :unavailable}
  end
end
