defmodule Cadence.Notifications.Actions do
  @moduledoc "Recipient-owned notification effects; invitation admission remains in Accounts."
  alias Cadence.{Accounts, Notifications}
  alias Cadence.Notifications.Recipient

  def execute(scope, action, %{"notification_id" => id} = input)
      when action in ["accept_invitation", "mark_notification_read"] and
             is_binary(id) and byte_size(id) in 1..512 and map_size(input) == 1 do
    with {:ok, user} <- Recipient.authorize(scope),
         {:ok, notification} <- Notifications.fetch_notification_for_user(user.user_id, id) do
      perform(action, user.user_id, notification)
    end
  end

  def execute(_, _, _), do: {:error, :invalid_input}

  defp perform("mark_notification_read", user_id, notification) do
    with {:ok, _} <- Notifications.mark_notification_read(notification.notification_id, user_id),
         do: {:ok, %{status: "read"}}
  end

  defp perform("accept_invitation", user_id, %{kind: :organization_invitation, metadata: metadata})
       when is_map(metadata) do
    case Map.get(metadata, "organization_invitation_id") do
      id when is_binary(id) ->
        with {:ok, _} <- Accounts.accept_invitation_as_user(user_id, id),
             do: {:ok, %{status: "accepted", navigate: "/"}}

      _ ->
        {:error, :unavailable}
    end
  end

  defp perform(_, _, _), do: {:error, :unavailable}
end
