defmodule Cadence.Notifications.DigestWorker do
  @moduledoc """
  Oban worker for sending notification digest emails.

  Runs on a schedule to batch notifications into daily/weekly digests.
  """

  use Oban.Worker, queue: :notifications

  import Ecto.Query

  alias Cadence.Accounts
  alias Cadence.Accounts.UserNotifier
  alias Cadence.Notifications.{Notification, NotificationPreference}
  alias Cadence.Repo
  alias Cadence.Time, as: CadenceTime

  @impl Oban.Worker
  def perform(%Oban.Job{args: %{"period" => period}}) do
    period_atom = String.to_existing_atom(period)
    frequency = "#{period}_digest"

    # Find users with digest preferences
    users_with_digests =
      from(p in NotificationPreference,
        where: p.email_frequency == ^frequency,
        select: p.user_id,
        distinct: true
      )
      |> Repo.all()

    for user_id <- users_with_digests do
      send_digest(user_id, period_atom)
    end

    :ok
  end

  defp send_digest(user_id, period) do
    # Get unsent notifications
    since = digest_cutoff(period)

    notifications =
      from(n in Notification,
        where: n.user_id == ^user_id,
        where: is_nil(n.email_sent_at),
        where: n.inserted_at >= ^since,
        order_by: [desc: n.inserted_at],
        preload: [:mission]
      )
      |> Repo.all()

    if length(notifications) > 0 do
      user = Accounts.get_user!(user_id)

      case UserNotifier.deliver_notification_digest(user, notifications, period) do
        {:ok, _email} ->
          # Mark all as sent
          ids = Enum.map(notifications, & &1.id)
          now = CadenceTime.now()

          from(n in Notification, where: n.id in ^ids)
          |> Repo.update_all(set: [email_sent_at: now])

        {:error, _reason} ->
          :ok
      end
    end
  end

  defp digest_cutoff(:daily), do: DateTime.add(CadenceTime.now(), -1, :day)
  defp digest_cutoff(:weekly), do: DateTime.add(CadenceTime.now(), -7, :day)
end
