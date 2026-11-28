defmodule CadenceWeb.Console.AccountNoticeController do
  @moduledoc """
  The signed-in person's own notices (#709; contract session.md "Account: notices"): a page
  newest first, and Mark read by id. Only the kinds `Cadence.Notifications.listed_kinds/0` names
  (today `organization_access_granted`); `pending_invitations_count`'s sibling
  `unread_notices_count` on the session counts the same rows.

  A notice that doesn't exist, isn't the caller's or isn't a listed kind is `404
  notice_not_found`, the same answer either way, so ids don't leak.
  """

  use CadenceWeb, :controller

  alias Cadence.Notifications
  alias Cadence.Notifications.Notification
  alias CadenceWeb.Console.Problem

  def index(conn, params) do
    opts = [cursor: params["cursor"], limit: limit(params["limit"])]

    case Notifications.listed_page(user_id(conn), opts) do
      {:ok, %{entries: entries, next_cursor: next_cursor}} ->
        json(conn, %{
          data: %{notices: Enum.map(entries, &row/1)},
          meta: %{next_cursor: next_cursor}
        })

      {:error, :invalid_cursor} ->
        Problem.respond(conn, :invalid_params, %{cursor: "is not a valid cursor"})
    end
  end

  def read(conn, %{"notice_id" => id}) do
    case Notifications.mark_listed_read(user_id(conn), id) do
      {:ok, notice} -> json(conn, %{data: row(notice)})
      {:error, :not_found} -> Problem.respond(conn, :notice_not_found)
    end
  end

  # The console words a notice from its kind and these facts, never the stored title or body.
  defp row(%Notification{metadata: metadata} = n) do
    %{
      id: n.notification_id,
      kind: Atom.to_string(n.kind),
      organization: %{
        id: metadata["organization_id"],
        name: metadata["organization_display_name"]
      },
      role: metadata["membership_role"],
      created_at: n.inserted_at,
      read_at: n.read_at
    }
  end

  defp limit(value) when is_binary(value) do
    case Integer.parse(value) do
      {n, ""} -> n
      _other -> nil
    end
  end

  defp limit(_value), do: nil

  defp user_id(conn), do: conn.assigns.current_scope.user.user_id
end
