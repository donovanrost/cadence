defmodule Cadence.Reads.Notifications.Inbox do
  @moduledoc "Recipient-scoped notification facts for the host account inbox."
  alias Cadence.{Accounts, Notifications}
  alias Cadence.Notifications.Recipient
  @keys ~w(unread before_at before_id)

  def load(scope, params) when is_map(params) do
    with {:ok, user} <- Recipient.authorize(scope),
         {:ok, query, opts} <- query(params) do
      page = Notifications.page_for_user(user.user_id, opts)
      ids = Enum.map(page.entries, &invitation_id/1)
      invitations = Accounts.invitation_statuses_for_user(user, ids)
      now = DateTime.utc_now()

      {:ok,
       %{
         "version" => 1,
         "user_id" => user.user_id,
         "observed_at" => DateTime.to_iso8601(now),
         "query" => query,
         "limit" => 50,
         "notifications" => Enum.map(page.entries, &row(&1, invitations, user.user_id, now)),
         "next_cursor" => cursor_dto(page.next_cursor)
       }}
    end
  end

  def load(_, _), do: {:error, :unavailable}

  def query(params) when is_map(params) do
    with true <-
           Enum.all?(params, fn {k, v} -> k in @keys and is_binary(v) and byte_size(v) <= 512 end),
         query = Map.new(@keys, &{&1, Map.get(params, &1, "")}),
         true <- query["unread"] in ["", "true"],
         {:ok, cursor} <- read_cursor(query) do
      {:ok, query, [unread: query["unread"] == "true", cursor: cursor]}
    else
      _ -> {:error, :invalid_query}
    end
  end

  def query(_), do: {:error, :invalid_query}

  defp read_cursor(%{"before_at" => "", "before_id" => ""}), do: {:ok, nil}

  defp read_cursor(%{"before_at" => at, "before_id" => id}) do
    with {:ok, time, _} <- DateTime.from_iso8601(at),
         true <- Regex.match?(~r/^[A-Za-z0-9][A-Za-z0-9_.:-]{0,511}$/, id) do
      {:ok, %{at: time, id: id}}
    else
      _ -> {:error, :invalid_cursor}
    end
  end

  defp cursor_dto(nil), do: nil
  defp cursor_dto(%{at: at, id: id}), do: %{"at" => DateTime.to_iso8601(at), "id" => id}

  defp row(n, invitations, user_id, now) do
    %{
      "id" => n.notification_id,
      "kind" => to_string(n.kind),
      "title" => n.title,
      "body" => n.body,
      "created_at" => DateTime.to_iso8601(n.inserted_at),
      "read_at" => timestamp(n.read_at),
      "invitation_status" => invitation_status(n, invitations, user_id, now)
    }
  end

  defp invitation_id(%{kind: :organization_invitation, metadata: metadata}) when is_map(metadata),
    do: Map.get(metadata, "organization_invitation_id")

  defp invitation_id(_), do: nil

  defp invitation_status(%{kind: :organization_invitation} = n, invitations, user_id, now) do
    case Map.get(invitations, invitation_id(n)) do
      %{status: "pending", expires_at: expires_at} ->
        if DateTime.compare(expires_at, now) == :gt, do: "pending", else: "expired"

      %{status: "accepted", accepted_by_user_id: ^user_id} ->
        "accepted"

      %{status: status} when status in ["revoked", "expired"] ->
        status

      _ ->
        "unavailable"
    end
  end

  defp invitation_status(_, _, _, _), do: "none"
  defp timestamp(nil), do: nil
  defp timestamp(at), do: DateTime.to_iso8601(at)
end
