defmodule Cadence.Notifications.EmailWorker do
  @moduledoc """
  Oban worker for sending immediate notification emails.
  """

  use Oban.Worker, queue: :notifications, max_attempts: 3

  alias Cadence.Accounts.UserNotifier
  alias Cadence.Notifications
  alias Cadence.Notifications.Notification
  alias Cadence.Repo

  @impl Oban.Worker
  def perform(%Oban.Job{args: %{"notification_id" => notification_id}}) do
    notification = Notifications.get_notification(notification_id)

    if notification && is_nil(notification.email_sent_at) do
      case UserNotifier.deliver_notification(notification) do
        {:ok, _email} ->
          notification
          |> Notification.mark_email_sent_changeset()
          |> Repo.update()

          :ok

        {:error, reason} ->
          {:error, reason}
      end
    else
      :ok
    end
  end
end
